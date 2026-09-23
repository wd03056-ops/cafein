import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/time_format.dart';
import '../models/report.dart';
import '../services/admin_access.dart';
import '../services/post_service.dart';
import '../services/report_moderation_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import '../utils/report_labels.dart';
import '../widgets/cafein_back_app_bar.dart';

/// Operator report detail + moderation actions.
/// Mutations go through Cloud Functions ([ReportModerationService]), not client Firestore.
class AdminReportDetailScreen extends StatefulWidget {
  const AdminReportDetailScreen({super.key, required this.reportId});

  final String reportId;

  @override
  State<AdminReportDetailScreen> createState() =>
      _AdminReportDetailScreenState();
}

class _AdminReportDetailScreenState extends State<AdminReportDetailScreen> {
  Report? _report;
  ReportContentSnapshot? _liveTarget;
  ReportContentSnapshot? _liveParentPost;
  Object? _error;
  bool _loading = true;
  bool _busy = false;
  bool _changed = false;

  late final TextEditingController _noteController;
  ReportAction _selectedAction = ReportAction.contentDeleted;

  @override
  void initState() {
    super.initState();
    _noteController = TextEditingController();
    _load();
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final detail =
          await ReportModerationService.instance.getReport(widget.reportId);
      if (!mounted) return;
      if (detail == null) {
        setState(() {
          _report = null;
          _liveTarget = null;
          _liveParentPost = null;
          _loading = false;
          _error = 'not_found';
        });
        return;
      }
      final report = detail.report;
      _noteController.text = report.adminNote ?? '';
      if (report.action != ReportAction.none) {
        _selectedAction = report.action;
      }
      setState(() {
        _report = report;
        _liveTarget = detail.liveTarget;
        _liveParentPost = detail.liveParentPost;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  String? get _reviewerId => AdminAccess.currentReviewerId;

  Future<void> _run(
    Future<Report> Function() action, {
    String successMessage = '저장했어요.',
    void Function(Report updated)? afterSuccess,
  }) async {
    final reviewer = _reviewerId;
    if (reviewer == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('로그인 후 처리할 수 있어요.')),
      );
      return;
    }
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final updated = await action();
      if (!mounted) return;
      afterSuccess?.call(updated);
      _noteController.text = updated.adminNote ?? _noteController.text;
      if (updated.action != ReportAction.none) {
        _selectedAction = updated.action;
      }
      setState(() {
        _report = updated;
        _changed = true;
        _busy = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(successMessage)),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('처리에 실패했어요. ($e)')),
      );
    }
  }

  Future<void> _startReview() async {
    final reviewer = _reviewerId;
    if (reviewer == null) return;
    await _run(
      () => ReportModerationService.instance.reviewReport(
        reportId: widget.reportId,
        reviewedBy: reviewer,
        adminNote: _noteController.text.trim().isEmpty
            ? null
            : _noteController.text.trim(),
      ),
    );
  }

  Future<void> _dismiss() async {
    final reviewer = _reviewerId;
    if (reviewer == null) return;
    await _run(
      () => ReportModerationService.instance.dismissReport(
        reportId: widget.reportId,
        reviewedBy: reviewer,
        adminNote: _noteController.text.trim(),
      ),
    );
  }

  /// Warn target user (no content delete), then resolve with user_warned.
  Future<void> _resolveByWarning() async {
    final reviewer = _reviewerId;
    if (reviewer == null) return;
    final report = _report;
    if (report == null) return;

    if (report.targetAuthorId.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('대상 작성자 ID가 없어 경고를 기록할 수 없어요.'),
        ),
      );
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('경고 처리'),
        content: const Text(
          '피신고자에게 경고를 기록하고 신고를 처리 완료로 저장합니다.\n'
          '게시글·댓글은 삭제되지 않습니다.\n'
          '신고자/피신고자에게 알림이 발송됩니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('경고 처리'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    await _run(
      () => ReportModerationService.instance.resolveByWarning(
        reportId: widget.reportId,
        reviewedBy: reviewer,
        adminNote: _noteController.text.trim(),
      ),
      successMessage: '경고를 기록하고 신고를 처리 완료했어요.',
    );
  }

  /// Deletes post/comment first, then resolves with content_deleted.
  Future<void> _resolveByDeletingContent() async {
    final reviewer = _reviewerId;
    if (reviewer == null) return;
    final report = _report;
    if (report == null) return;

    final type = report.targetType.trim().toLowerCase();
    if (type == 'user') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('사용자 대상 콘텐츠 삭제는 아직 지원하지 않아요.'),
        ),
      );
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('콘텐츠 삭제 후 처리 완료'),
        content: Text(
          type == 'comment'
              ? '신고된 댓글을 삭제하고 신고를 처리 완료로 저장합니다.\n'
                  '실제 삭제가 성공한 뒤에만 상태가 바뀝니다.'
              : '신고된 게시글을 삭제하고 신고를 처리 완료로 저장합니다.\n'
                  '댓글·공감·투표 등 관련 데이터도 함께 정리됩니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              '삭제 후 완료',
              style: TextStyle(color: Theme.of(ctx).colorScheme.error),
            ),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    await _run(
      () => ReportModerationService.instance.resolveByDeletingContent(
        reportId: widget.reportId,
        reviewedBy: reviewer,
        adminNote: _noteController.text.trim(),
      ),
      successMessage: '콘텐츠를 삭제하고 신고를 처리 완료했어요.',
      afterSuccess: (updated) {
        // Drop local feed cache for deleted post targets.
        final type = updated.targetType.trim().toLowerCase();
        if (type == 'post' && updated.targetId.trim().isNotEmpty) {
          PostService.instance.deletePost(updated.targetId.trim());
        }
      },
    );
  }

  void _copy(String label, String value) {
    if (value.isEmpty) return;
    Clipboard.setData(ClipboardData(text: value));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label 복사했어요.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        Navigator.of(context).pop(_changed);
      },
      child: Scaffold(
        appBar: CafeinBackAppBar(
          title: '신고 상세',
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(_changed),
              child: Text('닫기', style: CafeinTypography.button()),
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null || _report == null
                ? Center(
                    child: Text(
                      '신고를 불러오지 못했어요.',
                      style: CafeinTypography.commentBody(colors.muted),
                    ),
                  )
                : _buildBody(colors, _report!),
      ),
    );
  }

  Widget _buildBody(ColorScheme colors, Report r) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenH,
        8,
        AppSpacing.screenH,
        40,
      ),
      children: [
        _buildReportedContentSection(colors, r),
        const SizedBox(height: 20),
        const Divider(height: 0.5, thickness: 0.5),
        const SizedBox(height: 16),
        _FieldRow(
          label: reportFieldLabel('status'),
          value: reportStatusLabel(r.status),
        ),
        _FieldRow(
          label: reportFieldLabel('action'),
          value: reportActionLabel(r.action),
        ),
        _FieldRow(
          label: reportFieldLabel('targetType'),
          value: reportTargetTypeLabel(r.targetType),
        ),
        _FieldRow(
          label: reportFieldLabel('targetId'),
          value: r.targetId,
          onCopy: () => _copy(reportFieldLabel('targetId'), r.targetId),
        ),
        _FieldRow(
          label: reportFieldLabel('targetAuthorId'),
          value: r.targetAuthorId,
          onCopy: () =>
              _copy(reportFieldLabel('targetAuthorId'), r.targetAuthorId),
        ),
        _FieldRow(
          label: reportFieldLabel('reporterId'),
          value: r.reporterId,
          onCopy: () => _copy(reportFieldLabel('reporterId'), r.reporterId),
        ),
        _FieldRow(
          label: reportFieldLabel('parentPostId'),
          value: r.parentPostId ?? '—',
          onCopy: r.parentPostId == null || r.parentPostId!.isEmpty
              ? null
              : () => _copy(
                    reportFieldLabel('parentPostId'),
                    r.parentPostId!,
                  ),
        ),
        _FieldRow(
          label: reportFieldLabel('reason'),
          value: r.reason,
        ),
        _FieldRow(
          label: reportFieldLabel('createdAt'),
          value: r.createdAt == null
              ? '—'
              : '${formatRelativeTime(r.createdAt!)} · ${r.createdAt}',
        ),
        _FieldRow(
          label: reportFieldLabel('reviewedBy'),
          value: r.reviewedBy ?? '—',
        ),
        _FieldRow(
          label: reportFieldLabel('reviewedAt'),
          value: r.reviewedAt == null
              ? '—'
              : '${formatRelativeTime(r.reviewedAt!)} · ${r.reviewedAt}',
        ),
        _FieldRow(
          label: reportFieldLabel('reporterNotified'),
          value: reportBoolLabel(r.reporterNotified),
        ),
        _FieldRow(
          label: reportFieldLabel('reportedUserNotified'),
          value: reportBoolLabel(r.reportedUserNotified),
        ),
        const SizedBox(height: 20),
        const Divider(height: 0.5, thickness: 0.5),
        const SizedBox(height: 16),
        Text(
          reportFieldLabel('adminNote'),
          style: CafeinTypography.nickname(colors.onSurface),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _noteController,
          maxLines: 4,
          style: CafeinTypography.postBody(colors.onSurface),
          decoration: InputDecoration(
            hintText: '관리자 메모 (선택)',
            hintStyle: CafeinTypography.metadata(colors.mutedSoft),
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          '조치',
          style: CafeinTypography.nickname(colors.onSurface),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<ReportAction>(
          // ignore: deprecated_member_use — value still valid on this Flutter SDK
          value: _selectedAction,
          decoration: const InputDecoration(border: OutlineInputBorder()),
          items: [
            DropdownMenuItem(
              value: ReportAction.none,
              child: Text(reportActionLabel(ReportAction.none)),
            ),
            DropdownMenuItem(
              value: ReportAction.contentDeleted,
              child: Text(reportActionLabel(ReportAction.contentDeleted)),
            ),
            DropdownMenuItem(
              value: ReportAction.userWarned,
              child: Text(reportActionLabel(ReportAction.userWarned)),
            ),
            DropdownMenuItem(
              value: ReportAction.userSuspended,
              child: Text(reportActionLabel(ReportAction.userSuspended)),
            ),
          ],
          onChanged: _busy
              ? null
              : (v) {
                  if (v == null) return;
                  setState(() => _selectedAction = v);
                },
        ),
        const SizedBox(height: 24),
        if (_busy) const LinearProgressIndicator(minHeight: 2),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _busy ? null : _startReview,
          style: FilledButton.styleFrom(
            backgroundColor: colors.onSurface,
            foregroundColor: colors.surface,
            minimumSize: const Size.fromHeight(48),
          ),
          child: Text('검토 시작', style: CafeinTypography.button()),
        ),
        const SizedBox(height: 10),
        OutlinedButton(
          onPressed: _busy ? null : _dismiss,
          style: OutlinedButton.styleFrom(
            foregroundColor: colors.onSurface,
            minimumSize: const Size.fromHeight(48),
          ),
          child: Text('문제 없음으로 처리', style: CafeinTypography.button()),
        ),
        const SizedBox(height: 10),
        FilledButton(
          onPressed: _busy ? null : _resolveByDeletingContent,
          style: FilledButton.styleFrom(
            backgroundColor: colors.error,
            foregroundColor: colors.onError,
            minimumSize: const Size.fromHeight(48),
          ),
          child: Text(
            '콘텐츠 삭제 후 처리 완료',
            style: CafeinTypography.button(),
          ),
        ),
        const SizedBox(height: 10),
        FilledButton(
          onPressed: _busy ? null : _resolveByWarning,
          style: FilledButton.styleFrom(
            backgroundColor: colors.onSurface,
            foregroundColor: colors.surface,
            minimumSize: const Size.fromHeight(48),
          ),
          child: Text('경고 처리', style: CafeinTypography.button()),
        ),
        const SizedBox(height: 12),
        Text(
          '「콘텐츠 삭제 후 처리 완료」→ 콘텐츠 삭제\n'
          '「경고 처리」→ 콘텐츠 유지 + 경고 기록 + 알림\n'
          '「사용자 이용 제한」은 아직 지원하지 않습니다.',
          style: CafeinTypography.metadata(colors.muted),
        ),
      ],
    );
  }

  Widget _buildReportedContentSection(ColorScheme colors, Report r) {
    final type = r.targetType.trim().toLowerCase();
    final live = _liveTarget;
    final snap = r.targetSnapshot;
    final ReportContentSnapshot? primary =
        (live != null && live.hasDisplayableContent) ? live : snap;
    final usedSnapshotOnly =
        live == null && snap != null && snap.hasDisplayableContent;

    final parentLive = _liveParentPost;
    final parentSnap = r.parentPostSnapshot;
    final ReportContentSnapshot? parent = (parentLive != null &&
            parentLive.hasDisplayableContent)
        ? parentLive
        : parentSnap;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '신고된 콘텐츠',
          style: CafeinTypography.nickname(colors.onSurface),
        ),
        const SizedBox(height: 10),
        if (primary == null || !primary.hasDisplayableContent)
          Text(
            '신고 대상 콘텐츠를 확인할 수 없습니다.',
            style: CafeinTypography.commentBody(colors.muted),
          )
        else ...[
          if (usedSnapshotOnly)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                '원본이 삭제되어 신고 당시 저장된 내용을 표시합니다.',
                style: CafeinTypography.metadata(colors.muted),
              ),
            ),
          _ContentCard(
            badge: reportTargetTypeLabel(r.targetType),
            snapshot: primary,
            colors: colors,
          ),
          if (type == 'comment' &&
              parent != null &&
              parent.hasDisplayableContent) ...[
            const SizedBox(height: 12),
            Text(
              '원 게시글',
              style: CafeinTypography.metadata(colors.muted),
            ),
            const SizedBox(height: 6),
            _ContentCard(
              badge: '게시글',
              snapshot: parent,
              colors: colors,
              compact: true,
            ),
          ],
        ],
      ],
    );
  }
}

