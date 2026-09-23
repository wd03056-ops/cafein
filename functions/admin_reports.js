/**
 * Admin report moderation callables (Admin SDK).
 * Admin check: Firebase Auth identity + custom claim `admin:true`
 * and/or server-only ADMIN_UIDS param — never trust client flags.
 *
 * Do NOT call getFirestore()/getAuth() at module load — index.js must
 * initializeApp() first, then invoke createAdminReportCallables().
 */
const { getFirestore, FieldValue } = require("firebase-admin/firestore");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { defineString } = require("firebase-functions/params");
const { logger } = require("firebase-functions");

/** Comma-separated Firebase Auth UIDs (Kakao user ids) — server config only. */
const ADMIN_UIDS = defineString("ADMIN_UIDS", {
  default: "",
  description:
    "Comma-separated admin UIDs (Kakao/Firebase Auth). Prefer Auth custom claims admin:true long-term.",
});

/**
 * @param {string} region
 */
function createAdminReportCallables(region) {
  // Safe only after initializeApp() in index.js.
  const db = getFirestore();

  /**
   * @param {string} uid
   */
  function isAdminUid(uid) {
    const id = (uid || "").toString().trim();
    if (!id) return false;
    const raw = (ADMIN_UIDS.value() || "").toString();
    const set = new Set(
      raw
        .split(",")
        .map((s) => s.trim())
        .filter(Boolean),
    );
    return set.has(id);
  }

  /**
   * Extra claims for Custom Token minting (createFirebaseCustomToken).
   * @param {string} uid
   * @returns {{admin?: boolean}}
   */
  function adminClaimsForUid(uid) {
    return isAdminUid(uid) ? { admin: true } : {};
  }

  /**
   * @param {import("firebase-functions/v2/https").CallableRequest} request
   * @returns {string} admin uid
   */
  function assertIsAdmin(request) {
    if (!request.auth || !request.auth.uid) {
      throw new HttpsError(
        "unauthenticated",
        "Firebase Auth sign-in required (Custom Token bridge).",
      );
    }
    const uid = String(request.auth.uid).trim();
    const claimAdmin = request.auth.token && request.auth.token.admin === true;
    if (claimAdmin || isAdminUid(uid)) {
      return uid;
    }
    logger.warn("admin callable denied", { uid });
    throw new HttpsError(
      "permission-denied",
      "Admin privileges required.",
    );
  }

  function toMillis(value) {
    if (value == null) return null;
    if (typeof value.toMillis === "function") return value.toMillis();
    if (typeof value._seconds === "number") {
      return value._seconds * 1000 + Math.floor((value._nanoseconds || 0) / 1e6);
    }
    if (value instanceof Date) return value.getTime();
    if (typeof value === "number") return value;
    return null;
  }

  function serializeSnapshot(raw) {
    if (!raw || typeof raw !== "object") return null;
    const options = [];
    if (Array.isArray(raw.pollOptions)) {
      for (const item of raw.pollOptions) {
        const s = item != null ? String(item).trim() : "";
        if (s) options.push(s);
      }
    }
    return {
      content: (raw.content || "").toString(),
      topicName: (raw.topicName || "").toString(),
      authorDisplayName: (raw.authorDisplayName || "").toString(),
      createdAt: toMillis(raw.createdAt),
      pollQuestion: (raw.pollQuestion || "").toString(),
      pollOptions: options,
    };
  }

  function liveContentFromPostData(d) {
    const author =
      (d.authorNickname || d.nickname || d.author || "").toString().trim();
    let pollQuestion = "";
    const pollOptions = [];
    const poll = d.poll;
    if (poll && typeof poll === "object") {
      pollQuestion = (poll.question || "").toString().trim();
      if (Array.isArray(poll.options)) {
        for (const item of poll.options) {
          if (item && typeof item === "object") {
            const t = (item.text || "").toString().trim();
            if (t) pollOptions.push(t);
          }
        }
      }
    }
    return {
      exists: true,
      content: (d.content || "").toString(),
      topicName: (d.topicName || "").toString(),
      authorDisplayName: author,
      createdAt: toMillis(d.createdAt),
      pollQuestion,
      pollOptions,
    };
  }

  function liveContentFromCommentData(d) {
    const author =
      (d.authorNickname || d.nickname || d.author || "").toString().trim();
    return {
      exists: true,
      content: (d.content || "").toString(),
      topicName: "",
      authorDisplayName: author,
      createdAt: toMillis(d.createdAt),
      pollQuestion: "",
      pollOptions: [],
    };
  }

  function serializeReport(id, data) {
    const d = data || {};
    return {
      id: String(id),
      reporterId: (d.reporterId || "").toString(),
      targetType: (d.targetType || "").toString(),
      targetId: (d.targetId || "").toString(),
      targetAuthorId: (d.targetAuthorId || "").toString(),
      parentPostId: d.parentPostId != null ? String(d.parentPostId) : null,
      reason: (d.reason || "").toString(),
      status: (d.status || "pending").toString(),
      action: (d.action || "none").toString(),
      reviewedBy: d.reviewedBy != null ? String(d.reviewedBy) : null,
      reviewedAt: toMillis(d.reviewedAt),
      adminNote: d.adminNote != null ? String(d.adminNote) : null,
      reporterNotified: d.reporterNotified === true,
      reportedUserNotified: d.reportedUserNotified === true,
      createdAt: toMillis(d.createdAt),
      updatedAt: toMillis(d.updatedAt),
      targetSnapshot: serializeSnapshot(d.targetSnapshot),
      parentPostSnapshot: serializeSnapshot(d.parentPostSnapshot),
    };
  }

  async function deleteSubcollection(colRef) {
    for (;;) {
      const page = await colRef.limit(200).get();
      if (page.empty) break;
      const batch = db.batch();
      for (const doc of page.docs) {
        batch.delete(doc.ref);
      }
      await batch.commit();
    }
  }

  /**
   * Mirror PostsFirestoreService.deletePost cleanup (Admin SDK).
   */
  async function deletePostCascade(postId) {
    const id = (postId || "").toString().trim();
    if (!id) throw new HttpsError("invalid-argument", "postId is empty.");

    const postRef = db.collection("posts").doc(id);
    const snap = await postRef.get();
    if (!snap.exists) {
      logger.info("deletePostCascade: already missing", { postId: id });
      return { deleted: false, alreadyMissing: true };
    }

    const data = snap.data() || {};

    // Nested comment likes: delete per comment before wiping comments.
    const commentsSnap = await postRef.collection("comments").limit(500).get();
    for (const c of commentsSnap.docs) {
      await deleteSubcollection(c.ref.collection("likes"));
    }
    await deleteSubcollection(postRef.collection("comments"));
    await deleteSubcollection(postRef.collection("likes"));
    await deleteSubcollection(postRef.collection("poll_votes"));

    await postRef.delete();

    // Topic usageCount is adjusted by onPostDeletedTopicUsage trigger
    // (Admin SDK ledger). Do not decrement here — avoids double -1.

    return { deleted: true, alreadyMissing: false };
  }

  /**
   * Mirror CommentsFirestoreService.deleteComment cleanup (Admin SDK).
   */
  async function deleteCommentCascade(postId, commentId) {
    const pid = (postId || "").toString().trim();
    const cid = (commentId || "").toString().trim();
    if (!pid || !cid) {
      throw new HttpsError(
        "invalid-argument",
        "postId and commentId are required.",
      );
    }

    const commentRef = db
      .collection("posts")
      .doc(pid)
      .collection("comments")
      .doc(cid);
    const postRef = db.collection("posts").doc(pid);

    try {
      await deleteSubcollection(commentRef.collection("likes"));
    } catch (e) {
      logger.warn("comment likes cleanup failed", { message: e.message });
    }

    const commentSnap = await commentRef.get();
    if (!commentSnap.exists) {
      logger.info("deleteCommentCascade: already missing", {
        postId: pid,
        commentId: cid,
      });
      return { deleted: false, alreadyMissing: true };
    }

    await db.runTransaction(async (tx) => {
      const c = await tx.get(commentRef);
      if (!c.exists) return;
      const p = await tx.get(postRef);
      tx.delete(commentRef);
      if (p.exists) {
        const current = (p.data().commentCount || 0) | 0;
        tx.update(postRef, {
          commentCount: Math.max(0, current - 1),
          updatedAt: FieldValue.serverTimestamp(),
        });
      }
    });

    return { deleted: true, alreadyMissing: false };
  }

  async function writeWarningAction(report, adminUid, adminNote) {
    const targetUserId = (report.targetAuthorId || "").toString().trim();
    if (!targetUserId) {
      throw new HttpsError(
        "failed-precondition",
        "targetAuthorId missing; cannot record warning.",
      );
    }
    const reportId = report.id;
    await db
      .collection("users")
      .doc(targetUserId)
      .collection("moderation_actions")
      .doc(reportId)
      .set(
        {
          actionType: "user_warned",
          targetUserId,
          reportId,
          createdAt: FieldValue.serverTimestamp(),
          reviewedBy: adminUid,
          adminNote: (adminNote || "").toString(),
          targetType: (report.targetType || "").toString(),
          targetId: (report.targetId || "").toString(),
        },
        { merge: true },
      );
  }

  async function applyReportUpdate(reportId, payload) {
    const ref = db.collection("reports").doc(reportId);
    await ref.set(
      {
        ...payload,
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    const snap = await ref.get();
    return serializeReport(snap.id, snap.data());
  }

  const adminListReports = onCall({ region }, async (request) => {
    assertIsAdmin(request);
    const statusFilter = (request.data?.status || "").toString().trim();

    let query = db.collection("reports");
    // Avoid composite-index requirement: filter in memory when status set.
    const snap = await query.get();
    let rows = snap.docs.map((d) => serializeReport(d.id, d.data()));
    if (statusFilter) {
      rows = rows.filter((r) => {
        const s = (r.status || "pending").toLowerCase();
        return s === statusFilter.toLowerCase();
      });
    }
    rows.sort((a, b) => (b.createdAt || 0) - (a.createdAt || 0));
    return { reports: rows };
  });

  const adminGetReport = onCall({ region }, async (request) => {
    assertIsAdmin(request);
    const reportId = (request.data?.reportId || "").toString().trim();
    if (!reportId) {
      throw new HttpsError("invalid-argument", "reportId is required.");
    }
    const snap = await db.collection("reports").doc(reportId).get();
    if (!snap.exists) {
      throw new HttpsError("not-found", "Report not found.");
    }
    const report = serializeReport(snap.id, snap.data());

    // Live target (+ parent post for comments). Admin only.
    let target = null;
    let parentPost = null;
    const type = (report.targetType || "").toLowerCase();
    try {
      if (type === "post" && report.targetId) {
        const p = await db.collection("posts").doc(report.targetId).get();
        target = p.exists
          ? liveContentFromPostData(p.data() || {})
          : { exists: false };
      } else if (type === "comment" && report.targetId && report.parentPostId) {
        const c = await db
          .collection("posts")
          .doc(report.parentPostId)
          .collection("comments")
          .doc(report.targetId)
          .get();
        target = c.exists
          ? liveContentFromCommentData(c.data() || {})
          : { exists: false };
        const p = await db.collection("posts").doc(report.parentPostId).get();
        parentPost = p.exists
          ? liveContentFromPostData(p.data() || {})
          : { exists: false };
      } else if (type === "user" && report.targetId) {
        const u = await db.collection("users").doc(report.targetId).get();
        if (u.exists) {
          const d = u.data() || {};
          const nick = (d.nickname || d.kakaoNickname || "").toString().trim();
          target = {
            exists: true,
            content: "",
            topicName: "",
            authorDisplayName: nick || report.targetId,
            createdAt: toMillis(d.createdAt),
            pollQuestion: "",
            pollOptions: [],
          };
        } else {
          target = { exists: false };
        }
      }
    } catch (e) {
      logger.warn("adminGetReport target preview failed", { message: e.message });
    }

    return { report, target, parentPost };
  });

  /**
   * Resolve / review / dismiss a report.
   *
   * data: {
   *   reportId,
   *   action: none|content_deleted|user_warned|user_suspended,
   *   status?: reviewing|resolved|dismissed  (defaults by action),
   *   adminNote?: string
   * }
   */
  const adminResolveReport = onCall({ region }, async (request) => {
    const adminUid = assertIsAdmin(request);
    const reportId = (request.data?.reportId || "").toString().trim();
    const action = (request.data?.action || "none").toString().trim().toLowerCase();
    let status = (request.data?.status || "").toString().trim().toLowerCase();
    const adminNote =
      request.data?.adminNote != null
        ? String(request.data.adminNote).trim()
        : undefined;

    if (!reportId) {
      throw new HttpsError("invalid-argument", "reportId is required.");
    }
    const allowedActions = new Set([
      "none",
      "content_deleted",
      "user_warned",
      "user_suspended",
    ]);
    if (!allowedActions.has(action)) {
      throw new HttpsError("invalid-argument", `Unsupported action: ${action}`);
    }

    // Default status from action when omitted.
    if (!status) {
      if (action === "content_deleted" || action === "user_warned") {
        status = "resolved";
      } else if (action === "user_suspended") {
        status = "resolved";
      } else {
        status = "reviewing";
      }
    }
    const allowedStatus = new Set(["reviewing", "resolved", "dismissed"]);
    if (!allowedStatus.has(status)) {
      throw new HttpsError("invalid-argument", `Unsupported status: ${status}`);
    }

    const ref = db.collection("reports").doc(reportId);
    const snap = await ref.get();
    if (!snap.exists) {
      throw new HttpsError("not-found", "Report not found.");
    }
    const existing = snap.data() || {};
    const report = { id: reportId, ...existing };

    const prevStatus = (existing.status || "pending").toString();
    const prevAction = (existing.action || "none").toString();

    // Idempotent: already resolved with same action → return as-is (no re-notify).
    if (
      prevStatus === "resolved" &&
      status === "resolved" &&
      prevAction === action &&
      (action === "content_deleted" ||
        action === "user_warned" ||
        action === "user_suspended")
    ) {
      logger.info("adminResolveReport idempotent hit", { reportId, action });
      return { report: serializeReport(reportId, existing), idempotent: true };
    }

    // user_suspended: record-only TODO — do NOT implement account freeze.
    if (action === "user_suspended") {
      throw new HttpsError(
        "unimplemented",
        "user_suspended is not implemented yet (no account freeze).",
      );
    }

    if (action === "content_deleted") {
      if (status !== "resolved") {
        throw new HttpsError(
          "invalid-argument",
          "content_deleted requires status=resolved.",
        );
      }
      const targetType = (existing.targetType || "").toString().trim().toLowerCase();
      const targetId = (existing.targetId || "").toString().trim();

      if (targetType === "post") {
        await deletePostCascade(targetId);
      } else if (targetType === "comment") {
        const parentPostId = (existing.parentPostId || "").toString().trim();
        if (!parentPostId) {
          throw new HttpsError(
            "failed-precondition",
            "Comment report missing parentPostId.",
          );
        }
        await deleteCommentCascade(parentPostId, targetId);
      } else if (targetType === "user") {
        throw new HttpsError(
          "unimplemented",
          "user target content_deleted is not defined.",
        );
      } else {
        throw new HttpsError(
          "failed-precondition",
          `Unknown targetType: ${targetType}`,
        );
      }

      const updated = await applyReportUpdate(reportId, {
        status: "resolved",
        action: "content_deleted",
        reviewedBy: adminUid,
        reviewedAt: FieldValue.serverTimestamp(),
        ...(adminNote !== undefined ? { adminNote } : {}),
      });
      // onReportUpdated trigger handles notifications + notified flags.
      return { report: updated, idempotent: false };
    }

    if (action === "user_warned") {
      if (status !== "resolved") {
        throw new HttpsError(
          "invalid-argument",
          "user_warned requires status=resolved.",
        );
      }
      await writeWarningAction(
        {
          id: reportId,
          targetAuthorId: existing.targetAuthorId,
          targetType: existing.targetType,
          targetId: existing.targetId,
        },
        adminUid,
        adminNote || "",
      );
      const updated = await applyReportUpdate(reportId, {
        status: "resolved",
        action: "user_warned",
        reviewedBy: adminUid,
        reviewedAt: FieldValue.serverTimestamp(),
        ...(adminNote !== undefined ? { adminNote } : {}),
      });
      return { report: updated, idempotent: false };
    }

    // action === none → reviewing or dismissed
    if (status === "resolved") {
      throw new HttpsError(
        "invalid-argument",
        "status=resolved with action=none is not allowed; use dismiss or a concrete action.",
      );
    }
    const updated = await applyReportUpdate(reportId, {
      status,
      action: "none",
      reviewedBy: adminUid,
      reviewedAt: FieldValue.serverTimestamp(),
      ...(adminNote !== undefined ? { adminNote } : {}),
    });
    return { report: updated, idempotent: false };
  });

  return {
    adminListReports,
    adminGetReport,
    adminResolveReport,
    adminClaimsForUid,
    isAdminUid,
  };
}

module.exports = { createAdminReportCallables };
