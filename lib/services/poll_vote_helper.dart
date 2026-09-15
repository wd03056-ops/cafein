import 'package:flutter/material.dart';

import '../models/post.dart';
import '../screens/login_screen.dart';
import 'auth_service.dart';
import 'post_service.dart';
import 'posts_firestore_service.dart';

Future<bool> _ensureKakaoWriter(BuildContext context) async {
  final auth = AuthService.instance;
  if (auth.canWriteContent) return true;

  final loggedIn = await Navigator.of(context).push<bool>(
    MaterialPageRoute<bool>(builder: (_) => const LoginScreen()),
  );
  if (loggedIn != true || !context.mounted) return false;

  if (!auth.canWriteContent) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('카카오 로그인과 프로필 설정을 완료해 주세요.')),
    );
    return false;
  }
  return true;
}

/// Poll vote — Kakao login + onboarding required (no Firebase Auth).
Future<void> castPostVote(
  BuildContext context, {
  required Post post,
  required String optionId,
}) async {
  if (!await _ensureKakaoWriter(context) || !context.mounted) return;

  final kakaoId = AuthService.instance.kakaoUserId?.trim();
  if (kakaoId == null || kakaoId.isEmpty) return;

  try {
    final updated = await PostsFirestoreService.instance.castVote(
      postId: post.id,
      optionId: optionId,
      userId: kakaoId,
    );
    PostService.instance.upsertRemotePost(updated);
  } catch (e) {
    debugPrint('투표 저장 실패: $e');
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('투표를 저장하지 못했어요. 다시 시도해주세요.')),
    );
  }
}
