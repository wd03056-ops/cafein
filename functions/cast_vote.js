/**
 * Callable castVote — atomic poll vote via Admin SDK transaction.
 *
 * Client must NOT write pollVoters / poll.options[].voteCount directly.
 * Auth uid = Kakao user id (Custom Token). Client-sent userId is ignored.
 */
const { getFirestore, FieldValue } = require("firebase-admin/firestore");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { logger } = require("firebase-functions");

/**
 * @param {string} region
 * @returns {import("firebase-functions/v2/https").CallableFunction}
 */
function createCastVoteCallable(region) {
  return onCall({ region }, async (request) => {
    if (!request.auth || !request.auth.uid) {
      throw new HttpsError("unauthenticated", "Sign-in required to vote.");
    }

    const uid = String(request.auth.uid).trim();
    if (!uid) {
      throw new HttpsError("unauthenticated", "Sign-in required to vote.");
    }

    const postId = (request.data?.postId || "").toString().trim();
    const optionId = (request.data?.optionId || "").toString().trim();
    // Intentionally ignore request.data.userId / any client uid.

    if (!postId || !optionId) {
      throw new HttpsError(
        "invalid-argument",
        "postId and optionId are required.",
      );
    }

    const db = getFirestore();
    const postRef = db.collection("posts").doc(postId);

    try {
      const result = await db.runTransaction(async (tx) => {
        const snap = await tx.get(postRef);
        if (!snap.exists) {
          throw new HttpsError("not-found", "Post not found.");
        }

        const data = snap.data() || {};
        const rawPoll = data.poll;
        if (!rawPoll || typeof rawPoll !== "object" || Array.isArray(rawPoll)) {
          throw new HttpsError(
            "failed-precondition",
            "This post has no poll.",
          );
        }

        const pollMap = { ...rawPoll };
        const rawOptions = pollMap.options;
        if (!Array.isArray(rawOptions) || rawOptions.length === 0) {
          throw new HttpsError(
            "failed-precondition",
            "Poll has no options.",
          );
        }

        const options = [];
        for (const item of rawOptions) {
          if (!item || typeof item !== "object" || Array.isArray(item)) {
            throw new HttpsError(
              "failed-precondition",
              "Invalid poll options.",
            );
          }
          options.push({ ...item });
        }

        const hasOption = options.some(
          (o) => String(o.id || "").trim() === optionId,
        );
        if (!hasOption) {
          throw new HttpsError(
            "invalid-argument",
            "Unknown poll option.",
          );
        }

        const rawVoters = data.pollVoters;
        /** @type {Record<string, string>} */
        const voters = {};
        if (rawVoters != null) {
          if (typeof rawVoters !== "object" || Array.isArray(rawVoters)) {
            throw new HttpsError(
              "failed-precondition",
              "Invalid pollVoters.",
            );
          }
          for (const [key, value] of Object.entries(rawVoters)) {
            const k = String(key).trim();
            if (!k) continue;
            voters[k] = value == null ? "" : String(value).trim();
          }
        }

        const previousId = (voters[uid] || "").trim() || null;

        const readCount = (option) => {
          const n = option.voteCount ?? option.votes;
          const parsed = typeof n === "number" ? n : parseInt(String(n), 10);
          if (!Number.isFinite(parsed) || parsed < 0) return 0;
          return Math.floor(parsed);
        };

        const writeOptions = (mutator) => {
          for (const option of options) {
            const id = String(option.id || "").trim();
            let count = readCount(option);
            count = mutator(id, count);
            if (count < 0) count = 0;
            option.voteCount = count;
            delete option.votes;
          }
          pollMap.options = options;
        };

        /** @type {string|null} */
        let selectedOptionId;

        if (previousId === optionId) {
          // Same option again → cancel.
          writeOptions((id, count) => (id === optionId ? count - 1 : count));
          delete voters[uid];
          selectedOptionId = null;
        } else {
          writeOptions((id, count) => {
            let next = count;
            if (previousId && id === previousId) next = count - 1;
            if (id === optionId) next = count + 1;
            return next;
          });
          voters[uid] = optionId;
          selectedOptionId = optionId;
        }

        tx.update(postRef, {
          poll: pollMap,
          pollVoters: voters,
          updatedAt: FieldValue.serverTimestamp(),
        });

        return {
          success: true,
          postId,
          selectedOptionId,
          options: options.map((o) => ({
            id: String(o.id || "").trim(),
            text: String(o.text || "").trim(),
            voteCount: readCount(o),
          })),
        };
      });

      logger.info("castVote success", {
        postId,
        uid,
        selectedOptionId: result.selectedOptionId,
      });
      return result;
    } catch (e) {
      if (e instanceof HttpsError) throw e;
      logger.error("castVote failed", {
        postId,
        uid,
        message: e && e.message,
      });
      throw new HttpsError("internal", "Failed to cast vote.");
    }
  });
}

module.exports = { createCastVoteCallable };
