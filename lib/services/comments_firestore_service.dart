import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/comment.dart';

/// Firestore comments under `posts/{postId}/comments`.
class CommentsFirestoreService {
  CommentsFirestoreService._();
  static final CommentsFirestoreService instance = CommentsFirestoreService._();

  final _firestore = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _commentsRef(String postId) {
    return _firestore.collection('posts').doc(postId).collection('comments');
  }

  /// Oldest → newest.
  Stream<List<Comment>> watchComments(String postId) {
    return _commentsRef(postId)
        .orderBy('createdAt', descending: false)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        return Comment.fromFirestore(
          id: doc.id,
          postId: postId,
          data: doc.data(),
        );
      }).toList();
    });
  }

  Future<void> addComment({
    required String postId,
    required String content,
    required String authorId,
    required String authorNickname,
    String authorProfileImage = '',
  }) async {
    final text = content.trim();
    if (text.isEmpty) {
      throw ArgumentError('댓글 내용이 비어 있어요.');
    }
    if (authorId.trim().isEmpty) {
      throw ArgumentError('로그인이 필요해요.');
    }

    final nickname = authorNickname.trim().isEmpty
        ? '익명'
        : authorNickname.trim();

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

    final batch = _firestore.batch();
    final commentRef = _commentsRef(postId).doc();
    batch.set(commentRef, {
      'content': text,
      'authorId': authorId,
      'authorNickname': nickname,
      'authorProfileImage': profileImage,
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.update(_firestore.collection('posts').doc(postId), {
      'commentCount': FieldValue.increment(1),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    try {
      await batch.commit();
    } on FirebaseException catch (e) {
      // Post doc may not exist yet (local-only posts) — still save comment.
      if (e.code == 'not-found') {
        await commentRef.set({
          'content': text,
          'authorId': authorId,
          'authorNickname': nickname,
          'authorProfileImage': profileImage,
          'createdAt': FieldValue.serverTimestamp(),
        });
        return;
      }
      rethrow;
    }
  }
}
