import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Formats onboarding cafe type + experience into a short badge label.
String getBadgeText(String cafeType, String experience) {
  final shortType = cafeType.contains('프랜차이즈') ? '프차' : '개인';
  return '$shortType / $experience';
}

/// Compact author badge shown next to nickname.
class UserBadgeWidget extends StatelessWidget {
  const UserBadgeWidget({
    super.key,
    required this.cafeType,
    required this.experience,
  });

  final String cafeType;
  final String experience;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final badgeText = getBadgeText(cafeType, experience);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: colors.fill,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: colors.hairline, width: 0.5),
      ),
      child: Text(
        badgeText,
        style: TextStyle(
          fontFamily: 'Pretendard',
          color: colors.onSurfaceVariant,
          fontSize: 11,
          fontWeight: FontWeight.w500,
          height: 1.2,
          letterSpacing: -0.1,
        ),
      ),
    );
  }
}
