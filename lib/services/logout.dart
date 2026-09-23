import 'package:flutter/material.dart';
import 'package:kakao_flutter_sdk/kakao_flutter_sdk.dart';

import '../screens/main_shell.dart';
import 'auth_service.dart';
import 'fcm_service.dart';
import 'firebase_auth_bridge.dart';
import 'admin_access.dart';
import 'notification_inbox_service.dart';

/// Kakao logout + Firebase Auth signOut + clear app session → guest feed.
Future<void> handleLogout(BuildContext context) async {
  try {
    await FcmService.instance.unregisterCurrentToken();
  } catch (e) {
    debugPrint('로그아웃 시 FCM 토큰 정리 실패: $e');
  }

  try {
    await UserApi.instance.logout();
    debugPrint('카카오 로그아웃 성공');
  } catch (error) {
    debugPrint('카카오 로그아웃 실패: $error');
  }

  await FirebaseAuthBridge.instance.signOut();

  AuthService.instance.clearSession();
  AdminAccess.clear();
  NotificationInboxService.instance.clearLocal();

  if (!context.mounted) return;
  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute<void>(builder: (_) => const MainShell()),
    (route) => false,
  );
}
