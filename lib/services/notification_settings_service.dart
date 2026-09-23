import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_service.dart';
import 'user_firestore_service.dart';

/// In-app notification toggles (synced to SharedPreferences + Firestore users).
class CafeinNotificationSettings {
  const CafeinNotificationSettings({
    this.comment = true,
    this.reply = true,
    this.like = true,
  });

  final bool comment;
  final bool reply;
  final bool like;

  CafeinNotificationSettings copyWith({
    bool? comment,
    bool? reply,
    bool? like,
  }) {
    return CafeinNotificationSettings(
      comment: comment ?? this.comment,
      reply: reply ?? this.reply,
      like: like ?? this.like,
    );
  }

  Map<String, dynamic> toMap() => {
        'comment': comment,
        'reply': reply,
        'like': like,
      };

  factory CafeinNotificationSettings.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const CafeinNotificationSettings();
    return CafeinNotificationSettings(
      comment: map['comment'] as bool? ?? true,
      reply: map['reply'] as bool? ?? true,
      like: map['like'] as bool? ?? true,
    );
  }
}

class NotificationSettingsService {
  NotificationSettingsService._();
  static final NotificationSettingsService instance =
      NotificationSettingsService._();

  static const _prefsKey = 'cafein_notification_settings_v1';

  final _firestore = FirebaseFirestore.instance;
  CafeinNotificationSettings _cached = const CafeinNotificationSettings();
  bool _loaded = false;

  CafeinNotificationSettings get current => _cached;

  Future<CafeinNotificationSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          _cached = CafeinNotificationSettings.fromMap(decoded);
        } else if (decoded is Map) {
          _cached = CafeinNotificationSettings.fromMap(
            Map<String, dynamic>.from(decoded),
          );
        }
      } catch (e) {
        debugPrint('알림 설정 로컬 로드 실패: $e');
      }
    }

    final uid = AuthService.instance.kakaoUserId?.trim() ?? '';
    if (uid.isNotEmpty) {
      try {
        final snap = await UserDocCache.instance.get(uid);
        final remote = snap?.data()?['notificationSettings'];
        if (remote is Map) {
          _cached = CafeinNotificationSettings.fromMap(
            Map<String, dynamic>.from(remote),
          );
          await prefs.setString(_prefsKey, jsonEncode(_cached.toMap()));
        }
        // Missing remote map: keep local defaults. Persist only via [update]
        // so app launch / settings open does not seed-write every time.
      } catch (e) {
        debugPrint('알림 설정 원격 로드 실패: $e');
      }
    }

    _loaded = true;
    return _cached;
  }

  Future<void> update({
    bool? comment,
    bool? reply,
    bool? like,
  }) async {
    if (!_loaded) await load();
    _cached = _cached.copyWith(
      comment: comment,
      reply: reply,
      like: like,
    );

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(_cached.toMap()));
    debugPrint('[NOTIFICATION] notification settings updated');

    final uid = AuthService.instance.kakaoUserId?.trim() ?? '';
    if (uid.isEmpty) return;

    try {
      await _firestore.collection('users').doc(uid).set({
        'notificationSettings': _cached.toMap(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      UserDocCache.instance.invalidate(uid);
    } catch (e) {
      debugPrint('알림 설정 원격 저장 실패: $e');
    }
  }

  Future<void> clearLocal() async {
    _cached = const CafeinNotificationSettings();
    _loaded = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
  }
}
