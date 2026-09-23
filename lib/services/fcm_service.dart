import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../firebase_options.dart';
import '../navigation/app_navigator.dart';
import '../screens/post_detail_screen.dart';
import '../screens/report_result_screen.dart';
import 'auth_service.dart';
import 'notification_inbox_service.dart';
import 'notification_settings_service.dart';
import 'user_firestore_service.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  debugPrint('[NOTIFICATION] background message type=${message.data['type']}');
}

/// FCM init, token ↔ users/{kakaoId}, foreground display, tap → post detail.
class FcmService {
  FcmService._();
  static final FcmService instance = FcmService._();

  static const _androidChannelId = 'cafein_default';
  static const _androidChannelName = '카페인 알림';

  final _messaging = FirebaseMessaging.instance;
  final _local = FlutterLocalNotificationsPlugin();
  final _firestore = FirebaseFirestore.instance;

  bool _initialized = false;
  String? _currentToken;

  /// Whether a device FCM token is currently known (no token value exposed).
  bool get hasToken => _currentToken != null && _currentToken!.isNotEmpty;

  Future<void> init() async {
    if (_initialized) return;
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    await _initLocalNotifications();
    await _messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    FirebaseMessaging.onMessage.listen(_onForegroundMessage);
    FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageNavigation);

    final initial = await _messaging.getInitialMessage();
    if (initial != null) {
      // Defer until first frame so navigator is ready.
      Future<void>.delayed(const Duration(milliseconds: 800), () {
        _handleMessageNavigation(initial);
      });
    }

    _messaging.onTokenRefresh.listen((token) {
      _currentToken = token;
      unawaited(_saveTokenToUser(token));
    });

    _initialized = true;
    debugPrint('[NOTIFICATION] FCM initialized');
  }

  Future<void> _initLocalNotifications() async {
    const androidInit = AndroidInitializationSettings('@drawable/ic_stat_cafein');
    const iosInit = DarwinInitializationSettings();
    await _local.initialize(
      settings: const InitializationSettings(android: androidInit, iOS: iosInit),
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload == null || payload.isEmpty) return;
        try {
          final data = jsonDecode(payload) as Map<String, dynamic>;
          _openFromNotificationData(data);
        } catch (e) {
          debugPrint('알림 페이로드 파싱 실패: $e');
        }
      },
    );

    if (Platform.isAndroid) {
      await _local
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(
            const AndroidNotificationChannel(
              _androidChannelId,
              _androidChannelName,
              description: '댓글·공감 등 카페인 알림',
              importance: Importance.high,
            ),
          );
    }
  }

  /// Request OS permission when user enables notifications in settings.
  Future<bool> requestPermissionIfNeeded() async {
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    final enabled = settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
    if (!enabled) {
      debugPrint('[NOTIFICATION] notification permission denied');
    }
    return enabled;
  }

  Future<AuthorizationStatus> getPermissionStatus() async {
    final settings = await _messaging.getNotificationSettings();
    return settings.authorizationStatus;
  }

  /// Call after Kakao login + onboarding (or session restore).
  Future<void> registerForUser() async {
    final uid = AuthService.instance.kakaoUserId?.trim() ?? '';
    if (uid.isEmpty || !AuthService.instance.canWriteContent) return;

    await NotificationSettingsService.instance.load();

    try {
      final token = await _messaging.getToken();
      if (token == null || token.isEmpty) return;
      _currentToken = token;
      await _saveTokenToUser(token);
      debugPrint('[NOTIFICATION] FCM token registered');
    } catch (e) {
      debugPrint('FCM 토큰 등록 실패: $e');
    }

    unawaited(NotificationInboxService.instance.warmUnreadBadge());
  }

  Future<void> _saveTokenToUser(String token) async {
    final uid = AuthService.instance.kakaoUserId?.trim() ?? '';
    if (uid.isEmpty) return;
    try {
      final ref = _firestore.collection('users').doc(uid);
      final snap = await UserDocCache.instance.get(uid);
      final data = snap?.data();
      final existing = data?['fcmToken'] as String?;
      final tokens = data?['fcmTokens'];
      final alreadyListed = tokens is List && tokens.contains(token);
      if (existing == token && alreadyListed) {
        debugPrint('[NOTIFICATION] FCM token unchanged — write 생략');
        return;
      }

      await ref.set({
        'fcmToken': token,
        'fcmTokens': FieldValue.arrayUnion([token]),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      UserDocCache.instance.invalidate(uid);
    } catch (e) {
      debugPrint('FCM 토큰 저장 실패: $e');
    }
  }

  Future<void> unregisterCurrentToken() async {
    final uid = AuthService.instance.kakaoUserId?.trim() ?? '';
    final token = _currentToken;
    if (uid.isNotEmpty && token != null && token.isNotEmpty) {
      try {
        await _firestore.collection('users').doc(uid).set({
          'fcmTokens': FieldValue.arrayRemove([token]),
          'fcmToken': FieldValue.delete(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } catch (e) {
        debugPrint('FCM 토큰 해제 실패: $e');
      }
    }
    try {
      await _messaging.deleteToken();
    } catch (e) {
      debugPrint('FCM 토큰 삭제 실패: $e');
    }
    _currentToken = null;
  }

  void _onForegroundMessage(RemoteMessage message) {
    debugPrint(
      '[NOTIFICATION] foreground type=${message.data['type'] ?? ''}',
    );
    // Inbox docs are written by Cloud Functions; only refresh local badge/cache.
    NotificationInboxService.instance.onPushHint();

    final notification = message.notification;
    final title = notification?.title ?? '카페인';
    final body = notification?.body ?? _fallbackBody(message.data['type']);
    _local.show(
      id: message.hashCode,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _androidChannelId,
          _androidChannelName,
          channelDescription: '댓글·공감 등 카페인 알림',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@drawable/ic_stat_cafein',
        ),
        iOS: DarwinNotificationDetails(),
      ),
      payload: jsonEncode(message.data),
    );
  }

  String _fallbackBody(Object? type) {
    switch (type) {
      case 'comment':
        return '게시글에 댓글이 달렸어요.';
      case 'reply':
        return '내 댓글에 답글이 달렸어요.';
      case 'like':
        return '게시글에 공감이 눌렸어요.';
      case 'comment_like':
        return '댓글에 공감이 눌렸어요.';
      case 'report_result':
        return '신고 처리 결과가 도착했어요.';
      default:
        return '새 알림이 있어요.';
    }
  }

  void _handleMessageNavigation(RemoteMessage message) {
    _openFromNotificationData(Map<String, dynamic>.from(message.data));
  }

  /// Routes by [data.type]. report_result never opens deleted post/comment.
  void _openFromNotificationData(Map<String, dynamic> data) {
    final type = '${data['type'] ?? ''}'.trim();
    final nav = appNavigatorKey.currentState;
    if (nav == null) return;

    if (type == 'report_result') {
      final audience = '${data['audience'] ?? ''}'.trim();
      final targetType = '${data['targetType'] ?? ''}'.trim();
      final action = '${data['action'] ?? ''}'.trim();
      nav.push(
        MaterialPageRoute<void>(
          builder: (_) => ReportResultScreen(
            audience: audience.isEmpty ? 'reporter' : audience,
            targetType: targetType,
            action: action,
          ),
        ),
      );
      return;
    }

    final postId = '${data['postId'] ?? ''}'.trim();
    if (postId.isEmpty) return;
    nav.push(
      MaterialPageRoute<void>(
        builder: (_) => PostDetailScreen(
          postId: postId,
          forceRefreshOnOpen: true,
        ),
      ),
    );
  }
}
