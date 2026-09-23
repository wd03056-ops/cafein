import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/constants.dart';

/// Resolves the app anonymous nickname for a Kakao user id.
/// Never returns Kakao profile name / email.
Future<String> resolveAnonymousNickname(String userId) async {
  final id = userId.trim();
  if (id.isEmpty) return '익명';

  try {
    final snap =
        await FirebaseFirestore.instance.collection('users').doc(id).get();
    final nick = (snap.data()?['nickname'] as String?)?.trim() ?? '';
    if (nick.isNotEmpty) return nick;
  } catch (_) {
    // Fall through to stable seed nickname.
  }
  return AppConstants.nicknameFor(id);
}
