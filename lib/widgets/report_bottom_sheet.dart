import 'package:flutter/material.dart';

/// Report reason picker UI. Server save is wired later.
class ReportBottomSheet extends StatelessWidget {
  const ReportBottomSheet({
    super.key,
    required this.onSubmit,
  });

  final ValueChanged<String> onSubmit;

  static const reasons = [
    '욕설/비방',
    '광고/홍보',
    '개인정보 노출',
    '허위/악의적인 내용',
    '기타',
  ];

  static Future<void> show(
    BuildContext context, {
    required ValueChanged<String> onSubmit,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => ReportBottomSheet(onSubmit: onSubmit),
    );
  }

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
            ...reasons.map(
              (reason) => ListTile(
                title: Text(
                  reason,
                  style: TextStyle(color: colors.onSurface),
                ),
                onTap: () {
                  Navigator.pop(context);
                  onSubmit(reason);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
