import 'package:flutter/material.dart';

import '../models/post.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import 'feed_poll_preview.dart';
import 'post_author_meta.dart';
import 'topic_pill.dart';

/// SNS-style feed item: content-first, no card chrome.
///
/// The whole item (including empty space) opens detail via [onTap].
/// Nested actions (like / more / topic / vote / edit) keep their own handlers.
class PostListItem extends StatelessWidget {
  const PostListItem({
    super.key,
    required this.post,
    required this.onTap,
    this.onLike,
    this.onMore,
    this.onEdit,
    this.onDelete,
    this.onEditPoll,
    this.onTopicTap,
    this.onVote,
  });

  final Post post;
  final VoidCallback onTap;
  final VoidCallback? onLike;
  final VoidCallback? onMore;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onEditPoll;
  final ValueChanged<String>? onTopicTap;
  final ValueChanged<String>? onVote;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final preview = post.content.trim();
    final topic = post.topic;
    final poll = post.poll;
    // Own posts: 수정 / 삭제. Others: overflow menu.
    final showOwnerActions = onEdit != null || onDelete != null;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        splashFactory: NoSplash.splashFactory,
        highlightColor: colors.press,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenH,
            AppSpacing.listItemTop,
            AppSpacing.screenH,
            0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(child: PostAuthorMeta(post: post)),
                  if (onEdit != null)
                    TextButton(
                      onPressed: onEdit,
                      style: TextButton.styleFrom(
                        foregroundColor: colors.onSurfaceVariant,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                        textStyle: CafeinTypography.button(),
                      ),
                      child: const Text('수정'),
                    ),
                  if (onDelete != null)
                    TextButton(
                      onPressed: onDelete,
                      style: TextButton.styleFrom(
                        foregroundColor: colors.error,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                        textStyle: CafeinTypography.button(colors.error),
                      ),
                      child: const Text('삭제'),
                    ),
                  if (!showOwnerActions && onMore != null)
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
              Text(
                preview,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: CafeinTypography.postBody(colors.onSurface),
              ),
              SizedBox(height: poll != null ? AppSpacing.xl : AppSpacing.md),
              if (poll != null) ...[
                FeedPollPreview(
                  poll: poll,
                  onVote: onVote,
                  onEditPoll: onEditPoll,
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              SizedBox(
                height: 34,
                child: Row(
                  children: [
                    _Action(
                      icon: post.likedByMe
                          ? Icons.favorite
                          : Icons.favorite_border,
                      label: '${post.likeCount}',
                      color: post.likedByMe
                          ? colors.error
                          : colors.onSurface,
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
        ),
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
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: color),
            if (label != null) ...[
              const SizedBox(width: 5),
              Text(
                label!,
                style: CafeinTypography.reaction(color),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
