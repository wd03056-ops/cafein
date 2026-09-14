import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/post.dart';

/// Firestore-backed feed for the `posts` collection.
class PostsFirestoreService {
  PostsFirestoreService._();
  static final PostsFirestoreService instance = PostsFirestoreService._();

  final _firestore = FirebaseFirestore.instance;

  /// Latest posts first (`createdAt` descending).
  Stream<List<Post>> watchPosts() {
    return _firestore
        .collection('posts')
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
    return _firestore
        .collection('posts')
        .where('authorId', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(_mapDocs);
  }

  List<Post> _mapDocs(QuerySnapshot<Map<String, dynamic>> snapshot) {
    return snapshot.docs.map((doc) {
      return Post.fromFirestore(doc.id, doc.data());
    }).toList();
  }

  /// Create a post document and return the local [Post] model.
  Future<Post> createPost({
    required String content,
    required String authorId,
    required String authorNickname,
    String authorProfileImage = '',
    String? experience,
    String? cafeType,
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

    final doc = _firestore.collection('posts').doc();
    final nickname =
        authorNickname.trim().isEmpty ? '익명' : authorNickname.trim();
    final cleanedTags = tags
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList();

    await doc.set({
      'content': text,
      'authorId': authorId,
      'authorNickname': nickname,
      'nickname': nickname,
      'authorProfileImage': profileImage,
      'experience': experience ?? '',
      'cafeType': cafeType ?? '',
      'tags': cleanedTags,
      'likeCount': 0,
      'commentCount': 0,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    return Post(
      id: doc.id,
      content: text,
      createdAt: DateTime.now(),
      author: nickname,
      authorId: authorId,
      authorProfileImage: profileImage,
      experience: experience,
      cafeType: cafeType,
      tags: cleanedTags,
      remoteCommentCount: 0,
    );
  }
}
