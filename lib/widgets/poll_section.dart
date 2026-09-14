import 'package:flutter/material.dart';

import '../models/poll.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          poll.question,
          style: TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: colors.onSurface,
            height: 1.4,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        ...poll.options.map((option) {
          final ratio = total == 0 ? 0.0 : option.votes / total;
          final percent = (ratio * 100).round();
          final selected = option.selectedByMe;

          return Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: _VoteOptionItem(
              title: option.text,
              percentage: poll.hasVoted ? '$percent%' : null,
              isSelected: poll.hasVoted && selected,
              onTap: () {
                if (poll.hasVoted && selected) return;
                onVote(option.id);
              },
            ),
          );
        }),
        if (poll.hasVoted)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(
              '총 $total표 · 다른 선택지를 누르면 투표를 바꿀 수 있어요',
              style: TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 12,
                fontWeight: FontWeight.w400,
                color: colors.muted,
              ),
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

    return Material(
      color: isSelected ? colors.fillStrong : colors.fill,
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
                Icon(Icons.check, size: 16, color: colors.onSurfaceVariant),
                const SizedBox(width: AppSpacing.sm),
              ],
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 14,
                    height: 1.35,
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
                    fontSize: 13,
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
