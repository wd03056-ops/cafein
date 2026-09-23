import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// In-memory cache for `users/{uid}` so session restore / FCM / settings
/// share one read per process instead of three.
class UserDocCache {
  UserDocCache._();
  static final UserDocCache instance = UserDocCache._();

  DocumentSnapshot<Map<String, dynamic>>? _snap;
  String? _uid;

  Future<DocumentSnapshot<Map<String, dynamic>>?> get(
    String uid, {
    bool force = false,
  }) async {
    final id = uid.trim();
    if (id.isEmpty) return null;
    if (!force && _uid == id && _snap != null) return _snap;

    final snap =
        await FirebaseFirestore.instance.collection('users').doc(id).get();
    _uid = id;
    _snap = snap;
    return snap;
  }

  void invalidate([String? uid]) {
    if (uid == null || _uid == uid) {
      _snap = null;
      _uid = null;
    }
  }
}

/// Profile fields stored in Firestore `users/{kakaoUserId}`.
class FirestoreUserProfile {
  const FirestoreUserProfile({
    required this.uid,
    this.nickname = '',
    this.email = '',
    this.profileImage = '',
  });

  final String uid;
  final String nickname;
  final String email;
  final String profileImage;

  factory FirestoreUserProfile.fromDoc(
    String uid,
    Map<String, dynamic>? data,
  ) {
    final map = data ?? const <String, dynamic>{};
    return FirestoreUserProfile(
      uid: uid,
      nickname: (map['nickname'] as String?)?.trim() ?? '',
      email: (map['email'] as String?)?.trim() ?? '',
      profileImage: (map['profileImage'] as String?)?.trim() ?? '',
    );
  }
}

/// Saves Kakao account fields to Firestore `users/{kakaoUid}`.
///
/// Does not overwrite app [nickname] claimed via NicknameService.
/// Skips write when Kakao profile fields are unchanged; sets [createdAt] only
/// on first create so session restore does not rewrite every launch.
Future<void> saveUserToFirestore({
  required String uid,
  required String nickname,
  required String profileImage,
  required String email,
}) async {
  final id = uid.trim();
  if (id.isEmpty) return;

  try {
    final ref = FirebaseFirestore.instance.collection('users').doc(id);
    final snap = await UserDocCache.instance.get(id);
    final data = snap?.data();

    if (snap != null && snap.exists && data != null) {
      final same = (data['kakaoUserId']?.toString() ?? '') == id &&
          (data['kakaoNickname'] as String? ?? '') == nickname &&
          (data['profileImage'] as String? ?? '') == profileImage &&
          (data['email'] as String? ?? '') == email;
      if (same) {
        debugPrint('유저 데이터 변경 없음 — write 생략 ($id)');
        return;
      }

      await ref.set({
        'kakaoUserId': id,
        'kakaoNickname': nickname,
        'profileImage': profileImage,
        'email': email,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } else {
      await ref.set({
        'kakaoUserId': id,
        'kakaoNickname': nickname,
        'profileImage': profileImage,
        'email': email,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    UserDocCache.instance.invalidate(id);
    debugPrint('유저 데이터 파이어스토어 저장 성공! ($id)');
  } catch (e) {
    debugPrint('유저 데이터 저장 실패: $e');
  }
}

/// One-shot user profile read (uses [UserDocCache] when possible).
Future<FirestoreUserProfile?> fetchUserProfile(
  String uid, {
  bool forceRefresh = false,
}) async {
  final id = uid.trim();
  if (id.isEmpty) return null;

  try {
    final snap = await UserDocCache.instance.get(id, force: forceRefresh);
    if (snap == null || !snap.exists) {
      return FirestoreUserProfile(uid: id);
    }
    return FirestoreUserProfile.fromDoc(id, snap.data());
  } catch (e) {
    debugPrint('유저 프로필 조회 실패: $e');
    return FirestoreUserProfile(uid: id);
  }
}

/// Compatibility: one-shot stream (no live `snapshots()` listener).
Stream<FirestoreUserProfile?> watchUserProfile(String uid) {
  if (uid.trim().isEmpty) {
    return Stream.value(null);
  }
  return Stream.fromFuture(fetchUserProfile(uid));
}
