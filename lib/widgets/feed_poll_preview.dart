import 'package:flutter/material.dart';

import '../models/poll.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

/// Interactive poll on the feed — vote in place without opening detail.
class FeedPollPreview extends StatelessWidget {
  const FeedPollPreview({
    super.key,
    required this.poll,
    this.onVote,
    this.onEditPoll,
  });

  final Poll poll;
  final ValueChanged<String>? onVote;
  /// Own-post only: shows 「투표 수정」 beside the poll question.
  final VoidCallback? onEditPoll;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final total = poll.totalVotes;
    final canVote = onVote != null;
    final showResults = poll.hasVoted || total > 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (poll.trimmedTitle != null) ...[
                    Text(
                      poll.trimmedTitle!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: CafeinTypography.pollTitle(colors.onSurface),
                    ),
                    if (poll.question.trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        poll.question,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: CafeinTypography.commentBody(colors.onSurface),
                      ),
                    ],
                  ] else if (poll.question.trim().isNotEmpty)
                    Text(
                      poll.question,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: CafeinTypography.pollTitle(colors.onSurface),
                    ),
                ],
              ),
            ),
            if (onEditPoll != null) ...[
              const SizedBox(width: 8),
              GestureDetector(
                onTap: onEditPoll,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.only(left: 4, top: 1),
                  child: Text(
                    '투표 수정',
                    style: CafeinTypography.metadata(colors.secondaryText)
                        .copyWith(fontWeight: FontWeight.w500),
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        for (final option in poll.options)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: _FeedVoteOption(
              title: option.text,
              percentage: showResults
                  ? '${total == 0 ? 0 : ((option.votes / total) * 100).round()}%'
                  : null,
              isSelected: poll.hasVoted && option.selectedByMe,
              onTap: !canVote ? null : () => onVote!(option.id),
            ),
          ),
        if (showResults)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Text(
              '총 $total명 참여',
              style: CafeinTypography.metadata(colors.muted),
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
    final fg = isSelected ? colors.onSurface : colors.secondaryText;

    return Material(
      color: colors.fill,
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
                Icon(Icons.check, size: 15, color: fg),
                const SizedBox(width: 7),
              ],
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: CafeinTypography.pollOption(fg).copyWith(
                    fontWeight:
                        isSelected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
              if (percentage != null)
                Text(
                  percentage!,
                  style: CafeinTypography.reaction(fg).copyWith(
                    fontWeight:
                        isSelected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
