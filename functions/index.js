/**
 * CAFEIN Cloud Functions — FCM push for comment / like / report_result.
 * Deploy: firebase deploy --only functions,firestore:indexes
 *
 * Does NOT run in the Flutter app. No server keys in client code.
 *
 * Inbox safeguards:
 * 1) Self-action filter — actor === recipient → no notification
 * 2) Duplicate prevention — same unread slot → bump updatedAt only
 * 3) Cap + TTL — max inbox size per user; expireAt for Firestore TTL
 * 4) Report result — reports.reporterNotified / reportedUserNotified flags
 */
const { initializeApp } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");
const { getAuth } = require("firebase-admin/auth");
const { onDocumentCreated, onDocumentUpdated } = require("firebase-functions/v2/firestore");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { logger } = require("firebase-functions");

// Initialize Admin SDK before any module that calls getFirestore()/getAuth().
initializeApp();
const db = getFirestore();
const auth = getAuth();

/** Callable + Firestore triggers region (matches firebase.json Firestore). */
const CAFEIN_REGION = "asia-northeast3";

const { createAdminReportCallables } = require("./admin_reports");
const adminReports = createAdminReportCallables(CAFEIN_REGION);
exports.adminListReports = adminReports.adminListReports;
exports.adminGetReport = adminReports.adminGetReport;
exports.adminResolveReport = adminReports.adminResolveReport;

const { createCastVoteCallable } = require("./cast_vote");
exports.castVote = createCastVoteCallable(CAFEIN_REGION);

const { createEditPostPollCallable } = require("./edit_post_poll");
exports.editPostPoll = createEditPostPollCallable(CAFEIN_REGION);

const { createTopicUsageTriggers } = require("./topic_usage");
const topicUsage = createTopicUsageTriggers(CAFEIN_REGION);
exports.onPostCreatedTopicUsage = topicUsage.onPostCreated;
exports.onPostUpdatedTopicUsage = topicUsage.onPostUpdated;
exports.onPostDeletedTopicUsage = topicUsage.onPostDeleted;

const { createWithdrawAccountCallable } = require("./withdraw_account");
exports.withdrawAccount = createWithdrawAccountCallable(CAFEIN_REGION);

/**
 * Verify Kakao access token with Kakao API (never trust client-sent kakaoUserId alone).
 * @returns {Promise<string>} Kakao user id as string
 */
async function verifyKakaoAccessToken(accessToken) {
  const res = await fetch("https://kapi.kakao.com/v2/user/me", {
    method: "GET",
    headers: {
      Authorization: `Bearer ${accessToken}`,
      "Content-Type": "application/x-www-form-urlencoded;charset=utf-8",
    },
  });
  if (!res.ok) {
    const body = await res.text();
    logger.warn("Kakao token verify failed", {
      status: res.status,
      bodyPreview: body.slice(0, 120),
    });
    throw new Error(`kakao_verify_${res.status}`);
  }
  const data = await res.json();
  const id = data && data.id != null ? String(data.id).trim() : "";
  if (!id) {
    throw new Error("kakao_verify_no_id");
  }
  return id;
}

/**
 * Kakao access token → Firebase Custom Token (uid = Kakao user id).
 *
 * Client must NOT send a trusted kakaoUserId alone — server verifies the token
 * via kapi.kakao.com/v2/user/me, then createCustomToken(verifiedId).
 *
 * NOTE: Firestore Rules remain open in this phase. Before Play release, Rules
 * should require request.auth.uid; without this bridge, writes would fail then.
 */
