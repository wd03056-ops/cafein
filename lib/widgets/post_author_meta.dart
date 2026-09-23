import 'package:flutter/material.dart';

import '../core/time_format.dart';
import '../models/post.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import 'user_badge.dart';

/// Nickname + badge · time (topic is shown separately as a pill).
class PostAuthorMeta extends StatelessWidget {
  const PostAuthorMeta({
    super.key,
    required this.post,
  });

  final Post post;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final cafeType = post.cafeType;
    final experience = post.experience;
    final showBadge = cafeType != null &&
        cafeType.isNotEmpty &&
        experience != null &&
        experience.isNotEmpty;

    final metaStyle = CafeinTypography.metadata(colors.muted);

    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 6,
      runSpacing: 4,
      children: [
        Text(
          post.author,
          style: CafeinTypography.nickname(colors.onSurface),
        ),
        if (showBadge)
          UserBadgeWidget(
            cafeType: cafeType,
            experience: experience,
          ),
        Text('·', style: metaStyle),
        Text(formatRelativeTime(post.createdAt), style: metaStyle),
      ],
    );
  }
}
