import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/constants.dart';
import '../screens/main_shell.dart';
import '../services/account_withdrawal_service.dart';
import '../services/auth_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// App settings: notifications, version, legal, licenses.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const _pushPrefKey = 'cafein_push_enabled';
  static const _privacyPolicyUrl =
      'https://cafein-five.vercel.app/privacy/';
  static const _termsOfServiceUrl =
      'https://cafein-five.vercel.app/terms/';

  bool _pushEnabled = true;
  bool _loadingPrefs = true;
  String _versionLabel = '—';
  bool _checkingUpdate = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final push = prefs.getBool(_pushPrefKey) ?? true;

    String version = '1.0.0';
    try {
      final info = await PackageInfo.fromPlatform();
      version = info.version;
      if (info.buildNumber.isNotEmpty) {
        version = '${info.version} (${info.buildNumber})';
      }
    } catch (_) {
      // Keep fallback from pubspec-style default.
    }

    if (!mounted) return;
    setState(() {
      _pushEnabled = push;
      _versionLabel = version;
      _loadingPrefs = false;
    });
  }

  Future<void> _setPushEnabled(bool value) async {
    setState(() => _pushEnabled = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_pushPrefKey, value);
  }

  Future<void> _checkLatestVersion() async {
    if (_checkingUpdate) return;
    setState(() => _checkingUpdate = true);

    // TODO: replace with store / server version API
    await Future<void>.delayed(const Duration(milliseconds: 600));

    if (!mounted) return;
    setState(() => _checkingUpdate = false);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('현재 최신 버전을 사용 중이에요.')),
    );
  }

  Future<void> _launchInBrowser(String urlString) async {
    final url = Uri.parse(urlString);
    final launched = await launchUrl(
      url,
      mode: LaunchMode.externalApplication,
    );
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('링크를 열 수 없어요.')),
      );
    }
  }

  void _openLicenses() {
    showLicensePage(
      context: context,
      applicationName: AppConstants.appName,
      applicationVersion: _versionLabel,
      applicationIcon: const FlutterLogo(size: 48),
      applicationLegalese: '© Cafein',
    );
  }

  Future<void> _withdrawAccount() async {
    debugPrint('[DELETE ACCOUNT] button clicked');

    if (!AuthService.instance.canWriteContent) {
      debugPrint('[DELETE ACCOUNT] blocked: not logged in / onboarding incomplete');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('로그인 후 이용할 수 있어요.')),
      );
      return;
    }

    debugPrint('[DELETE ACCOUNT] confirmation');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('회원 탈퇴'),
        content: const Text(
          '정말 탈퇴하시겠습니까?\n\n'
          '탈퇴하면 계정 정보와 개인 식별 정보가 삭제되며\n'
          '복구할 수 없습니다.\n'
          '작성하신 게시글·댓글은 익명으로 남습니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              '탈퇴하기',
              style: TextStyle(
                color: Theme.of(ctx).colorScheme.error,
              ),
            ),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) {
      debugPrint('[DELETE ACCOUNT] confirmation cancelled');
      return;
    }

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const PopScope(
        canPop: false,
        child: Center(
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('탈퇴 처리 중…'),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    try {
      await AccountWithdrawalService.instance.withdraw();
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop(); // loading
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => const MainShell()),
        (route) => false,
      );
    } catch (e, st) {
      debugPrint('회원 탈퇴 실패: $e');
      debugPrint('$st');
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop(); // loading
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('탈퇴 실패'),
          content: const Text(
            '회원 탈퇴에 실패했습니다.\n잠시 후 다시 시도해 주세요.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('확인'),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final loggedIn = AuthService.instance.hasCompletedOnboarding;

    return Scaffold(
      appBar: AppBar(
        title: const Text('설정'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenH,
          8,
          AppSpacing.screenH,
          40,
        ),
        children: [
          const _SectionLabel('알림'),
          _SwitchRow(
            title: '푸시 알림',
            value: _pushEnabled,
            enabled: !_loadingPrefs,
            onChanged: _setPushEnabled,
          ),
          const SizedBox(height: 20),
          const Divider(height: 0.5, thickness: 0.5),
          const SizedBox(height: 12),
          const _SectionLabel('앱 정보'),
          _NavRow(
            title: '버전 정보',
            trailing: _checkingUpdate
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    _versionLabel,
                    style: TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                      color: Theme.of(context).colorScheme.muted,
                    ),
                  ),
            onTap: _checkLatestVersion,
          ),
          _NavRow(
            title: '이용약관',
            onTap: () => _launchInBrowser(_termsOfServiceUrl),
          ),
          _NavRow(
            title: '개인정보처리방침',
            onTap: () => _launchInBrowser(_privacyPolicyUrl),
          ),
          _NavRow(
            title: '오픈소스 라이선스',
            onTap: _openLicenses,
          ),
          if (loggedIn) ...[
            const SizedBox(height: 20),
            const Divider(height: 0.5, thickness: 0.5),
            const SizedBox(height: 12),
            const _SectionLabel('계정'),
            _NavRow(
              title: '회원 탈퇴',
              onTap: () {
                // Explicit callback so the async Future is started reliably.
                _withdrawAccount();
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Text(
        text,
        style: TextStyle(
          fontFamily: 'Pretendard',
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: colors.muted,
        ),
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.title,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 16,
                fontWeight: FontWeight.w500,
                letterSpacing: -0.2,
                color: colors.onSurface,
              ),
            ),
          ),
          Switch.adaptive(
            value: value,
            onChanged: enabled ? onChanged : null,
            activeThumbColor: colors.surface,
            activeTrackColor: colors.onSurface,
          ),
        ],
      ),
    );
  }
}

class _NavRow extends StatelessWidget {
  const _NavRow({
    required this.title,
    required this.onTap,
    this.trailing,
  });

  final String title;
  final VoidCallback onTap;
  final Widget? trailing;

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
              child: Text(
                title,
                style: TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  letterSpacing: -0.2,
                  color: colors.onSurface,
                ),
              ),
            ),
            if (trailing != null) ...[
              trailing!,
              const SizedBox(width: 6),
            ],
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
