/**
 * Callable withdrawAccount — sever post/comment authorship on withdrawal.
 *
 * Admin SDK remaps authorId → deleted_<id> so the same Kakao UID cannot
 * reclaim old content after rejoin. Client must not change authorId (Rules).
 *
 * Auth: request.auth.uid only. Client-sent uid is ignored.
 * Does NOT delete Firebase Auth users or unlink Kakao (client-side).
 */
const crypto = require("crypto");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { logger } = require("firebase-functions");

const ANONYMIZED_NICKNAME = "탈퇴한 사용자";
const BATCH_LIMIT = 400;

/**
 * @param {string} region
 * @returns {import("firebase-functions/v2/https").CallableFunction}
 */
function createWithdrawAccountCallable(region) {
  return onCall({ region }, async (request) => {
    if (!request.auth || !request.auth.uid) {
      throw new HttpsError("unauthenticated", "Sign-in required to withdraw.");
    }

    const uid = String(request.auth.uid).trim();
    if (!uid) {
      throw new HttpsError("unauthenticated", "Sign-in required to withdraw.");
    }

    const db = getFirestore();
    const deletedId = newDeletedAuthorId(uid);

    logger.info("withdrawAccount start", {
      uid,
      deletedIdPrefix: deletedId.slice(0, 16),
    });

    try {
      const postsUpdated = await anonymizePosts(db, uid, deletedId);
      const commentsUpdated = await anonymizeComments(db, uid, deletedId);
      await deleteBlocksByBlocker(db, uid);
      await deleteNotificationsForRecipient(db, uid);
      await deleteNicknameOwnedBy(db, uid);
      await deleteUserDoc(db, uid);

      logger.info("withdrawAccount success", {
        uid,
        deletedIdPrefix: deletedId.slice(0, 16),
        postsUpdated,
        commentsUpdated,
      });

      return {
        success: true,
        deletedId,
        postsUpdated,
        commentsUpdated,
      };
    } catch (e) {
      if (e instanceof HttpsError) throw e;
      logger.error("withdrawAccount failed", {
        uid,
        message: e && e.message ? e.message : String(e),
      });
      throw new HttpsError("internal", "Account withdrawal failed.");
    }
  });
}

/**
 * @param {string} uid
 * @returns {string}
 */
function newDeletedAuthorId(uid) {
  let id;
  do {
    id = `deleted_${crypto.randomUUID().replace(/-/g, "")}`;
  } while (id === uid);
  return id;
}

/**
 * @param {FirebaseFirestore.Firestore} db
 * @param {string} uid
 * @param {string} deletedId
 * @returns {Promise<number>}
 */
async function anonymizePosts(db, uid, deletedId) {
  const snap = await db.collection("posts").where("authorId", "==", uid).get();
  if (snap.empty) return 0;

  let batch = db.batch();
  let ops = 0;
  let updated = 0;

  for (const doc of snap.docs) {
    batch.update(doc.ref, {
      authorId: deletedId,
      authorWithdrawn: true,
      authorNickname: ANONYMIZED_NICKNAME,
      nickname: ANONYMIZED_NICKNAME,
      authorProfileImage: "",
      updatedAt: FieldValue.serverTimestamp(),
    });
    ops += 1;
    updated += 1;
    if (ops >= BATCH_LIMIT) {
      await batch.commit();
      batch = db.batch();
      ops = 0;
    }
  }
  if (ops > 0) await batch.commit();
  return updated;
}

/**
 * @param {FirebaseFirestore.Firestore} db
 * @param {string} uid
 * @param {string} deletedId
 * @returns {Promise<number>}
 */
async function anonymizeComments(db, uid, deletedId) {
  const snap = await db
    .collectionGroup("comments")
    .where("authorId", "==", uid)
    .get();
  if (snap.empty) return 0;

  let batch = db.batch();
  let ops = 0;
  let updated = 0;

  for (const doc of snap.docs) {
    batch.update(doc.ref, {
      authorId: deletedId,
      authorWithdrawn: true,
      authorNickname: ANONYMIZED_NICKNAME,
      authorProfileImage: "",
      updatedAt: FieldValue.serverTimestamp(),
    });
    ops += 1;
    updated += 1;
    if (ops >= BATCH_LIMIT) {
      await batch.commit();
      batch = db.batch();
      ops = 0;
    }
  }
  if (ops > 0) await batch.commit();
  return updated;
}

/**
 * @param {FirebaseFirestore.Firestore} db
 * @param {string} uid
 */
async function deleteBlocksByBlocker(db, uid) {
  // Idempotent: empty pages → done.
  // eslint-disable-next-line no-constant-condition
  while (true) {
    const page = await db
      .collection("blocks")
      .where("blockerId", "==", uid)
      .limit(200)
      .get();
    if (page.empty) break;
    const batch = db.batch();
    for (const doc of page.docs) {
      batch.delete(doc.ref);
    }
    await batch.commit();
  }
}

/**
 * @param {FirebaseFirestore.Firestore} db
 * @param {string} uid
 */
async function deleteNotificationsForRecipient(db, uid) {
  // eslint-disable-next-line no-constant-condition
  while (true) {
    const page = await db
      .collection("notifications")
      .where("recipientUserId", "==", uid)
      .limit(200)
      .get();
    if (page.empty) break;
    const batch = db.batch();
    for (const doc of page.docs) {
      batch.delete(doc.ref);
    }
    await batch.commit();
  }
}

/**
 * Delete nicknames/{nick} when owned by uid. Reads users.nickname first.
 * @param {FirebaseFirestore.Firestore} db
 * @param {string} uid
 */
async function deleteNicknameOwnedBy(db, uid) {
  let nickname = "";
  try {
    const userSnap = await db.collection("users").doc(uid).get();
    if (userSnap.exists) {
      const data = userSnap.data() || {};
      nickname = String(data.nickname || "").trim();
    }
  } catch (e) {
    logger.warn("withdrawAccount: read users for nickname failed", {
      uid,
      message: e && e.message ? e.message : String(e),
    });
  }

  if (!nickname) return;

  try {
    const nickRef = db.collection("nicknames").doc(nickname);
    const nickSnap = await nickRef.get();
    if (!nickSnap.exists) return;
    const owner = String((nickSnap.data() || {}).uid || "").trim();
    if (owner === uid) {
      await nickRef.delete();
    }
  } catch (e) {
    logger.warn("withdrawAccount: nickname delete failed", {
      uid,
      message: e && e.message ? e.message : String(e),
    });
  }
}

/**
 * @param {FirebaseFirestore.Firestore} db
 * @param {string} uid
 */
async function deleteUserDoc(db, uid) {
  const ref = db.collection("users").doc(uid);
  const snap = await ref.get();
  if (!snap.exists) return;
  await ref.delete();
}

module.exports = {
  createWithdrawAccountCallable,
  ANONYMIZED_NICKNAME,
};
