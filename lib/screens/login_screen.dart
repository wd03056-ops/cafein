import 'package:flutter/material.dart';
import 'package:kakao_flutter_sdk/kakao_flutter_sdk.dart';

import '../services/auth_service.dart';
import '../services/user_firestore_service.dart';
import '../theme/app_colors.dart';
import 'main_shell.dart';
import 'onboarding_screen.dart';

/// Kakao login entry — then onboarding or main depending on profile.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _loading = false;

  void _enterApp() {
    if (!mounted) return;
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop(true);
      return;
    }
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const MainShell()),
      (route) => false,
    );
  }

  Future<void> _handleKakaoLogin() async {
    if (_loading) return;
    setState(() => _loading = true);

    try {
      final isInstalled = await isKakaoTalkInstalled();
      final OAuthToken token = isInstalled
          ? await UserApi.instance.loginWithKakaoTalk()
          : await UserApi.instance.loginWithKakaoAccount();

      debugPrint('카카오 로그인 성공! 토큰: ${token.accessToken}');

      final user = await UserApi.instance.me();
      final kakaoUserId = user.id.toString();
      debugPrint('카카오 유저 고유 ID: $kakaoUserId');

      final kakaoAccount = user.kakaoAccount;
      final kakaoProfile = kakaoAccount?.profile;
      await saveUserToFirestore(
        uid: kakaoUserId,
        nickname: kakaoProfile?.nickname ?? '',
        profileImage: kakaoProfile?.profileImageUrl ?? '',
        email: kakaoAccount?.email ?? '',
      );

      final needsOnboarding =
          AuthService.instance.signInWithKakao(kakaoUserId);

      if (!mounted) return;

      if (needsOnboarding) {
        final completed = await Navigator.of(context).push<bool>(
          MaterialPageRoute<bool>(builder: (_) => const OnboardingScreen()),
        );
        if (!mounted) return;
        if (completed == true) {
          _enterApp();
        }
      } else {
        _enterApp();
      }
    } catch (error) {
      debugPrint('카카오 로그인 실패: $error');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('카카오 로그인에 실패했어요. 다시 시도해주세요.')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leadingWidth: canPop ? 48 : 16,
        titleSpacing: 0,
        leading: canPop
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: '뒤로',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                onPressed: () => Navigator.of(context).maybePop(),
              )
            : const SizedBox.shrink(),
        title: const Text('로그인'),
      ),
      body: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '카페인에 오신 걸\n환영해요.',
                style: TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  height: 1.35,
                  color: colors.onSurface,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '카카오로 시작하면 익명 닉네임으로\n안전하게 이야기를 나눌 수 있어요.',
                style: TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  height: 1.5,
                  color: colors.muted,
                ),
              ),
              const Spacer(),
              SizedBox(
                height: 52,
                child: FilledButton(
                  onPressed: _loading ? null : _handleKakaoLogin,
                  style: FilledButton.styleFrom(
                    backgroundColor: colors.kakaoYellow,
                    disabledBackgroundColor: colors.kakaoYellowDisabled,
                    foregroundColor: colors.kakaoInk,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _loading
                      ? SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: colors.kakaoInk,
                          ),
                        )
                      : const Text(
                          '카카오로 3초 만에 시작하기',
                          style: TextStyle(
                            fontFamily: 'Pretendard',
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}
