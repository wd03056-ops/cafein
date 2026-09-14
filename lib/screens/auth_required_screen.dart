import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'login_screen.dart';

/// Shown before write when not logged in — opens Kakao login.
class AuthRequiredScreen extends StatelessWidget {
  const AuthRequiredScreen({super.key});

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
              '글을 쓰려면 로그인이 필요해요',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: colors.onSurface,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '카카오로 시작하면 닉네임과 근무 정보를\n입력한 뒤 익명으로 이야기를 나눌 수 있어요.',
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
              onPressed: () => Navigator.of(context).pop(),
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
