import 'package:flutter/material.dart';

import '../core/time_format.dart';
import '../models/post.dart';
import '../theme/app_colors.dart';
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

    final metaStyle = TextStyle(
      fontFamily: 'Pretendard',
      fontSize: 12,
      fontWeight: FontWeight.w400,
      letterSpacing: -0.1,
      color: colors.muted,
      height: 1.2,
    );

    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 6,
      runSpacing: 4,
      children: [
        Text(
          post.author,
          style: TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 13,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.2,
            color: colors.onSurface,
            height: 1.2,
          ),
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
