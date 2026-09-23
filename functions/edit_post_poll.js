/**
 * Callable editPostPoll — author may change poll question/options safely.
 *
 * Preserves voteCount for matching option ids; prunes pollVoters for removed
 * options. Client must NOT write poll / pollVoters / voteCount on post update.
 */
const { getFirestore, FieldValue } = require("firebase-admin/firestore");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { logger } = require("firebase-functions");

function norm(value) {
  if (value == null) return "";
  return String(value).trim();
}

function readCount(option) {
  const n = option.voteCount ?? option.votes;
  const parsed = typeof n === "number" ? n : parseInt(String(n), 10);
  if (!Number.isFinite(parsed) || parsed < 0) return 0;
  return Math.floor(parsed);
}

/**
 * @param {string} region
 */
function createEditPostPollCallable(region) {
  return onCall({ region }, async (request) => {
    if (!request.auth || !request.auth.uid) {
      throw new HttpsError("unauthenticated", "Sign-in required.");
    }
    const uid = String(request.auth.uid).trim();
    const postId = norm(request.data?.postId);
    if (!postId) {
      throw new HttpsError("invalid-argument", "postId is required.");
    }

    const clearPoll = request.data?.clearPoll === true;
    const rawPoll = request.data?.poll;

    if (!clearPoll && (rawPoll == null || typeof rawPoll !== "object")) {
      throw new HttpsError(
        "invalid-argument",
        "poll object or clearPoll:true is required.",
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
        if (norm(data.authorId) !== uid) {
          throw new HttpsError(
            "permission-denied",
            "Only the post author can edit the poll.",
          );
        }

        if (clearPoll) {
          tx.update(postRef, {
            poll: FieldValue.delete(),
            pollVoters: FieldValue.delete(),
            updatedAt: FieldValue.serverTimestamp(),
          });
          return { success: true, cleared: true, poll: null };
        }

        const question = norm(rawPoll.question);
        const title = norm(rawPoll.title);
        const rawOptions = rawPoll.options;
        if (!question) {
          throw new HttpsError("invalid-argument", "poll.question required.");
        }
        if (!Array.isArray(rawOptions) || rawOptions.length < 2) {
          throw new HttpsError(
            "invalid-argument",
            "poll needs at least 2 options.",
          );
        }

        const previousById = {};
        const existingPoll = data.poll;
        if (existingPoll && typeof existingPoll === "object") {
          const prevOpts = existingPoll.options;
          if (Array.isArray(prevOpts)) {
            for (const o of prevOpts) {
              if (!o || typeof o !== "object") continue;
              const id = norm(o.id);
              if (id) previousById[id] = o;
            }
          }
        }

        const nextOptions = [];
        const seen = new Set();
        for (let i = 0; i < rawOptions.length; i++) {
          const item = rawOptions[i];
          if (!item || typeof item !== "object") {
            throw new HttpsError("invalid-argument", "Invalid poll option.");
          }
          const text = norm(item.text);
          if (!text) continue;
          let id = norm(item.id);
          if (!id) id = `opt_${i}`;
          if (seen.has(id)) {
            throw new HttpsError("invalid-argument", "Duplicate option id.");
          }
          seen.add(id);
          const prev = previousById[id];
          nextOptions.push({
            id,
            text,
            voteCount: prev ? readCount(prev) : 0,
          });
        }
        if (nextOptions.length < 2) {
          throw new HttpsError(
            "invalid-argument",
            "poll needs at least 2 non-empty options.",
          );
        }

        const validIds = new Set(nextOptions.map((o) => o.id));
        const voters = {};
        const rawVoters = data.pollVoters;
        if (rawVoters && typeof rawVoters === "object" && !Array.isArray(rawVoters)) {
          for (const [key, value] of Object.entries(rawVoters)) {
            const k = norm(key);
            const optId = norm(value);
            if (k && optId && validIds.has(optId)) {
              voters[k] = optId;
            }
          }
        }

        const pollMap = {
          question,
          options: nextOptions,
        };
        if (title) pollMap.title = title;

        tx.update(postRef, {
          poll: pollMap,
          pollVoters: voters,
          updatedAt: FieldValue.serverTimestamp(),
        });

        return {
          success: true,
          cleared: false,
          poll: pollMap,
          pollVoters: voters,
        };
      });

      logger.info("editPostPoll success", {
        postId,
        uid,
        cleared: result.cleared === true,
      });
      return result;
    } catch (e) {
      if (e instanceof HttpsError) throw e;
      logger.error("editPostPoll failed", {
        postId,
        uid,
        message: e && e.message,
      });
      throw new HttpsError("internal", "Failed to edit poll.");
    }
  });
}

module.exports = { createEditPostPollCallable };
