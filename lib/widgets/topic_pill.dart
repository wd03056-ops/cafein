import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Minimal topic pill shown above post body.
class TopicPill extends StatelessWidget {
  const TopicPill({
    super.key,
    required this.topic,
    this.onTap,
  });

  final String topic;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Align(
      alignment: Alignment.centerLeft,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: colors.fill,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            topic,
            style: TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: colors.onSurfaceVariant,
              height: 1.2,
            ),
          ),
        ),
      ),
    );
  }
}
