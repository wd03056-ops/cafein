import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import 'login_screen.dart';

/// Guest write/comment/like/vote gate — opens the single Kakao login screen.
class AuthRequiredScreen {
  AuthRequiredScreen._();

  /// Opens [LoginScreen] once when the user cannot write yet.
  /// Returns true when the user can write content afterwards.
  static Future<bool> ensureWriter(BuildContext context) async {
    if (AuthService.instance.canWriteContent) return true;
    final authReady = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) => const LoginScreen()),
    );
    return authReady == true && AuthService.instance.canWriteContent;
  }
}
