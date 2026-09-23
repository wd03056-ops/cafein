/**
 * CAFEIN — one-shot migration: sever legacy withdrawn post/comment authorIds.
 *
 * Remaps:
 *   authorWithdrawn == true && authorId not starting with "deleted_"
 *   → authorId = deleted_<uuid> (one deletedId per legacy Kakao UID)
 *
 * DEFAULT = dry-run (reads only; no Firestore writes).
 * Writes ONLY with explicit --apply.
 *
 * Does NOT:
 *  - modify content / likeCount / poll / topicId / etc.
 *  - change authorWithdrawn == false docs
 *  - deploy / touch Rules / Flutter / Functions
 *
 * Usage (from this folder):
 *   npm install
 *   set GOOGLE_APPLICATION_CREDENTIALS=path\to\serviceAccount.json
 *   npm run migrate:dry-run
 *   npm run migrate:apply
 */

const crypto = require("crypto");
const fs = require("fs");
const path = require("path");
const admin = require("firebase-admin");

const PAGE_SIZE = 300;
const WRITE_BATCH_SIZE = 400;
const ANONYMIZED_NICKNAME = "탈퇴한 사용자";

function parseArgs(argv) {
  const flags = new Set(argv.slice(2));
  return {
    apply: flags.has("--apply"),
    help: flags.has("--help") || flags.has("-h"),
  };
}

function initAdmin() {
  if (admin.apps.length) return admin.firestore();

  const projectId =
    process.env.GCLOUD_PROJECT ||
    process.env.GOOGLE_CLOUD_PROJECT ||
    process.env.FIREBASE_PROJECT_ID ||
    "truestory-9eb36";

  try {
    admin.initializeApp({
      credential: admin.credential.applicationDefault(),
      projectId,
    });
  } catch (e) {
    console.error(
      "firebase-admin init failed. Set GOOGLE_APPLICATION_CREDENTIALS to a service account JSON.",
    );
    throw e;
  }
  return admin.firestore();
}

function stamp() {
  const d = new Date();
  const pad = (n) => String(n).padStart(2, "0");
  return (
    `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}_` +
    `${pad(d.getHours())}${pad(d.getMinutes())}${pad(d.getSeconds())}`
  );
}

function normId(value) {
  if (value == null) return "";
  return String(value).trim();
}

function isDeletedAuthorId(authorId) {
  return normId(authorId).startsWith("deleted_");
}

function newDeletedAuthorId() {
  return `deleted_${crypto.randomUUID().replace(/-/g, "")}`;
}

/**
 * Paginate posts where authorWithdrawn == true.
 * @returns {Promise<{
 *   postsScanned: number,
 *   legacy: Array<{ postId: string, authorId: string, authorNickname: string }>,
 *   alreadyMigrated: number,
 *   missingAuthorId: number,
 * }>}
 */
async function scanWithdrawnPosts(db) {
  const legacy = [];
  let postsScanned = 0;
  let alreadyMigrated = 0;
  let missingAuthorId = 0;
  let last = null;

  for (;;) {
    let q = db
      .collection("posts")
      .where("authorWithdrawn", "==", true)
      .orderBy(admin.firestore.FieldPath.documentId())
      .select("authorId", "authorNickname", "authorWithdrawn", "nickname")
      .limit(PAGE_SIZE);
    if (last) q = q.startAfter(last);

    const snap = await q.get();
    if (snap.empty) break;

    for (const doc of snap.docs) {
      postsScanned += 1;
      const data = doc.data() || {};
      const authorId = normId(data.authorId);
      if (!authorId) {
        missingAuthorId += 1;
        continue;
      }
      if (isDeletedAuthorId(authorId)) {
        alreadyMigrated += 1;
        continue;
      }
      legacy.push({
        postId: doc.id,
        authorId,
        authorNickname:
          data.authorNickname == null
            ? ""
            : String(data.authorNickname).trim(),
        path: `posts/${doc.id}`,
      });
    }

    last = snap.docs[snap.docs.length - 1];
    if (snap.size < PAGE_SIZE) break;
  }

  return {
    postsScanned,
    legacy,
    alreadyMigrated,
    missingAuthorId,
  };
}

/**
 * Paginate collectionGroup('comments') where authorWithdrawn == true.
 */
