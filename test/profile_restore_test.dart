// ignore_for_file: depend_on_referenced_packages
import 'package:cafein/models/post.dart';
import 'package:cafein/services/auth_service.dart';
import 'package:cafein/services/post_service.dart';
import 'package:cafein/services/user_firestore_service.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final auth = AuthService.instance;
  final posts = PostService.instance;
  var lookupCalls = 0;

  Post postBy(String authorId) => Post(
        id: 'p_$authorId',
        content: 'c',
        createdAt: DateTime(2026),
        authorId: authorId,
      );

  void serverHas(FirestoreUserProfile? profile) {
    auth.remoteProfileLookup = (uid) async {
      lookupCalls++;
      return profile;
    };
  }

  setUpAll(() async {
    setupFirebaseCoreMocks();
    await Firebase.initializeApp();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    lookupCalls = 0;
    auth.remoteBadgeLookup = (_) async => null;
    auth.clearSession();
  });

  test('1. existing user: users/{uid} with nickname → onboarding skipped',
      () async {
    serverHas(const FirestoreUserProfile(
      uid: 'u_existing',
      nickname: '기존닉',
      cafeType: '개인카페',
      experience: '1~3년',
    ));

    final needsOnboarding =
        await auth.signInWithKakaoRestoringProfile('u_existing');

    expect(needsOnboarding, isFalse);
    expect(auth.isLoggedIn, isTrue);
    expect(auth.currentUserId, 'u_existing');
    expect(auth.canWriteContent, isTrue);
    expect(auth.nickname, '기존닉');
    final mine = postBy('u_existing');
    expect(posts.isMyPost(mine.id, post: mine), isTrue);
    final other = postBy('someone_else');
    expect(posts.isMyPost(other.id, post: other), isFalse);
  });

  test('2. new user: no users/{uid} → onboarding, logged out until done',
      () async {
    serverHas(null);

    final needsOnboarding = await auth.signInWithKakaoRestoringProfile('u_new');

    expect(needsOnboarding, isTrue);
    expect(auth.kakaoUserId, 'u_new');
    expect(auth.isLoggedIn, isFalse);
    expect(auth.currentUserId, isNull);
    expect(auth.canWriteContent, isFalse);
    final post = postBy('u_new');
    expect(posts.isMyPost(post.id, post: post), isFalse);
  });

  test('3. incomplete profile: doc without nickname → onboarding', () async {
    serverHas(const FirestoreUserProfile(uid: 'u_incomplete'));

    final needsOnboarding =
        await auth.signInWithKakaoRestoringProfile('u_incomplete');

    expect(needsOnboarding, isTrue);
    expect(auth.currentUserId, isNull);
  });

  test('4. withdrawn user: doc deleted → fresh onboarding', () async {
    serverHas(null);

    final needsOnboarding =
        await auth.signInWithKakaoRestoringProfile('u_withdrawn');

    expect(needsOnboarding, isTrue);
    expect(auth.nickname, isNull);
    expect(auth.hasLocalProfile('u_withdrawn'), isFalse);
  });

  test('5. logout after restore → currentUserId null, no owner UI', () async {
    serverHas(const FirestoreUserProfile(uid: 'u_logout', nickname: '닉5'));
    await auth.signInWithKakaoRestoringProfile('u_logout');
    expect(auth.currentUserId, 'u_logout');

    auth.clearSession();

    expect(auth.currentUserId, isNull);
    expect(auth.isLoggedIn, isFalse);
    final post = postBy('u_logout');
    expect(posts.isMyPost(post.id, post: post), isFalse);
    expect(auth.isCurrentUser('u_logout'), isFalse);
  });

  test('6. reinstall: empty prefs → restored, saved locally, nickname kept',
      () async {
    serverHas(const FirestoreUserProfile(uid: 'u_reinstall', nickname: '원래닉'));
    auth.remoteBadgeLookup =
        (_) async => (cafeType: '프랜차이즈', experience: '3~5년');

    expect(auth.hasLocalProfile('u_reinstall'), isFalse);
    await auth.signInWithKakaoRestoringProfile('u_reinstall');

    expect(auth.nickname, '원래닉');
    expect(auth.cafeType, '프랜차이즈');
    expect(auth.experience, '3~5년');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('cafein_profiles_v1'), contains('원래닉'));

    // Next login uses the local cache — no second users/{uid} read.
    auth.clearSession();
    auth.remoteProfileLookup = (_) async => throw StateError('must not call');
    final needsOnboarding =
        await auth.signInWithKakaoRestoringProfile('u_reinstall');
    expect(needsOnboarding, isFalse);
    expect(auth.nickname, '원래닉');
    expect(lookupCalls, 1);
  });

  test('7. lookup failure ≠ new user: throws, stays logged out', () async {
    auth.remoteProfileLookup = (_) async => throw StateError('offline');

    await expectLater(
      auth.signInWithKakaoRestoringProfile('u_offline'),
      throwsA(isA<ProfileLookupException>()),
    );
    expect(auth.isLoggedIn, isFalse);
    expect(auth.currentUserId, isNull);
    expect(auth.hasLocalProfile('u_offline'), isFalse);
  });

  test('8. badge lookup failure does not block restore', () async {
    serverHas(const FirestoreUserProfile(uid: 'u_badge', nickname: '닉8'));
    auth.remoteBadgeLookup = (_) async => throw StateError('posts offline');

    final needsOnboarding =
        await auth.signInWithKakaoRestoringProfile('u_badge');

    expect(needsOnboarding, isFalse);
    expect(auth.nickname, '닉8');
    expect(auth.cafeType, '');
  });
}
