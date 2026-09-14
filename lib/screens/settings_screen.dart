import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/constants.dart';
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
      'https://giddy-gaura-998.notion.site/3daad28bec5c801f981de11846a8501a';
  static const _termsOfServiceUrl =
      'https://giddy-gaura-998.notion.site/3daad28bec5c80f1bcb4ce10bda82c99';

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

  @override
  Widget build(BuildContext context) {
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
            title: '개인정보 처리방침',
            onTap: () => _launchInBrowser(_privacyPolicyUrl),
          ),
          _NavRow(
            title: '오픈소스 라이선스',
            onTap: _openLicenses,
          ),
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
