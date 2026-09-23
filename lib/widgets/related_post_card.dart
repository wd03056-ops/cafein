import 'package:flutter/material.dart';

import '../core/time_format.dart';
import '../models/post.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import 'topic_pill.dart';
import 'user_badge.dart';

/// Related post horizontal card with thin border
class RelatedPostCard extends StatelessWidget {
  const RelatedPostCard({
    super.key,
    required this.post,
    required this.onTap,
  });

  final Post post;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final preview = post.content.replaceAll('\n', ' ').trim();
    final showBadge = post.cafeType != null &&
        post.cafeType!.isNotEmpty &&
        post.experience != null &&
        post.experience!.isNotEmpty;

    return SizedBox(
      width: 248,
      child: Material(
        color: colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: colors.hairline, width: 0.8),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          splashFactory: NoSplash.splashFactory,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    style: CafeinTypography.metadata(colors.onSurface),
                    children: [
                      TextSpan(
                        text: post.author,
                        style: CafeinTypography.nickname(colors.onSurface),
                      ),
                      if (showBadge)
                        TextSpan(
                          text:
                              '  ${getBadgeText(post.cafeType!, post.experience!)}',
                          style: CafeinTypography.metadata(
                            colors.secondaryText,
                          ),
                        ),
                      TextSpan(
                        text: ' · ${formatRelativeTime(post.createdAt)}',
                        style: CafeinTypography.metadata(colors.muted),
                      ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (post.topic != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  TopicPill(topic: post.topic!),
                ],
                const SizedBox(height: AppSpacing.sm),
                Expanded(
                  child: Text(
                    preview,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: CafeinTypography.commentBody(colors.onSurface),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  '공감 ${post.likeCount} · 댓글 ${post.commentCount}',
                  style: CafeinTypography.metadata(colors.muted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