async function scanWithdrawnComments(db) {
  const legacy = [];
  let commentsScanned = 0;
  let alreadyMigrated = 0;
  let missingAuthorId = 0;
  let last = null;

  for (;;) {
    let q = db
      .collectionGroup("comments")
      .where("authorWithdrawn", "==", true)
      .orderBy(admin.firestore.FieldPath.documentId())
      .select("authorId", "authorNickname", "authorWithdrawn", "postId")
      .limit(PAGE_SIZE);
    if (last) q = q.startAfter(last);

    const snap = await q.get();
    if (snap.empty) break;

    for (const doc of snap.docs) {
      commentsScanned += 1;
      const data = doc.data() || {};
      const authorId = normId(data.authorId);
      if (!authorId) {
        missingAuthorId += 1;
        continue;
      }
      if (isDeletedAuthorId(authorId)) {
        alreadyMigrated += 1;
        continue;
      }
      // posts/{postId}/comments/{commentId}
      const parent = doc.ref.parent; // comments
      const postRef = parent && parent.parent;
      const postId =
        (postRef && postRef.id) ||
        normId(data.postId) ||
        "";
      legacy.push({
        commentId: doc.id,
        postId,
        authorId,
        authorNickname:
          data.authorNickname == null
            ? ""
            : String(data.authorNickname).trim(),
        path: doc.ref.path,
      });
    }

    last = snap.docs[snap.docs.length - 1];
    if (snap.size < PAGE_SIZE) break;
  }

  return {
    commentsScanned,
    legacy,
    alreadyMigrated,
    missingAuthorId,
  };
}

/**
 * @param {FirebaseFirestore.Firestore} db
 * @param {string[]} uids
 * @returns {Promise<Map<string, boolean>>}
 */
async function checkUsersExist(db, uids) {
  /** @type {Map<string, boolean>} */
  const exists = new Map();
  const unique = [...new Set(uids.map(normId).filter(Boolean))];

  // getAll in chunks of 100 (Firestore limit)
  const CHUNK = 100;
  for (let i = 0; i < unique.length; i += CHUNK) {
    const slice = unique.slice(i, i + CHUNK);
    const refs = slice.map((uid) => db.collection("users").doc(uid));
    const snaps = await db.getAll(...refs);
    for (let j = 0; j < snaps.length; j++) {
      exists.set(slice[j], snaps[j].exists);
    }
  }
  return exists;
}

/**
 * Build per-legacyUid plan with one deletedId each.
 */
async function buildPlan(db, postScan, commentScan) {
  /** @type {Map<string, { posts: typeof postScan.legacy, comments: typeof commentScan.legacy }>} */
  const byUid = new Map();

  for (const row of postScan.legacy) {
    const uid = row.authorId;
    if (!byUid.has(uid)) byUid.set(uid, { posts: [], comments: [] });
    byUid.get(uid).posts.push(row);
  }
  for (const row of commentScan.legacy) {
    const uid = row.authorId;
    if (!byUid.has(uid)) byUid.set(uid, { posts: [], comments: [] });
    byUid.get(uid).comments.push(row);
  }

  const uids = [...byUid.keys()].sort();
  const usersExists = await checkUsersExist(db, uids);

  const groups = [];
  let reRegisteredUids = 0;
  let orphanUids = 0;

  for (const legacyUid of uids) {
    const bucket = byUid.get(legacyUid);
    const exists = usersExists.get(legacyUid) === true;
    if (exists) reRegisteredUids += 1;
    else orphanUids += 1;

    groups.push({
      legacyUid,
      deletedId: newDeletedAuthorId(),
      usersExists: exists,
      reRegistered: exists,
      orphan: !exists,
      posts: bucket.posts,
      comments: bucket.comments,
      counts: {
        posts: bucket.posts.length,
        comments: bucket.comments.length,
      },
    });
  }

  const stats = {
    postsScanned: postScan.postsScanned,
    commentsScanned: commentScan.commentsScanned,
    legacyWithdrawnPosts: postScan.legacy.length,
    legacyWithdrawnComments: commentScan.legacy.length,
    alreadyMigratedPosts: postScan.alreadyMigrated,
    alreadyMigratedComments: commentScan.alreadyMigrated,
    missingAuthorIdPosts: postScan.missingAuthorId,
    missingAuthorIdComments: commentScan.missingAuthorId,
    uniqueLegacyUids: uids.length,
    reRegisteredUids,
    orphanUids,
    estimatedReads:
      postScan.postsScanned +
      commentScan.commentsScanned +
      uids.length,
    estimatedWrites:
      postScan.legacy.length + commentScan.legacy.length,
  };

  return {
    generatedAt: new Date().toISOString(),
    mode: "preview",
    policy: {
      target:
        "authorWithdrawn==true AND authorId does not start with deleted_",
      skip: "authorWithdrawn!=true OR authorId starts with deleted_",
      deletedId:
        "deleted_ + crypto.randomUUID() (hyphens stripped); one per legacyUid",
      fieldsUpdated: [
        "authorId",
        "authorWithdrawn",
        "authorNickname",
        "nickname (posts only)",
        "authorProfileImage",
      ],
      fieldsNotUpdated: [
        "content",
        "likeCount",
        "commentCount",
        "likedBy",
        "poll",
        "pollVoters",
        "topicId",
        "topicName",
        "createdAt",
        "updatedAt",
      ],
      topicUsageNote:
        "onPostUpdated returns early when topicId unchanged — authorId-only updates do not change usageCount",
    },
    stats,
    groups,
  };
}

