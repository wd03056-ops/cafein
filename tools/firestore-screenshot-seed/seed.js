/**
 * Write CAFEIN Play Store screenshot seed into Firestore.
 *
 * Usage (from this folder):
 *   npm install
 *   set GOOGLE_APPLICATION_CREDENTIALS=path\to\serviceAccount.json
 *   npm run seed
 *
 * Does NOT run from the Flutter app.
 */

const fs = require('fs');
const path = require('path');
const admin = require('firebase-admin');
const {
  SEED_TAG,
  TOPICS,
  POSTS,
  topicNameKey,
  buildManifest,
} = require('./data');

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

function hoursAgo(hours) {
  return new Date(Date.now() - hours * 60 * 60 * 1000);
}

function minutesAgo(minutes) {
  return new Date(Date.now() - minutes * 60 * 1000);
}

async function seed() {
  const db = initAdmin();
  const manifest = buildManifest();

  console.log(`[seed] tag=${SEED_TAG}`);
  console.log(
    `[seed] topics=${manifest.topics.length} posts=${manifest.posts.length} ` +
      `comments=${manifest.comments.length} polls=${manifest.pollPostIds.length}`,
  );

  // ── Topics ──
  for (const topic of TOPICS) {
    const key = topicNameKey(topic.name);
    const topicRef = db.collection('topics').doc(topic.id);
    const nameRef = db.collection('topic_names').doc(key);

    const existingName = await nameRef.get();
    if (existingName.exists) {
      const existingId = (existingName.data()?.topicId || '').trim();
      if (existingId && existingId !== topic.id) {
        if (!existingId.startsWith('screenshot_')) {
          console.warn(
            `[seed] WARN topic_names/${key} already points to production topicId=${existingId}. ` +
              `Skipping topic_names write; posts still use ${topic.id}.`,
          );
        } else {
          await nameRef.set(
            {
              topicId: topic.id,
              name: topic.name,
              updatedAt: admin.firestore.Timestamp.fromDate(new Date()),
              seedTag: SEED_TAG,
            },
            { merge: true },
          );
        }
      } else {
        await nameRef.set(
          {
            topicId: topic.id,
            name: topic.name,
            updatedAt: admin.firestore.Timestamp.fromDate(new Date()),
            seedTag: SEED_TAG,
          },
          { merge: true },
        );
      }
    } else {
      await nameRef.set({
        topicId: topic.id,
        name: topic.name,
        updatedAt: admin.firestore.Timestamp.fromDate(new Date()),
        seedTag: SEED_TAG,
      });
    }

    const createdAt = hoursAgo(80);
    await topicRef.set({
      name: topic.name,
      nameKey: key,
      usageCount: topic.usageCount,
      createdAt: admin.firestore.Timestamp.fromDate(createdAt),
      updatedAt: admin.firestore.Timestamp.fromDate(new Date()),
      seedTag: SEED_TAG,
    });
    console.log(`[seed] topic ${topic.id} (${topic.name})`);
  }

  // ── Posts + comments ──
  for (const post of POSTS) {
    const author = post.author;
    const created = hoursAgo(post.hoursAgo);
    const commentCount = (post.comments || []).length;

    const postData = {
      content: post.content,
      authorId: author.id,
      authorNickname: author.nickname,
      nickname: author.nickname,
      authorProfileImage: '',
      experience: author.experience,
      cafeType: author.cafeType,
      likeCount: post.likeCount,
      commentCount,
      likedBy: {},
      createdAt: admin.firestore.Timestamp.fromDate(created),
      updatedAt: admin.firestore.Timestamp.fromDate(created),
      tags: [post.topicName],
      topicId: post.topicId,
      topicName: post.topicName,
      pollVoters: {},
      seedTag: SEED_TAG,
    };

    if (post.poll) {
      postData.poll = {
        question: post.poll.question,
        options: post.poll.options.map((o) => ({
          id: o.id,
          text: o.text,
          voteCount: o.voteCount,
        })),
      };
    }

    await db.collection('posts').doc(post.id).set(postData);
    console.log(
      `[seed] post ${post.id} topic=${post.topicName} comments=${commentCount}` +
        (post.poll ? ' [poll]' : ''),
    );

    for (const c of post.comments || []) {
      const cAuthor = c.author;
      const cCreated = minutesAgo(c.minutesAgo);
      await db
        .collection('posts')
        .doc(post.id)
        .collection('comments')
        .doc(c.id)
        .set({
          content: c.content,
          authorId: cAuthor.id,
          authorNickname: cAuthor.nickname,
          authorProfileImage: '',
          experience: cAuthor.experience,
          cafeType: cAuthor.cafeType,
          likeCount: c.likeCount,
          likedBy: {},
          createdAt: admin.firestore.Timestamp.fromDate(cCreated),
          updatedAt: admin.firestore.Timestamp.fromDate(cCreated),
          seedTag: SEED_TAG,
        });
    }
  }

  const manifestPath = path.join(__dirname, 'MANIFEST.generated.json');
  fs.writeFileSync(manifestPath, JSON.stringify(manifest, null, 2), 'utf8');
  console.log(`[seed] wrote ${manifestPath}`);
  console.log('[seed] done. Run `npm run delete` later to remove these docs.');
}

seed().catch((err) => {
  console.error(err);
  process.exit(1);
});
