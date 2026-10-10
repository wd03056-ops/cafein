import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:kakao_flutter_sdk/kakao_flutter_sdk.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_auth_bridge.dart';
import 'nickname_lookup_cache.dart';
import 'posts_firestore_service.dart';
import 'user_firestore_service.dart';

/// `users/{uid}` could not be read (network / permission). Distinct from
/// "document missing" so existing users are never sent to onboarding by error.
class ProfileLookupException implements Exception {
  const ProfileLookupException(this.cause);

  final Object cause;

  @override
  String toString() => 'ProfileLookupException: $cause';
}

typedef ProfileBadge = ({String cafeType, String experience});

/// Badge fields from the user's newest post (users docs usually lack them).
Future<ProfileBadge?> _latestPostBadge(String uid) async {
  final posts = await PostsFirestoreService.instance.fetchPostsByAuthor(uid);
  for (final post in posts) {
    final cafeType = post.cafeType?.trim() ?? '';
    final experience = post.experience?.trim() ?? '';
    if (cafeType.isNotEmpty && experience.isNotEmpty) {
      return (cafeType: cafeType, experience: experience);
    }
  }
  return null;
}

class _UserProfile {
  const _UserProfile({
    required this.nickname,
    required this.cafeType,
    required this.experience,
  });

  final String nickname;
  final String cafeType;
  final String experience;

  Map<String, String> toJson() => {
        'nickname': nickname,
        'cafeType': cafeType,
        'experience': experience,
      };

  static _UserProfile? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final nickname = json['nickname'] as String?;
    final cafeType = json['cafeType'] as String?;
    final experience = json['experience'] as String?;
    if (nickname == null ||
        cafeType == null ||
        experience == null ||
        nickname.trim().isEmpty) {
      return null;
    }
    return _UserProfile(
      nickname: nickname,
      cafeType: cafeType,
      experience: experience,
    );
  }
}

/// Result of restoring a Kakao session at app launch.
enum KakaoSessionStatus {
  /// Valid token + onboarding profile ready → go to main.
  authenticated,

  /// Valid token but no nickname/profile yet → onboarding.
  needsOnboarding,

  /// No token or token invalid/expired → login.
  none,
}

/// Auth + onboarding profile, keyed by Kakao user id.
///
/// Primary identity remains Kakao OAuth + in-app onboarding.
/// [FirebaseAuthBridge] also signs into Firebase Auth via Custom Token
/// (uid = Kakao user id) so future Firestore Rules can use `request.auth`.
/// Email/Password Auth is not used.
class AuthService extends ChangeNotifier {
  AuthService._();
  static final AuthService instance = AuthService._();

  static const _profilesPrefsKey = 'cafein_profiles_v1';

  bool _isLoggedIn = false;
  String? _kakaoUserId;
  String? _nickname;
  String? _cafeType;
  String? _experience;
  bool _initialized = false;

  /// Survives logout / restart (persisted).
  final Map<String, _UserProfile> _profilesByKakaoId = {};

  bool get isLoggedIn => _isLoggedIn;
  String? get kakaoUserId => _kakaoUserId;
  String? get nickname => _nickname;
  String? get cafeType => _cafeType;
  String? get experience => _experience;
  String? get experienceLabel => _experience;

  bool get hasCompletedOnboarding =>
      _isLoggedIn && _nickname != null && _nickname!.trim().isNotEmpty;

  /// Uid for ownership checks (수정/삭제). Null unless fully logged in —
  /// [kakaoUserId] alone can linger while onboarding is still pending.
  String? get currentUserId {
    if (!_isLoggedIn) return null;
    final id = _kakaoUserId?.trim();
    return (id == null || id.isEmpty) ? null : id;
  }

  /// True only when logged in and [authorId] is the current user's uid.
  bool isCurrentUser(String? authorId) {
    final uid = currentUserId;
    final author = authorId?.trim() ?? '';
    return uid != null && author.isNotEmpty && author == uid;
  }

  bool get needsOnboarding =>
      _kakaoUserId != null &&
      (_nickname == null || _nickname!.trim().isEmpty);

  /// Kakao login completed + in-app profile set (can write posts/comments/likes).
  bool get canWriteContent {
    if (!hasCompletedOnboarding) return false;
    final kakaoId = _kakaoUserId?.trim();
    return kakaoId != null && kakaoId.isNotEmpty;
  }

  /// Throws if the user cannot create posts / comments / likes / votes.
  void requireKakaoWriter() {
    if (!canWriteContent) {
      throw StateError('카카오 로그인과 프로필 설정을 완료해 주세요.');
    }
  }

