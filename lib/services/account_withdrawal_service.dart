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
    AuthService.instance.requireKakaoWriter();
    final uid = AuthService.instance.kakaoUserId?.trim() ?? '';
    final nickname = AuthService.instance.nickname?.trim() ?? '';
    if (uid.isEmpty) {
      throw StateError('로그인 정보가 없어요.');
    }

    await _anonymizePosts(uid);
    await _anonymizeComments(uid);
    await BlockFirestoreService.instance.deleteBlocksByBlocker(uid);

    if (nickname.isNotEmpty) {
      try {
        final nickDoc = await _firestore.collection('nicknames').doc(nickname).get();
        if (nickDoc.exists) {
          final owner = (nickDoc.data()?['uid'] as String?)?.trim();
          if (owner == uid) {
            await nickDoc.reference.delete();
          }
        }
      } catch (e) {
        debugPrint('닉네임 인덱스 삭제 실패: $e');
      }
    }

    try {
      await _firestore.collection('users').doc(uid).delete();
    } catch (e) {
      debugPrint('유저 문서 삭제 실패: $e');
    }

    try {
      await UserApi.instance.unlink();
    } catch (e) {
      debugPrint('카카오 unlink 실패, logout으로 대체: $e');
      try {
        await UserApi.instance.logout();
      } catch (e2) {
        debugPrint('카카오 로그아웃 실패: $e2');
      }
    }

    BlockFirestoreService.instance.clearCache();
    AuthService.instance.clearSession();
  }

  Future<void> _anonymizePosts(String uid) async {
    try {
      QuerySnapshot<Map<String, dynamic>> page;
      do {
        page = await _firestore
            .collection('posts')
            .where('authorId', isEqualTo: uid)
            .limit(100)
            .get();
        if (page.docs.isEmpty) break;
        final batch = _firestore.batch();
        for (final doc in page.docs) {
          batch.update(doc.reference, {
            'authorNickname': anonymizedNickname,
            'nickname': anonymizedNickname,
            'authorProfileImage': '',
            'updatedAt': FieldValue.serverTimestamp(),
            'authorWithdrawn': true,
          });
        }
        await batch.commit();
      } while (page.docs.isNotEmpty);
    } catch (e) {
      debugPrint('게시글 익명화 실패: $e');
    }
  }

  Future<void> _anonymizeComments(String uid) async {
    // Comments live under posts; query collection group if available.
    try {
      QuerySnapshot<Map<String, dynamic>> page;
      do {
        page = await _firestore
            .collectionGroup('comments')
            .where('authorId', isEqualTo: uid)
            .limit(100)
            .get();
        if (page.docs.isEmpty) break;
        final batch = _firestore.batch();
        for (final doc in page.docs) {
          batch.update(doc.reference, {
            'authorNickname': anonymizedNickname,
            'authorProfileImage': '',
            'updatedAt': FieldValue.serverTimestamp(),
            'authorWithdrawn': true,
          });
        }
        await batch.commit();
      } while (page.docs.isNotEmpty);
    } catch (e) {
      debugPrint('댓글 익명화 실패(컬렉션 그룹 인덱스 필요할 수 있음): $e');
    }
  }
}
