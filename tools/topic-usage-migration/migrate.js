/**
 * CAFEIN — one-shot topics.usageCount recalculation from posts.topicId.
 *
 * DEFAULT = dry-run (no Firestore writes).
 * Writes ONLY with explicit --apply.
 *
 * Does NOT:
 *  - modify posts
 *  - create/delete topic docs
 *  - rewrite topic_usage_ledger (see README)
 *  - deploy anything
 *
 * Usage (from this folder):
 *   npm install
 *   set GOOGLE_APPLICATION_CREDENTIALS=path\to\serviceAccount.json
 *   npm run migrate:dry-run
 *   npm run migrate:verify
 *   npm run migrate:apply
 */

const fs = require("fs");
const path = require("path");
const admin = require("firebase-admin");

const POSTS_PAGE_SIZE = 300;
const TOPICS_PAGE_SIZE = 300;
const WRITE_BATCH_SIZE = 400;

function parseArgs(argv) {
  const flags = new Set(argv.slice(2));
  return {
    apply: flags.has("--apply"),
    verify: flags.has("--verify"),
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

function normTopicId(value) {
  if (value == null) return "";
  return String(value).trim();
}

function readUsageCount(data) {
  const n = data && data.usageCount;
  const parsed = typeof n === "number" ? n : parseInt(String(n), 10);
  if (!Number.isFinite(parsed) || parsed < 0) return 0;
  return Math.floor(parsed);
}

function stamp() {
  const d = new Date();
  const pad = (n) => String(n).padStart(2, "0");
  return (
    `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}_` +
    `${pad(d.getHours())}${pad(d.getMinutes())}${pad(d.getSeconds())}`
  );
}

/**
 * Paginate posts; count by topicId only.
 * Soft-delete: CAFEIN hard-deletes posts — every existing doc counts.
 */
async function scanPosts(db) {
  /** @type {Map<string, number>} */
  const counts = new Map();
  const legacyMissingTopicId = [];
  let postsScanned = 0;
  let postsWithTopic = 0;
  let postsWithoutTopic = 0;

  let last = null;
  for (;;) {
    let q = db
      .collection("posts")
      .orderBy(admin.firestore.FieldPath.documentId())
      .select("topicId", "topicName")
      .limit(POSTS_PAGE_SIZE);
    if (last) q = q.startAfter(last);

    const snap = await q.get();
    if (snap.empty) break;

    for (const doc of snap.docs) {
      postsScanned += 1;
      const data = doc.data() || {};
      const topicId = normTopicId(data.topicId);
      const topicName =
        data.topicName == null ? "" : String(data.topicName).trim();

      if (!topicId) {
        postsWithoutTopic += 1;
        if (topicName) {
          legacyMissingTopicId.push({
            postId: doc.id,
            topicName,
          });
        }
        continue;
      }

      postsWithTopic += 1;
      counts.set(topicId, (counts.get(topicId) || 0) + 1);
    }

    last = snap.docs[snap.docs.length - 1];
    if (snap.size < POSTS_PAGE_SIZE) break;
  }

  return {
    counts,
    postsScanned,
    postsWithTopic,
    postsWithoutTopic,
    legacyMissingTopicId,
  };
}

/**
 * Load every topics/{id} doc.
 */
async function loadAllTopics(db) {
  /** @type {Map<string, { name: string, current: number }>} */
  const topics = new Map();
  let last = null;

  for (;;) {
    let q = db
      .collection("topics")
      .orderBy(admin.firestore.FieldPath.documentId())
      .select("name", "usageCount")
      .limit(TOPICS_PAGE_SIZE);
    if (last) q = q.startAfter(last);

    const snap = await q.get();
    if (snap.empty) break;

    for (const doc of snap.docs) {
      const data = doc.data() || {};
      topics.set(doc.id, {
        name: data.name == null ? "" : String(data.name).trim(),
        current: readUsageCount(data),
      });
    }

    last = snap.docs[snap.docs.length - 1];
    if (snap.size < TOPICS_PAGE_SIZE) break;
  }

  return topics;
}

function buildReport(postScan, topics) {
  const rows = [];
  const orphanTopicIds = [];

  // Every existing topic doc → expected = post count or 0
  for (const [topicId, meta] of topics.entries()) {
    const expected = postScan.counts.get(topicId) || 0;
    const current = meta.current;
    rows.push({
      topicId,
      topicName: meta.name,
      currentUsageCount: current,
      expectedUsageCount: expected,
      delta: expected - current,
      orphan: false,
    });
  }

  // topicIds on posts with no topics/{id} doc
  for (const [topicId, expected] of postScan.counts.entries()) {
    if (topics.has(topicId)) continue;
    orphanTopicIds.push({
      topicId,
      expectedUsageCount: expected,
    });
    rows.push({
      topicId,
      topicName: "(missing topic doc)",
      currentUsageCount: null,
      expectedUsageCount: expected,
      delta: null,
      orphan: true,
    });
  }

  rows.sort((a, b) => {
    const an = a.topicName || a.topicId;
    const bn = b.topicName || b.topicId;
    return an.localeCompare(bn, "ko");
  });

  const mismatches = rows.filter(
    (r) => !r.orphan && r.delta !== 0,
  );
  const matched = rows.filter((r) => !r.orphan && r.delta === 0);

  return {
    generatedAt: new Date().toISOString(),
    countBasis: "posts.topicId (hard-deleted posts absent; no soft-delete)",
    softDeletePolicy: "none — deletePost hard-deletes; all existing posts count",
    ledgerPolicy:
      "NOT modified by this script — reconcile topic_usage_ledger separately if needed",
    stats: {
      postsScanned: postScan.postsScanned,
      postsWithTopic: postScan.postsWithTopic,
      postsWithoutTopic: postScan.postsWithoutTopic,
      uniqueTopicIdsOnPosts: postScan.counts.size,
      topicsDocuments: topics.size,
      mismatchCount: mismatches.length,
      matchedCount: matched.length,
      orphanTopicIdCount: orphanTopicIds.length,
      legacyTopicIdMissingCount: postScan.legacyMissingTopicId.length,
    },
    mismatches,
    matchedSample: matched.slice(0, 20),
    orphanTopicIds,
    legacyMissingTopicId: postScan.legacyMissingTopicId.slice(0, 100),
    legacyMissingTopicIdTruncated:
      postScan.legacyMissingTopicId.length > 100,
    allRows: rows,
  };
}

function printPreview(report) {
  console.log("");
  console.log("=== Topic usageCount migration preview ===");
  console.log(`basis: ${report.countBasis}`);
  console.log(`soft-delete: ${report.softDeletePolicy}`);
  console.log(`ledger: ${report.ledgerPolicy}`);
  console.log("");
  console.log("Stats:");
  for (const [k, v] of Object.entries(report.stats)) {
    console.log(`  ${k}: ${v}`);
  }
  console.log("");

  if (report.mismatches.length === 0) {
    console.log("All existing topic docs already match expected counts.");
  } else {
    console.log("Mismatches (will change under --apply):");
    for (const row of report.mismatches) {
      const label = row.topicName || row.topicId;
      const sign = row.delta > 0 ? "+" : "";
      console.log(
        `  ${label} (${row.topicId}): ` +
          `current=${row.currentUsageCount} expected=${row.expectedUsageCount} ` +
          `delta=${sign}${row.delta}`,
      );
    }
  }

  if (report.orphanTopicIds.length) {
    console.log("");
    console.log(
      "Orphan topicIds (posts reference them; no topics/{id} — NOT auto-created):",
    );
    for (const o of report.orphanTopicIds) {
      console.log(
        `  ${o.topicId}: expectedCount=${o.expectedUsageCount}`,
      );
    }
  }

  if (report.legacyMissingTopicId.length) {
    console.log("");
    console.log(
      "Legacy posts with topicName but no topicId (NOT counted; not guessed):",
    );
    const show = report.legacyMissingTopicId.slice(0, 20);
    for (const row of show) {
      console.log(
        `  post=${row.postId} topicName=${JSON.stringify(row.topicName)}`,
      );
    }
    if (report.legacyMissingTopicIdTruncated) {
      console.log("  ... truncated (see JSON preview)");
    }
  }

  console.log("");
  console.log(
    `Estimated reads: ~${report.stats.postsScanned} posts + ${report.stats.topicsDocuments} topics`,
  );
  console.log(
    `Estimated writes (--apply): ${report.stats.mismatchCount} topic updates (set usageCount)`,
  );
}

async function applyMismatches(db, mismatches) {
  const FieldValue = admin.firestore.FieldValue;
  let written = 0;

  for (let i = 0; i < mismatches.length; i += WRITE_BATCH_SIZE) {
    const chunk = mismatches.slice(i, i + WRITE_BATCH_SIZE);
    const batch = db.batch();
    for (const row of chunk) {
      const ref = db.collection("topics").doc(row.topicId);
      batch.update(ref, {
        usageCount: row.expectedUsageCount,
        updatedAt: FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
    written += chunk.length;
    console.log(`[apply] wrote ${written}/${mismatches.length}`);
  }

  return written;
}

function writeJson(prefix, report) {
  const file = path.join(
    __dirname,
    `${prefix}_${stamp()}.json`,
  );
  fs.writeFileSync(file, JSON.stringify(report, null, 2), "utf8");
  console.log(`Wrote ${file}`);
  return file;
}

async function main() {
  const args = parseArgs(process.argv);
  if (args.help) {
    console.log(`Usage:
  node migrate.js              dry-run (default; no writes)
  node migrate.js --verify     same as dry-run; exit 1 if mismatches
  node migrate.js --apply      set topics.usageCount = expected (explicit)

Requires GOOGLE_APPLICATION_CREDENTIALS (service account).`);
    process.exit(0);
  }

  if (args.apply && args.verify) {
    console.error("Use either --apply or --verify, not both.");
    process.exit(2);
  }

  const mode = args.apply ? "APPLY" : args.verify ? "VERIFY" : "DRY-RUN";
  console.log(`[migrate] mode=${mode}`);
  if (!args.apply) {
    console.log("[migrate] Firestore will NOT be modified.");
  } else {
    console.log(
      "[migrate] WILL write topics.usageCount for mismatched docs only.",
    );
  }

  const db = initAdmin();
  console.log("[migrate] scanning posts…");
  const postScan = await scanPosts(db);
  console.log(
    `[migrate] posts scanned=${postScan.postsScanned} withTopic=${postScan.postsWithTopic}`,
  );
  console.log("[migrate] loading topics…");
  const topics = await loadAllTopics(db);
  console.log(`[migrate] topics loaded=${topics.size}`);

  const report = buildReport(postScan, topics);
  printPreview(report);

  const previewPath = writeJson(
    args.apply
      ? "topic_usage_migration_apply"
      : "topic_usage_migration_preview",
    report,
  );

  if (args.apply) {
    if (report.mismatches.length === 0) {
      console.log("[apply] nothing to update.");
    } else {
      const n = await applyMismatches(db, report.mismatches);
      console.log(`[apply] done. updated=${n}`);
      console.log(
        "[apply] Re-run: npm run migrate:verify  to confirm mismatchCount=0",
      );
    }
  } else if (args.verify) {
    if (report.stats.mismatchCount > 0) {
      console.error(
        `[verify] FAIL mismatchCount=${report.stats.mismatchCount} (see ${previewPath})`,
      );
      process.exit(1);
    }
    console.log("[verify] PASS mismatchCount=0");
  } else {
    console.log(
      "[dry-run] No writes. To apply: npm run migrate:apply",
    );
  }
}

main().catch((e) => {
  console.error("[migrate] failed:", e && e.message ? e.message : e);
  process.exit(1);
});
