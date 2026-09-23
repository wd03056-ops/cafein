import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'nickname_lookup_cache.dart';
import 'user_firestore_service.dart';

/// Thrown when another user already owns the nickname.
class NicknameTakenException implements Exception {
  @override
  String toString() => 'NicknameTakenException';
}

String normalizeNickname(String nickname) =>
    nickname.replaceAll(RegExp(r'\s+'), '').trim();

/// Nickname uniqueness via `nicknames/{nickname}` (no `users` list queries).
class NicknameService {
  NicknameService._();
  static final NicknameService instance = NicknameService._();

  final _firestore = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _nicknames =>
      _firestore.collection('nicknames');

  CollectionReference<Map<String, dynamic>> get _users =>
      _firestore.collection('users');

  /// True if [nickname] is claimed by someone other than [excludeUid].
  ///
  /// Uses `nicknames/{normalized}` document get only — never lists `users`.
  Future<bool> isNicknameTaken(
    String nickname, {
    String? excludeUid,
  }) async {
    final cleaned = normalizeNickname(nickname);
    if (cleaned.isEmpty) return false;

    try {
      final nickDoc = await _nicknames.doc(cleaned).get();
      if (!nickDoc.exists) return false;
      final owner = (nickDoc.data()?['uid'] as String?)?.trim();
      if (owner == null || owner.isEmpty) return true;
      if (excludeUid != null && owner == excludeUid) return false;
      return true;
    } catch (e) {
      debugPrint('닉네임 중복 조회 실패: $e');
      rethrow;
    }
  }

  Future<void> claimNickname({
    required String uid,
    required String nickname,
    String? previousNickname,
  }) async {
    final cleaned = normalizeNickname(nickname);
    if (cleaned.isEmpty) {
      throw ArgumentError('닉네임이 비어 있어요.');
    }
    if (uid.trim().isEmpty) {
      throw ArgumentError('로그인이 필요해요.');
    }

    final previous = previousNickname == null
        ? ''
        : normalizeNickname(previousNickname);

    await _firestore.runTransaction((tx) async {
      final nickRef = _nicknames.doc(cleaned);
      final nickSnap = await tx.get(nickRef);

      DocumentSnapshot<Map<String, dynamic>>? previousSnap;
      DocumentReference<Map<String, dynamic>>? previousRef;
      if (previous.isNotEmpty && previous != cleaned) {
        previousRef = _nicknames.doc(previous);
        previousSnap = await tx.get(previousRef);
      }

      if (nickSnap.exists) {
        final owner = (nickSnap.data()?['uid'] as String?)?.trim();
        if (owner != null && owner.isNotEmpty && owner != uid) {
          throw NicknameTakenException();
        }
      }

      tx.set(nickRef, {
        'uid': uid,
        'nickname': cleaned,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      tx.set(
        _users.doc(uid),
        {
          'nickname': cleaned,
          'kakaoUserId': uid,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      if (previousRef != null && previousSnap != null && previousSnap.exists) {
        final owner = (previousSnap.data()?['uid'] as String?)?.trim();
        if (owner == uid) {
          tx.delete(previousRef);
        }
      }
    });

    NicknameLookupCache.instance.put(uid, cleaned);
    UserDocCache.instance.invalidate(uid);
  }
}
