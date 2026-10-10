/**
 * Callable createReviewerCustomToken — Google Play review account sign-in.
 *
 * Issues a Firebase Custom Token for the fixed reviewer uid only after the
 * client sends the server-configured access code. Never grants admin claims.
 *
 * Params (functions/.env, never commit):
 *   REVIEWER_LOGIN_ENABLED=true
 *   REVIEWER_ACCESS_CODE=<long random code shared only via Play Console "App access">
 */
const crypto = require("crypto");
const { getAuth } = require("firebase-admin/auth");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { defineString } = require("firebase-functions/params");
const { logger } = require("firebase-functions");

const REVIEWER_UID = "google_reviewer";
const REVIEWER_EMAIL = "reviewer@test.com";
const REVIEWER_NICKNAME = "구글심사관";
const REVIEWER_CAFE_TYPE = "개인카페";
const REVIEWER_EXPERIENCE = "1~3년";
const MIN_ACCESS_CODE_LENGTH = 12;

const REVIEWER_LOGIN_ENABLED = defineString("REVIEWER_LOGIN_ENABLED", {
  default: "false",
  description: "Set to true to allow Play reviewer sign-in.",
});

const REVIEWER_ACCESS_CODE = defineString("REVIEWER_ACCESS_CODE", {
  default: "",
  description: "Access code given to Google Play reviewers (App access).",
});

/**
 * @param {string} a
 * @param {string} b
 * @returns {boolean}
 */
function codesMatch(a, b) {
  const left = crypto.createHash("sha256").update(a, "utf8").digest();
  const right = crypto.createHash("sha256").update(b, "utf8").digest();
  return crypto.timingSafeEqual(left, right);
}

/**
 * Seed users/{REVIEWER_UID} + nicknames/{nick} so the reviewer skips
 * onboarding. Keeps an existing reviewer nickname if already claimed.
 * @param {FirebaseFirestore.Firestore} db
 * @returns {Promise<{nickname: string, cafeType: string, experience: string}>}
 */
async function ensureReviewerProfile(db) {
  const userRef = db.collection("users").doc(REVIEWER_UID);

  return db.runTransaction(async (tx) => {
    const userSnap = await tx.get(userRef);
    const data = userSnap.exists ? userSnap.data() || {} : {};

    let nickname = String(data.nickname || "").trim();
    const cafeType = String(data.cafeType || "").trim() || REVIEWER_CAFE_TYPE;
    const experience =
      String(data.experience || "").trim() || REVIEWER_EXPERIENCE;

    if (!nickname) {
      nickname = REVIEWER_NICKNAME;
      const nickRef = db.collection("nicknames").doc(nickname);
      const nickSnap = await tx.get(nickRef);
      const owner = nickSnap.exists
        ? String((nickSnap.data() || {}).uid || "").trim()
        : "";
      if (owner && owner !== REVIEWER_UID) {
        throw new HttpsError(
          "failed-precondition",
          "Reviewer nickname is already taken by another user.",
        );
      }
      tx.set(nickRef, {
        uid: REVIEWER_UID,
        nickname,
        updatedAt: FieldValue.serverTimestamp(),
      });
    }

    const profile = {
      kakaoUserId: REVIEWER_UID,
      nickname,
      cafeType,
      experience,
      email: REVIEWER_EMAIL,
      kakaoNickname: REVIEWER_NICKNAME,
      profileImage: "",
      updatedAt: FieldValue.serverTimestamp(),
    };
    if (!userSnap.exists) {
      profile.createdAt = FieldValue.serverTimestamp();
    }
    tx.set(userRef, profile, { merge: true });

    return { nickname, cafeType, experience };
  });
}

/**
 * @param {string} region
 * @returns {import("firebase-functions/v2/https").CallableFunction}
 */
function createReviewerLoginCallable(region) {
  return onCall({ region }, async (request) => {
    const enabled =
      String(REVIEWER_LOGIN_ENABLED.value() || "").trim().toLowerCase() ===
      "true";
    const expected = String(REVIEWER_ACCESS_CODE.value() || "").trim();

    if (!enabled || expected.length < MIN_ACCESS_CODE_LENGTH) {
      logger.warn("createReviewerCustomToken: disabled or not configured");
      throw new HttpsError(
        "failed-precondition",
        "Reviewer sign-in is not available.",
      );
    }

    const provided = String(request.data?.accessCode || "").trim();
    if (!provided || !codesMatch(provided, expected)) {
      logger.warn("createReviewerCustomToken: invalid access code");
      throw new HttpsError("permission-denied", "Invalid access code.");
    }

    const db = getFirestore();
    let profile;
    try {
      profile = await ensureReviewerProfile(db);
    } catch (e) {
      if (e instanceof HttpsError) throw e;
      logger.error("createReviewerCustomToken: profile seed failed", {
        message: e && e.message ? e.message : String(e),
      });
      throw new HttpsError("internal", "Failed to prepare reviewer account.");
    }

    try {
      // No admin claim — reviewer is a regular community user.
      const customToken = await getAuth().createCustomToken(REVIEWER_UID, {
        reviewer: true,
      });
      logger.info("createReviewerCustomToken success", { uid: REVIEWER_UID });
      return {
        customToken,
        uid: REVIEWER_UID,
        nickname: profile.nickname,
        cafeType: profile.cafeType,
        experience: profile.experience,
      };
    } catch (e) {
      logger.error("createReviewerCustomToken: token failed", {
        message: e && e.message ? e.message : String(e),
      });
      throw new HttpsError("internal", "Failed to create reviewer token.");
    }
  });
}

module.exports = {
  createReviewerLoginCallable,
  REVIEWER_UID,
};
