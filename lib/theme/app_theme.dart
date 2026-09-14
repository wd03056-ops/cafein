import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Neutral SNS themes with light + dark support.
class AppTheme {
  static const Color _error = Color(0xFFE11D48);

  static ThemeData light() => _build(
        brightness: Brightness.light,
        scheme: const ColorScheme.light(
          primary: Color(0xFF000000),
          onPrimary: Color(0xFFFFFFFF),
          secondary: Color(0xFF000000),
          onSecondary: Color(0xFFFFFFFF),
          surface: Color(0xFFFFFFFF),
          onSurface: Color(0xFF000000),
          onSurfaceVariant: Color(0xFF737373),
          surfaceContainerHighest: Color(0xFFF4F4F4),
          surfaceContainerHigh: Color(0xFFECECEC),
          outline: Color(0xFFE8E8E8),
          outlineVariant: Color(0xFFE8E8E8),
          error: _error,
          onError: Color(0xFFFFFFFF),
        ),
        statusBarIconBrightness: Brightness.dark,
      );

  static ThemeData dark() => _build(
        brightness: Brightness.dark,
        scheme: const ColorScheme.dark(
          primary: Color(0xFFF5F5F5),
          onPrimary: Color(0xFF121212),
          secondary: Color(0xFFF5F5F5),
          onSecondary: Color(0xFF121212),
          surface: Color(0xFF121212),
          onSurface: Color(0xFFF5F5F5),
          onSurfaceVariant: Color(0xFFB0B0B0),
          surfaceContainerHighest: Color(0xFF2A2A2A),
          surfaceContainerHigh: Color(0xFF333333),
          outline: Color(0xFF3A3A3A),
          outlineVariant: Color(0xFF3A3A3A),
          error: _error,
          onError: Color(0xFFFFFFFF),
        ),
        statusBarIconBrightness: Brightness.light,
      );

  static ThemeData _build({
    required Brightness brightness,
    required ColorScheme scheme,
    required Brightness statusBarIconBrightness,
  }) {
    final isDark = brightness == Brightness.dark;
    final onSurface = scheme.onSurface;
    final surface = scheme.surface;
    final outline = scheme.outline;
    final fill = scheme.surfaceContainerHighest;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      fontFamily: 'Pretendard',
      colorScheme: scheme,
      scaffoldBackgroundColor: surface,
      canvasColor: surface,
      cardColor: surface,
      dividerColor: outline,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: _NoPageTransitionsBuilder(),
          TargetPlatform.iOS: _NoPageTransitionsBuilder(),
          TargetPlatform.macOS: _NoPageTransitionsBuilder(),
          TargetPlatform.windows: _NoPageTransitionsBuilder(),
          TargetPlatform.linux: _NoPageTransitionsBuilder(),
          TargetPlatform.fuchsia: _NoPageTransitionsBuilder(),
        },
      ),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        foregroundColor: onSurface,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: surface,
          statusBarIconBrightness: statusBarIconBrightness,
          statusBarBrightness:
              isDark ? Brightness.dark : Brightness.light,
          systemNavigationBarColor: surface,
          systemNavigationBarIconBrightness: statusBarIconBrightness,
        ),
        titleTextStyle: TextStyle(
          fontFamily: 'Pretendard',
          color: onSurface,
          fontSize: 20,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.3,
        ),
        iconTheme: IconThemeData(color: onSurface, size: 24),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: onSurface,
        unselectedLabelColor: onSurface,
        indicatorColor: onSurface,
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: outline,
        labelStyle: const TextStyle(
          fontFamily: 'Pretendard',
          fontWeight: FontWeight.w600,
          fontSize: 14,
        ),
        unselectedLabelStyle: const TextStyle(
          fontFamily: 'Pretendard',
          fontWeight: FontWeight.w500,
          fontSize: 14,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: fill,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        hintStyle: TextStyle(
          fontFamily: 'Pretendard',
          color: onSurface.withValues(alpha: 0.35),
          fontSize: 15,
          fontWeight: FontWeight.w400,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: fill,
        selectedColor: onSurface,
        labelStyle: TextStyle(
          fontFamily: 'Pretendard',
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: onSurface,
        ),
        secondaryLabelStyle: TextStyle(
          fontFamily: 'Pretendard',
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: surface,
        ),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        padding: const EdgeInsets.symmetric(horizontal: 4),
      ),
      dividerTheme: DividerThemeData(
        color: outline,
        thickness: 0.5,
        space: 0.5,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        height: 64,
        indicatorColor: Colors.transparent,
        overlayColor: WidgetStateProperty.all(Colors.transparent),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          return IconThemeData(color: onSurface, size: 24);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontFamily: 'Pretendard',
            color: onSurface,
            fontSize: 11,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          );
        }),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: surface,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: isDark ? const Color(0xFFE8E8E8) : const Color(0xFF1A1A1A),
        contentTextStyle: TextStyle(
          fontFamily: 'Pretendard',
          color: isDark ? const Color(0xFF121212) : Colors.white,
        ),
      ),
      textTheme: TextTheme(
        bodyLarge: TextStyle(
          fontFamily: 'Pretendard',
          fontSize: 16,
          height: 1.55,
          color: onSurface,
          fontWeight: FontWeight.w400,
        ),
        bodyMedium: TextStyle(
          fontFamily: 'Pretendard',
          fontSize: 16,
          height: 1.55,
          color: onSurface,
          fontWeight: FontWeight.w400,
        ),
        titleLarge: TextStyle(
          fontFamily: 'Pretendard',
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: onSurface,
        ),
        titleMedium: TextStyle(
          fontFamily: 'Pretendard',
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: onSurface,
        ),
        labelLarge: TextStyle(
          fontFamily: 'Pretendard',
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: onSurface,
        ),
        labelMedium: TextStyle(
          fontFamily: 'Pretendard',
          fontSize: 13,
          fontWeight: FontWeight.w400,
          color: onSurface,
        ),
        labelSmall: TextStyle(
          fontFamily: 'Pretendard',
          fontSize: 12,
          fontWeight: FontWeight.w400,
          color: onSurface,
        ),
      ),
    );
  }
}

class _NoPageTransitionsBuilder extends PageTransitionsBuilder {
  const _NoPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return child;
  }
}
