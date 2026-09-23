import 'package:flutter/material.dart';

import '../core/time_format.dart';
import '../models/report.dart';
import '../services/admin_access.dart';
import '../services/report_moderation_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import '../utils/report_labels.dart';
import '../widgets/cafein_back_app_bar.dart';
import 'admin_report_detail_screen.dart';

/// Operator-only reports queue. Not shown to normal users via [AdminAccess].
class AdminReportsScreen extends StatefulWidget {
  const AdminReportsScreen({super.key});

  @override
  State<AdminReportsScreen> createState() => _AdminReportsScreenState();
}

class _AdminReportsScreenState extends State<AdminReportsScreen> {
  /// null = 전체
  ReportStatus? _filter;
  late Future<List<Report>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Report>> _load() {
    return ReportModerationService.instance.listAllReports(status: _filter);
  }

  void _reload() {
    setState(() => _future = _load());
  }

  void _setFilter(ReportStatus? status) {
    if (_filter == status) return;
    setState(() {
      _filter = status;
      _future = _load();
    });
  }

  Future<void> _openDetail(Report report) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => AdminReportDetailScreen(reportId: report.id),
      ),
    );
    if (changed == true && mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    if (!AdminAccess.canOpenAdminUi) {
      return Scaffold(
        appBar: const CafeinBackAppBar(title: '신고 관리'),
        body: Center(
          child: Text(
            '접근 권한이 없어요.',
            style: CafeinTypography.commentBody(colors.muted),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: CafeinBackAppBar(
        title: '신고 관리',
        actions: [
          IconButton(
            tooltip: '새로고침',
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenH,
              8,
              AppSpacing.screenH,
              8,
            ),
            child: Row(
              children: [
                _FilterChip(
                  label: '전체',
                  selected: _filter == null,
                  onTap: () => _setFilter(null),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: reportStatusLabel(ReportStatus.pending),
                  selected: _filter == ReportStatus.pending,
                  onTap: () => _setFilter(ReportStatus.pending),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: reportStatusLabel(ReportStatus.reviewing),
                  selected: _filter == ReportStatus.reviewing,
                  onTap: () => _setFilter(ReportStatus.reviewing),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: reportStatusLabel(ReportStatus.resolved),
                  selected: _filter == ReportStatus.resolved,
                  onTap: () => _setFilter(ReportStatus.resolved),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: reportStatusLabel(ReportStatus.dismissed),
                  selected: _filter == ReportStatus.dismissed,
                  onTap: () => _setFilter(ReportStatus.dismissed),
                ),
              ],
            ),
          ),
          const Divider(height: 0.5, thickness: 0.5),
          Expanded(
            child: FutureBuilder<List<Report>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      '신고 목록을 불러오지 못했어요.',
                      style: CafeinTypography.commentBody(colors.muted),
                    ),
                  );
                }
                final rows = snapshot.data ?? const [];
                if (rows.isEmpty) {
                  return Center(
                    child: Text(
                      '해당 상태의 신고가 없어요.',
                      style: CafeinTypography.commentBody(colors.muted),
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.screenH,
                    8,
                    AppSpacing.screenH,
                    40,
                  ),
                  itemCount: rows.length,
                  separatorBuilder: (_, _) =>
                      const Divider(height: 0.5, thickness: 0.5),
                  itemBuilder: (context, index) {
                    final r = rows[index];
                    final when = r.createdAt == null
                        ? '—'
                        : formatRelativeTime(r.createdAt!);
                    return InkWell(
                      onTap: () => _openDetail(r),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  reportTargetTypeLabel(r.targetType),
                                  style: CafeinTypography.nickname(
                                    colors.onSurface,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  reportStatusLabel(r.status),
                                  style: CafeinTypography.metadata(
                                    colors.muted,
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  when,
                                  style: CafeinTypography.metadata(
                                    colors.muted,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              r.reason.isEmpty ? '사유 없음' : r.reason,
                              style: CafeinTypography.postBody(
                                colors.onSurface,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${reportFieldLabel('targetId')}: '
                              '${r.targetId.isEmpty ? '—' : r.targetId}',
                              style: CafeinTypography.metadata(colors.muted),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: selected ? colors.onSurface : colors.surface,
      shape: StadiumBorder(
        side: BorderSide(color: colors.onSurface.withValues(alpha: 0.2)),
      ),
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(
            label,
            style: CafeinTypography.metadata(
              selected ? colors.surface : colors.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}
