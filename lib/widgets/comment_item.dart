import 'package:flutter/material.dart';

import '../core/time_format.dart';
import '../models/comment.dart';
import '../services/auth_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import 'user_badge.dart';

class CommentItem extends StatelessWidget {
  const CommentItem({
    super.key,
    required this.comment,
    this.onMore,
    this.onEdit,
    this.onDelete,
    this.onLike,
  });

  final Comment comment;
  final VoidCallback? onMore;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onLike;

  bool get _isMine {
    final myId = AuthService.instance.kakaoUserId?.trim() ?? '';
    final authorId = comment.authorId?.trim() ?? '';
    return myId.isNotEmpty && authorId.isNotEmpty && myId == authorId;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final cafeType = comment.cafeType;
    final experience = comment.experience;
    final showBadge = cafeType != null &&
        cafeType.isNotEmpty &&
        experience != null &&
        experience.isNotEmpty;
    final showOwnerActions = _isMine && (onEdit != null || onDelete != null);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenH,
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    Text(
                      comment.authorNickname,
                      style: CafeinTypography.nickname(colors.onSurface),
                    ),
                    if (showBadge)
                      UserBadgeWidget(
                        cafeType: cafeType,
                        experience: experience,
                      ),
                  ],
                ),
              ),
              if (showOwnerActions) ...[
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
              ] else if (onMore != null)
                GestureDetector(
                  onTap: onMore,
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 4, 0),
                    child: Icon(
                      Icons.more_horiz,
                      size: 18,
                      color: colors.onSurface,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.sm),
            child: Text(
              comment.content,
              style: CafeinTypography.commentBody(colors.onSurface),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Text(
                formatRelativeTime(comment.createdAt),
                style: CafeinTypography.metadata(colors.muted),
              ),
              const SizedBox(width: 12),
              _CommentLike(
                likedByMe: comment.likedByMe,
                likeCount: comment.likeCount,
                onLike: onLike,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CommentLike extends StatelessWidget {
  const _CommentLike({
    required this.likedByMe,
    required this.likeCount,
    this.onLike,
  });

  final bool likedByMe;
  final int likeCount;
  final VoidCallback? onLike;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final color = likedByMe ? colors.error : colors.secondaryText;
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          likedByMe ? Icons.favorite : Icons.favorite_border,
          size: 16,
          color: color,
        ),
        const SizedBox(width: 4),
        Text(
          '$likeCount',
          style: CafeinTypography.metadata(color),
        ),
      ],
    );
    if (onLike == null) return row;
    return InkWell(
      onTap: onLike,
      splashFactory: NoSplash.splashFactory,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
        child: row,
      ),
    );
  }
}
