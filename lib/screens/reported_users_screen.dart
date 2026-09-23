import 'package:flutter/material.dart';

import '../services/anonymous_nickname_resolver.dart';
import '../services/report_firestore_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import '../widgets/cafein_back_app_bar.dart';

/// Settings → 신고한 사용자
class ReportedUsersScreen extends StatefulWidget {
  const ReportedUsersScreen({super.key});

  @override
  State<ReportedUsersScreen> createState() => _ReportedUsersScreenState();
}

class _ReportedUsersScreenState extends State<ReportedUsersScreen> {
  late Future<List<_ReportRow>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<_ReportRow>> _load() async {
    final reports = await ReportFirestoreService.instance.listMyReports();
    final rows = <_ReportRow>[];
    for (final r in reports) {
      final authorId = r.targetAuthorId.trim();
      final nick = authorId.isEmpty
          ? '익명'
          : await resolveAnonymousNickname(authorId);
      rows.add(
        _ReportRow(
          reportId: r.id,
          nickname: nick,
          reason: r.reason.isEmpty ? '사유 없음' : r.reason,
        ),
      );
    }
    return rows;
  }

  Future<void> _reload() async {
    setState(() => _future = _load());
  }

  Future<void> _withdraw(String reportId) async {
    try {
      await ReportFirestoreService.instance.withdrawReport(reportId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('신고를 철회했어요.')),
      );
      await _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('신고 철회에 실패했어요.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: const CafeinBackAppBar(title: '신고한 사용자'),
      body: FutureBuilder<List<_ReportRow>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Text(
                '목록을 불러오지 못했어요.',
                style: CafeinTypography.commentBody(colors.muted),
              ),
            );
          }
          final rows = snapshot.data ?? const [];
          if (rows.isEmpty) {
            return Center(
              child: Text(
                '신고한 사용자가 없어요.',
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
              final row = rows[index];
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            row.nickname,
                            style: CafeinTypography.nickname(colors.onSurface),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '사유: ${row.reason}',
                            style: CafeinTypography.metadata(colors.muted),
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: () => _withdraw(row.reportId),
                      child: Text(
                        '신고 철회',
                        style: CafeinTypography.button(),
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _ReportRow {
  const _ReportRow({
    required this.reportId,
    required this.nickname,
    required this.reason,
  });

  final String reportId;
  final String nickname;
  final String reason;
}