function printPreview(plan) {
  console.log("");
  console.log("=== Withdrawn content migration preview ===");
  console.log("");

  if (plan.groups.length === 0) {
    console.log("No legacy withdrawn content found.");
  }

  for (const g of plan.groups) {
    console.log(`UID: ${g.legacyUid}`);
    console.log(`users/${g.legacyUid} exists: ${g.usersExists}`);
    if (g.reRegistered) {
      console.log("→ RE-REGISTERED (withdrawn content still points at live uid)");
    }
    console.log(`deletedId: ${g.deletedId}`);
    console.log("");
    console.log("posts:");
    console.log(`  ${g.counts.posts} document(s)`);
    console.log("");
    console.log("comments:");
    console.log(`  ${g.counts.comments} document(s)`);
    console.log("");
    console.log("--------------------------------");
    console.log("");
  }

  console.log("Stats:");
  for (const [k, v] of Object.entries(plan.stats)) {
    console.log(`  ${k}: ${v}`);
  }
  console.log("");
  console.log(
    `Estimated reads: ~${plan.stats.estimatedReads} ` +
      `(withdrawn posts + withdrawn comments + users exists checks)`,
  );
  console.log(
    `Estimated writes (--apply): ${plan.stats.estimatedWrites} ` +
      `(identity fields only; no updatedAt)`,
  );
}

/**
 * Apply identity remaps. Processes one legacyUid fully before the next
 * so a partial crash leaves fewer split deletedIds.
 */
async function applyPlan(db, plan) {
  let postsWritten = 0;
  let commentsWritten = 0;

  for (const g of plan.groups) {
    console.log(
      `[apply] uid=${g.legacyUid} → ${g.deletedId} ` +
        `posts=${g.counts.posts} comments=${g.counts.comments}`,
    );

    // Re-check live state so --apply is safe if dry-run preview is stale.
    const postUpdates = [];
    for (const row of g.posts) {
      const ref = db.collection("posts").doc(row.postId);
      const snap = await ref.get();
      if (!snap.exists) continue;
      const data = snap.data() || {};
      if (data.authorWithdrawn !== true) continue;
      const aid = normId(data.authorId);
      if (!aid || isDeletedAuthorId(aid)) continue;
      if (aid !== g.legacyUid) continue;
      postUpdates.push(ref);
    }

    const commentUpdates = [];
    for (const row of g.comments) {
      const ref = db.doc(row.path);
      const snap = await ref.get();
      if (!snap.exists) continue;
      const data = snap.data() || {};
      if (data.authorWithdrawn !== true) continue;
      const aid = normId(data.authorId);
      if (!aid || isDeletedAuthorId(aid)) continue;
      if (aid !== g.legacyUid) continue;
      commentUpdates.push(ref);
    }

    const identityPost = {
      authorId: g.deletedId,
      authorWithdrawn: true,
      authorNickname: ANONYMIZED_NICKNAME,
      nickname: ANONYMIZED_NICKNAME,
      authorProfileImage: "",
    };
    const identityComment = {
      authorId: g.deletedId,
      authorWithdrawn: true,
      authorNickname: ANONYMIZED_NICKNAME,
      authorProfileImage: "",
    };

    for (let i = 0; i < postUpdates.length; i += WRITE_BATCH_SIZE) {
      const chunk = postUpdates.slice(i, i + WRITE_BATCH_SIZE);
      const batch = db.batch();
      for (const ref of chunk) {
        batch.update(ref, identityPost);
      }
      await batch.commit();
      postsWritten += chunk.length;
    }

    for (let i = 0; i < commentUpdates.length; i += WRITE_BATCH_SIZE) {
      const chunk = commentUpdates.slice(i, i + WRITE_BATCH_SIZE);
      const batch = db.batch();
      for (const ref of chunk) {
        batch.update(ref, identityComment);
      }
      await batch.commit();
      commentsWritten += chunk.length;
    }
  }

  return { postsWritten, commentsWritten };
}

