import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/poll.dart';
import '../models/post.dart';
import '../models/topic.dart';
import 'auth_service.dart';
import 'topics_firestore_service.dart';

/// Firestore-backed feed for the `posts` collection.
class PostsFirestoreService {
  PostsFirestoreService._();
  static final PostsFirestoreService instance = PostsFirestoreService._();

  final _firestore = FirebaseFirestore.instance;
  final _topics = TopicsFirestoreService.instance;

  CollectionReference<Map<String, dynamic>> get _posts =>
      _firestore.collection('posts');

  CollectionReference<Map<String, dynamic>> _votesRef(String postId) =>
      _posts.doc(postId).collection('poll_votes');

  CollectionReference<Map<String, dynamic>> _likesRef(String postId) =>
      _posts.doc(postId).collection('likes');

  CollectionReference<Map<String, dynamic>> _commentsRef(String postId) =>
      _posts.doc(postId).collection('comments');

  /// Latest posts first (`createdAt` descending).
  Stream<List<Post>> watchPosts() {
    return _posts
        .orderBy('createdAt', descending: true)
        .snapshots()
        .asyncMap((snap) => _mapAndEnrich(snap));
  }

  /// Posts written by [authorId], newest first.
  Stream<List<Post>> watchPostsByAuthor(String authorId) {
    final uid = authorId.trim();
    if (uid.isEmpty) {
      return Stream.value(const []);
    }
    return _posts
        .where('authorId', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .asyncMap((snap) => _mapAndEnrich(snap));
  }

  /// Posts for a topic id, newest first.
  Stream<List<Post>> watchPostsByTopicId(String topicId) {
    final id = topicId.trim();
    if (id.isEmpty) {
      return Stream.value(const []);
    }
    return _posts
        .where('topicId', isEqualTo: id)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .asyncMap((snap) => _mapAndEnrich(snap));
  }

  /// One-shot fetch for topic feeds (supports client-side popular sort).
  Future<List<Post>> fetchPostsByTopicId(String topicId) async {
    final id = topicId.trim();
    if (id.isEmpty) return const [];
    final snap = await _posts
        .where('topicId', isEqualTo: id)
        .orderBy('createdAt', descending: true)
        .get();
    return _mapAndEnrich(snap);
  }

  Future<List<Post>> _mapAndEnrich(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) async {
    final uid = AuthService.instance.kakaoUserId?.trim();
    final posts = snapshot.docs.map((doc) {
      final data = doc.data();
      var post = Post.fromFirestore(doc.id, data);
      if (uid != null && uid.isNotEmpty && post.poll != null) {
        final rawVoters = data['pollVoters'];
        if (rawVoters is Map) {
          final optionId = rawVoters[uid]?.toString().trim();
          post = post.copyWith(
            poll: post.poll!.withMyVote(
              (optionId != null && optionId.isNotEmpty) ? optionId : null,
            ),
          );
        }
      }
      return post;
    }).toList();
    return enrichWithMyLikes(posts);
  }

  /// Attach my vote + like flags for the signed-in user.
  Future<List<Post>> enrichPosts(List<Post> posts) async {
    var next = await enrichWithMyVotes(posts);
    next = await enrichWithMyLikes(next);
    return next;
  }

  /// Attach hasVoted from post `pollVoters.{auth.uid}` (or legacy poll_votes).
  Future<List<Post>> enrichWithMyVotes(List<Post> posts) async {
    final uid = AuthService.instance.kakaoUserId?.trim();
    if (uid == null || uid.isEmpty) return posts;

    final indexed = <int, Post>{};
    final futures = <Future<void>>[];

    for (var i = 0; i < posts.length; i++) {
      final post = posts[i];
      if (post.poll == null) {
        indexed[i] = post;
        continue;
      }
      // Prefer vote already applied from pollVoters during mapping.
      if (post.poll!.hasVoted) {
        indexed[i] = post;
        continue;
      }
      futures.add(() async {
        try {
          // Legacy fallback: posts/{id}/poll_votes/{uid}
          final voteSnap = await _votesRef(post.id).doc(uid).get();
          final optionId =
              (voteSnap.data()?['optionId'] as String?)?.trim();
          indexed[i] = post.copyWith(
            poll: post.poll!.withMyVote(voteSnap.exists ? optionId : null),
          );
        } catch (e) {
          debugPrint('투표 상태 조회 실패 (${post.id}): $e');
          indexed[i] = post;
        }
      }());
    }

    await Future.wait(futures);
    return [
      for (var i = 0; i < posts.length; i++) indexed[i] ?? posts[i],
    ];
  }

  /// Attach likedByMe from `likes/{kakaoUserId}`.
  Future<List<Post>> enrichWithMyLikes(List<Post> posts) async {
    final uid = AuthService.instance.kakaoUserId?.trim();
    if (uid == null || uid.isEmpty) return posts;
    if (posts.isEmpty) return posts;

    final indexed = <int, Post>{};
    final futures = <Future<void>>[];

    for (var i = 0; i < posts.length; i++) {
      final post = posts[i];
      futures.add(() async {
        try {
          final likeSnap = await _likesRef(post.id).doc(uid).get();
          indexed[i] = post.copyWith(likedByMe: likeSnap.exists);
        } catch (e) {
          debugPrint('공감 상태 조회 실패 (${post.id}): $e');
          indexed[i] = post;
        }
      }());
    }

    await Future.wait(futures);
    return [
      for (var i = 0; i < posts.length; i++) indexed[i] ?? posts[i],
    ];
  }

  Future<Post?> getPost(String postId) async {
    final snap = await _posts.doc(postId).get();
    if (!snap.exists || snap.data() == null) return null;
    final data = snap.data()!;
    var post = Post.fromFirestore(snap.id, data);
    final uid = AuthService.instance.kakaoUserId?.trim();
    if (uid != null && uid.isNotEmpty && post.poll != null) {
      final rawVoters = data['pollVoters'];
      if (rawVoters is Map) {
        final optionId = rawVoters[uid]?.toString().trim();
        post = post.copyWith(
          poll: post.poll!.withMyVote(
            (optionId != null && optionId.isNotEmpty) ? optionId : null,
          ),
        );
      }
    }
    final enriched = await enrichPosts([post]);
    return enriched.first;
  }

  /// Same-topic posts for "비슷한 글". Excludes [excludePostId].
  Future<List<Post>> fetchSimilarPosts({
    required String topicId,
    required String excludePostId,
    int limit = 5,
  }) async {
    final tid = topicId.trim();
    if (tid.isEmpty) return const [];

    final snap = await _posts
        .where('topicId', isEqualTo: tid)
        .orderBy('createdAt', descending: true)
        .limit(24)
        .get();

    final posts = snap.docs
        .map((doc) => Post.fromFirestore(doc.id, doc.data()))
        .where((p) => p.id != excludePostId)
        .toList();

    posts.sort((a, b) {
      final byLikes = b.likeCount.compareTo(a.likeCount);
      if (byLikes != 0) return byLikes;
      return b.createdAt.compareTo(a.createdAt);
    });

    final capped = posts.take(limit).toList();
    return enrichPosts(capped);
  }

  /// Toggle like. Doc id = Kakao user id (1 like / user / post).
  Future<Post> toggleLike({
    required String postId,
    String? userId,
  }) async {
    AuthService.instance.requireKakaoWriter();
    final uid = (userId ?? AuthService.instance.kakaoUserId)?.trim() ?? '';
    if (uid.isEmpty) {
      throw StateError('카카오 로그인 후 이용해 주세요.');
    }

    await _firestore.runTransaction((tx) async {
      final postRef = _posts.doc(postId);
      final likeRef = _likesRef(postId).doc(uid);
      final postSnap = await tx.get(postRef);
      final likeSnap = await tx.get(likeRef);

      if (!postSnap.exists || postSnap.data() == null) {
        throw StateError('글을 찾을 수 없어요.');
      }

      if (likeSnap.exists) {
        final current =
            (postSnap.data()?['likeCount'] as num?)?.toInt() ?? 0;
        tx.delete(likeRef);
        tx.update(postRef, {
          'likeCount': (current - 1).clamp(0, 1 << 30),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } else {
        tx.set(likeRef, {
          'userId': uid,
          'postId': postId,
          'kakaoUserId': uid,
          'createdAt': FieldValue.serverTimestamp(),
        });
        tx.update(postRef, {
          'likeCount': FieldValue.increment(1),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    });

    final refreshed = await getPost(postId);
    if (refreshed == null) {
      throw StateError('공감 후 글을 불러오지 못했어요.');
    }
    return refreshed;
  }

  /// Create a post. Resolves/creates topic and increments usage on success.
  Future<Post> createPost({
    required String content,
    required String authorId,
    required String authorNickname,
    String authorProfileImage = '',
    String? experience,
    String? cafeType,
    String? topicName,
    List<String> tags = const [],
    Poll? poll,
  }) async {
    AuthService.instance.requireKakaoWriter();

    final text = content.trim();
    if (text.isEmpty) {
      throw ArgumentError('내용이 비어 있어요.');
    }

    String profileImage = authorProfileImage.trim();
    if (profileImage.isEmpty) {
      final profileUid = authorId.trim().isNotEmpty
          ? authorId.trim()
          : (AuthService.instance.kakaoUserId?.trim() ?? '');
      try {
        if (profileUid.isNotEmpty) {
          final userDoc =
              await _firestore.collection('users').doc(profileUid).get();
          profileImage =
              (userDoc.data()?['profileImage'] as String?)?.trim() ?? '';
        }
      } catch (e) {
        debugPrint('프로필 이미지 조회 실패: $e');
      }
    }

    Topic? topic;
    final rawTopic = (topicName ?? (tags.isNotEmpty ? tags.first : null));
    if (rawTopic != null && normalizeTopicName(rawTopic).isNotEmpty) {
      topic = await _topics.ensureTopic(rawTopic);
    }

    final doc = _posts.doc();
    final nickname =
        authorNickname.trim().isEmpty ? '익명' : authorNickname.trim();
    final topicTags =
        topic == null ? const <String>[] : <String>[topic.name];

    Poll? storedPoll;
    if (poll != null &&
        poll.question.trim().isNotEmpty &&
        poll.options.length >= 2) {
      storedPoll = Poll(
        question: poll.question.trim(),
        options: [
          for (var i = 0; i < poll.options.length; i++)
            PollOption(
              id: poll.options[i].id.trim().isEmpty
                  ? 'opt_$i'
                  : poll.options[i].id.trim(),
              text: poll.options[i].text.trim(),
              votes: 0,
            ),
        ],
      );
    }

    final data = <String, dynamic>{
      'content': text,
      'authorId': authorId,
      'authorNickname': nickname,
      'nickname': nickname,
      'authorProfileImage': profileImage,
      'experience': experience ?? '',
      'cafeType': cafeType ?? '',
      'likeCount': 0,
      'commentCount': 0,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'tags': topicTags,
    };

    if (topic != null) {
      data['topicId'] = topic.id;
      data['topicName'] = topic.name;
    } else {
      data['topicId'] = null;
      data['topicName'] = null;
    }

    if (storedPoll != null) {
      data['poll'] = storedPoll.toMap();
    }

    final batch = _firestore.batch();
    batch.set(doc, data);
    if (topic != null) {
      batch.set(
        _firestore.collection('topics').doc(topic.id),
        {
          'usageCount': FieldValue.increment(1),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    }
    await batch.commit();

    return Post(
      id: doc.id,
      content: text,
      createdAt: DateTime.now(),
      author: nickname,
      authorId: authorId,
      authorProfileImage: profileImage,
      experience: experience,
      cafeType: cafeType,
      tags: topicTags,
      topicId: topic?.id,
      topicName: topic?.name,
      remoteCommentCount: 0,
      poll: storedPoll,
    );
  }

  /// Cast or change a vote.
  ///
  /// Vote records live on the post doc (`pollVoters.{auth.uid}`) so they
  /// work under rules that only allow `posts/{postId}` (no `poll_votes`).
  Future<Post> castVote({
    required String postId,
    required String optionId,
    String? userId,
  }) async {
    AuthService.instance.requireKakaoWriter();
    final uid = (userId ?? AuthService.instance.kakaoUserId)?.trim() ?? '';
    final optId = optionId.trim();
    if (uid.isEmpty || optId.isEmpty) {
      throw ArgumentError('투표 정보가 올바르지 않아요.');
    }

    await _firestore.runTransaction((tx) async {
      final postRef = _posts.doc(postId);
      final postSnap = await tx.get(postRef);

      if (!postSnap.exists || postSnap.data() == null) {
        throw StateError('글을 찾을 수 없어요.');
      }

      final data = Map<String, dynamic>.from(postSnap.data()!);
      final rawPoll = data['poll'];
      if (rawPoll is! Map) {
        throw StateError('이 글에는 투표가 없어요.');
      }
      final pollMap = Map<String, dynamic>.from(rawPoll);
      final rawOptions = pollMap['options'];
      if (rawOptions is! List || rawOptions.isEmpty) {
        throw StateError('투표 선택지가 없어요.');
      }

      final options = <Map<String, dynamic>>[
        for (final item in rawOptions)
          if (item is Map) Map<String, dynamic>.from(item),
      ];

      final hasOption =
          options.any((o) => (o['id'] as String?)?.trim() == optId);
      if (!hasOption) {
        throw StateError('존재하지 않는 선택지예요.');
      }

      final voters = <String, dynamic>{};
      final rawVoters = data['pollVoters'];
      if (rawVoters is Map) {
        rawVoters.forEach((key, value) {
          voters['$key'] = value;
        });
      }

      final previousId = (voters[uid] as String?)?.trim();
      if (previousId == optId) {
        return;
      }

      for (final option in options) {
        final id = (option['id'] as String?)?.trim();
        final current = (option['voteCount'] as num?)?.toInt() ??
            (option['votes'] as num?)?.toInt() ??
            0;
        var next = current;
        if (previousId != null && id == previousId) {
          next = (current - 1).clamp(0, 1 << 30);
        }
        if (id == optId) {
          next = current + 1;
        }
        option['voteCount'] = next;
        option.remove('votes');
      }

      pollMap['options'] = options;
      voters[uid] = optId;

      tx.update(postRef, {
        'poll': pollMap,
        'pollVoters': voters,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });

    final refreshed = await getPost(postId);
    if (refreshed == null) {
      throw StateError('투표 후 글을 불러오지 못했어요.');
    }
    return refreshed;
  }

  /// Update content / topic. Does not reset an existing poll with votes.
  Future<Post> updatePost({
    required String postId,
    required String content,
    String? topicName,
    bool clearTopic = false,
    Poll? poll,
    bool setPollIfMissing = false,
  }) async {
    AuthService.instance.requireKakaoWriter();

    final text = content.trim();
    if (text.isEmpty) {
      throw ArgumentError('내용이 비어 있어요.');
    }

    final ref = _posts.doc(postId);
    final snap = await ref.get();
    if (!snap.exists || snap.data() == null) {
      throw StateError('글을 찾을 수 없어요.');
    }
    final current = Post.fromFirestore(snap.id, snap.data()!);

    String? nextTopicId;
    String? nextTopicName;
    final topicTags = <String>[];

    if (clearTopic) {
      nextTopicId = null;
      nextTopicName = null;
    } else if (topicName != null &&
        normalizeTopicName(topicName).isNotEmpty) {
      final topic = await _topics.ensureTopic(topicName);
      nextTopicId = topic.id;
      nextTopicName = topic.name;
      topicTags.add(topic.name);
    } else {
      nextTopicId = current.topicId;
      nextTopicName = current.topicName ?? current.topic;
      if (nextTopicName != null) topicTags.add(nextTopicName);
    }

    final updates = <String, dynamic>{
      'content': text,
      'topicId': nextTopicId,
      'topicName': nextTopicName,
      'tags': topicTags,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    // Only attach a new poll when the post had none (never wipe votes).
    Poll? nextPoll = current.poll;
    if (setPollIfMissing &&
        current.poll == null &&
        poll != null &&
        poll.question.trim().isNotEmpty &&
        poll.options.length >= 2) {
      nextPoll = Poll(
        question: poll.question.trim(),
        options: [
          for (var i = 0; i < poll.options.length; i++)
            PollOption(
              id: poll.options[i].id.trim().isEmpty
                  ? 'opt_$i'
                  : poll.options[i].id.trim(),
              text: poll.options[i].text.trim(),
              votes: 0,
            ),
        ],
      );
      updates['poll'] = nextPoll.toMap();
    }

    await ref.update(updates);

    final oldId = current.topicId?.trim();
    final newId = nextTopicId?.trim();
    if (oldId != newId && newId != null && newId.isNotEmpty) {
      await _topics.incrementUsage(newId);
    }

    if (oldId != null && oldId.isNotEmpty && oldId != newId) {
      await _topics.decrementUsage(oldId);
    }

    final updated = current.copyWith(
      content: text,
      topicId: nextTopicId,
      topicName: nextTopicName,
      tags: topicTags,
      clearTopic: clearTopic,
      poll: nextPoll,
    );
    final enriched = await enrichPosts([updated]);
    return enriched.first;
  }

  /// Change only the topic of a post.
  Future<Post> updatePostTopic({
    required String postId,
    String? topicName,
  }) async {
    final clear = topicName == null || normalizeTopicName(topicName).isEmpty;
    final snap = await _posts.doc(postId).get();
    if (!snap.exists || snap.data() == null) {
      throw StateError('글을 찾을 수 없어요.');
    }
    final current = Post.fromFirestore(snap.id, snap.data()!);
    return updatePost(
      postId: postId,
      content: current.content,
      topicName: clear ? null : topicName,
      clearTopic: clear,
    );
  }

  /// Delete post + comments + likes. Does not delete Topic docs.
  Future<void> deletePost(String postId) async {
    AuthService.instance.requireKakaoWriter();

    final ref = _posts.doc(postId);
    final snap = await ref.get();
    if (!snap.exists) return;
    final data = snap.data();
    final topicId = (data?['topicId'] as String?)?.trim();

    await _deleteSubcollectionDocs(_commentsRef(postId));
    await _deleteSubcollectionDocs(_likesRef(postId));
    await _deleteSubcollectionDocs(_votesRef(postId));

    await ref.delete();
    if (topicId != null && topicId.isNotEmpty) {
      try {
        await _topics.decrementUsage(topicId);
      } catch (e) {
        debugPrint('주제 usageCount 감소 실패: $e');
      }
    }
  }

  Future<void> _deleteSubcollectionDocs(
    CollectionReference<Map<String, dynamic>> col,
  ) async {
    try {
      QuerySnapshot<Map<String, dynamic>> page;
      do {
        page = await col.limit(200).get();
        if (page.docs.isEmpty) break;
        final batch = _firestore.batch();
        for (final doc in page.docs) {
          batch.delete(doc.reference);
        }
        await batch.commit();
      } while (page.docs.isNotEmpty);
    } catch (e) {
      debugPrint('서브컬렉션 삭제 실패 (${col.path}): $e');
    }
  }
}
