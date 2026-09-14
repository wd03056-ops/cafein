import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/post.dart';
import '../models/topic.dart';
import 'topics_firestore_service.dart';

/// Firestore-backed feed for the `posts` collection.
class PostsFirestoreService {
  PostsFirestoreService._();
  static final PostsFirestoreService instance = PostsFirestoreService._();

  final _firestore = FirebaseFirestore.instance;
  final _topics = TopicsFirestoreService.instance;

  CollectionReference<Map<String, dynamic>> get _posts =>
      _firestore.collection('posts');

  /// Latest posts first (`createdAt` descending).
  Stream<List<Post>> watchPosts() {
    return _posts
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(_mapDocs);
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
        .map(_mapDocs);
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
        .map(_mapDocs);
  }

  /// One-shot fetch for topic feeds (supports client-side popular sort).
  Future<List<Post>> fetchPostsByTopicId(String topicId) async {
    final id = topicId.trim();
    if (id.isEmpty) return const [];
    final snap = await _posts
        .where('topicId', isEqualTo: id)
        .orderBy('createdAt', descending: true)
        .get();
    return _mapDocs(snap);
  }

  List<Post> _mapDocs(QuerySnapshot<Map<String, dynamic>> snapshot) {
    return snapshot.docs.map((doc) {
      return Post.fromFirestore(doc.id, doc.data());
    }).toList();
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
  }) async {
    final text = content.trim();
    if (text.isEmpty) {
      throw ArgumentError('내용이 비어 있어요.');
    }

    String profileImage = authorProfileImage.trim();
    if (profileImage.isEmpty) {
      try {
        final userDoc =
            await _firestore.collection('users').doc(authorId).get();
        profileImage =
            (userDoc.data()?['profileImage'] as String?)?.trim() ?? '';
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
    );
  }

  /// Update content / topic / poll-related fields on an existing post.
  Future<Post> updatePost({
    required String postId,
    required String content,
    String? topicName,
    bool clearTopic = false,
  }) async {
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

    final batch = _firestore.batch();
    batch.update(ref, {
      'content': text,
      'topicId': nextTopicId,
      'topicName': nextTopicName,
      'tags': topicTags,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    final oldId = current.topicId?.trim();
    final newId = nextTopicId?.trim();
    if (oldId != newId) {
      if (oldId != null && oldId.isNotEmpty) {
        // Safe decrement via transaction after batch would race; do after.
      }
      if (newId != null && newId.isNotEmpty) {
        batch.set(
          _firestore.collection('topics').doc(newId),
          {
            'usageCount': FieldValue.increment(1),
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      }
    }

    await batch.commit();

    if (oldId != null &&
        oldId.isNotEmpty &&
        oldId != newId) {
      await _topics.decrementUsage(oldId);
    }

    return current.copyWith(
      content: text,
      topicId: nextTopicId,
      topicName: nextTopicName,
      tags: topicTags,
      clearTopic: clearTopic,
    );
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

  /// Delete post and decrement its topic usage.
  Future<void> deletePost(String postId) async {
    final ref = _posts.doc(postId);
    final snap = await ref.get();
    if (!snap.exists) return;
    final data = snap.data();
    final topicId = (data?['topicId'] as String?)?.trim();

    await ref.delete();
    if (topicId != null && topicId.isNotEmpty) {
      await _topics.decrementUsage(topicId);
    }
  }
}
