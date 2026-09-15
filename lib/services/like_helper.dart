import 'package:flutter/material.dart';

import '../models/post.dart';
import '../screens/auth_required_screen.dart';
import 'auth_service.dart';
import 'post_service.dart';
import 'posts_firestore_service.dart';

Future<bool> _ensureKakaoWriter(BuildContext context) async {
  final auth = AuthService.instance;
  if (auth.canWriteContent) return true;

  final ready = await AuthRequiredScreen.ensureWriter(context);
  if (!ready || !context.mounted) return false;
  return auth.canWriteContent;
}

/// Like toggle — Kakao login + onboarding required (no Firebase Auth).
Future<void> togglePostLike(
  BuildContext context, {
  required Post post,
}) async {
  if (!await _ensureKakaoWriter(context) || !context.mounted) return;

  final kakaoId = AuthService.instance.kakaoUserId?.trim();
  if (kakaoId == null || kakaoId.isEmpty) return;

  try {
    final updated = await PostsFirestoreService.instance.toggleLike(
      postId: post.id,
      userId: kakaoId,
    );
    PostService.instance.upsertRemotePost(updated);
  } catch (e) {
    debugPrint('공감 저장 실패: $e');
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('공감을 저장하지 못했어요. 다시 시도해주세요.')),
    );
  }
}
