import 'package:flutter/material.dart';

import '../models/comment.dart';
import '../screens/auth_required_screen.dart';
import 'auth_service.dart';
import 'comments_firestore_service.dart';

/// In-flight comment like locks (per commentId) — does not block other comments.
final Set<String> _pendingCommentLikes = <String>{};

Future<bool> _ensureKakaoWriter(BuildContext context) async {
  final auth = AuthService.instance;
  if (auth.canWriteContent) return true;

  final ready = await AuthRequiredScreen.ensureWriter(context);
  if (!ready || !context.mounted) return false;
  return auth.canWriteContent;
}

/// Comment like toggle — same Kakao gate as post likes.
Future<Comment?> toggleCommentLike(
  BuildContext context, {
  required Comment comment,
}) async {
  return toggleCommentLikeOptimistic(context, comment: comment);
}

/// Optimistic comment like with rollback. Returns final comment, or null
/// if auth cancelled / locked / failed (UI already rolled back on fail).
Future<Comment?> toggleCommentLikeOptimistic(
  BuildContext context, {
  required Comment comment,
  void Function(Comment optimistic)? onLocalUpdate,
}) async {
  debugPrint('[COMMENT_LIKE_DEBUG] tap commentId=${comment.id}');
  if (!await _ensureKakaoWriter(context) || !context.mounted) {
    debugPrint('[COMMENT_LIKE_DEBUG] aborted: auth gate');
    return null;
  }

  final kakaoId = AuthService.instance.kakaoUserId?.trim();
  if (kakaoId == null || kakaoId.isEmpty) return null;

  final commentId = comment.id.trim();
  if (commentId.isEmpty || commentId.startsWith('local_')) return null;
  if (_pendingCommentLikes.contains(commentId)) {
    debugPrint('[COMMENT_LIKE_DEBUG] aborted: pending lock');
    return null;
  }
  _pendingCommentLikes.add(commentId);

  final wasLiked = comment.likedByMe;
  final prevCount = comment.likeCount;
  final optimistic = comment.copyWith(
    likedByMe: !wasLiked,
    likeCount: wasLiked
        ? (prevCount - 1).clamp(0, 1 << 30)
        : prevCount + 1,
  );

  debugPrint('[COMMENT_LIKE_DEBUG] before isLiked=$wasLiked count=$prevCount');
  debugPrint(
    '[COMMENT_LIKE_DEBUG] local UI update '
    'isLiked=${optimistic.likedByMe} count=${optimistic.likeCount}',
  );

  onLocalUpdate?.call(optimistic);
  CommentsFirestoreService.instance.patchCachedComment(
    comment.postId,
    optimistic,
  );

  try {
    debugPrint('[COMMENT_LIKE_DEBUG] firestore write start');
    final updated = await CommentsFirestoreService.instance.toggleCommentLike(
      postId: comment.postId,
      commentId: commentId,
      userId: kakaoId,
    );
    debugPrint(
      '[COMMENT_LIKE_DEBUG] firestore write success '
      'isLiked=${updated.likedByMe} count=${updated.likeCount}',
    );
    onLocalUpdate?.call(updated);
    return updated;
  } catch (e) {
    debugPrint('[COMMENT_LIKE_DEBUG] firestore write failed: $e');
    debugPrint('댓글 공감 저장 실패: $e');
    final rolled = comment.copyWith(
      likedByMe: wasLiked,
      likeCount: prevCount,
    );
    onLocalUpdate?.call(rolled);
    CommentsFirestoreService.instance.patchCachedComment(
      comment.postId,
      rolled,
    );
    if (!context.mounted) return null;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('공감을 저장하지 못했어요. 다시 시도해주세요.')),
    );
    return null;
  } finally {
    _pendingCommentLikes.remove(commentId);
  }
}
