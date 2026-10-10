import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:kakao_flutter_sdk/kakao_flutter_sdk.dart';

import 'admin_access.dart';

/// Kakao → Firebase Auth Custom Token bridge.
///
/// Does **not** replace Kakao login. After Kakao OAuth succeeds, the app sends
/// the Kakao **access token** to Cloud Function [createFirebaseCustomToken],
/// which verifies it with Kakao's API and returns a Firebase Custom Token
/// whose uid is the verified Kakao user id.
///
/// Failure here must not block Kakao session / existing app features while
/// Firestore Rules remain open. Before Play release, Rules should require
/// `request.auth` — then this bridge becomes mandatory for writes.
class FirebaseAuthBridge {
  FirebaseAuthBridge._();
  static final FirebaseAuthBridge instance = FirebaseAuthBridge._();

  /// Must match Cloud Function region (`asia-northeast3`).
  static const region = 'asia-northeast3';

  final _auth = FirebaseAuth.instance;

  /// Current Firebase Auth uid (expected = Kakao user id), or null.
  String? get firebaseAuthUid => _auth.currentUser?.uid;

  bool get isSignedIn => _auth.currentUser != null;

  /// Exchange Kakao access token → Firebase Custom Token → signIn.
  ///
  /// Returns true on success. Never throws to callers — logs and returns false
  /// so Kakao login UX stays intact when the bridge fails.
  Future<bool> signInWithKakaoAccessToken(String kakaoAccessToken) async {
    final token = kakaoAccessToken.trim();
    if (token.isEmpty) {
      debugPrint('[FIREBASE_AUTH_BRIDGE] customTokenLogin=failed reason=empty_token');
      return false;
    }

    try {
      final callable = FirebaseFunctions.instanceFor(region: region)
          .httpsCallable('createFirebaseCustomToken');
      final result = await callable.call(<String, dynamic>{
        'kakaoAccessToken': token,
      });

      final data = result.data;
      if (data is! Map) {
        debugPrint('[FIREBASE_AUTH_BRIDGE] customTokenLogin=failed reason=bad_response');
        return false;
      }
      final map = Map<String, dynamic>.from(data);
      final customToken = (map['customToken'] as String?)?.trim() ?? '';
      final uid = (map['uid'] as String?)?.trim() ?? '';
      if (customToken.isEmpty) {
        debugPrint('[FIREBASE_AUTH_BRIDGE] customTokenLogin=failed reason=no_token');
        return false;
      }

      final cred = await _auth.signInWithCustomToken(customToken);
      final firebaseUid = cred.user?.uid ?? _auth.currentUser?.uid ?? '';
      debugPrint(
        '[FIREBASE_AUTH_BRIDGE] kakaoUserId=$uid '
        'firebaseAuthUid=$firebaseUid customTokenLogin=success',
      );
      if (uid.isNotEmpty && firebaseUid.isNotEmpty && uid != firebaseUid) {
        debugPrint(
          '[FIREBASE_AUTH_BRIDGE] WARNING uid mismatch '
          'kakao=$uid firebase=$firebaseUid',
        );
      }
      // Sync Settings menu visibility with token claim (admin:true if ADMIN_UIDS).
      await AdminAccess.refreshAdminClaim(forceRefresh: true);
      return firebaseUid.isNotEmpty;
    } catch (e) {
      debugPrint('[FIREBASE_AUTH_BRIDGE] customTokenLogin=failed error=$e');
      return false;
    }
  }

  /// Use current Kakao SDK token (login or session restore).
  Future<bool> signInWithCurrentKakaoToken() async {
    try {
      final oauth = await TokenManagerProvider.instance.manager.getToken();
      final access = oauth?.accessToken.trim() ?? '';
      if (access.isEmpty) {
        debugPrint('[FIREBASE_AUTH_BRIDGE] customTokenLogin=failed reason=no_kakao_token');
        return false;
      }
      return signInWithKakaoAccessToken(access);
    } catch (e) {
      debugPrint('[FIREBASE_AUTH_BRIDGE] customTokenLogin=failed error=$e');
      return false;
    }
  }

