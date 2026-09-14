import 'package:flutter/material.dart';

/// Semantic colors derived from [ColorScheme] for light/dark safety.
extension CafeinColors on ColorScheme {
  /// Secondary / meta text (time, hints).
  Color get muted => onSurface.withValues(alpha: brightness == Brightness.dark ? 0.55 : 0.45);

  /// Softer muted (placeholders).
  Color get mutedSoft => onSurface.withValues(alpha: brightness == Brightness.dark ? 0.4 : 0.35);

  /// Filled chip / option / input background.
  Color get fill => brightness == Brightness.dark
      ? surfaceContainerHighest
      : const Color(0xFFF5F5F5);

  /// Slightly stronger fill (selected vote, etc.).
  Color get fillStrong => brightness == Brightness.dark
      ? surfaceContainerHigh
      : const Color(0xFFE8E8E8);

  /// Hairline borders that stay visible in dark mode.
  Color get hairline => outline;

  /// Soft press highlight.
  Color get press => onSurface.withValues(alpha: 0.06);

  /// Accent used for confirm checks (readable on both themes).
  Color get accentBlue => const Color(0xFF3182F6);

  /// Kakao brand yellow (login).
  Color get kakaoYellow => const Color(0xFFFEE500);

  Color get kakaoYellowDisabled => const Color(0xFFF5E99A);

  Color get kakaoInk => const Color(0xFF191919);
}
