import 'package:flutter/material.dart';

import '../models/post.dart';
import '../screens/auth_required_screen.dart';
import 'auth_service.dart';
import 'post_service.dart';
import 'posts_firestore_service.dart';

/// In-flight post like locks (per postId) — blocks duplicate writes only.
final Set<String> _pendingPostLikes = <String>{};

Future<bool> _ensureKakaoWriter(BuildContext context) async {
  final auth = AuthService.instance;
  if (auth.canWriteContent) return true;

  final ready = await AuthRequiredScreen.ensureWriter(context);
  if (!ready || !context.mounted) return false;
  return auth.canWriteContent;
}

/// Like toggle — Kakao login + onboarding required (no Firebase Auth).
///
/// Applies optimistic UI immediately, then writes to Firestore.
/// On failure, rolls back local like state.
Future<void> togglePostLike(
  BuildContext context, {
  required Post post,
}) async {
  debugPrint('[POST_LIKE_DEBUG] tap');
  if (!await _ensureKakaoWriter(context) || !context.mounted) {
    debugPrint('[POST_LIKE_DEBUG] aborted: auth gate');
    return;
  }

  final kakaoId = AuthService.instance.kakaoUserId?.trim();
  if (kakaoId == null || kakaoId.isEmpty) return;

  final postId = post.id.trim();
  if (postId.isEmpty) return;
  if (_pendingPostLikes.contains(postId)) {
    debugPrint('[POST_LIKE_DEBUG] aborted: pending lock postId=$postId');
    return;
  }
  _pendingPostLikes.add(postId);

  final baseline = PostService.instance.getById(postId) ??
      PostsFirestoreService.instance.peekCachedPostStale(postId) ??
      post;
  final wasLiked = baseline.likedByMe;
  final prevCount = baseline.likeCount;
  final optimistic = baseline.copyWith(
    likedByMe: !wasLiked,
    likeCount: wasLiked
        ? (prevCount - 1).clamp(0, 1 << 30)
        : prevCount + 1,
  );

  debugPrint('[POST_LIKE_DEBUG] postId=$postId');
  debugPrint('[POST_LIKE_DEBUG] userId=$kakaoId');
  debugPrint('[POST_LIKE_DEBUG] before isLiked=$wasLiked');
  debugPrint('[POST_LIKE_DEBUG] before likeCount=$prevCount');
  debugPrint('[POST_LIKE_DEBUG] local UI update');
  debugPrint(
    '[POST_LIKE_DEBUG] after isLiked=${optimistic.likedByMe}',
  );
  debugPrint(
    '[POST_LIKE_DEBUG] after likeCount=${optimistic.likeCount}',
  );

  // Immediate UI + like cache so a concurrent one-shot get cannot reset icon.
  PostsFirestoreService.instance.setLikedByMeCache(
    postId,
    optimistic.likedByMe,
  );
  PostService.instance.upsertRemotePost(optimistic);
  PostsFirestoreService.instance.applyLocalPostUpdate(optimistic);

  try {
    debugPrint('[POST_LIKE_DEBUG] firestore write start');
    final updated = await PostsFirestoreService.instance.toggleLike(
      postId: postId,
      userId: kakaoId,
    );
    debugPrint(
      '[POST_LIKE_DEBUG] firestore write success '
      'isLiked=${updated.likedByMe} likeCount=${updated.likeCount}',
    );
    PostsFirestoreService.instance.setLikedByMeCache(
      postId,
      updated.likedByMe,
    );
    PostService.instance.upsertRemotePost(updated);
    PostsFirestoreService.instance.applyLocalPostUpdate(updated);
  } catch (e) {
    debugPrint('[POST_LIKE_DEBUG] firestore write failed: $e');
    debugPrint('공감 저장 실패: $e');
    final rolled = baseline.copyWith(
      likedByMe: wasLiked,
      likeCount: prevCount,
    );
    PostsFirestoreService.instance.setLikedByMeCache(postId, wasLiked);
    PostService.instance.upsertRemotePost(rolled);
    PostsFirestoreService.instance.applyLocalPostUpdate(rolled);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('공감을 저장하지 못했어요. 다시 시도해주세요.')),
    );
  } finally {
    _pendingPostLikes.remove(postId);
  }
}