exports.createFirebaseCustomToken = onCall(
  { region: CAFEIN_REGION },
  async (request) => {
    const accessToken = (request.data?.kakaoAccessToken || "").toString().trim();
    if (!accessToken) {
      throw new HttpsError(
        "invalid-argument",
        "kakaoAccessToken is required.",
      );
    }

    let kakaoUserId;
    try {
      kakaoUserId = await verifyKakaoAccessToken(accessToken);
    } catch (e) {
      logger.warn("createFirebaseCustomToken: Kakao verify failed", {
        message: e.message,
      });
      throw new HttpsError(
        "unauthenticated",
        "Kakao access token is invalid or expired.",
      );
    }

    try {
      // Optional admin claim when uid is in server ADMIN_UIDS (not client allowlist).
      const claims = adminReports.adminClaimsForUid(kakaoUserId);
      const customToken = await auth.createCustomToken(kakaoUserId, claims);
      logger.info("createFirebaseCustomToken success", {
        kakaoUserId,
        adminClaim: claims.admin === true,
      });
      return { customToken, uid: kakaoUserId };
    } catch (e) {
      logger.error("createCustomToken failed", { message: e.message });
      throw new HttpsError("internal", "Failed to create Firebase custom token.");
    }
  }
);

/** Keep at most this many inbox docs per recipient (oldest pruned). */
const MAX_INBOX_PER_USER = 50;
/** Days until Firestore TTL may delete the doc (requires TTL policy on expireAt). */
const INBOX_TTL_DAYS = 30;

function sameUid(a, b) {
  const left = (a || "").toString().trim();
  const right = (b || "").toString().trim();
  return left.length > 0 && left === right;
}

async function tokensForUser(userId) {
  const snap = await db.collection("users").doc(userId).get();
  if (!snap.exists) return { tokens: [], settings: {} };
  const data = snap.data() || {};
  const settings = data.notificationSettings || {};
  const tokens = new Set();
  if (typeof data.fcmToken === "string" && data.fcmToken) {
    tokens.add(data.fcmToken);
  }
  if (Array.isArray(data.fcmTokens)) {
    for (const t of data.fcmTokens) {
      if (typeof t === "string" && t) tokens.add(t);
    }
  }
  return { tokens: [...tokens], settings };
}

function inboxDocId({
  recipientUserId,
  type,
  postId,
  commentId,
  actorUserId,
}) {
  // Deterministic id → one unread slot per (recipient, type, post, comment, actor).
  return [
    recipientUserId,
    type,
    postId || "-",
    commentId || "-",
    actorUserId || "-",
  ].join("__");
}

function expireAtFrom(now = new Date()) {
  return new Date(now.getTime() + INBOX_TTL_DAYS * 24 * 60 * 60 * 1000);
}

/** Max grapheme-ish chars for notification preview snapshot (~30–40). */
const POST_PREVIEW_MAX = 40;

/**
 * Short content snapshot for inbox + FCM message (not full body).
 * Collapses whitespace/newlines; truncates with "…".
 */
function makePostPreview(raw, maxLen = POST_PREVIEW_MAX) {
  if (raw == null) return "";
  const s = String(raw)
    .replace(/\r\n/g, "\n")
    .replace(/\n+/g, " ")
    .replace(/\s+/g, " ")
    .trim();
  if (!s) return "";
  if ([...s].length <= maxLen) return s;
  return `${[...s].slice(0, maxLen).join("").trimEnd()}…`;
}

function postContentFromData(post) {
  if (!post || typeof post !== "object") return "";
  const content = post.content != null ? String(post.content) : "";
  if (content.trim()) return content;
  const body = post.body != null ? String(post.body) : "";
  return body;
}

/** Prefer denormalized nickname on the action doc, else users/{uid}.nickname. */
async function resolveActorNickname(actorUserId, hint) {
  const fromHint = (hint || "").toString().trim();
  if (fromHint) return fromHint;
  const uid = (actorUserId || "").toString().trim();
  if (!uid) return "누군가";
  try {
    const snap = await db.collection("users").doc(uid).get();
    if (snap.exists) {
      const d = snap.data() || {};
      const n = (d.nickname || d.kakaoNickname || "").toString().trim();
      if (n) return n;
    }
  } catch (e) {
    logger.warn("resolveActorNickname failed", { uid, message: e.message });
  }
  return "누군가";
}

/**
 * Final social notification sentence (shared by inbox + FCM).
 * comment/like quote postPreview; comment_like quotes commentPreview.
 */
