import 'package:flutter/material.dart';
import 'package:kakao_flutter_sdk/kakao_flutter_sdk.dart';

import 'auth_service.dart';
import '../screens/main_shell.dart';

/// Kakao logout + clear app session, then open feed (guest browse).
Future<void> handleLogout(BuildContext context) async {
  try {
    await UserApi.instance.logout();
    debugPrint('카카오 로그아웃 성공');
  } catch (error) {
    debugPrint('카카오 로그아웃 실패: $error');
  }

  AuthService.instance.clearSession();

  if (!context.mounted) return;
  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute<void>(builder: (_) => const MainShell()),
    (route) => false,
  );
}
