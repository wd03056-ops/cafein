import 'package:flutter/material.dart';

/// Report reason picker. Caller persists via [onSubmit].
class ReportBottomSheet extends StatefulWidget {
  const ReportBottomSheet({
    super.key,
    required this.onSubmit,
  });

  final ValueChanged<String> onSubmit;

  static const reasons = [
    '욕설/비방',
    '성적인 내용',
    '개인정보 노출',
    '광고/스팸',
    '불법/부적절한 내용',
    '기타',
  ];

  static Future<void> show(
    BuildContext context, {
    required ValueChanged<String> onSubmit,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => ReportBottomSheet(onSubmit: onSubmit),
    );
  }

  @override
  State<ReportBottomSheet> createState() => _ReportBottomSheetState();
}

class _ReportBottomSheetState extends State<ReportBottomSheet> {
  String? _selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Text(
                '신고 사유를 선택해주세요',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: colors.onSurface,
                ),
              ),
            ),
            ...ReportBottomSheet.reasons.map((reason) {
              final selected = _selected == reason;
              return ListTile(
                title: Text(
                  reason,
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 15,
                    color: colors.onSurface,
                  ),
                ),
                leading: Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  color: colors.onSurface,
                  size: 22,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                onTap: () => setState(() => _selected = reason),
              );
            }),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: FilledButton(
                onPressed: _selected == null
                    ? null
                    : () {
                        final reason = _selected!;
                        Navigator.pop(context);
                        widget.onSubmit(reason);
                      },
                style: FilledButton.styleFrom(
                  backgroundColor: colors.onSurface,
                  foregroundColor: colors.surface,
                  disabledBackgroundColor:
                      colors.onSurface.withValues(alpha: 0.2),
                  minimumSize: const Size.fromHeight(48),
                ),
                child: const Text(
                  '신고하기',
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