  /// Google Play reviewer sign-in (no Kakao SDK).
  ///
  /// Server verifies [accessCode] and returns a Custom Token for the fixed
  /// reviewer uid plus its seeded profile. Throws [ReviewerLoginException].
  Future<ReviewerLoginResult> signInAsReviewer(String accessCode) async {
    final code = accessCode.trim();
    if (code.isEmpty) {
      throw const ReviewerLoginException('접근 코드를 입력해 주세요.');
    }

    final Map<String, dynamic> map;
    try {
      final callable = FirebaseFunctions.instanceFor(region: region)
          .httpsCallable('createReviewerCustomToken');
      final result = await callable.call(<String, dynamic>{
        'accessCode': code,
      });
      final data = result.data;
      if (data is! Map) {
        throw const ReviewerLoginException('서버 응답이 올바르지 않아요.');
      }
      map = Map<String, dynamic>.from(data);
    } on FirebaseFunctionsException catch (e) {
      debugPrint('[FIREBASE_AUTH_BRIDGE] reviewerLogin=failed code=${e.code}');
      throw ReviewerLoginException(switch (e.code) {
        'permission-denied' => '접근 코드가 올바르지 않아요.',
        'failed-precondition' => '심사용 로그인이 비활성화되어 있어요.',
        'unavailable' || 'deadline-exceeded' => '네트워크 상태를 확인해 주세요.',
        _ => '심사용 로그인에 실패했어요.',
      });
    }

    final customToken = (map['customToken'] as String?)?.trim() ?? '';
    final uid = (map['uid'] as String?)?.trim() ?? '';
    final nickname = (map['nickname'] as String?)?.trim() ?? '';
    final cafeType = (map['cafeType'] as String?)?.trim() ?? '';
    final experience = (map['experience'] as String?)?.trim() ?? '';
    if (customToken.isEmpty ||
        uid.isEmpty ||
        nickname.isEmpty ||
        cafeType.isEmpty ||
        experience.isEmpty) {
      throw const ReviewerLoginException('서버 응답이 올바르지 않아요.');
    }

    try {
      final cred = await _auth.signInWithCustomToken(customToken);
      final firebaseUid = cred.user?.uid ?? '';
      if (firebaseUid != uid) {
        await signOut();
        throw const ReviewerLoginException('심사용 로그인에 실패했어요.');
      }
    } on FirebaseAuthException catch (e) {
      debugPrint('[FIREBASE_AUTH_BRIDGE] reviewerLogin=failed auth=${e.code}');
      throw const ReviewerLoginException('심사용 로그인에 실패했어요.');
    }

    await AdminAccess.refreshAdminClaim(forceRefresh: true);
    debugPrint('[FIREBASE_AUTH_BRIDGE] reviewerLogin=success uid=$uid');
    return ReviewerLoginResult(
      uid: uid,
      nickname: nickname,
      cafeType: cafeType,
      experience: experience,
    );
  }

  /// Firebase Auth uid persisted from a previous launch (waits for restore).
  Future<String?> restoredUid() async {
    try {
      final user = await _auth
          .authStateChanges()
          .first
          .timeout(const Duration(seconds: 3));
      return user?.uid;
    } catch (_) {
      return _auth.currentUser?.uid;
    }
  }

  /// Best-effort Firebase Auth sign-out (does not throw).
  Future<void> signOut() async {
    try {
      await _auth.signOut();
      AdminAccess.clear();
      debugPrint('[FIREBASE_AUTH_BRIDGE] firebaseAuthSignOut=success');
    } catch (e) {
      debugPrint('[FIREBASE_AUTH_BRIDGE] firebaseAuthSignOut=failed error=$e');
    }
  }
}

class ReviewerLoginResult {
  const ReviewerLoginResult({
    required this.uid,
    required this.nickname,
    required this.cafeType,
    required this.experience,
  });

  final String uid;
  final String nickname;
  final String cafeType;
  final String experience;
}

class ReviewerLoginException implements Exception {
  const ReviewerLoginException(this.message);

  final String message;

  @override
  String toString() => message;
}
