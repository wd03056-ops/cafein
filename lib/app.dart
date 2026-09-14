import 'package:flutter/material.dart';

import 'core/constants.dart';
import 'screens/auth_gate_screen.dart';
import 'theme/app_theme.dart';

class CafeinApp extends StatelessWidget {
  const CafeinApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      locale: const Locale('ko'),
      scrollBehavior: const _NoOverscrollBehavior(),
      home: const AuthGateScreen(),
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
