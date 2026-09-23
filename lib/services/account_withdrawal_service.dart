import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:kakao_flutter_sdk/kakao_flutter_sdk.dart';

import 'auth_service.dart';
import 'block_firestore_service.dart';
import 'comments_firestore_service.dart';
import 'fcm_service.dart';
import 'firebase_auth_bridge.dart';
import 'admin_access.dart';
import 'nickname_lookup_cache.dart';
import 'notification_inbox_service.dart';
import 'notification_settings_service.dart';
import 'post_service.dart';
import 'posts_firestore_service.dart';
import '../core/constants.dart';

/// Account withdrawal — keeps posts/comments as anonymous community content,
/// severs authorship via Cloud Function [withdrawAccount] (Admin SDK), then
/// clears Kakao / Firebase Auth session and local state.
///
/// Firebase Auth: signs out only. Deleting the Firebase Auth user record is
/// deferred (needs Admin SDK / reauth) — see project security roadmap.
class AccountWithdrawalService {
  AccountWithdrawalService._();
  static final AccountWithdrawalService instance = AccountWithdrawalService._();

  static const anonymizedNickname = AppConstants.withdrawnAuthorNickname;

  Future<void> withdraw() async {
    debugPrint('[DELETE ACCOUNT] deleteAccount started');
    AuthService.instance.requireKakaoWriter();
    final uid = AuthService.instance.kakaoUserId?.trim() ?? '';
    if (uid.isEmpty) {
      throw StateError('로그인 정보가 없어요.');
    }

    debugPrint('[DELETE ACCOUNT] calling withdrawAccount');
    await _ensureFirebaseAuth();
    final deletedId = await _callWithdrawAccount();

    // Soft-update in-memory caches so a same-process rejoin cannot show the
    // old nickname via stale authorId == Kakao UID entries.
    _applyWithdrawalToLocalCaches(uid, deletedId);

    debugPrint('[DELETE ACCOUNT] unregistering FCM / local notification prefs');
    try {
      await FcmService.instance.unregisterCurrentToken();
    } catch (e, st) {
      debugPrint('FCM unregister 실패: $e');
      debugPrint('$st');
    }
    await NotificationSettingsService.instance.clearLocal();

    debugPrint('[DELETE ACCOUNT] unlinking Kakao');
    try {
      await UserApi.instance.unlink();
      debugPrint('[DELETE ACCOUNT] Kakao unlink success');
    } catch (e, st) {
      debugPrint('카카오 unlink 실패, logout으로 대체: $e');
      debugPrint('$st');
      try {
        await UserApi.instance.logout();
      } catch (e2, st2) {
        debugPrint('카카오 로그아웃 실패: $e2');
        debugPrint('$st2');
      }
    }

    // Always clear device token store so auto-login cannot restore the old session.
    await AuthService.instance.clearKakaoTokenStore();

    // Firebase Auth session only (Auth user doc deletion = later / Admin SDK).
    await FirebaseAuthBridge.instance.signOut();

    debugPrint('[DELETE ACCOUNT] signing out');
    BlockFirestoreService.instance.clearCache();
    NotificationInboxService.instance.clearLocal();
    AdminAccess.clear();
    // Must remove SharedPreferences profile — clearSession alone keeps it and
    // signInWithKakao would restore the old nickname on next login.
    await AuthService.instance.clearAccountAfterWithdrawal(uid);
    debugPrint('[DELETE ACCOUNT] completed');
  }

  /// Server anonymize + Firestore user cleanup. Throws on failure — caller
  /// must not treat withdrawal as complete.
  Future<void> _ensureFirebaseAuth() async {
    if (FirebaseAuthBridge.instance.isSignedIn) return;
    final ok = await FirebaseAuthBridge.instance.signInWithCurrentKakaoToken();
    if (!ok || !FirebaseAuthBridge.instance.isSignedIn) {
      throw StateError(
        'Firebase Auth 세션이 없어 탈퇴를 완료할 수 없어요. '
        '카카오 로그인 후 다시 시도해 주세요.',
      );
    }
  }

  Future<String> _callWithdrawAccount() async {
    try {
      final callable = FirebaseFunctions.instanceFor(
        region: FirebaseAuthBridge.region,
      ).httpsCallable('withdrawAccount');
      final result = await callable.call(<String, dynamic>{});
      final raw = result.data;
      if (raw is! Map) {
        throw StateError('탈퇴 응답이 올바르지 않아요.');
      }
      final map = Map<String, dynamic>.from(raw);
      if (map['success'] != true) {
        throw StateError('회원 탈퇴에 실패했습니다.');
      }
      final deletedId = (map['deletedId'] as String?)?.trim() ?? '';
      if (deletedId.isEmpty || !deletedId.startsWith('deleted_')) {
        throw StateError('탈퇴 응답이 올바르지 않아요.');
      }
      debugPrint(
        '[DELETE ACCOUNT] withdrawAccount ok '
        'posts=${map['postsUpdated']} comments=${map['commentsUpdated']}',
      );
      return deletedId;
    } on FirebaseFunctionsException catch (e) {
      debugPrint(
        '[DELETE ACCOUNT] withdrawAccount failed code=${e.code} msg=${e.message}',
      );
      rethrow;
    }
  }

  void _applyWithdrawalToLocalCaches(String uid, String deletedId) {
    NicknameLookupCache.instance.invalidate(uid);
    PostsFirestoreService.instance.applyAuthorWithdrawalInCache(
      oldAuthorId: uid,
      deletedAuthorId: deletedId,
      displayNickname: anonymizedNickname,
    );
    CommentsFirestoreService.instance.applyAuthorWithdrawalInCache(
      oldAuthorId: uid,
      deletedAuthorId: deletedId,
      displayNickname: anonymizedNickname,
    );
    PostService.instance.applyAuthorWithdrawalInCache(
      oldAuthorId: uid,
      deletedAuthorId: deletedId,
      displayNickname: anonymizedNickname,
    );
  }
}
