import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../theme/app_colors.dart';
import 'login_screen.dart';

/// Prompt shown when a guest tries to write / comment / like / vote.
class AuthRequiredScreen extends StatelessWidget {
  const AuthRequiredScreen({
    super.key,
    this.title = '로그인이나 회원가입이 필요해요',
    this.message =
        '글을 보기는 로그인 없이 가능해요.\n글을 쓰거나 댓글을 남기거나 공감하려면\n로그인 또는 회원가입이 필요합니다.',
  });

  final String title;
  final String message;

  /// Opens this screen, then Kakao login/onboarding if needed.
  /// Returns true when the user can write content afterwards.
  static Future<bool> ensureWriter(BuildContext context) async {
    if (AuthService.instance.canWriteContent) return true;
    final authReady = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) => const AuthRequiredScreen()),
    );
    return authReady == true && AuthService.instance.canWriteContent;
  }

  Future<void> _startLogin(BuildContext context) async {
    final completed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) => const LoginScreen()),
    );
    if (!context.mounted) return;
    if (completed == true) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 24),
            Text(
              title,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: colors.onSurface,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              message,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: colors.onSurface,
                height: 1.5,
              ),
            ),
            const Spacer(),
            SizedBox(
              height: 52,
              child: FilledButton(
                onPressed: () => _startLogin(context),
                style: FilledButton.styleFrom(
                  backgroundColor: colors.kakaoYellow,
                  foregroundColor: colors.kakaoInk,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  '카카오로 3초 만에 시작하기',
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              style: TextButton.styleFrom(foregroundColor: colors.onSurface),
              child: const Text('돌아가서 글 구경하기'),
            ),
            const SizedBox(height: 8),
            Text(
              '실명이나 복잡한 서류는 요구하지 않아요.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.muted,
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