function buildSocialMessage({ type, actorNickname, preview }) {
  const nick = (actorNickname || "").toString().trim() || "누군가";
  const p = (preview || "").toString().trim();
  if (type === "comment") {
    return p
      ? `${nick}님이 "${p}" 게시글에 댓글을 남겼습니다.`
      : `${nick}님이 게시글에 댓글을 남겼습니다.`;
  }
  if (type === "like") {
    return p
      ? `${nick}님이 "${p}" 게시글에 공감을 남겼습니다.`
      : `${nick}님이 게시글에 공감을 남겼습니다.`;
  }
  if (type === "comment_like") {
    return p
      ? `${nick}님이 "${p}" 댓글에 공감을 남겼습니다.`
      : `${nick}님이 댓글에 공감을 남겼습니다.`;
  }
  return "";
}

/**
 * Upsert inbox notification.
 * @returns {{ skipped?: string, duplicated?: boolean, created?: boolean }}
 */
async function writeInbox({
  recipientUserId,
  actorUserId,
  actorNickname,
  type,
  postId,
  commentId,
  message,
  postPreview,
  commentPreview,
}) {
  const recipient = (recipientUserId || "").trim();
  const actor = (actorUserId || "").trim();
  if (!recipient) return { skipped: "no_recipient" };

  // 1) Self-action filter (defense in depth; triggers also check this).
  if (sameUid(recipient, actor)) {
    logger.info("self-action filtered", { type, recipient, actor });
    return { skipped: "self_action" };
  }

  const now = new Date();
  const expireAt = expireAtFrom(now);
  const pid = postId || "";
  const cid = commentId || "";
  const preview =
    postPreview == null ? "" : String(postPreview).trim();
  const cPreview =
    commentPreview == null ? "" : String(commentPreview).trim();
  const nick =
    actorNickname == null ? "" : String(actorNickname).trim();
  const ref = db.collection("notifications").doc(
    inboxDocId({
      recipientUserId: recipient,
      type,
      postId: pid,
      commentId: cid,
      actorUserId: actor,
    })
  );

  const existing = await ref.get();
  if (existing.exists) {
    const prev = existing.data() || {};
    // 2) Unread duplicate → bump timestamp only (no second doc).
    if (prev.isRead === false) {
      const bump = {
        updatedAt: now,
        expireAt,
        message,
      };
      if (nick) bump.actorNickname = nick;
      if (preview) bump.postPreview = preview;
      if (cPreview) bump.commentPreview = cPreview;
      await ref.update(bump);
      logger.info("inbox duplicate bumped", { type, recipient, actor, postId: pid });
      return { duplicated: true };
    }
    // Previously read → reopen as unread for new activity.
    const reopen = {
      recipientUserId: recipient,
      actorUserId: actor,
      type,
      postId: pid,
      commentId: cid,
      message,
      isRead: false,
      updatedAt: now,
      expireAt,
      createdAt: prev.createdAt || now,
    };
    if (nick) reopen.actorNickname = nick;
    if (preview) reopen.postPreview = preview;
    if (cPreview) reopen.commentPreview = cPreview;
    await ref.set(reopen, { merge: true });
    await pruneInbox(recipient);
    return { created: true };
  }

  const created = {
    recipientUserId: recipient,
    actorUserId: actor,
    type,
    postId: pid,
    commentId: cid,
    message,
    isRead: false,
    createdAt: now,
    updatedAt: now,
    expireAt,
  };
  if (nick) created.actorNickname = nick;
  if (preview) created.postPreview = preview;
  if (cPreview) created.commentPreview = cPreview;
  await ref.set(created);

  // 3) Cap growth per recipient.
  await pruneInbox(recipient);
  return { created: true };
}

/** Delete oldest inbox docs beyond MAX_INBOX_PER_USER. */
async function pruneInbox(recipientUserId) {
  try {
    const snap = await db
      .collection("notifications")
      .where("recipientUserId", "==", recipientUserId)
      .orderBy("createdAt", "desc")
      .limit(MAX_INBOX_PER_USER + 30)
      .get();

    if (snap.size <= MAX_INBOX_PER_USER) return;

    const overflow = snap.docs.slice(MAX_INBOX_PER_USER);
    const batch = db.batch();
    for (const doc of overflow) {
      batch.delete(doc.ref);
    }
    await batch.commit();
    logger.info("inbox pruned", {
      recipientUserId,
      deleted: overflow.length,
    });
  } catch (e) {
    // Index may be building; never fail the notification path.
    logger.warn("inbox prune skipped", { message: e.message });
  }
}

