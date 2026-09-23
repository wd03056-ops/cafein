import 'package:flutter/material.dart';

import '../services/anonymous_nickname_resolver.dart';
import '../services/block_firestore_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import '../widgets/cafein_back_app_bar.dart';

/// Settings → 차단한 사용자
class BlockedUsersScreen extends StatefulWidget {
  const BlockedUsersScreen({super.key});

  @override
  State<BlockedUsersScreen> createState() => _BlockedUsersScreenState();
}

class _BlockedUsersScreenState extends State<BlockedUsersScreen> {
  List<_BlockedRow>? _rows;
  Object? _loadError;
  bool _loading = true;
  final Set<String> _unblocking = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final blocks = await BlockFirestoreService.instance.listMyBlocks();
      final rows = <_BlockedRow>[];
      for (final b in blocks) {
        final nick = await resolveAnonymousNickname(b.blockedUserId);
        rows.add(_BlockedRow(userId: b.blockedUserId, nickname: nick));
      }
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e;
        _loading = false;
      });
    }
  }

  Future<void> _unblock(String userId) async {
    if (_unblocking.contains(userId)) return;
    setState(() => _unblocking.add(userId));

    try {
      await BlockFirestoreService.instance.unblockUser(userId);
      if (!mounted) return;

      // Unblock succeeded — update local list immediately (do not treat UI
      // refresh failures as unblock failures).
      setState(() {
        _rows = [...?_rows]..removeWhere((r) => r.userId == userId);
        _unblocking.remove(userId);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('차단을 해제했어요.')),
      );
    } catch (e) {
      debugPrint('차단 해제 실패: $e');
      if (!mounted) return;
      setState(() => _unblocking.remove(userId));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('차단 해제에 실패했어요.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: const CafeinBackAppBar(title: '차단한 사용자'),
      body: _buildBody(colors),
    );
  }

  Widget _buildBody(ColorScheme colors) {
    if (_loading && _rows == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_loadError != null && _rows == null) {
      return Center(
        child: Text(
          '목록을 불러오지 못했어요.',
          style: CafeinTypography.commentBody(colors.muted),
        ),
      );
    }

    final rows = _rows ?? const <_BlockedRow>[];
    if (rows.isEmpty) {
      return Center(
        child: Text(
          '차단한 사용자가 없어요.',
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
      separatorBuilder: (_, _) => const Divider(height: 0.5, thickness: 0.5),
      itemBuilder: (context, index) {
        final row = rows[index];
        final busy = _unblocking.contains(row.userId);
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  row.nickname,
                  style: CafeinTypography.nickname(colors.onSurface),
                ),
              ),
              TextButton(
                onPressed: busy ? null : () => _unblock(row.userId),
                child: Text(
                  busy ? '해제 중…' : '차단 해제',
                  style: CafeinTypography.button(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _BlockedRow {
  const _BlockedRow({required this.userId, required this.nickname});

  final String userId;
  final String nickname;
}
