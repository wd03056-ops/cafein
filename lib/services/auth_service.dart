import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:kakao_flutter_sdk/kakao_flutter_sdk.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'user_firestore_service.dart';

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
/// Firebase Auth (Email/Password etc.) is intentionally not used.
/// Identity is Kakao OAuth + in-app onboarding only.
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
        clearSession();
        return KakaoSessionStatus.none;
      }

      final user = await UserApi.instance.me();
      final kakaoUserId = user.id.toString();
      debugPrint('자동 로그인: 카카오 유저 ID $kakaoUserId');

      final needsOnboarding = signInWithKakao(kakaoUserId);

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
    notifyListeners();
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
