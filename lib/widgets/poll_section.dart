import 'package:flutter/material.dart';

import '../models/poll.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

class PollSection extends StatelessWidget {
  const PollSection({
    super.key,
    required this.poll,
    required this.onVote,
  });

  final Poll poll;
  final ValueChanged<String> onVote;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final total = poll.totalVotes;
    final showResults = poll.hasVoted || total > 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (poll.trimmedTitle != null) ...[
          Text(
            poll.trimmedTitle!,
            style: CafeinTypography.pollTitle(colors.onSurface),
          ),
          if (poll.question.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              poll.question,
              style: CafeinTypography.commentBody(colors.onSurface),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
        ] else if (poll.question.trim().isNotEmpty) ...[
          Text(
            poll.question,
            style: CafeinTypography.pollTitle(colors.onSurface),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        ...poll.options.map((option) {
          final ratio = total == 0 ? 0.0 : option.votes / total;
          final percent = (ratio * 100).round();
          final selected = option.selectedByMe;

          return Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: _VoteOptionItem(
              title: option.text,
              percentage: showResults ? '$percent%' : null,
              isSelected: poll.hasVoted && selected,
              onTap: () => onVote(option.id),
            ),
          );
        }),
        if (showResults)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Text(
              poll.hasVoted && poll.options.any((o) => o.selectedByMe)
                  ? '총 $total명 참여 · 같은 선택지를 다시 누르면 취소할 수 있어요'
                  : '총 $total명 참여',
              style: CafeinTypography.metadata(colors.muted),
            ),
          ),
      ],
    );
  }
}

class _VoteOptionItem extends StatelessWidget {
  const _VoteOptionItem({
    required this.title,
    required this.isSelected,
    required this.onTap,
    this.percentage,
  });

  final String title;
  final String? percentage;
  final bool isSelected;
  final VoidCallback onTap;

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
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              if (isSelected) ...[
                Icon(Icons.check, size: 16, color: fg),
                const SizedBox(width: AppSpacing.sm),
              ],
              Expanded(
                child: Text(
                  title,
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
