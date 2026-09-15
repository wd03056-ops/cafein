import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/nickname_validator.dart';
import '../services/auth_service.dart';
import '../services/nickname_service.dart';
import '../theme/app_colors.dart';
import '../widgets/no_underline_text_editing_controller.dart';
import 'main_shell.dart';

/// Collects nickname / cafe type / experience after login.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _nicknameController = NoUnderlineTextEditingController();
  String _cafeType = '개인카페';
  String _selectedExperience = '3개월 이상';
  String? _nicknameErrorText;
  bool _submitting = false;
  bool _agreedTerms = false;
  bool _agreedPrivacy = false;

  static const _privacyPolicyUrl =
      'https://cafein-five.vercel.app/privacy/';
  static const _termsOfServiceUrl =
      'https://cafein-five.vercel.app/terms/';

  static const List<String> _experienceOptions = [
    '1개월 미만',
    '1개월 이상',
    '3개월 이상',
    '6개월 이상',
    '1~3년',
    '4~5년 이상',
  ];

  @override
  void dispose() {
    _nicknameController.dispose();
    super.dispose();
  }

  Future<void> _openUrl(String urlString) async {
    final url = Uri.parse(urlString);
    final launched = await launchUrl(url, mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('링크를 열 수 없어요.')),
      );
    }
  }

  bool _validateNicknameFormat(String nickname) {
    final cleaned = nickname.replaceAll(RegExp(r'\s+'), '').trim();
    final error = nicknameValidationError(cleaned);
    setState(() => _nicknameErrorText = error);
    return error == null;
  }

  Future<void> _completeOnboarding() async {
    if (_submitting) return;

    if (!_agreedTerms || !_agreedPrivacy) {
      setState(
        () => _nicknameErrorText = '이용약관과 개인정보처리방침에 동의해 주세요.',
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('이용약관과 개인정보처리방침에 동의해 주세요.')),
      );
      return;
    }

    final sanitizedNickname =
        _nicknameController.text.replaceAll(RegExp(r'\s+'), '').trim();

    if (!_validateNicknameFormat(sanitizedNickname)) {
      return;
    }

    if (_nicknameController.text != sanitizedNickname) {
      _nicknameController.text = sanitizedNickname;
    }

    final auth = AuthService.instance;
    final uid = auth.kakaoUserId;
    if (uid == null || uid.isEmpty) {
      setState(() => _nicknameErrorText = '로그인 정보가 없어요. 다시 로그인해 주세요.');
      return;
    }

    if (auth.isNicknameUsedLocally(sanitizedNickname, excludeUid: uid)) {
      setState(() => _nicknameErrorText = '이미 사용 중인 닉네임이에요.');
      return;
    }

    setState(() => _submitting = true);
    try {
      final taken = await NicknameService.instance.isNicknameTaken(
        sanitizedNickname,
        excludeUid: uid,
      );
      if (taken) {
        if (!mounted) return;
        setState(() {
          _nicknameErrorText = '이미 사용 중인 닉네임이에요.';
          _submitting = false;
        });
        return;
      }

      await NicknameService.instance.claimNickname(
        uid: uid,
        nickname: sanitizedNickname,
      );

      auth.completeOnboarding(
        nickname: sanitizedNickname,
        cafeType: _cafeType,
        experience: _selectedExperience,
      );

      if (!mounted) return;
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop(true);
        return;
      }
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => const MainShell()),
        (route) => false,
      );
    } on NicknameTakenException {
      if (!mounted) return;
      setState(() => _nicknameErrorText = '이미 사용 중인 닉네임이에요.');
    } catch (e) {
      debugPrint('닉네임 저장 실패: $e');
      if (!mounted) return;
      setState(
        () => _nicknameErrorText = '닉네임 확인에 실패했어요. 잠시 후 다시 시도해 주세요.',
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();
    const radius = BorderRadius.all(Radius.circular(12));
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        // Keep a stable toolbar geometry — leadingWidth: 0 can clip under status bar.
        automaticallyImplyLeading: false,
        leadingWidth: canPop ? 48 : 16,
        titleSpacing: 0,
        leading: canPop
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: '뒤로',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                onPressed: () => Navigator.of(context).maybePop(),
              )
            : const SizedBox.shrink(),
        title: const Text('추가 정보 입력'),
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '커뮤니티에서 사용할\n정보를 입력해주세요.',
                style: TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  height: 1.35,
                  color: colors.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '익명으로 안전하게 활동할 수 있어요.',
                style: TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  color: colors.muted,
                ),
              ),
              const SizedBox(height: 32),
              Text(
                '닉네임',
                style: TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: colors.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _nicknameController,
                autofocus: true,
                textInputAction: TextInputAction.done,
                inputFormatters: [
                  FilteringTextInputFormatter.deny(RegExp(r'\s')),
                ],
                onChanged: (_) {
                  if (_nicknameErrorText != null) {
                    setState(() => _nicknameErrorText = null);
                  }
                },
                style: TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 15,
                  color: colors.onSurface,
                  decoration: TextDecoration.none,
                ),
                decoration: InputDecoration(
                  hintText: '사용할 닉네임을 입력하세요 (띄어쓰기 불가)',
                  hintStyle: TextStyle(
                    fontFamily: 'Pretendard',
                    color: colors.mutedSoft,
                  ),
                  errorText: _nicknameErrorText,
                  errorStyle: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 12,
                    height: 1.4,
                    color: colors.error,
                  ),
                  filled: true,
                  fillColor: colors.fill,
                  border: const OutlineInputBorder(
                    borderRadius: radius,
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: const OutlineInputBorder(
                    borderRadius: radius,
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: const OutlineInputBorder(
                    borderRadius: radius,
                    borderSide: BorderSide.none,
                  ),
                  errorBorder: OutlineInputBorder(
                    borderRadius: radius,
                    borderSide: BorderSide(color: colors.error),
                  ),
                  focusedErrorBorder: OutlineInputBorder(
                    borderRadius: radius,
                    borderSide: BorderSide(color: colors.error, width: 1.2),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 14,
                  ),
                ),
              ),
              if (_nicknameErrorText == null) ...[
                const SizedBox(height: 6),
                Text(
                  '※ 띄어쓰기는 자동으로 무시되며, 본명이나 유추 가능한 닉네임은 피해주세요.',
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    height: 1.4,
                    color: colors.muted,
                  ),
                ),
              ],
              const SizedBox(height: 28),
              Text(
                '근무 형태',
                style: TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: colors.onSurface,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _SelectChip(
                      label: '개인 카페',
                      selected: _cafeType == '개인카페',
                      onTap: () => setState(() => _cafeType = '개인카페'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _SelectChip(
                      label: '프랜차이즈',
                      selected: _cafeType == '프랜차이즈',
                      onTap: () => setState(() => _cafeType = '프랜차이즈'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              Text(
                '근무 경력',
                style: TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: colors.onSurface,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final option in _experienceOptions)
                    _ExperienceChip(
                      label: option,
                      selected: _selectedExperience == option,
                      onTap: () =>
                          setState(() => _selectedExperience = option),
                    ),
                ],
              ),
              const SizedBox(height: 28),
              _ConsentRow(
                value: _agreedTerms,
                label: '이용약관 동의 (필수)',
                onChanged: (v) => setState(() => _agreedTerms = v ?? false),
                onOpen: () => _openUrl(_termsOfServiceUrl),
              ),
              _ConsentRow(
                value: _agreedPrivacy,
                label: '개인정보처리방침 동의 (필수)',
                onChanged: (v) => setState(() => _agreedPrivacy = v ?? false),
                onOpen: () => _openUrl(_privacyPolicyUrl),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton(
                  onPressed: _submitting ? null : _completeOnboarding,
                  style: FilledButton.styleFrom(
                    backgroundColor: colors.onSurface,
                    foregroundColor: colors.surface,
                    disabledBackgroundColor: colors.onSurface.withValues(
                      alpha: 0.4,
                    ),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _submitting
                      ? SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: colors.surface,
                          ),
                        )
                      : const Text(
                          '시작하기',
                          style: TextStyle(
                            fontFamily: 'Pretendard',
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SelectChip extends StatelessWidget {
  const _SelectChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Material(
      color: selected ? colors.onSurface : colors.fill,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        splashFactory: NoSplash.splashFactory,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: selected ? colors.surface : colors.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

class _ExperienceChip extends StatelessWidget {
  const _ExperienceChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Material(
      color: selected ? colors.onSurface : colors.fill,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        splashFactory: NoSplash.splashFactory,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Text(
            label,
            style: TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 13,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: selected ? colors.surface : colors.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

class _ConsentRow extends StatelessWidget {
  const _ConsentRow({
    required this.value,
    required this.label,
    required this.onChanged,
    required this.onOpen,
  });

  final bool value;
  final String label;
  final ValueChanged<bool?> onChanged;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Checkbox(
            value: value,
            onChanged: onChanged,
            activeColor: colors.onSurface,
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => onChanged(!value),
              child: Text(
                label,
                style: TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 14,
                  color: colors.onSurface,
                ),
              ),
            ),
          ),
          TextButton(
            onPressed: onOpen,
            child: Text(
              '보기',
              style: TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 13,
                color: colors.muted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
