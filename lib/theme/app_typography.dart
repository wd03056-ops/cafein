import 'package:flutter/material.dart';

/// CAFEIN typography scale — Pretendard-based hierarchy.
///
/// Prefer these styles over ad-hoc fontSize / fontWeight so titles, body,
/// nicknames, and metadata stay visually distinct on real devices.
abstract final class CafeinTypography {
  static const String fontFamily = 'Pretendard';

  static const TextStyle _base = TextStyle(
    fontFamily: fontFamily,
    decoration: TextDecoration.none,
  );

  /// AppBar / screen titles (설정, 차단한 사용자, …).
  static TextStyle screenTitle([Color? color]) => _base.copyWith(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        height: 1.3,
        letterSpacing: -0.4,
        color: color,
      );

  /// Reserved for non-post screen section headers (not post content —
  /// CAFEIN posts have no title field).
  static TextStyle postTitle([Color? color]) => _base.copyWith(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        height: 1.4,
        letterSpacing: -0.3,
        color: color,
      );

  /// Poll question — slightly heavier than light body, not a loud headline.
  static TextStyle pollTitle([Color? color]) => _base.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        height: 1.4,
        letterSpacing: -0.1,
        color: color,
      );

  /// Poll option label — smaller/lighter than [pollTitle].
  static TextStyle pollOption([Color? color]) => _base.copyWith(
        fontSize: 15,
        fontWeight: FontWeight.w300,
        height: 1.35,
        letterSpacing: -0.05,
        color: color,
      );

  /// Primary reading text (feed + detail body).
  /// YouTube / Instagram-like: Light, not Medium/SemiBold.
  static TextStyle postBody([Color? color]) => _base.copyWith(
        fontSize: 13,
        fontWeight: FontWeight.w300,
        height: 1.55,
        letterSpacing: -0.05,
        color: color,
      );

  /// Comment body — same size as [postBody] for consistent reading.
  static TextStyle commentBody([Color? color]) => _base.copyWith(
        fontSize: 13,
        fontWeight: FontWeight.w300,
        height: 1.5,
        letterSpacing: -0.05,
        color: color,
      );

  /// Author / commenter nickname — same size as body, Regular weight so
  /// body remains the visual focus.
  static TextStyle nickname([Color? color]) => _base.copyWith(
        fontSize: 13,
        fontWeight: FontWeight.w400,
        height: 1.25,
        letterSpacing: -0.2,
        color: color,
      );

  /// Topic pill label (고충, 주휴수당, …).
  static TextStyle topic([Color? color]) => _base.copyWith(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        height: 1.2,
        letterSpacing: -0.1,
        color: color,
      );

  /// Time, experience meta, hints.
  static TextStyle metadata([Color? color]) => _base.copyWith(
        fontSize: 12,
        fontWeight: FontWeight.w300,
        height: 1.25,
        letterSpacing: -0.05,
        color: color,
      );

  /// Like / comment counts.
  static TextStyle reaction([Color? color]) => _base.copyWith(
        fontSize: 13,
        fontWeight: FontWeight.w400,
        height: 1.2,
        letterSpacing: -0.05,
        color: color,
      );

  /// Primary / text buttons.
  static TextStyle button([Color? color]) => _base.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        height: 1.2,
        letterSpacing: -0.1,
        color: color,
      );

  /// Home 인기 / 최신 sort tabs.
  /// Metrics match the 인기(selected) baseline — selection is color only so
  /// switching tabs never shifts glyph size/weight.
  static TextStyle sortTab({required bool selected, Color? color}) =>
      _base.copyWith(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        height: 1.2,
        letterSpacing: -0.3,
        color: color,
      );

  /// Builds [TextTheme] wired to CAFEIN scale (inherits [ThemeData.fontFamily]).
  static TextTheme textTheme(Color onSurface) {
    return TextTheme(
      displaySmall: screenTitle(onSurface),
      headlineMedium: screenTitle(onSurface),
      headlineSmall: postTitle(onSurface),
      titleLarge: postTitle(onSurface),
      titleMedium: nickname(onSurface),
      titleSmall: topic(onSurface),
      bodyLarge: postBody(onSurface),
      bodyMedium: commentBody(onSurface),
      bodySmall: metadata(onSurface),
      labelLarge: button(onSurface),
      labelMedium: reaction(onSurface),
      labelSmall: metadata(onSurface),
    );
  }
}