async function sendPush({ tokens, title, body, data }) {
  if (!tokens.length) {
    logger.info("No FCM tokens for recipient");
    return;
  }
  const res = await getMessaging().sendEachForMulticast({
    tokens,
    notification: { title, body },
    data,
    android: {
      priority: "high",
      notification: { channelId: "cafein_default" },
    },
  });
  logger.info(`FCM sent success=${res.successCount} failure=${res.failureCount}`);
}

/** New comment under posts/{postId}/comments/{commentId} */
exports.onCommentCreated = onDocumentCreated(
  "posts/{postId}/comments/{commentId}",
  async (event) => {
    const snap = event.data;
    if (!snap) return;
    const comment = snap.data() || {};
    const postId = event.params.postId;
    const commentId = event.params.commentId;
    const actorId = (comment.authorId || comment.kakaoUserId || "").trim();

    const postSnap = await db.collection("posts").doc(postId).get();
    if (!postSnap.exists) return;
    const post = postSnap.data() || {};
    const recipientId = (post.authorId || "").trim();

    // 1) Self-action: my comment on my post → no inbox / no push
    if (!recipientId || !actorId || sameUid(recipientId, actorId)) {
      logger.info("comment self-action skipped", { postId, actorId, recipientId });
      return;
    }

    const { tokens, settings } = await tokensForUser(recipientId);
    if (settings.comment === false) {
      logger.info("comment notification disabled for recipient");
      return;
    }

    const actorNickname = await resolveActorNickname(
      actorId,
      comment.authorNickname || comment.nickname || comment.author
    );
    const postPreview = makePostPreview(postContentFromData(post));
    const message = buildSocialMessage({
      type: "comment",
      actorNickname,
      preview: postPreview,
    });
    const inbox = await writeInbox({
      recipientUserId: recipientId,
      actorUserId: actorId,
      actorNickname,
      type: "comment",
      postId,
      commentId,
      message,
      postPreview,
    });
    if (inbox.skipped || inbox.duplicated) return;

    await sendPush({
      tokens,
      title: "카페인",
      body: message,
      data: {
        type: "comment",
        postId: String(postId),
        commentId: String(commentId),
      },
    });
    logger.info("comment notification requested");
  }
);

/** New like doc posts/{postId}/likes/{userId} — only on create (not unlike) */
exports.onLikeCreated = onDocumentCreated(
  "posts/{postId}/likes/{userId}",
  async (event) => {
    const snap = event.data;
    if (!snap) return;
    const like = snap.data() || {};
    const postId = event.params.postId;
    const actorId = (
      event.params.userId ||
      like.userId ||
      like.kakaoUserId ||
      ""
    ).trim();

    const postSnap = await db.collection("posts").doc(postId).get();
    if (!postSnap.exists) return;
    const post = postSnap.data() || {};
    const recipientId = (post.authorId || "").trim();

    // 1) Self-action: liked my own post
    if (!recipientId || !actorId || sameUid(recipientId, actorId)) {
      logger.info("like self-action skipped", { postId, actorId, recipientId });
      return;
    }

    const { tokens, settings } = await tokensForUser(recipientId);
    if (settings.like === false) {
      logger.info("like notification disabled for recipient");
      return;
    }

    const actorNickname = await resolveActorNickname(actorId);
    const postPreview = makePostPreview(postContentFromData(post));
    const message = buildSocialMessage({
      type: "like",
      actorNickname,
      preview: postPreview,
    });
    const inbox = await writeInbox({
      recipientUserId: recipientId,
      actorUserId: actorId,
      actorNickname,
      type: "like",
      postId,
      commentId: "",
      message,
      postPreview,
    });
    // Unread duplicate (unlike→like spam): bump only, no extra push
    if (inbox.skipped || inbox.duplicated) return;

    await sendPush({
      tokens,
      title: "카페인",
      body: message,
      data: {
        type: "like",
        postId: String(postId),
      },
    });
    logger.info("like notification requested");
  }
);

