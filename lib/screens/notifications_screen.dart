import 'package:flutter/material.dart';

import '../models/app_notification.dart';
import '../services/auth_service.dart';
import '../services/notification_inbox_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import '../widgets/cafein_back_app_bar.dart';
import 'post_detail_screen.dart';
import 'report_result_screen.dart';

/// In-app notification inbox (reads Cloud Function–written `notifications`).
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final _inbox = NotificationInboxService.instance;
  Object? _error;
  bool _booting = true;
  bool _selecting = false;
  final Set<String> _selectedIds = {};

  @override
  void initState() {
    super.initState();
    _inbox.addListener(_onInbox);
    _boot();
  }

  @override
  void dispose() {
    _inbox.removeListener(_onInbox);
    super.dispose();
  }

  void _onInbox() {
    if (!mounted) return;
    // Drop selection for docs that no longer exist.
    if (_selecting && _selectedIds.isNotEmpty) {
      final alive = _inbox.items.map((n) => n.id).toSet();
      _selectedIds.removeWhere((id) => !alive.contains(id));
    }
    setState(() {});
  }

  Future<void> _boot() async {
    setState(() {
      _booting = true;
      _error = null;
    });
    try {
      await _inbox.load(force: false);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _booting = false);
    }
  }

  Future<void> _refresh() async {
    setState(() => _error = null);
    try {
      await _inbox.load(force: true);
    } catch (e) {
      if (mounted) {
        setState(() => _error = e);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('알림을 불러오지 못했어요.')),
        );
      }
    }
  }

  Future<void> _markAllRead() async {
    if (_inbox.unreadCount <= 0) return;
    try {
      await _inbox.markAllRead();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('모두 읽음 처리했어요.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('모두 읽음 처리에 실패했어요.')),
      );
    }
  }

  void _enterSelectMode() {
    setState(() {
      _selecting = true;
      _selectedIds.clear();
    });
  }

  void _exitSelectMode() {
    setState(() {
      _selecting = false;
      _selectedIds.clear();
    });
  }

  void _toggleSelected(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _toggleSelectAll() {
    final all = _inbox.items.map((n) => n.id).toSet();
    setState(() {
      if (_selectedIds.length == all.length && all.isNotEmpty) {
        _selectedIds.clear();
      } else {
        _selectedIds
          ..clear()
          ..addAll(all);
      }
    });
  }

  Future<void> _deleteSelected() async {
    if (_selectedIds.isEmpty) return;
    final count = _selectedIds.length;
    try {
      await _inbox.deleteNotifications(_selectedIds.toList());
      if (!mounted) return;
      _exitSelectMode();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('알림 $count개를 삭제했어요.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('알림을 삭제하지 못했어요.')),
      );
    }
  }

  Future<void> _deleteAll() async {
    if (_inbox.items.isEmpty) return;
    final colors = Theme.of(context).colorScheme;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('알림을 모두 삭제할까요?'),
        content: const Text('모든 알림이 삭제됩니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              '삭제',
              style: TextStyle(color: colors.error),
            ),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await _inbox.deleteAllNotifications();
      if (!mounted) return;
      _exitSelectMode();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('알림을 모두 삭제했어요.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('알림을 삭제하지 못했어요.')),
      );
    }
  }

  Future<void> _open(AppNotification n) async {
    if (_selecting) {
      _toggleSelected(n.id);
      return;
    }

    try {
      await _inbox.markRead(n.id);
    } catch (_) {
      // Still navigate; read state may retry next refresh.
    }
    if (!mounted) return;

    final type = n.type.trim().toLowerCase();
    if (type == 'report_result') {
      final audience =
          n.commentId.trim().toLowerCase() == 'reported' ? 'reported' : 'reporter';
      final warned = n.message.contains('경고');
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => ReportResultScreen(
            audience: audience,
            action: warned ? 'user_warned' : '',
            messageOverride: n.message.isEmpty ? null : n.message,
          ),
        ),
      );
      return;
    }

    final postId = n.postId.trim();
    if (postId.isEmpty) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => PostDetailScreen(
          postId: postId,
          forceRefreshOnOpen: true,
        ),
      ),
    );
  }

  List<Widget> _appBarActions(bool loggedIn) {
    if (!loggedIn) return const [];

    if (_selecting) {
      final allCount = _inbox.items.length;
      final allSelected =
          allCount > 0 && _selectedIds.length == allCount;
      final hasSelection = _selectedIds.isNotEmpty;
      return [
        TextButton(
          onPressed: allCount == 0 ? null : _toggleSelectAll,
          child: Text(
            allSelected ? '선택 해제' : '전체 선택',
            style: CafeinTypography.button(),
          ),
        ),
        if (hasSelection)
          TextButton(
            onPressed: _deleteSelected,
            child: Text(
              '삭제(${_selectedIds.length})',
              style: CafeinTypography.button(
                Theme.of(context).colorScheme.error,
              ),
            ),
          )
        else
          TextButton(
            onPressed: allCount == 0 ? null : _deleteAll,
            child: Text(
              '전체 삭제',
              style: CafeinTypography.button(),
            ),
          ),
      ];
    }

    return [
      if (_inbox.unreadCount > 0)
        TextButton(
          onPressed: _markAllRead,
          child: Text(
            '모두 읽음',
            style: CafeinTypography.button(),
          ),
        ),
      if (_inbox.items.isNotEmpty)
        TextButton(
          onPressed: _enterSelectMode,
          child: Text(
            '선택',
            style: CafeinTypography.button(),
          ),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final loggedIn = AuthService.instance.canWriteContent;

    return Scaffold(
      appBar: CafeinBackAppBar(
        title: _selecting
            ? (_selectedIds.isEmpty
                ? '선택'
                : '${_selectedIds.length}개 선택')
            : '알림',
        onBack: _selecting
            ? () {
                _exitSelectMode();
              }
            : null,
        actions: _appBarActions(loggedIn),
      ),
      body: !loggedIn
          ? Center(
              child: Text(
                '로그인 후 알림을 확인할 수 있어요.',
                style: CafeinTypography.commentBody(colors.muted),
              ),
            )
          : _booting && _inbox.items.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : _error != null && _inbox.items.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '알림을 불러오지 못했어요.',
                            style: CafeinTypography.commentBody(colors.muted),
                          ),
                          const SizedBox(height: 12),
                          TextButton(
                            onPressed: _boot,
                            child: const Text('다시 시도'),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _selecting ? () async {} : _refresh,
                      child: _inbox.items.isEmpty
                          ? ListView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              children: [
                                SizedBox(
                                  height:
                                      MediaQuery.sizeOf(context).height * 0.35,
                                ),
                                Text(
                                  '알림이 없어요',
                                  textAlign: TextAlign.center,
                                  style: CafeinTypography.nickname(
                                    colors.onSurface,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '아직 받은 알림이 없습니다.',
                                  textAlign: TextAlign.center,
                                  style: CafeinTypography.commentBody(
                                    colors.muted,
                                  ),
                                ),
                              ],
                            )
                          : ListView.separated(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.only(bottom: 40),
                              itemCount: _inbox.items.length,
                              separatorBuilder: (_, _) => Divider(
                                height: 0.5,
                                thickness: 0.5,
                                color: colors.onSurface.withValues(alpha: 0.08),
                              ),
                              itemBuilder: (context, index) {
                                final n = _inbox.items[index];
                                return _NotificationTile(
                                  notification: n,
                                  selecting: _selecting,
                                  selected: _selectedIds.contains(n.id),
                                  onTap: () => _open(n),
                                );
                              },
                            ),
                    ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({
    required this.notification,
    required this.onTap,
    this.selecting = false,
    this.selected = false,
  });

  final AppNotification notification;
  final VoidCallback onTap;
  final bool selecting;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final n = notification;
    final unread = !n.isRead;
    final message = composeNotificationDisplayMessage(n);
    final when = n.createdAt == null
        ? ''
        : formatNotificationTime(n.createdAt!);
    final bodyStyle = CafeinTypography.postBody(colors.onSurface);

    return Material(
      color: unread
          ? colors.onSurface.withValues(alpha: 0.04)
          : colors.surface,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenH,
            14,
            AppSpacing.screenH,
            14,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (selecting)
                Padding(
                  padding: const EdgeInsets.only(right: 10, top: 2),
                  child: Icon(
                    selected
                        ? Icons.check_box
                        : Icons.check_box_outline_blank,
                    size: 22,
                    color: selected
                        ? colors.onSurface
                        : colors.onSurface.withValues(alpha: 0.35),
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Icon(
                    unread ? Icons.circle : Icons.circle_outlined,
                    size: 8,
                    color: unread
                        ? colors.onSurface
                        : colors.onSurface.withValues(alpha: 0.25),
                  ),
                ),
              if (!selecting) const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      notificationTypeLabel(n.type),
                      style: CafeinTypography.nickname(colors.onSurface),
                    ),
                    const SizedBox(height: 4),
                    _NotificationMessageText(
                      type: n.type,
                      message: message,
                      style: bodyStyle,
                    ),
                    if (when.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        when,
                        style: CafeinTypography.metadata(colors.muted),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Renders social notification messages with the quoted preview in w600.
class _NotificationMessageText extends StatelessWidget {
  const _NotificationMessageText({
    required this.type,
    required this.message,
    required this.style,
  });

  final String type;
  final String message;
  final TextStyle style;

  static final _quotedPreview = RegExp(r'"([^"]*)"');

  bool get _isSocial {
    switch (type.trim().toLowerCase()) {
      case 'comment':
      case 'like':
      case 'comment_like':
        return true;
      default:
        return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isSocial) {
      return Text(
        message,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: style,
      );
    }

    final match = _quotedPreview.firstMatch(message);
    if (match == null) {
      return Text(
        message,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: style,
      );
    }

    final bold = style.copyWith(fontWeight: FontWeight.w600);
    final before = message.substring(0, match.start);
    final quoted = match.group(0)!;
    final after = message.substring(match.end);

    return Text.rich(
      TextSpan(
        children: [
          if (before.isNotEmpty) TextSpan(text: before, style: style),
          TextSpan(text: quoted, style: bold),
          if (after.isNotEmpty) TextSpan(text: after, style: style),
        ],
      ),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }
}
