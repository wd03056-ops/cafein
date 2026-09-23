/**
 * Topic usageCount — derived from posts.topicId via Firestore triggers.
 *
 * Client must NOT increment/decrement usageCount.
 * Idempotency: topic_usage_ledger/{postId} tracks the applied topicId
 * (or cleared:true after delete) so at-least-once delivery does not
 * double-count.
 *
 * IMPORTANT: Firestore transactions require ALL reads before ANY writes.
 * A→B updates must read both topic docs before writing either count.
 */
const { getFirestore, FieldValue } = require("firebase-admin/firestore");
const {
  onDocumentCreated,
  onDocumentUpdated,
  onDocumentDeleted,
} = require("firebase-functions/v2/firestore");
const { logger } = require("firebase-functions");

const LEDGER = "topic_usage_ledger";

function normTopicId(value) {
  if (value == null) return "";
  return String(value).trim();
}

function readCount(data) {
  const n = data && data.usageCount;
  const parsed = typeof n === "number" ? n : parseInt(String(n), 10);
  if (!Number.isFinite(parsed) || parsed < 0) return 0;
  return Math.floor(parsed);
}

/**
 * Apply usage deltas inside an open transaction.
 * Caller must NOT have written yet; this function reads then writes.
 *
 * @param {FirebaseFirestore.Transaction} tx
 * @param {FirebaseFirestore.Firestore} db
 * @param {string} decrementId
 * @param {string} incrementId
 */
async function applyUsageDeltasInTx(tx, db, decrementId, incrementId) {
  const decId = normTopicId(decrementId);
  const incId = normTopicId(incrementId);

  /** @type {FirebaseFirestore.DocumentReference|null} */
  let decRef = null;
  /** @type {FirebaseFirestore.DocumentSnapshot|null} */
  let decSnap = null;
  /** @type {FirebaseFirestore.DocumentReference|null} */
  let incRef = null;
  /** @type {FirebaseFirestore.DocumentSnapshot|null} */
  let incSnap = null;

  // ---- ALL READS ----
  if (decId) {
    decRef = db.collection("topics").doc(decId);
    decSnap = await tx.get(decRef);
  }
  if (incId) {
    if (incId === decId) {
      incRef = decRef;
      incSnap = decSnap;
    } else {
      incRef = db.collection("topics").doc(incId);
      incSnap = await tx.get(incRef);
    }
  }

  // ---- ALL WRITES ----
  if (decId && decRef && decSnap && decSnap.exists && incId !== decId) {
    const current = readCount(decSnap.data());
    tx.update(decRef, {
      usageCount: Math.max(0, current - 1),
      updatedAt: FieldValue.serverTimestamp(),
    });
  } else if (decId && (!decSnap || !decSnap.exists)) {
    logger.warn("topic missing for usageCount -1", { topicId: decId });
  }

  if (incId && incRef && incSnap && incSnap.exists) {
    const current = readCount(incSnap.data());
    if (incId !== decId) {
      tx.update(incRef, {
        usageCount: current + 1,
        updatedAt: FieldValue.serverTimestamp(),
      });
    }
  } else if (incId) {
    // ensureTopic should have created the doc before post write; fail so
    // the trigger retries instead of advancing the ledger without +1.
    throw new Error(`topic missing for usageCount +1: ${incId}`);
  }
}

/**
 * @param {string} region
 */
function createTopicUsageTriggers(region) {
  const db = getFirestore();

  const onPostCreated = onDocumentCreated(
    { region, document: "posts/{postId}" },
    async (event) => {
      const postId = event.params.postId;
      const data = event.data?.data() || {};
      const topicId = normTopicId(data.topicId);
      if (!topicId) return;

      try {
        await db.runTransaction(async (tx) => {
          const ledgerRef = db.collection(LEDGER).doc(postId);
          const ledger = await tx.get(ledgerRef);
          if (ledger.exists) {
            return;
          }
          await applyUsageDeltasInTx(tx, db, "", topicId);
          tx.set(ledgerRef, {
            topicId,
            updatedAt: FieldValue.serverTimestamp(),
          });
        });
        logger.info("topic usage +1 (create)", { postId, topicId });
      } catch (e) {
        logger.error("topic usage create failed", {
          postId,
          topicId,
          message: e && e.message,
        });
        throw e;
      }
    },
  );

  const onPostUpdated = onDocumentUpdated(
    { region, document: "posts/{postId}" },
    async (event) => {
      const postId = event.params.postId;
      const before = event.data?.before?.data() || {};
      const after = event.data?.after?.data() || {};
      // Flutter writes posts.topicId (string doc id) + topicName (display).
      const beforeId = normTopicId(before.topicId);
      const afterId = normTopicId(after.topicId);
      if (beforeId === afterId) return;

      try {
        await db.runTransaction(async (tx) => {
          const ledgerRef = db.collection(LEDGER).doc(postId);
          const ledger = await tx.get(ledgerRef);

          if (ledger.exists && ledger.data().cleared === true) {
            return;
          }

          // Ledger = last applied topic for this post (not a skip-all flag).
          const ledgerTopic = ledger.exists
            ? normTopicId(ledger.data().topicId)
            : beforeId;

          // Idempotent retry: already moved to afterId.
          if (ledgerTopic === afterId) {
            if (!ledger.exists && afterId) {
              tx.set(ledgerRef, {
                topicId: afterId,
                updatedAt: FieldValue.serverTimestamp(),
              });
            }
            return;
          }

          // Decrement whatever the ledger currently says we counted
          // (falls back to beforeId for legacy posts without ledger).
          await applyUsageDeltasInTx(tx, db, ledgerTopic, afterId);

          if (afterId) {
            tx.set(ledgerRef, {
              topicId: afterId,
              updatedAt: FieldValue.serverTimestamp(),
            });
          } else if (ledger.exists) {
            tx.delete(ledgerRef);
          } else {
            // Legacy clear with no ledger: nothing to delete.
          }
        });
        logger.info("topic usage move (update)", {
          postId,
          beforeId,
          afterId,
        });
      } catch (e) {
        logger.error("topic usage update failed", {
          postId,
          beforeId,
          afterId,
          message: e && e.message,
        });
        throw e;
      }
    },
  );

  const onPostDeleted = onDocumentDeleted(
    { region, document: "posts/{postId}" },
    async (event) => {
      const postId = event.params.postId;
      const data = event.data?.data() || {};
      const eventTopicId = normTopicId(data.topicId);

      try {
        await db.runTransaction(async (tx) => {
          const ledgerRef = db.collection(LEDGER).doc(postId);
          const ledger = await tx.get(ledgerRef);

          if (ledger.exists && ledger.data().cleared === true) {
            return;
          }

          let tid = "";
          if (ledger.exists) {
            tid = normTopicId(ledger.data().topicId);
          } else {
            tid = eventTopicId;
          }

          await applyUsageDeltasInTx(tx, db, tid, "");

          tx.set(ledgerRef, {
            cleared: true,
            topicId: tid || null,
            updatedAt: FieldValue.serverTimestamp(),
          });
        });
        logger.info("topic usage -1 (delete)", {
          postId,
          topicId: eventTopicId,
        });
      } catch (e) {
        logger.error("topic usage delete failed", {
          postId,
          message: e && e.message,
        });
        throw e;
      }
    },
  );

  return { onPostCreated, onPostUpdated, onPostDeleted };
}

module.exports = { createTopicUsageTriggers };
