import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_typography.dart';

/// Topic label above post body — blue text only, no chip background.
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
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Text(
            topic,
            style: CafeinTypography.topic(colors.topicAccent),
          ),
        ),
      ),
    );
  }
}
