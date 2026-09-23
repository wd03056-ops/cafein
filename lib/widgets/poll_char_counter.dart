import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_typography.dart';

/// Small `12/40` counter; current count turns red when over [maxLength].
class PollCharCounter extends StatelessWidget {
  const PollCharCounter({
    super.key,
    required this.controller,
    required this.maxLength,
  });

  final TextEditingController controller;
  final int maxLength;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final base = CafeinTypography.metadata(colors.mutedSoft).copyWith(
      fontSize: 11,
      height: 1.2,
    );

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final count = controller.text.length;
        final over = count > maxLength;
        return Padding(
          padding: const EdgeInsets.only(left: 6),
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '$count',
                  style: base.copyWith(
                    color: over ? colors.error : colors.mutedSoft,
                    fontWeight: over ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
                TextSpan(text: '/$maxLength', style: base),
              ],
            ),
          ),
        );
      },
    );
  }
}
