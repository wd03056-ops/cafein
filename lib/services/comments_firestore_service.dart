import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/comment.dart';
import 'auth_service.dart';

/// Firestore comments under `posts/{postId}/comments`.
class CommentsFirestoreService {
  CommentsFirestoreService._();
  static final CommentsFirestoreService instance = CommentsFirestoreService._();

  final _firestore = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _commentsRef(String postId) {
    return _firestore.collection('posts').doc(postId).collection('comments');
  }

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
    AuthService.instance.requireKakaoWriter();

    final text = content.trim();
    if (text.isEmpty) {
      throw ArgumentError('댓글 내용이 비어 있어요.');
    }
    if (authorId.trim().isEmpty) {
      throw ArgumentError('로그인이 필요해요.');
    }

    final nickname =
        authorNickname.trim().isEmpty ? '익명' : authorNickname.trim();

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
      'updatedAt': FieldValue.serverTimestamp(),
    });
    batch.update(_firestore.collection('posts').doc(postId), {
      'commentCount': FieldValue.increment(1),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    try {
      await batch.commit();
    } on FirebaseException catch (e) {
      if (e.code == 'not-found') {
        await commentRef.set({
          'content': text,
          'authorId': authorId,
          'authorNickname': nickname,
          'authorProfileImage': profileImage,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        return;
      }
      rethrow;
    }
  }

  /// Owner-only delete. Decrements post `commentCount` (never below 0).
  Future<void> deleteComment({
    required String postId,
    required String commentId,
  }) async {
    AuthService.instance.requireKakaoWriter();
    final uid = AuthService.instance.kakaoUserId?.trim() ?? '';
    if (uid.isEmpty) {
      throw StateError('로그인이 필요해요.');
    }

    final commentRef = _commentsRef(postId).doc(commentId);
    final postRef = _firestore.collection('posts').doc(postId);

    await _firestore.runTransaction((tx) async {
      final commentSnap = await tx.get(commentRef);
      if (!commentSnap.exists || commentSnap.data() == null) {
        throw StateError('댓글을 찾을 수 없어요.');
      }
      final authorId =
          (commentSnap.data()?['authorId'] as String?)?.trim() ?? '';
      if (authorId != uid) {
        throw StateError('본인 댓글만 삭제할 수 있어요.');
      }

      final postSnap = await tx.get(postRef);
      final current =
          (postSnap.data()?['commentCount'] as num?)?.toInt() ?? 0;

      tx.delete(commentRef);
      if (postSnap.exists) {
        tx.update(postRef, {
          'commentCount': (current - 1).clamp(0, 1 << 30),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    });
  }
}