  /// Load persisted profiles once at startup.
  Future<void> init() async {
    if (_initialized) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_profilesPrefsKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          decoded.forEach((key, value) {
            final profile = _UserProfile.fromJson(
              value is Map<String, dynamic>
                  ? value
                  : Map<String, dynamic>.from(value as Map),
            );
            if (profile != null) {
              _profilesByKakaoId[key] = profile;
            }
          });
        }
      }
    } catch (e) {
      debugPrint('프로필 로드 실패: $e');
    }
    _initialized = true;
  }

  Future<void> _persistProfiles() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final map = <String, dynamic>{
        for (final e in _profilesByKakaoId.entries) e.key: e.value.toJson(),
      };
      await prefs.setString(_profilesPrefsKey, jsonEncode(map));
    } catch (e) {
      debugPrint('프로필 저장 실패: $e');
    }
  }

  /// Check saved Kakao token and restore local session if still valid.
  Future<KakaoSessionStatus> tryRestoreKakaoSession() async {
    await init();

    try {
      final token = await TokenManagerProvider.instance.manager.getToken();
      if (token == null) {
        debugPrint('저장된 카카오 토큰 없음');
        if (await _tryRestoreReviewerSession()) {
          return KakaoSessionStatus.authenticated;
        }
        clearSession();
        return KakaoSessionStatus.none;
      }

      final user = await UserApi.instance.me();
      final kakaoUserId = user.id.toString();
      debugPrint('자동 로그인: 카카오 유저 ID $kakaoUserId');

      // Refresh Firebase Auth from current Kakao access token. Await only when
      // the profile must be restored from users/{uid} (read needs auth).
      if (hasLocalProfile(kakaoUserId)) {
        unawaited(FirebaseAuthBridge.instance.signInWithCurrentKakaoToken());
      } else {
        await FirebaseAuthBridge.instance.signInWithCurrentKakaoToken();
      }

      // ProfileLookupException → catch below → guest (Kakao token kept).
      final needsOnboarding =
          await signInWithKakaoRestoringProfile(kakaoUserId);

      final kakaoAccount = user.kakaoAccount;
      final kakaoProfile = kakaoAccount?.profile;
      unawaited(
        saveUserToFirestore(
          uid: kakaoUserId,
          nickname: kakaoProfile?.nickname ?? '',
          profileImage: kakaoProfile?.profileImageUrl ?? '',
          email: kakaoAccount?.email ?? '',
        ),
      );

      return needsOnboarding
          ? KakaoSessionStatus.needsOnboarding
          : KakaoSessionStatus.authenticated;
    } catch (error) {
      debugPrint('카카오 세션 복원 실패: $error');
      clearSession();
      return KakaoSessionStatus.none;
    }
  }

  /// Called after Kakao login succeeds.
  /// Returns true when onboarding (앱 내 정보 입력) is still required.
  bool signInWithKakao(String kakaoUserId) {
    _kakaoUserId = kakaoUserId;
    final existing = _profilesByKakaoId[kakaoUserId];
    if (existing != null) {
      _nickname = existing.nickname;
      _cafeType = existing.cafeType;
      _experience = existing.experience;
      _isLoggedIn = true;
      notifyListeners();
      return false;
    }

    _nickname = null;
    _cafeType = null;
    _experience = null;
    _isLoggedIn = false;
    notifyListeners();
    return true;
  }

  bool hasLocalProfile(String kakaoUserId) =>
      _profilesByKakaoId.containsKey(kakaoUserId.trim());

  @visibleForTesting
  Future<FirestoreUserProfile?> Function(String uid) remoteProfileLookup =
      fetchUserProfileStrict;

  @visibleForTesting
  Future<ProfileBadge?> Function(String uid) remoteBadgeLookup =
      _latestPostBadge;

  /// [signInWithKakao] + restore from Firestore `users/{uid}` when the local
  /// profile is missing (e.g. reinstall / package change).
  ///
  /// Returns true when onboarding is still required (no doc, or no nickname
  /// — includes withdrawn users whose doc was deleted).
  /// Throws [ProfileLookupException] if the lookup itself failed; the
  /// session stays logged out in that case.
  Future<bool> signInWithKakaoRestoringProfile(String kakaoUserId) async {
    await init();
    final uid = kakaoUserId.trim();
    if (!signInWithKakao(uid)) return false;

    final FirestoreUserProfile? remote;
    try {
      remote = await remoteProfileLookup(uid);
    } catch (e) {
      debugPrint('[PROFILE_RESTORE] lookup failed uid=$uid error=$e');
      throw ProfileLookupException(e);
    }

    final nickname = remote?.nickname.trim() ?? '';
    if (remote == null || nickname.isEmpty) {
      debugPrint('[PROFILE_RESTORE] uid=$uid result=onboarding '
          'docExists=${remote != null}');
      return true;
    }

    var cafeType = remote.cafeType;
    var experience = remote.experience;
    if (cafeType.isEmpty || experience.isEmpty) {
      try {
        final badge = await remoteBadgeLookup(uid);
        if (badge != null) {
          if (cafeType.isEmpty) cafeType = badge.cafeType;
          if (experience.isEmpty) experience = badge.experience;
        }
      } catch (e) {
        debugPrint('[PROFILE_RESTORE] badge lookup skipped: $e');
      }
    }

    // Logout / another login happened while awaiting the lookup.
    if (_kakaoUserId != uid) {
      throw const ProfileLookupException('session changed during restore');
    }

    _nickname = nickname;
    _cafeType = cafeType;
    _experience = experience;
    _isLoggedIn = true;
    _profilesByKakaoId[uid] = _UserProfile(
      nickname: nickname,
      cafeType: cafeType,
      experience: experience,
    );
    await _persistProfiles();
    NicknameLookupCache.instance.put(uid, nickname);
    debugPrint('[PROFILE_RESTORE] uid=$uid result=restored');
    notifyListeners();
    return false;
  }

  /// Fixed Firebase uid of the Google Play review account (server-issued).
  static const reviewerUid = 'google_reviewer';

  bool get isReviewer => _kakaoUserId == reviewerUid;

  /// Session for the Play reviewer account after [FirebaseAuthBridge.signInAsReviewer].
  /// Profile is seeded server-side, so onboarding is skipped.
  Future<void> signInAsReviewer({
    required String uid,
    required String nickname,
    required String cafeType,
    required String experience,
  }) async {
    await init();
    _kakaoUserId = uid;
    _nickname = nickname;
    _cafeType = cafeType;
    _experience = experience;
    _isLoggedIn = true;
    _profilesByKakaoId[uid] = _UserProfile(
      nickname: nickname,
      cafeType: cafeType,
      experience: experience,
    );
    await _persistProfiles();
    notifyListeners();
  }

  Future<bool> _tryRestoreReviewerSession() async {
    final profile = _profilesByKakaoId[reviewerUid];
    if (profile == null) return false;
    final uid = await FirebaseAuthBridge.instance.restoredUid();
    if (uid != reviewerUid) return false;
    debugPrint('자동 로그인: 심사용 계정');
    signInWithKakao(reviewerUid);
    return true;
  }

  void setLoggedIn(bool value) {
    if (_isLoggedIn == value && value) return;
    _isLoggedIn = value;
    if (!value) {
      _kakaoUserId = null;
      _nickname = null;
      _cafeType = null;
      _experience = null;
    }
    notifyListeners();
  }

  /// Clears local session after Kakao logout (keeps saved profiles).
  void clearSession() {
    _isLoggedIn = false;
    _kakaoUserId = null;
    _nickname = null;
    _cafeType = null;
    _experience = null;
    UserDocCache.instance.invalidate();
    NicknameLookupCache.instance.invalidate();
    if (kDebugMode) {
      debugPrint('[AUTH_STATE] cleared currentUserId=$currentUserId '
          'isLoggedIn=$_isLoggedIn');
    }
    notifyListeners();
  }

  /// Account withdrawal: wipe session + this Kakao user's persisted onboarding
  /// profile so the next login starts as a new signup (onboarding required).
  /// Does not change Kakao login APIs — only local cache.
  Future<void> clearAccountAfterWithdrawal(String kakaoUserId) async {
    final id = kakaoUserId.trim();
    if (id.isNotEmpty) {
      _profilesByKakaoId.remove(id);
      await _persistProfiles();
      debugPrint('[DELETE ACCOUNT] removed local profile for withdrawn user');
    }
    clearSession();
  }

  /// Drop any leftover Kakao OAuth tokens from the device token store.
  Future<void> clearKakaoTokenStore() async {
    try {
      await TokenManagerProvider.instance.manager.clear();
      debugPrint('[DELETE ACCOUNT] Kakao token store cleared');
    } catch (e) {
      debugPrint('카카오 토큰 저장소 삭제 실패: $e');
    }
  }

  bool isNicknameUsedLocally(String nickname, {String? excludeUid}) {
    final cleaned = nickname.replaceAll(RegExp(r'\s+'), '').trim();
    if (cleaned.isEmpty) return false;
    for (final e in _profilesByKakaoId.entries) {
      if (excludeUid != null && e.key == excludeUid) continue;
      if (e.value.nickname == cleaned) return true;
    }
    return false;
  }

  void completeOnboarding({
    required String nickname,
    required String cafeType,
    required String experience,
  }) {
    final cleaned = nickname.trim();
    _nickname = cleaned;
    _cafeType = cafeType;
    _experience = experience;
    _isLoggedIn = true;

    final kakaoId = _kakaoUserId;
    if (kakaoId != null) {
      _profilesByKakaoId[kakaoId] = _UserProfile(
        nickname: cleaned,
        cafeType: cafeType,
        experience: experience,
      );
      _persistProfiles();
    }
    notifyListeners();
  }
}
