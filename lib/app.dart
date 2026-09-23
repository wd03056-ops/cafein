import 'package:flutter/material.dart';

import 'core/constants.dart';
import 'navigation/app_navigator.dart';
import 'screens/main_shell.dart';
import 'screens/onboarding_screen.dart';
import 'services/auth_service.dart';
import 'theme/app_theme.dart';

class CafeinApp extends StatelessWidget {
  const CafeinApp({
    super.key,
    required this.initialSession,
  });

  final KakaoSessionStatus initialSession;

  Widget get _home {
    return switch (initialSession) {
      KakaoSessionStatus.authenticated => const MainShell(),
      KakaoSessionStatus.needsOnboarding => const OnboardingScreen(),
      // Guests can browse the feed; write/comment/like require login.
      KakaoSessionStatus.none => const MainShell(),
    };
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: appNavigatorKey,
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      locale: const Locale('ko'),
      scrollBehavior: const _NoOverscrollBehavior(),
      // Ignore OS accessibility font size / "Bold text" so Pretendard
      // weights stay exactly as designed (like Instagram / YouTube).
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(
            textScaler: TextScaler.noScaling,
            boldText: false,
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: _home,
    );
  }
}

/// Disable overscroll stretch / bounce glow on scroll.
class _NoOverscrollBehavior extends MaterialScrollBehavior {
  const _NoOverscrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    return const ClampingScrollPhysics();
  }

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child;
  }
}
