import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import 'login_screen.dart';
import 'main_shell.dart';
import 'onboarding_screen.dart';

/// Startup gate: restore Kakao session, then route to login / onboarding / main.
class AuthGateScreen extends StatefulWidget {
  const AuthGateScreen({super.key});

  @override
  State<AuthGateScreen> createState() => _AuthGateScreenState();
}

class _AuthGateScreenState extends State<AuthGateScreen> {
  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final status = await AuthService.instance.tryRestoreKakaoSession();
    if (!mounted) return;

    final Widget page = switch (status) {
      KakaoSessionStatus.authenticated => const MainShell(),
      KakaoSessionStatus.needsOnboarding => const OnboardingScreen(),
      KakaoSessionStatus.none => const LoginScreen(),
    };

    // Use a real route so AppBar / SafeArea get stable MediaQuery insets.
    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        pageBuilder: (_, _, _) => page,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      body: Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(
            strokeWidth: 2.4,
            color: colors.onSurface,
          ),
        ),
      ),
    );
  }
}
