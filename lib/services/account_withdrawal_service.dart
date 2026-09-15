import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:kakao_flutter_sdk/kakao_flutter_sdk.dart';

import 'auth_service.dart';
import 'block_firestore_service.dart';

/// Account withdrawal — keeps posts/comments as anonymous community content,
/// removes personal identifiers and local session. Does not use Firebase Auth.
class AccountWithdrawalService {
  AccountWithdrawalService._();
  static final AccountWithdrawalService instance = AccountWithdrawalService._();

  final _firestore = FirebaseFirestore.instance;

  static const anonymizedNickname = '탈퇴한 사용자';

  Future<void> withdraw() async {
    debugPrint('[DELETE ACCOUNT] deleteAccount started');
    AuthService.instance.requireKakaoWriter();
    final uid = AuthService.instance.kakaoUserId?.trim() ?? '';
    final nickname = AuthService.instance.nickname?.trim() ?? '';
    if (uid.isEmpty) {
      throw StateError('로그인 정보가 없어요.');
    }

    debugPrint('[DELETE ACCOUNT] anonymizing posts');
    await _anonymizePosts(uid);

    debugPrint('[DELETE ACCOUNT] anonymizing comments');
    await _anonymizeComments(uid);

    debugPrint('[DELETE ACCOUNT] deleting blocks');
    await BlockFirestoreService.instance.deleteBlocksByBlocker(uid);

    debugPrint('[DELETE ACCOUNT] deleting user data');
    if (nickname.isNotEmpty) {
      try {
        final nickDoc =
            await _firestore.collection('nicknames').doc(nickname).get();
        if (nickDoc.exists) {
          final owner = (nickDoc.data()?['uid'] as String?)?.trim();
          if (owner == uid) {
            await nickDoc.reference.delete();
          }
        }
      } catch (e, st) {
        debugPrint('닉네임 인덱스 삭제 실패: $e');
        debugPrint('$st');
      }
    }

    try {
      await _firestore.collection('users').doc(uid).delete();
    } catch (e, st) {
      debugPrint('유저 문서 삭제 실패: $e');
      debugPrint('$st');
    }

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

    debugPrint('[DELETE ACCOUNT] signing out');
    BlockFirestoreService.instance.clearCache();
    // Must remove SharedPreferences profile — clearSession alone keeps it and
    // signInWithKakao would restore the old nickname on next login.
    await AuthService.instance.clearAccountAfterWithdrawal(uid);
    debugPrint('[DELETE ACCOUNT] completed');
  }

  /// Anonymize display fields only. Keeps [authorId] for moderation.
  /// Loads matching docs once (no cursor loop) so we never re-query the same
  /// `authorId` set forever after nickname-only updates.
  Future<void> _anonymizePosts(String uid) async {
    try {
      final snap = await _firestore
          .collection('posts')
          .where('authorId', isEqualTo: uid)
          .get();
      debugPrint(
        '[DELETE ACCOUNT] posts to anonymize=${snap.docs.length}',
      );
      for (var i = 0; i < snap.docs.length; i += 400) {
        final chunk = snap.docs.skip(i).take(400);
        final batch = _firestore.batch();
        for (final doc in chunk) {
          batch.update(doc.reference, {
            'authorNickname': anonymizedNickname,
            'nickname': anonymizedNickname,
            'authorProfileImage': '',
            'updatedAt': FieldValue.serverTimestamp(),
            'authorWithdrawn': true,
          });
        }
        await batch.commit();
      }
    } catch (e, st) {
      debugPrint('게시글 익명화 실패: $e');
      debugPrint('$st');
      rethrow;
    }
  }

  Future<void> _anonymizeComments(String uid) async {
    try {
      final snap = await _firestore
          .collectionGroup('comments')
          .where('authorId', isEqualTo: uid)
          .get();
      debugPrint(
        '[DELETE ACCOUNT] comments to anonymize=${snap.docs.length}',
      );
      for (var i = 0; i < snap.docs.length; i += 400) {
        final chunk = snap.docs.skip(i).take(400);
        final batch = _firestore.batch();
        for (final doc in chunk) {
          batch.update(doc.reference, {
            'authorNickname': anonymizedNickname,
            'authorProfileImage': '',
            'updatedAt': FieldValue.serverTimestamp(),
            'authorWithdrawn': true,
          });
        }
        await batch.commit();
      }
    } catch (e, st) {
      debugPrint('댓글 익명화 실패(컬렉션 그룹 인덱스가 필요할 수 있음): $e');
      debugPrint('$st');
      // Comments anonymization should not block account deletion.
    }
  }
}