function writeJson(prefix, plan) {
  const file = path.join(__dirname, `${prefix}_${stamp()}.json`);
  // Preview JSON: trim path lists if huge — keep counts + sample paths
  const slim = {
    ...plan,
    groups: plan.groups.map((g) => ({
      legacyUid: g.legacyUid,
      deletedId: g.deletedId,
      usersExists: g.usersExists,
      reRegistered: g.reRegistered,
      orphan: g.orphan,
      counts: g.counts,
      posts: g.posts.map((p) => ({
        postId: p.postId,
        authorId: p.authorId,
        authorNickname: p.authorNickname,
      })),
      comments: g.comments.map((c) => ({
        commentId: c.commentId,
        postId: c.postId,
        path: c.path,
        authorId: c.authorId,
        authorNickname: c.authorNickname,
      })),
    })),
  };
  fs.writeFileSync(file, JSON.stringify(slim, null, 2), "utf8");
  console.log(`Wrote ${file}`);
  return file;
}

async function main() {
  const args = parseArgs(process.argv);
  if (args.help) {
    console.log(`Usage:
  node migrate.js              dry-run (default; no writes)
  node migrate.js --apply      remap legacy withdrawn authorIds (explicit)

Requires GOOGLE_APPLICATION_CREDENTIALS (service account).`);
    process.exit(0);
  }

  const mode = args.apply ? "APPLY" : "DRY-RUN";
  console.log(`[migrate] mode=${mode}`);
  if (!args.apply) {
    console.log("[migrate] Firestore will NOT be modified.");
  } else {
    console.log(
      "[migrate] WILL update identity fields on legacy withdrawn posts/comments only.",
    );
  }

  const db = initAdmin();

  console.log("[migrate] scanning withdrawn posts…");
  const postScan = await scanWithdrawnPosts(db);
  console.log(
    `[migrate] posts scanned=${postScan.postsScanned} ` +
      `legacy=${postScan.legacy.length} alreadyMigrated=${postScan.alreadyMigrated}`,
  );

  console.log("[migrate] scanning withdrawn comments…");
  const commentScan = await scanWithdrawnComments(db);
  console.log(
    `[migrate] comments scanned=${commentScan.commentsScanned} ` +
      `legacy=${commentScan.legacy.length} alreadyMigrated=${commentScan.alreadyMigrated}`,
  );

  console.log("[migrate] building plan + users/{uid} existence…");
  const plan = await buildPlan(db, postScan, commentScan);
  plan.mode = args.apply ? "apply" : "dry-run";
  printPreview(plan);

  const previewPath = writeJson(
    args.apply
      ? "withdrawn_content_migration_apply"
      : "withdrawn_content_migration_preview",
    plan,
  );

  if (args.apply) {
    if (plan.groups.length === 0) {
      console.log("[apply] nothing to update.");
    } else {
      const result = await applyPlan(db, plan);
      console.log(
        `[apply] done. postsWritten=${result.postsWritten} ` +
          `commentsWritten=${result.commentsWritten}`,
      );
      console.log(
        "[apply] Re-run dry-run to confirm legacyWithdrawn* counts are 0.",
      );
    }
    console.log(`[apply] report: ${previewPath}`);
  } else {
    console.log("[dry-run] No writes. To apply: npm run migrate:apply");
    console.log(`[dry-run] preview: ${previewPath}`);
  }
}

main().catch((e) => {
  console.error("[migrate] failed:", e && e.message ? e.message : e);
  process.exit(1);
});
