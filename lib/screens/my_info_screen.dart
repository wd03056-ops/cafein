import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/logout.dart';
import '../services/user_firestore_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import 'edit_profile_screen.dart';
import 'login_screen.dart';
import 'my_posts_screen.dart';
import 'settings_screen.dart';

/// My info / my page tab.
class MyInfoScreen extends StatelessWidget {
  const MyInfoScreen({super.key});

  Future<void> _handleAuthTap(BuildContext context, bool loggedIn) async {
    if (loggedIn) {
      _showLogoutDialog(context);
      return;
    }
    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) => const LoginScreen()),
    );
  }

  void _showLogoutDialog(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          surfaceTintColor: Colors.transparent,
          title: Text(
            '로그아웃',
            style: TextStyle(
              fontFamily: 'Pretendard',
              fontWeight: FontWeight.w700,
              color: colors.onSurface,
            ),
          ),
          content: Text(
            '정말 로그아웃 하시겠습니까?',
            style: TextStyle(
              fontFamily: 'Pretendard',
              color: colors.onSurface,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(
                '취소',
                style: TextStyle(
                  fontFamily: 'Pretendard',
                  color: colors.muted,
                ),
              ),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(dialogContext);
                await handleLogout(context);
              },
              child: Text(
                '확인',
                style: TextStyle(
                  fontFamily: 'Pretendard',
                  color: colors.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _openEditProfile(BuildContext context) async {
    final auth = AuthService.instance;
    await Navigator.of(context).push<Map<String, String>>(
      MaterialPageRoute(
        builder: (_) => EditProfileScreen(
          currentNickname: auth.nickname ?? '',
          currentCafeType: auth.cafeType,
          currentExperience: auth.experience,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('내정보'),
      ),
      body: ListenableBuilder(
        listenable: AuthService.instance,
        builder: (context, _) {
          final auth = AuthService.instance;
          final loggedIn = auth.hasCompletedOnboarding;
          final uid = auth.kakaoUserId;

          if (!loggedIn || uid == null || uid.isEmpty) {
            return _LoggedOutBody(
              onLogin: () => _handleAuthTap(context, false),
              onSettings: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const SettingsScreen(),
                  ),
                );
              },
            );
          }

          return StreamBuilder<FirestoreUserProfile?>(
            stream: watchUserProfile(uid),
            builder: (context, snapshot) {
              final remote = snapshot.data;
              final nickname = (auth.nickname?.trim().isNotEmpty == true)
                  ? auth.nickname!.trim()
                  : (remote?.nickname.trim().isNotEmpty == true
                      ? remote!.nickname.trim()
                      : '카페인');
              final email = remote?.email.trim() ?? '';
              final profileImage = remote?.profileImage.trim() ?? '';
              final profileLine = [
                if (auth.cafeType != null && auth.cafeType!.isNotEmpty)
                  auth.cafeType!,
                if (auth.experienceLabel != null &&
                    auth.experienceLabel!.isNotEmpty)
                  auth.experienceLabel!,
              ].join(' · ');

              return ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screenH,
                  8,
                  AppSpacing.screenH,
                  40,
                ),
                children: [
                  const SizedBox(height: 8),
                  _ProfileHeader(
                    nickname: nickname,
                    email: email,
                    profileImageUrl: profileImage,
                    subtitle: profileLine.isEmpty
                        ? '카페 종사자 커뮤니티'
                        : profileLine,
                  ),
                  const SizedBox(height: 28),
                  _MenuRow(
                    title: '내가 쓴 글',
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const MyPostsScreen(),
                        ),
                      );
                    },
                  ),
                  _MenuRow(
                    title: '정보 수정',
                    onTap: () => _openEditProfile(context),
                  ),
                  _MenuRow(
                    title: '설정',
                    subtitle: '이용약관 · 개인정보 · 라이선스',
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const SettingsScreen(),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 20),
                  const Divider(height: 0.5, thickness: 0.5),
                  const SizedBox(height: 8),
                  _MenuRow(
                    title: '로그아웃',
                    titleColor: Theme.of(context).colorScheme.error,
                    showChevron: false,
                    onTap: () => _handleAuthTap(context, true),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _LoggedOutBody extends StatelessWidget {
  const _LoggedOutBody({
    required this.onLogin,
    required this.onSettings,
  });

  final VoidCallback onLogin;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenH,
        8,
        AppSpacing.screenH,
        40,
      ),
      children: [
        const SizedBox(height: 8),
        _ProfileHeader(
          nickname: '카페인',
          email: '',
          profileImageUrl: '',
          subtitle: '둘러보기 중 · 글쓰기는 로그인 후 가능해요',
        ),
        const SizedBox(height: 28),
        _MenuRow(
          title: '설정',
          subtitle: '이용약관 · 개인정보 · 라이선스',
          onTap: onSettings,
        ),
        const SizedBox(height: 20),
        const Divider(height: 0.5, thickness: 0.5),
        const SizedBox(height: 8),
        _MenuRow(
          title: '시작하기',
          onTap: onLogin,
        ),
        const SizedBox(height: 8),
        Text(
          '카카오로 시작하면 프로필과 내 글을 확인할 수 있어요.',
          style: TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 13,
            color: colors.muted,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.nickname,
    required this.email,
    required this.profileImageUrl,
    required this.subtitle,
  });

  final String nickname;
  final String email;
  final String profileImageUrl;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final hasImage = profileImageUrl.isNotEmpty;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        CircleAvatar(
          radius: 36,
          backgroundColor: colors.fill,
          backgroundImage: hasImage ? NetworkImage(profileImageUrl) : null,
          child: hasImage
              ? null
              : Text(
                  nickname.isNotEmpty ? nickname.characters.first : '?',
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: colors.onSurface,
                  ),
                ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                nickname,
                style: TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.4,
                  height: 1.25,
                  color: colors.onSurface,
                ),
              ),
              if (email.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  email,
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    color: colors.muted,
                  ),
                ),
              ],
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  color: colors.muted,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.title,
    this.onTap,
    this.titleColor,
    this.subtitle,
    this.showChevron = true,
  });

  final String title;
  final VoidCallback? onTap;
  final Color? titleColor;
  final String? subtitle;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return InkWell(
      onTap: onTap,
      splashFactory: NoSplash.splashFactory,
      highlightColor: colors.press,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 15),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      letterSpacing: -0.2,
                      color: titleColor ?? colors.onSurface,
                    ),
                  ),
                  if (subtitle != null && subtitle!.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      subtitle!,
                      style: TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        color: colors.muted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (showChevron)
              Icon(
                Icons.chevron_right,
                size: 22,
                color: colors.muted,
              ),
          ],
        ),
      ),
    );
  }
}
