import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import '../widgets/cafein_back_app_bar.dart';

/// Shown when a [report_result] FCM / local notification is tapped.
///
/// Does not open deleted post/comment detail.
/// Does not expose sanction details or other users' personal info.
class ReportResultScreen extends StatelessWidget {
  const ReportResultScreen({
    super.key,
    required this.audience,
    this.targetType = '',
    this.action = '',
    this.messageOverride,
  });

  /// `reporter` | `reported` (from FCM data).
  final String audience;
  final String targetType;

  /// `content_deleted` | `user_warned` | … (from FCM data).
  final String action;

  /// Inbox message when opening from in-app notifications.
  final String? messageOverride;

  bool get _isReporter => audience.trim().toLowerCase() == 'reporter';

  bool get _isWarned =>
      action.trim().toLowerCase() == 'user_warned';

  String get _title {
    if (_isReporter) return '신고가 처리되었습니다.';
    if (_isWarned) return '운영정책 관련 안내';
    if (targetType.trim().toLowerCase() == 'comment') {
      return '댓글이 운영정책에 따라 처리되었습니다.';
    }
    return '게시글이 운영정책에 따라 처리되었습니다.';
  }

  String get _body {
    final override = messageOverride?.trim() ?? '';
    if (override.isNotEmpty) return override;
    if (_isReporter) {
      return '신고하신 내용을 운영자가 확인하고 처리했습니다.';
    }
    if (_isWarned) {
      return '신고된 콘텐츠를 검토한 결과 운영정책에 따라 '
          '경고 조치되었습니다.';
    }
    return '신고된 콘텐츠를 검토한 결과 운영정책에 따라 '
        '해당 콘텐츠가 삭제되었습니다.';
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: const CafeinBackAppBar(title: '알림'),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenH,
          24,
          AppSpacing.screenH,
          40,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _title,
              style: CafeinTypography.postTitle(colors.onSurface),
            ),
            const SizedBox(height: 12),
            Text(
              _body,
              style: CafeinTypography.postBody(colors.onSurface),
            ),
            const SizedBox(height: 24),
            Text(
              '자세한 제재 내용이나 다른 사용자 정보는 표시되지 않습니다.',
              style: CafeinTypography.metadata(colors.muted),
            ),
          ],
        ),
      ),
    );
  }
}