/** New comment-like doc posts/{postId}/comments/{commentId}/likes/{userId} */
exports.onCommentLikeCreated = onDocumentCreated(
  "posts/{postId}/comments/{commentId}/likes/{userId}",
  async (event) => {
    const snap = event.data;
    if (!snap) return;
    const like = snap.data() || {};
    const postId = event.params.postId;
    const commentId = event.params.commentId;
    const actorId = (
      event.params.userId ||
      like.userId ||
      like.kakaoUserId ||
      ""
    ).trim();

    const commentSnap = await db
      .collection("posts")
      .doc(postId)
      .collection("comments")
      .doc(commentId)
      .get();
    if (!commentSnap.exists) return;
    const comment = commentSnap.data() || {};
    const recipientId = (comment.authorId || "").trim();

    // 1) Self-action: liked my own comment
    if (!recipientId || !actorId || sameUid(recipientId, actorId)) {
      logger.info("comment-like self-action skipped", {
        postId,
        commentId,
        actorId,
        recipientId,
      });
      return;
    }

    const { tokens, settings } = await tokensForUser(recipientId);
    if (settings.like === false) {
      logger.info("comment like notification disabled for recipient");
      return;
    }

    const actorNickname = await resolveActorNickname(actorId);
    // Preview = liked comment content (not parent post).
    const commentPreview = makePostPreview(
      comment.content != null ? String(comment.content) : ""
    );
    const message = buildSocialMessage({
      type: "comment_like",
      actorNickname,
      preview: commentPreview,
    });
    const inbox = await writeInbox({
      recipientUserId: recipientId,
      actorUserId: actorId,
      actorNickname,
      type: "comment_like",
      postId,
      commentId,
      message,
      commentPreview,
    });
    if (inbox.skipped || inbox.duplicated) return;

    await sendPush({
      tokens,
      title: "카페인",
      body: message,
      data: {
        type: "comment_like",
        postId: String(postId),
        commentId: String(commentId),
      },
    });
    logger.info("comment like notification requested");
  }
);

/**
 * Report moderation result → inbox + FCM (reuse writeInbox / sendPush).
 * Fires when a report is resolved with content_deleted or user_warned.
 * Idempotent via reports.reporterNotified / reportedUserNotified.
 */
