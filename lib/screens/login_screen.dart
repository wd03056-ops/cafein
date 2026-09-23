import 'package:flutter/material.dart';
import 'package:kakao_flutter_sdk/kakao_flutter_sdk.dart';

import '../services/auth_service.dart';
import '../services/fcm_service.dart';
import '../services/firebase_auth_bridge.dart';
import '../services/user_firestore_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import 'main_shell.dart';
import 'onboarding_screen.dart';

/// Kakao login entry — then onboarding or main depending on profile.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  static const _kakaoYellow = Color(0xFFFEE500);
  static const _kakaoInk = Color(0xFF191919);

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

      debugPrint('카카오 로그인 성공');

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

      // Firebase Auth bridge (optional while Rules are open; must not block Kakao).
      await FirebaseAuthBridge.instance
          .signInWithKakaoAccessToken(token.accessToken);

      if (!mounted) return;

      if (needsOnboarding) {
        final completed = await Navigator.of(context).push<bool>(
          MaterialPageRoute<bool>(builder: (_) => const OnboardingScreen()),
        );
        if (!mounted) return;
        if (completed == true) {
          await FcmService.instance.registerForUser();
          _enterApp();
        }
      } else {
        await FcmService.instance.registerForUser();
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
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: canPop
            ? IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                tooltip: '뒤로',
                onPressed: () => Navigator.of(context).maybePop(),
              )
            : null,
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.screenH + 8,
                12,
                AppSpacing.screenH + 8,
                20,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - 32,
                ),
                child: IntrinsicHeight(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 16),
                      Text(
                        '카페인에 오신 걸\n환영해요',
                        style: CafeinTypography.screenTitle(colors.onSurface),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        '카카오로 시작하면 익명 닉네임으로\n안전하게 이야기를 나눌 수 있어요.',
                        style: CafeinTypography.commentBody(colors.muted),
                      ),
                      const Spacer(),
                      const SizedBox(height: 32),
                      _KakaoLoginButton(
                        loading: _loading,
                        onPressed: _handleKakaoLogin,
                        background: _kakaoYellow,
                        foreground: _kakaoInk,
                        disabledBackground: colors.kakaoYellowDisabled,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '카카오계정으로 간편하게 시작할 수 있어요',
                        textAlign: TextAlign.center,
                        style: CafeinTypography.metadata(colors.muted),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Kakao-style CTA: #FEE500, symbol + label, generous tap target.
class _KakaoLoginButton extends StatelessWidget {
  const _KakaoLoginButton({
    required this.loading,
    required this.onPressed,
    required this.background,
    required this.foreground,
    required this.disabledBackground,
  });

  final bool loading;
  final VoidCallback onPressed;
  final Color background;
  final Color foreground;
  final Color disabledBackground;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: loading ? disabledBackground : background,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: loading ? null : onPressed,
        borderRadius: BorderRadius.circular(12),
        splashFactory: NoSplash.splashFactory,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: loading
                ? Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: foreground,
                      ),
                    ),
                  )
                : Row(
                    children: [
                      const _KakaoSymbol(size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '카카오로 3초 만에 시작하기',
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.ellipsis,
                          style: CafeinTypography.button(foreground),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

/// Simplified Kakao Talk mark (speech bubble) for brand recognition.
class _KakaoSymbol extends StatelessWidget {
  const _KakaoSymbol({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _KakaoSymbolPainter(color: const Color(0xFF191919)),
      ),
    );
  }
}

class _KakaoSymbolPainter extends CustomPainter {
  _KakaoSymbolPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final w = size.width;
    final h = size.height;

    final bubble = Path()
      ..moveTo(w * 0.12, h * 0.18)
      ..cubicTo(w * 0.12, h * 0.06, w * 0.28, 0, w * 0.5, 0)
      ..cubicTo(w * 0.72, 0, w * 0.88, h * 0.06, w * 0.88, h * 0.18)
      ..cubicTo(w * 0.88, h * 0.32, w * 0.72, h * 0.42, w * 0.55, h * 0.42)
      ..lineTo(w * 0.38, h * 0.42)
      ..lineTo(w * 0.22, h * 0.58)
      ..lineTo(w * 0.28, h * 0.42)
      ..cubicTo(w * 0.18, h * 0.40, w * 0.12, h * 0.30, w * 0.12, h * 0.18)
      ..close();

    canvas.drawPath(bubble, paint);
  }

  @override
  bool shouldRepaint(covariant _KakaoSymbolPainter oldDelegate) =>
      oldDelegate.color != color;
}