class _ContentCard extends StatelessWidget {
  const _ContentCard({
    required this.badge,
    required this.snapshot,
    required this.colors,
    this.compact = false,
  });

  final String badge;
  final ReportContentSnapshot snapshot;
  final ColorScheme colors;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final body = snapshot.content.trim();
    final when = snapshot.createdAt == null
        ? null
        : formatRelativeTime(snapshot.createdAt!);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: colors.onSurface.withValues(alpha: 0.12)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '[$badge]',
            style: CafeinTypography.metadata(colors.muted),
          ),
          if (body.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              body,
              style: CafeinTypography.postBody(colors.onSurface),
            ),
          ],
          if (snapshot.pollQuestion.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              '투표: ${snapshot.pollQuestion}',
              style: CafeinTypography.commentBody(colors.onSurface),
            ),
            for (final opt in snapshot.pollOptions)
              Text(
                '· $opt',
                style: CafeinTypography.metadata(colors.muted),
              ),
          ],
          if (!compact && snapshot.topicName.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              '주제: ${snapshot.topicName}',
              style: CafeinTypography.metadata(colors.muted),
            ),
          ],
          if (snapshot.authorDisplayName.isNotEmpty || when != null) ...[
            const SizedBox(height: 6),
            Text(
              [
                if (snapshot.authorDisplayName.isNotEmpty)
                  '작성자: ${snapshot.authorDisplayName}',
                if (when != null) '작성일: $when',
              ].join(' · '),
              style: CafeinTypography.metadata(colors.muted),
            ),
          ],
        ],
      ),
    );
  }
}

class _FieldRow extends StatelessWidget {
  const _FieldRow({
    required this.label,
    required this.value,
    this.onCopy,
  });

  final String label;
  final String value;
  final VoidCallback? onCopy;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: CafeinTypography.metadata(colors.muted),
            ),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? '—' : value,
              style: CafeinTypography.postBody(colors.onSurface),
            ),
          ),
          if (onCopy != null)
            IconButton(
              onPressed: onCopy,
              icon: const Icon(Icons.copy, size: 18),
              tooltip: '복사',
              visualDensity: VisualDensity.compact,
            ),
        ],
      ),
    );
  }
}