exports.onReportUpdated = onDocumentUpdated(
  "reports/{reportId}",
  async (event) => {
    const beforeSnap = event.data.before;
    const afterSnap = event.data.after;
    if (!beforeSnap || !afterSnap) return;

    const after = afterSnap.data() || {};
    const reportId = event.params.reportId;
    const action = (after.action || "").trim();

    if (
      after.status !== "resolved" ||
      (action !== "content_deleted" && action !== "user_warned")
    ) {
      return;
    }

    const reporterId = (after.reporterId || "").trim();
    const targetAuthorId = (after.targetAuthorId || "").trim();
    const targetType = (after.targetType || "").trim().toLowerCase();
    const reviewedBy = (after.reviewedBy || "").trim() || "cafein_ops";

    // Actor must not equal recipient or writeInbox self-filters.
    const actorId =
      sameUid(reviewedBy, reporterId) || sameUid(reviewedBy, targetAuthorId)
        ? "cafein_ops"
        : reviewedBy;

    const reporterTitle = "신고가 처리되었습니다.";
    const reporterMessage =
      "신고하신 내용을 운영자가 확인하고 처리했습니다.";

    let reportedTitle;
    let reportedMessage;
    if (action === "user_warned") {
      reportedTitle = "운영정책 관련 안내";
      reportedMessage =
        "신고된 콘텐츠를 검토한 결과 운영정책에 따라 경고 조치되었습니다.";
    } else if (targetType === "comment") {
      reportedTitle = "댓글이 운영정책에 따라 처리되었습니다.";
      reportedMessage =
        "신고된 콘텐츠를 검토한 결과 운영정책에 따라 해당 콘텐츠가 삭제되었습니다.";
    } else {
      reportedTitle = "게시글이 운영정책에 따라 처리되었습니다.";
      reportedMessage =
        "신고된 콘텐츠를 검토한 결과 운영정책에 따라 해당 콘텐츠가 삭제되었습니다.";
    }

    const updates = {};

    // ── Reporter (generic — never expose sanction details) ──
    if (reporterId && after.reporterNotified !== true) {
      try {
        const { tokens } = await tokensForUser(reporterId);
        const inbox = await writeInbox({
          recipientUserId: reporterId,
          actorUserId: actorId,
          type: "report_result",
          postId: reportId,
          commentId: "reporter",
          message: reporterMessage,
        });
        if (inbox.skipped === "no_recipient") {
          logger.warn("report_result reporter no recipient", { reportId });
        } else {
          if (!inbox.skipped && !inbox.duplicated) {
            await sendPush({
              tokens,
              title: reporterTitle,
              body: reporterMessage,
              data: {
                type: "report_result",
                reportId: String(reportId),
                audience: "reporter",
                targetType: String(targetType || ""),
                action: String(action),
              },
            });
            logger.info("report_result reporter notification requested", {
              reportId,
              reporterId,
              action,
            });
          } else {
            logger.info("report_result reporter inbox skipped/duplicated", {
              reportId,
              inbox,
            });
          }
          updates.reporterNotified = true;
        }
      } catch (e) {
        logger.error("report_result reporter notify failed", {
          reportId,
          message: e.message,
        });
      }
    }

    // ── Reported author ──
    // content_deleted: post/comment only (user wipe not implemented)
    // user_warned: any target with targetAuthorId (content stays)
    const canNotifyReportedContentDeleted =
      action === "content_deleted" &&
      (targetType === "post" || targetType === "comment") &&
      targetAuthorId.length > 0 &&
      !sameUid(reporterId, targetAuthorId) &&
      after.reportedUserNotified !== true;

    const canNotifyReportedWarned =
      action === "user_warned" &&
      targetAuthorId.length > 0 &&
      !sameUid(reporterId, targetAuthorId) &&
      after.reportedUserNotified !== true;

    const canNotifyReported =
      canNotifyReportedContentDeleted || canNotifyReportedWarned;

    if (canNotifyReported) {
      try {
        const { tokens } = await tokensForUser(targetAuthorId);
        const inbox = await writeInbox({
          recipientUserId: targetAuthorId,
          actorUserId: actorId,
          type: "report_result",
          postId: reportId,
          commentId: "reported",
          message: reportedMessage,
        });
        if (inbox.skipped === "no_recipient") {
          logger.warn("report_result reported no recipient", { reportId });
        } else {
          if (!inbox.skipped && !inbox.duplicated) {
            await sendPush({
              tokens,
              title: reportedTitle,
              body: reportedMessage,
              data: {
                type: "report_result",
                reportId: String(reportId),
                audience: "reported",
                targetType: String(targetType || ""),
                action: String(action),
              },
            });
            logger.info("report_result reported notification requested", {
              reportId,
              targetAuthorId,
              action,
            });
          } else {
            logger.info("report_result reported inbox skipped/duplicated", {
              reportId,
              inbox,
            });
          }
          updates.reportedUserNotified = true;
        }
      } catch (e) {
        logger.error("report_result reported notify failed", {
          reportId,
          message: e.message,
        });
      }
    } else if (
      action === "content_deleted" &&
      targetType === "user" &&
      after.reportedUserNotified !== true
    ) {
      logger.info("report_result skip reported user (user target / TODO)", {
        reportId,
      });
      updates.reportedUserNotified = true;
    } else if (
      sameUid(reporterId, targetAuthorId) &&
      after.reportedUserNotified !== true
    ) {
      // Self-report: only reporter message; avoid duplicate to same user.
      updates.reportedUserNotified = true;
    }

    if (Object.keys(updates).length > 0) {
      try {
        await afterSnap.ref.set(
          {
            ...updates,
            updatedAt: new Date(),
          },
          { merge: true }
        );
      } catch (e) {
        logger.error("report notified flags update failed", {
          reportId,
          message: e.message,
        });
      }
    }
  }
);

