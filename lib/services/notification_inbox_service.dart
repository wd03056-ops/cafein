import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/app_notification.dart';
import 'auth_service.dart';
import 'nickname_lookup_cache.dart';

/// In-app notification inbox over Firestore `notifications`.
///
/// Docs are created only by Cloud Functions. This service reads / marks read
/// with one-shot gets + memory cache (no perpetual snapshots).
class NotificationInboxService extends ChangeNotifier {
  NotificationInboxService._();
  static final NotificationInboxService instance = NotificationInboxService._();

  static const _pageLimit = 50;
  static const _cacheTtl = Duration(minutes: 2);

  final _firestore = FirebaseFirestore.instance;

  List<AppNotification>? _items;
  DateTime? _fetchedAt;
  String? _cachedUid;
  int _unreadCount = 0;
  bool _loading = false;

  List<AppNotification> get items =>
      List<AppNotification>.unmodifiable(_items ?? const []);

  int get unreadCount => _unreadCount;

  String get unreadBadgeLabel {
    if (_unreadCount <= 0) return '';
    if (_unreadCount > 99) return '99+';
    return '$_unreadCount';
  }

  bool get isLoading => _loading;

  bool get _hasFreshCache {
    if (_items == null || _fetchedAt == null) return false;
    final uid = AuthService.instance.kakaoUserId?.trim() ?? '';
    if (uid.isEmpty || uid != _cachedUid) return false;
    return DateTime.now().difference(_fetchedAt!) < _cacheTtl;
  }

  CollectionReference<Map<String, dynamic>> get _col =>
      _firestore.collection('notifications');

  /// Warm badge after login / session restore (no-op if guest or cache fresh).
  Future<void> warmUnreadBadge() async {
    final uid = AuthService.instance.kakaoUserId?.trim() ?? '';
    if (uid.isEmpty || !AuthService.instance.canWriteContent) {
      clearLocal();
      return;
    }
    if (_hasFreshCache) return;
    try {
      await load(force: false);
    } catch (e) {
      debugPrint('[INBOX] warmUnreadBadge failed: $e');
    }
  }

  /// Load inbox. Uses memory cache unless [force] (pull-to-refresh / open after stale).
  Future<List<AppNotification>> load({bool force = false}) async {
    final uid = AuthService.instance.kakaoUserId?.trim() ?? '';
    if (uid.isEmpty) {
      clearLocal();
      return const [];
    }

    if (!force && _hasFreshCache) {
      return items;
    }

    _loading = true;
    notifyListeners();

    try {
      final snap = await _col
          .where('recipientUserId', isEqualTo: uid)
          .orderBy('createdAt', descending: true)
          .limit(_pageLimit)
          .get();

      final list = snap.docs
          .map((d) => AppNotification.fromFirestore(d.id, d.data()))
          .toList();

      final withLiveNicks = await _applyLiveActorNicknames(list);

      _items = withLiveNicks;
      _cachedUid = uid;
      _fetchedAt = DateTime.now();
      _unreadCount = withLiveNicks.where((n) => !n.isRead).length;
      _loading = false;
      notifyListeners();
      return items;
    } catch (e) {
      _loading = false;
      notifyListeners();
      debugPrint('[INBOX] load failed: $e');
      rethrow;
    }
  }

  /// Prefer current `users/{actorUserId}.nickname` over CF snapshot.
  Future<List<AppNotification>> _applyLiveActorNicknames(
    List<AppNotification> list,
  ) async {
    if (list.isEmpty) return list;
    final map = await NicknameLookupCache.instance.resolveMany(
      list.map((n) => n.actorUserId),
    );
    if (map.isEmpty) return list;
    final out = <AppNotification>[];
    for (final n in list) {
      final live = map[n.actorUserId.trim()];
      if (live != null && live.isNotEmpty && live != n.actorNickname) {
        out.add(n.copyWith(actorNickname: live));
      } else {
        out.add(n);
      }
    }
    return out;
  }

  /// FCM foreground hint — bump unread and invalidate list cache (no extra write).
  void onPushHint() {
    final uid = AuthService.instance.kakaoUserId?.trim() ?? '';
    if (uid.isEmpty) return;
    _fetchedAt = null;
    _unreadCount += 1;
    notifyListeners();
  }

