import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Profile fields stored in Firestore `users/{uid}`.
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

/// Saves Kakao account fields to Firestore `users/{uid}`.
Future<void> saveUserToFirestore({
  required String uid,
  required String nickname,
  required String profileImage,
  required String email,
}) async {
  final firestore = FirebaseFirestore.instance;

  try {
    await firestore.collection('users').doc(uid).set({
      'nickname': nickname,
      'profileImage': profileImage,
      'email': email,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    debugPrint('유저 데이터 파이어스토어 저장 성공!');
  } catch (e) {
    debugPrint('유저 데이터 저장 실패: $e');
  }
}

/// Real-time stream of the signed-in user's Firestore profile.
Stream<FirestoreUserProfile?> watchUserProfile(String uid) {
  if (uid.trim().isEmpty) {
    return Stream.value(null);
  }
  return FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .snapshots()
      .map((snap) {
    if (!snap.exists) {
      return FirestoreUserProfile(uid: uid);
    }
    return FirestoreUserProfile.fromDoc(uid, snap.data());
  });
}
