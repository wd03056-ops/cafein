import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/constants.dart';
import '../screens/admin_reports_screen.dart';
import '../screens/blocked_users_screen.dart';
import '../screens/main_shell.dart';
import '../screens/reported_users_screen.dart';
import '../services/account_withdrawal_service.dart';
import '../services/admin_access.dart';
import '../services/auth_service.dart';
import '../services/fcm_service.dart';
import '../services/notification_settings_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import '../widgets/cafein_back_app_bar.dart';

/// App settings: notifications, version, legal, licenses.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const _privacyPolicyUrl =
      'https://cafein-five.vercel.app/privacy/';
  static const _termsOfServiceUrl =
      'https://cafein-five.vercel.app/terms/';

  CafeinNotificationSettings _notif = const CafeinNotificationSettings();
  bool _loadingPrefs = true;
  bool _osPermissionDenied = false;
  String _versionLabel = '—';
  bool _checkingUpdate = false;
  bool _canOpenAdminUi = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final settings = await NotificationSettingsService.instance.load();

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

    var osDenied = false;
    try {
      final status = await FcmService.instance.getPermissionStatus();
      osDenied = status == AuthorizationStatus.denied;
    } catch (_) {}

    // Refresh admin claim for Settings menu (server ADMIN_UIDS → token claim).
    await AdminAccess.refreshAdminClaim(forceRefresh: false);

    if (!mounted) return;
    setState(() {
      _notif = settings;
      _versionLabel = version;
      _osPermissionDenied = osDenied;
      _canOpenAdminUi = AdminAccess.canOpenAdminUi;
      _loadingPrefs = false;
    });
  }

  Future<void> _setNotif({
    bool? comment,
    bool? like,
  }) async {
    final turningOn = (comment == true) || (like == true);
    if (turningOn) {
      final ok = await FcmService.instance.requestPermissionIfNeeded();
      if (!mounted) return;
      setState(() => _osPermissionDenied = !ok);
      if (ok) {
        await FcmService.instance.registerForUser();
      }
    }

    await NotificationSettingsService.instance.update(
      comment: comment,
      like: like,
    );
    if (!mounted) return;
    setState(() => _notif = NotificationSettingsService.instance.current);
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
      applicationIcon: Padding(
        padding: const EdgeInsets.all(8),
        child: Image.asset(
          'assets/images/cafeinlogo.png',
          width: 48,
          height: 48,
          fit: BoxFit.contain,
        ),
      ),
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
      appBar: const CafeinBackAppBar(title: '설정'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenH,
          8,
          AppSpacing.screenH,
          40,
        ),
        children: [
          const _SectionLabel('알림 설정'),
          if (!loggedIn)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                '로그인 후 알림을 설정할 수 있어요.',
                style: CafeinTypography.commentBody(
                  Theme.of(context).colorScheme.muted,
                ),
              ),
            )
          else ...[
            _SwitchRow(
              title: '댓글 알림',
              value: _notif.comment,
              enabled: !_loadingPrefs,
              onChanged: (v) => _setNotif(comment: v),
            ),
            _SwitchRow(
              title: '공감 알림',
              value: _notif.like,
              enabled: !_loadingPrefs,
              onChanged: (v) => _setNotif(like: v),
            ),
            if (_osPermissionDenied)
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 4),
                child: Text(
                  '휴대폰 설정에서 알림이 차단되어 있을 수 있습니다.',
                  style: CafeinTypography.metadata(
                    Theme.of(context).colorScheme.muted,
                  ),
                ),
              ),
          ],
          if (loggedIn) ...[
            const SizedBox(height: 20),
            const Divider(height: 0.5, thickness: 0.5),
            const SizedBox(height: 12),
            const _SectionLabel('안전'),
            _NavRow(
              title: '차단한 사용자',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const BlockedUsersScreen(),
                  ),
                );
              },
            ),
            _NavRow(
              title: '신고한 사용자',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const ReportedUsersScreen(),
                  ),
                );
              },
            ),
            if (_canOpenAdminUi)
              _NavRow(
                title: '신고 관리 (운영)',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const AdminReportsScreen(),
                    ),
                  );
                },
              ),
          ],
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
                    style: CafeinTypography.metadata(
                      Theme.of(context).colorScheme.muted,
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
        style: CafeinTypography.nickname(colors.muted),
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
              style: CafeinTypography.postBody(colors.onSurface)
                  .copyWith(fontWeight: FontWeight.w500, letterSpacing: -0.2),
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
                style: CafeinTypography.postBody(colors.onSurface)
                    .copyWith(fontWeight: FontWeight.w500, letterSpacing: -0.2),
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
