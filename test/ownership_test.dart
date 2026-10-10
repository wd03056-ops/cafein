// ignore_for_file: depend_on_referenced_packages
import 'package:cafein/models/post.dart';
import 'package:cafein/services/auth_service.dart';
import 'package:cafein/services/post_service.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _login(String uid) => AuthService.instance.signInAsReviewer(
      uid: uid,
      nickname: 'nick_$uid',
      cafeType: '개인카페',
      experience: '1~3년',
    );

Post _postBy(String id, String? authorId) => Post(
      id: id,
      content: 'c',
      createdAt: DateTime(2026),
      authorId: authorId,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final auth = AuthService.instance;
  final posts = PostService.instance;
  final postA = _postBy('pA', 'userA');

  setUpAll(() async {
    setupFirebaseCoreMocks();
    await Firebase.initializeApp();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    auth.clearSession();
  });

  test('logged out: never mine (fresh launch / after logout)', () {
    expect(auth.currentUserId, isNull);
    expect(auth.isLoggedIn, isFalse);
    expect(posts.isMyPost(postA.id, post: postA), isFalse);
    expect(auth.isCurrentUser('userA'), isFalse);
  });

  test('A: login → mine, logout → not mine (incl. session-written ids)',
      () async {
    await _login('userA');
    posts.markAsMyPost('pLocal');
    expect(posts.isMyPost(postA.id, post: postA), isTrue);
    expect(posts.isMyPost('pLocal', post: _postBy('pLocal', null)), isTrue);

    auth.clearSession();
    expect(auth.currentUserId, isNull);
    expect(posts.isMyPost(postA.id, post: postA), isFalse);
    expect(posts.isMyPost('pLocal', post: _postBy('pLocal', null)), isFalse);
  });

  test('B: logout notifies PostService listeners (menus rebuild)', () async {
    await _login('userA');
    var notified = 0;
    void listener() => notified++;
    posts.addListener(listener);
    auth.clearSession();
    posts.removeListener(listener);
    expect(notified, greaterThan(0));
  });

  test('E: logout then same user login → mine again', () async {
    await _login('userA');
    auth.clearSession();
    await _login('userA');
    expect(posts.isMyPost(postA.id, post: postA), isTrue);
  });

  test('F: user A then user B → A post is not mine for B', () async {
    await _login('userA');
    posts.markAsMyPost('pLocalA');
    await _login('userB');
    expect(posts.isMyPost(postA.id, post: postA), isFalse);
    expect(posts.isMyPost('pLocalA', post: _postBy('pLocalA', null)), isFalse);
    expect(auth.isCurrentUser('userA'), isFalse);
  });

  test('Kakao id set but onboarding pending → not mine', () {
    final needsOnboarding = auth.signInWithKakao('userNoProfile');
    expect(needsOnboarding, isTrue);
    expect(auth.kakaoUserId, 'userNoProfile');
    expect(auth.currentUserId, isNull);
    final post = _postBy('pX', 'userNoProfile');
    expect(posts.isMyPost(post.id, post: post), isFalse);
    expect(auth.isCurrentUser('userNoProfile'), isFalse);
  });
}
