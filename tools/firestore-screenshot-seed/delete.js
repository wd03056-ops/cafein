/**
 * Delete CAFEIN Play Store screenshot seed from Firestore.
 *
 * Usage:
 *   npm run delete
 *
 * Removes fixed screenshot_* ids and any docs with seedTag.
 * Does NOT run from the Flutter app.
 */

const admin = require('firebase-admin');
const { SEED_TAG, TOPICS, POSTS, topicNameKey, buildManifest } = require('./data');

function initAdmin() {
  if (admin.apps.length) return admin.firestore();

  const projectId =
    process.env.GCLOUD_PROJECT ||
    process.env.GOOGLE_CLOUD_PROJECT ||
    process.env.FIREBASE_PROJECT_ID ||
    'truestory-9eb36';

  try {
    admin.initializeApp({
      credential: admin.credential.applicationDefault(),
      projectId,
    });
  } catch (e) {
    console.error(
      'firebase-admin init failed. Set GOOGLE_APPLICATION_CREDENTIALS to a service account JSON.',
    );
    throw e;
  }
  return admin.firestore();
}

async function deleteCollectionDocs(db, collectionPath, ids) {
  for (const id of ids) {
    const ref = db.collection(collectionPath).doc(id);
    const snap = await ref.get();
    if (snap.exists) {
      await ref.delete();
      console.log(`[delete] ${collectionPath}/${id}`);
    }
  }
}

async function deleteCommentsForPost(db, postId, commentIds) {
  for (const commentId of commentIds) {
    const ref = db
      .collection('posts')
      .doc(postId)
      .collection('comments')
      .doc(commentId);
    const snap = await ref.get();
    if (snap.exists) {
      await ref.delete();
      console.log(`[delete] posts/${postId}/comments/${commentId}`);
    }
  }

  // Also wipe any leftover comments under the post (seedTag match).
  const leftover = await db
    .collection('posts')
    .doc(postId)
    .collection('comments')
    .where('seedTag', '==', SEED_TAG)
    .get();
  for (const doc of leftover.docs) {
    await doc.ref.delete();
    console.log(`[delete] posts/${postId}/comments/${doc.id} (seedTag)`);
  }
}

async function deleteBySeedTag(db, collection) {
  const snap = await db
    .collection(collection)
    .where('seedTag', '==', SEED_TAG)
    .get();
  for (const doc of snap.docs) {
    if (collection === 'posts') {
      const comments = await doc.ref.collection('comments').get();
      for (const c of comments.docs) {
        await c.ref.delete();
      }
    }
    await doc.ref.delete();
    console.log(`[delete] ${collection}/${doc.id} (seedTag query)`);
  }
}

async function main() {
  const db = initAdmin();
  const manifest = buildManifest();

  console.log(`[delete] tag=${SEED_TAG}`);

  // Comments then posts (fixed ids)
  for (const post of POSTS) {
    await deleteCommentsForPost(
      db,
      post.id,
      (post.comments || []).map((c) => c.id),
    );
  }
  await deleteCollectionDocs(db, 'posts', manifest.posts);

  // Topics + topic_names written by seed (only if seedTag or screenshot_ topicId)
  for (const topic of TOPICS) {
    const key = topicNameKey(topic.name);
    const nameRef = db.collection('topic_names').doc(key);
    const nameSnap = await nameRef.get();
    if (nameSnap.exists) {
      const data = nameSnap.data() || {};
      const tid = (data.topicId || '').trim();
      if (data.seedTag === SEED_TAG || tid === topic.id) {
        await nameRef.delete();
        console.log(`[delete] topic_names/${key}`);
      } else {
        console.log(
          `[delete] skip topic_names/${key} (owned by topicId=${tid})`,
        );
      }
    }
  }
  await deleteCollectionDocs(db, 'topics', manifest.topics);

  // Sweep any leftover tagged docs
  await deleteBySeedTag(db, 'posts');
  await deleteBySeedTag(db, 'topics');

  const taggedNames = await db
    .collection('topic_names')
    .where('seedTag', '==', SEED_TAG)
    .get();
  for (const doc of taggedNames.docs) {
    await doc.ref.delete();
    console.log(`[delete] topic_names/${doc.id} (seedTag)`);
  }

  console.log('[delete] done');
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
