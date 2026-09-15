import 'package:flutter/material.dart';

import '../core/time_format.dart';
import '../models/comment.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import 'user_badge.dart';

class CommentItem extends StatelessWidget {
  const CommentItem({
    super.key,
    required this.comment,
    required this.onMore,
    this.onLike,
  });

  final Comment comment;
  final VoidCallback onMore;
  final VoidCallback? onLike;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final cafeType = comment.cafeType;
    final experience = comment.experience;
    final showBadge = cafeType != null &&
        cafeType.isNotEmpty &&
        experience != null &&
        experience.isNotEmpty;
    final profileUrl = comment.authorProfileImage?.trim();
    final hasProfile = profileUrl != null && profileUrl.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenH,
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: colors.fill,
            backgroundImage: hasProfile ? NetworkImage(profileUrl) : null,
            child: hasProfile
                ? null
                : Text(
                    comment.author.isNotEmpty
                        ? comment.author.characters.first
                        : '?',
                    style: TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: colors.onSurface,
                    ),
                  ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          Text(
                            comment.authorNickname,
                            style: TextStyle(
                              fontFamily: 'Pretendard',
                              color: colors.onSurface,
                              fontWeight: FontWeight.w500,
                              fontSize: 14,
                            ),
                          ),
                          if (showBadge)
                            UserBadgeWidget(
                              cafeType: cafeType,
                              experience: experience,
                            ),
                          Text(
                            '·',
                            style: TextStyle(
                              fontFamily: 'Pretendard',
                              color: colors.muted,
                              fontSize: 12,
                            ),
                          ),
                          Text(
                            formatRelativeTime(comment.createdAt),
                            style: TextStyle(
                              fontFamily: 'Pretendard',
                              color: colors.muted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.more_horiz, size: 18),
                      color: colors.onSurface,
                      onPressed: onMore,
                      tooltip: '더보기',
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.sm),
                  child: Text(
                    comment.content,
                    style: TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 15,
                      height: 1.4,
                      fontWeight: FontWeight.w400,
                      color: colors.onSurface,
                    ),
                  ),
                ),
                if (onLike != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  InkWell(
                    onTap: onLike,
                    splashFactory: NoSplash.splashFactory,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 2,
                        horizontal: 2,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            comment.likedByMe
                                ? Icons.favorite
                                : Icons.favorite_border,
                            size: 16,
                            color: comment.likedByMe
                                ? colors.error
                                : colors.onSurface,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${comment.likeCount}',
                            style: TextStyle(
                              fontFamily: 'Pretendard',
                              fontSize: 12,
                              color: colors.onSurface,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
