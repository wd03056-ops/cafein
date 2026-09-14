import 'package:flutter/material.dart';

import '../models/poll.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// Interactive poll on the feed — vote in place without opening detail.
class FeedPollPreview extends StatelessWidget {
  const FeedPollPreview({
    super.key,
    required this.poll,
    this.onVote,
  });

  final Poll poll;
  final ValueChanged<String>? onVote;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final total = poll.totalVotes;
    final canVote = onVote != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          poll.question,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: colors.onSurface,
            height: 1.35,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        for (final option in poll.options)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: _FeedVoteOption(
              title: option.text,
              percentage: poll.hasVoted
                  ? '${total == 0 ? 0 : ((option.votes / total) * 100).round()}%'
                  : null,
              isSelected: poll.hasVoted && option.selectedByMe,
              onTap: !canVote
                  ? null
                  : () {
                      if (poll.hasVoted && option.selectedByMe) return;
                      onVote!(option.id);
                    },
            ),
          ),
        if (poll.hasVoted)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(
              '총 $total표',
              style: TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 11,
                fontWeight: FontWeight.w400,
                color: colors.muted,
              ),
            ),
          ),
      ],
    );
  }
}

class _FeedVoteOption extends StatelessWidget {
  const _FeedVoteOption({
    required this.title,
    required this.isSelected,
    this.percentage,
    this.onTap,
  });

  final String title;
  final String? percentage;
  final bool isSelected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Material(
      color: isSelected ? colors.fillStrong : colors.fill,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        splashFactory: NoSplash.splashFactory,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              if (isSelected) ...[
                Icon(Icons.check, size: 15, color: colors.onSurfaceVariant),
                const SizedBox(width: 7),
              ],
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 13,
                    height: 1.3,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    color: colors.onSurface,
                  ),
                ),
              ),
              if (percentage != null)
                Text(
                  percentage!,
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                    color: colors.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
