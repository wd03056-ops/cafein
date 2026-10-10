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

  static const _reviewerTapTarget = 5;
  static const _reviewerTapWindow = Duration(milliseconds: 1500);

  bool _loading = false;
  int _titleTapCount = 0;
  DateTime? _lastTitleTap;

  void _onTitleTap() {
    if (_loading) return;
    final now = DateTime.now();
    final last = _lastTitleTap;
    _titleTapCount = (last != null && now.difference(last) <= _reviewerTapWindow)
        ? _titleTapCount + 1
        : 1;
    _lastTitleTap = now;
    if (_titleTapCount >= _reviewerTapTarget) {
      _titleTapCount = 0;
      _lastTitleTap = null;
      _handleReviewerLogin();
    }
  }

  /// Keyboard dismiss + dialog exit animation must finish before navigating.
  Future<void> _waitForUiToSettle() async {
    FocusManager.instance.primaryFocus?.unfocus();
    await Future<void>.delayed(const Duration(milliseconds: 250));
    await WidgetsBinding.instance.endOfFrame;
  }

  Future<void> _handleReviewerLogin() async {
    final code = await showDialog<String>(
      context: context,
      builder: (_) => const _ReviewerCodeDialog(),
    );
    if (!mounted) return;
    await _waitForUiToSettle();
    if (!mounted || code == null || code.trim().isEmpty) return;

    setState(() => _loading = true);
    try {
      final result = await FirebaseAuthBridge.instance.signInAsReviewer(code);
      await AuthService.instance.signInAsReviewer(
        uid: result.uid,
        nickname: result.nickname,
        cafeType: result.cafeType,
        experience: result.experience,
      );
      await FcmService.instance.registerForUser();
      if (!mounted) return;
      await _waitForUiToSettle();
      _enterApp();
    } catch (error) {
      debugPrint('심사용 로그인 실패: $error');
      if (!mounted) return;
      final message = error is ReviewerLoginException
          ? error.message
          : '심사용 로그인에 실패했어요.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

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

      // Firebase Auth first: reading/writing users/{uid} requires request.auth.
      await FirebaseAuthBridge.instance
          .signInWithKakaoAccessToken(token.accessToken);

      // Local profile, else restore from users/{uid}, else onboarding.
      // Runs before saveUserToFirestore so the lookup sees the original doc.
      final needsOnboarding = await AuthService.instance
          .signInWithKakaoRestoringProfile(kakaoUserId);

      final kakaoAccount = user.kakaoAccount;
      final kakaoProfile = kakaoAccount?.profile;
      await saveUserToFirestore(
        uid: kakaoUserId,
        nickname: kakaoProfile?.nickname ?? '',
        profileImage: kakaoProfile?.profileImageUrl ?? '',
        email: kakaoAccount?.email ?? '',
      );

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
    } on ProfileLookupException catch (error) {
      // Lookup failed ≠ new user: never onboard; drop the half session.
      debugPrint('회원 정보 조회 실패: $error');
      AuthService.instance.clearSession();
      await FirebaseAuthBridge.instance.signOut();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('회원 정보를 불러오지 못했어요. 네트워크 상태를 확인해 주세요.'),
          action: SnackBarAction(
            label: '다시 시도',
            onPressed: _handleKakaoLogin,
          ),
        ),
      );
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
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _onTitleTap,
                        child: Text(
                          '카페인에 오신 걸\n환영해요',
                          style: CafeinTypography.screenTitle(colors.onSurface),
                        ),
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

/// Owns its controller so it is disposed only after the exit animation ends.
class _ReviewerCodeDialog extends StatefulWidget {
  const _ReviewerCodeDialog();

  @override
  State<_ReviewerCodeDialog> createState() => _ReviewerCodeDialogState();
}

class _ReviewerCodeDialogState extends State<_ReviewerCodeDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _close([String? value]) {
    FocusScope.of(context).unfocus();
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('심사용 로그인'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        obscureText: true,
        textInputAction: TextInputAction.done,
        decoration: const InputDecoration(hintText: '접근 코드'),
        onSubmitted: _close,
      ),
      actions: [
        TextButton(
          onPressed: _close,
          child: const Text('취소'),
        ),
        TextButton(
          onPressed: () => _close(_controller.text),
          child: const Text('로그인'),
        ),
      ],
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
