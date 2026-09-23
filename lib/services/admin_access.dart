import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'auth_service.dart';

/// Client-side gate for **showing** admin UI only.
///
/// **Not a security boundary.** Real admin checks run in Cloud Functions
/// (`adminListReports` / `adminGetReport` / `adminResolveReport`) using:
/// 1. Firebase Auth `request.auth.uid` (Custom Token = Kakao user id)
/// 2. Auth custom claim `admin: true` (minted when uid ∈ server `ADMIN_UIDS`)
///
/// UI visibility follows the same claim: [canOpenAdminUi] is true only when
/// the current Firebase ID token has `admin == true`.
/// Never reads `ADMIN_UIDS` or hard-codes Kakao user ids in the client.
class AdminAccess {
  AdminAccess._();

  static bool _adminClaim = false;
  static bool _refreshedOnce = false;

  /// Whether Settings may show the admin reports entry.
  static bool get canOpenAdminUi {
    final kakaoId = AuthService.instance.kakaoUserId?.trim() ?? '';
    if (kakaoId.isEmpty) return false;
    final firebaseUid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
    if (firebaseUid.isEmpty) return false;
    return _adminClaim;
  }

  /// Kakao / Firebase Auth uid of the signed-in operator (for display only).
  /// Server `reviewedBy` always comes from `request.auth.uid`, not this value.
  static String? get currentReviewerId {
    final uid = AuthService.instance.kakaoUserId?.trim() ?? '';
    return uid.isEmpty ? null : uid;
  }

  /// Reload `admin` custom claim from Firebase Auth ID token.
  ///
  /// Call after Custom Token sign-in and when opening Settings.
  /// [forceRefresh] true forces a network token refresh (after login).
  static Future<void> refreshAdminClaim({bool forceRefresh = false}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _adminClaim = false;
      _refreshedOnce = true;
      debugPrint('[ADMIN_ACCESS] adminClaim=false reason=no_firebase_user');
      return;
    }

    try {
      final result = await user.getIdTokenResult(forceRefresh);
      final claim = result.claims?['admin'] == true;
      _adminClaim = claim;
      _refreshedOnce = true;
      debugPrint(
        '[ADMIN_ACCESS] firebaseUid=${user.uid} adminClaim=$claim '
        'refreshedOnce=$_refreshedOnce forceRefresh=$forceRefresh',
      );
    } catch (e) {
      _adminClaim = false;
      _refreshedOnce = true;
      debugPrint('[ADMIN_ACCESS] adminClaim=false error=$e');
    }
  }

  /// Clear cached claim on logout / withdrawal.
  static void clear() {
    _adminClaim = false;
    _refreshedOnce = false;
    debugPrint('[ADMIN_ACCESS] cleared');
  }
}
