import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Multi-uid → current `users/{uid}.nickname` memory cache.
///
/// Avoids one get() per list row: same author is resolved once per process
/// until [invalidate]. Not a long-lived snapshots listener.
class NicknameLookupCache {
  NicknameLookupCache._();
  static final NicknameLookupCache instance = NicknameLookupCache._();

  final _firestore = FirebaseFirestore.instance;
  final Map<String, String> _nicks = {};
  final Map<String, Future<String?>> _inflight = {};

  /// Cached nickname if present (may be empty string for known-missing).
  String? peek(String uid) {
    final id = uid.trim();
    if (id.isEmpty) return null;
    return _nicks[id];
  }

  /// Seed / overwrite after nickname claim (no network).
  void put(String uid, String nickname) {
    final id = uid.trim();
    final nick = nickname.trim();
    if (id.isEmpty || nick.isEmpty) return;
    _nicks[id] = nick;
  }

  void invalidate([String? uid]) {
    final id = uid?.trim() ?? '';
    if (id.isEmpty) {
      _nicks.clear();
      _inflight.clear();
      return;
    }
    _nicks.remove(id);
    _inflight.remove(id);
  }

  Future<String?> resolve(String uid, {bool force = false}) async {
    final id = uid.trim();
    if (id.isEmpty) return null;
    if (!force && _nicks.containsKey(id)) {
      final cached = _nicks[id]!;
      return cached.isEmpty ? null : cached;
    }
    if (!force) {
      final pending = _inflight[id];
      if (pending != null) return pending;
    }

    final future = _fetch(id);
    _inflight[id] = future;
    try {
      return await future;
    } finally {
      _inflight.remove(id);
    }
  }

  /// Resolve many uids with shared cache; parallel gets for misses only.
  Future<Map<String, String>> resolveMany(Iterable<String> uids) async {
    final unique = <String>{};
    for (final u in uids) {
      final id = u.trim();
      if (id.isNotEmpty) unique.add(id);
    }
    if (unique.isEmpty) return const {};

    final result = <String, String>{};
    final misses = <String>[];
    for (final id in unique) {
      if (_nicks.containsKey(id)) {
        final n = _nicks[id]!;
        if (n.isNotEmpty) result[id] = n;
      } else {
        misses.add(id);
      }
    }

    if (misses.isEmpty) return result;

    await Future.wait(misses.map((id) async {
      final nick = await resolve(id);
      if (nick != null && nick.isNotEmpty) {
        result[id] = nick;
      }
    }));
    return result;
  }

  Future<String?> _fetch(String id) async {
    try {
      final snap = await _firestore.collection('users').doc(id).get();
      final data = snap.data();
      final nick = (data?['nickname'] as String?)?.trim() ??
          (data?['kakaoNickname'] as String?)?.trim() ??
          '';
      _nicks[id] = nick;
      return nick.isEmpty ? null : nick;
    } catch (e) {
      debugPrint('[NICK_CACHE] resolve failed uid=$id error=$e');
      return null;
    }
  }
}