  Future<void> markRead(String notificationId) async {
    final id = notificationId.trim();
    if (id.isEmpty || _items == null) return;

    final index = _items!.indexWhere((n) => n.id == id);
    if (index < 0) return;
    final prev = _items![index];
    if (prev.isRead) return;

    _items = [
      for (var i = 0; i < _items!.length; i++)
        if (i == index) prev.copyWith(isRead: true) else _items![i],
    ];
    _unreadCount = (_unreadCount - 1).clamp(0, 1 << 30);
    notifyListeners();

    try {
      await _col.doc(id).set({
        'isRead': true,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[INBOX] markRead failed: $e');
      _items = [
        for (var i = 0; i < _items!.length; i++)
          if (i == index) prev else _items![i],
      ];
      _unreadCount = _items!.where((n) => !n.isRead).length;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> markAllRead() async {
    if (_items == null) return;
    final unread = _items!.where((n) => !n.isRead).toList();
    if (unread.isEmpty) return;

    final previous = List<AppNotification>.from(_items!);
    final previousUnread = _unreadCount;

    _items = [
      for (final n in _items!) n.isRead ? n : n.copyWith(isRead: true),
    ];
    _unreadCount = 0;
    notifyListeners();

    try {
      // Firestore batch max 500; inbox capped at 50.
      for (var i = 0; i < unread.length; i += 400) {
        final chunk = unread.skip(i).take(400);
        final batch = _firestore.batch();
        for (final n in chunk) {
          batch.set(
            _col.doc(n.id),
            {
              'isRead': true,
              'updatedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
        }
        await batch.commit();
      }
    } catch (e) {
      debugPrint('[INBOX] markAllRead failed: $e');
      _items = previous;
      _unreadCount = previousUnread;
      notifyListeners();
      rethrow;
    }
  }

  /// Delete selected inbox docs (current user's list). Optimistic + batch.
  Future<void> deleteNotifications(List<String> notificationIds) async {
    final uid = AuthService.instance.kakaoUserId?.trim() ?? '';
    if (uid.isEmpty || _items == null) return;

    final ids = notificationIds
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet();
    if (ids.isEmpty) return;

    final previous = List<AppNotification>.from(_items!);
    final toDelete = previous.where((n) => ids.contains(n.id)).toList();
    if (toDelete.isEmpty) return;

    _items = previous.where((n) => !ids.contains(n.id)).toList();
    _unreadCount = _items!.where((n) => !n.isRead).length;
    _fetchedAt = DateTime.now();
    notifyListeners();

    try {
      for (var i = 0; i < toDelete.length; i += 400) {
        final chunk = toDelete.skip(i).take(400);
        final batch = _firestore.batch();
        for (final n in chunk) {
          batch.delete(_col.doc(n.id));
        }
        await batch.commit();
      }
    } catch (e) {
      debugPrint('[INBOX] deleteNotifications failed: $e');
      _items = previous;
      _unreadCount = previous.where((n) => !n.isRead).length;
      notifyListeners();
      rethrow;
    }
  }

  /// Delete all currently loaded inbox docs (≤ [_pageLimit]).
  Future<void> deleteAllNotifications() async {
    if (_items == null || _items!.isEmpty) return;
    await deleteNotifications(_items!.map((n) => n.id).toList());
  }

  void clearLocal() {
    _items = null;
    _fetchedAt = null;
    _cachedUid = null;
    _unreadCount = 0;
    _loading = false;
    notifyListeners();
  }

  /// Soft-remap actor nicknames in the loaded inbox after a profile rename.
  void remapActorNickname(String actorUserId, String nickname) {
    final uid = actorUserId.trim();
    final nick = nickname.trim();
    if (uid.isEmpty || nick.isEmpty || _items == null) return;
    var changed = false;
    final next = <AppNotification>[];
    for (final n in _items!) {
      if (n.actorUserId.trim() == uid && n.actorNickname != nick) {
        changed = true;
        next.add(n.copyWith(actorNickname: nick));
      } else {
        next.add(n);
      }
    }
    if (!changed) return;
    _items = next;
    notifyListeners();
  }
}
