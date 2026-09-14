import 'package:flutter/material.dart';

import '../models/post.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import 'feed_poll_preview.dart';
import 'post_author_meta.dart';
import 'topic_pill.dart';

/// SNS-style feed item: content-first, no card chrome.
class PostListItem extends StatelessWidget {
  const PostListItem({
    super.key,
    required this.post,
    required this.onTap,
    this.onLike,
    this.onMore,
    this.onEdit,
    this.onTopicTap,
    this.onVote,
  });

  final Post post;
  final VoidCallback onTap;
  final VoidCallback? onLike;
  final VoidCallback? onMore;
  final VoidCallback? onEdit;
  final ValueChanged<String>? onTopicTap;
  final ValueChanged<String>? onVote;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final preview = post.content.trim();
    final topic = post.topic;
    final poll = post.poll;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenH,
        AppSpacing.listItemTop,
        AppSpacing.screenH,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: InkWell(
                  onTap: onTap,
                  splashFactory: NoSplash.splashFactory,
                  highlightColor: colors.press,
                  child: PostAuthorMeta(post: post),
                ),
              ),
              if (onEdit != null)
                TextButton(
                  onPressed: onEdit,
                  style: TextButton.styleFrom(
                    foregroundColor: colors.onSurfaceVariant,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                  child: const Text(
                    '수정',
                    style: TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              if (onMore != null)
                GestureDetector(
                  onTap: onMore,
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.xs,
                      AppSpacing.xs,
                      0,
                      AppSpacing.xs,
                    ),
                    child: Icon(
                      Icons.more_horiz,
                      size: 18,
                      color: colors.onSurface,
                    ),
                  ),
                ),
            ],
          ),
          InkWell(
            onTap: onTap,
            splashFactory: NoSplash.splashFactory,
            highlightColor: colors.press,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (topic != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  TopicPill(
                    topic: topic,
                    onTap: onTopicTap == null
                        ? null
                        : () => onTopicTap!(topic),
                  ),
                  const SizedBox(height: AppSpacing.md),
                ] else
                  const SizedBox(height: AppSpacing.md),
                if (post.title != null && post.title!.trim().isNotEmpty) ...[
                  Text(
                    post.title!.trim(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 16,
                      height: 1.35,
                      letterSpacing: -0.2,
                      color: colors.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],
                Text(
                  preview,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 15,
                    height: 1.4,
                    letterSpacing: -0.1,
                    color: colors.onSurface,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
          if (poll != null) ...[
            const SizedBox(height: AppSpacing.md),
            FeedPollPreview(
              poll: poll,
              onVote: onVote,
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          SizedBox(
            height: 34,
            child: Row(
              children: [
                _Action(
                  icon: post.likedByMe
                      ? Icons.favorite
                      : Icons.favorite_border,
                  label: '${post.likeCount}',
                  color: post.likedByMe ? colors.error : colors.onSurface,
                  onTap: onLike,
                ),
                const SizedBox(width: 18),
                _Action(
                  icon: Icons.chat_bubble_outline,
                  label: '${post.commentCount}',
                  color: colors.onSurface,
                  onTap: onTap,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.listItemBottom),
        ],
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({
    required this.icon,
    this.label,
    required this.color,
    this.onTap,
  });

  final IconData icon;
  final String? label;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      splashFactory: NoSplash.splashFactory,
      borderRadius: BorderRadius.circular(8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: color),
          if (label != null) ...[
            const SizedBox(width: 5),
            Text(
              label!,
              style: TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 13,
                fontWeight: FontWeight.w400,
                color: color,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
