import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/nickname_validator.dart';
import '../services/auth_service.dart';
import '../services/comments_firestore_service.dart';
import '../services/nickname_service.dart';
import '../services/notification_inbox_service.dart';
import '../services/post_service.dart';
import '../services/posts_firestore_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import '../widgets/cafein_back_app_bar.dart';
import '../widgets/no_underline_text_editing_controller.dart';

/// Edit nickname / cafe type / experience after onboarding.
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({
    super.key,
    this.currentNickname,
    this.currentCafeType,
    this.currentExperience,
  });

  final String? currentNickname;
  final String? currentCafeType;
  final String? currentExperience;

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late final NoUnderlineTextEditingController _nicknameController;
  late String _cafeType;
  late String _selectedExperience;
  late final String _originalNickname;
  String? _nicknameErrorText;
  bool _submitting = false;

  static const List<String> _experienceOptions = [
    '1개월 미만',
    '1개월 이상',
    '3개월 이상',
    '6개월 이상',
    '1~3년',
    '4~5년 이상',
  ];

  @override
  void initState() {
    super.initState();
    final auth = AuthService.instance;
    _originalNickname =
        (widget.currentNickname ?? auth.nickname ?? '').trim();
    _nicknameController = NoUnderlineTextEditingController(
      text: widget.currentNickname ?? auth.nickname ?? '',
    );
    _cafeType = widget.currentCafeType ?? auth.cafeType ?? '개인카페';
    _selectedExperience =
        widget.currentExperience ?? auth.experience ?? '3개월 이상';
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    super.dispose();
  }

  bool _validateNicknameFormat(String nickname) {
    final cleaned = nickname.replaceAll(RegExp(r'\s+'), '').trim();
    final error = nicknameValidationError(cleaned);
    setState(() => _nicknameErrorText = error);
    return error == null;
  }

  Future<void> _save() async {
    if (_submitting) return;

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
      if (sanitizedNickname != normalizeNickname(_originalNickname)) {
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
          previousNickname: _originalNickname,
        );
      } else {
        // Nickname unchanged — still sync profile fields on user doc.
        await NicknameService.instance.claimNickname(
          uid: uid,
          nickname: sanitizedNickname,
          previousNickname: _originalNickname,
        );
      }

      PostsFirestoreService.instance.remapAuthorNickname(uid, sanitizedNickname);
      CommentsFirestoreService.instance.remapAuthorNickname(uid, sanitizedNickname);
      PostService.instance.remapAuthorNickname(uid, sanitizedNickname);
      NotificationInboxService.instance.remapActorNickname(
        uid,
        sanitizedNickname,
      );

      auth.completeOnboarding(
        nickname: sanitizedNickname,
        cafeType: _cafeType,
        experience: _selectedExperience,
      );

      if (!mounted) return;
      Navigator.of(context).pop({
        'nickname': sanitizedNickname,
        'cafeType': _cafeType,
        'experience': _selectedExperience,
      });
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
    const radius = BorderRadius.all(Radius.circular(12));
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: const CafeinBackAppBar(title: '정보 수정'),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '닉네임',
                style: CafeinTypography.nickname(colors.onSurface),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _nicknameController,
                textInputAction: TextInputAction.done,
                inputFormatters: [
                  FilteringTextInputFormatter.deny(RegExp(r'\s')),
                ],
                onChanged: (_) {
                  if (_nicknameErrorText != null) {
                    setState(() => _nicknameErrorText = null);
                  }
                },
                style: CafeinTypography.commentBody(colors.onSurface),
                decoration: InputDecoration(
                  hintText: '닉네임을 입력하세요',
                  hintStyle: CafeinTypography.metadata(colors.mutedSoft),
                  errorText: _nicknameErrorText,
                  errorStyle: CafeinTypography.metadata(colors.error),
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
                  style: CafeinTypography.metadata(colors.muted),
                ),
              ],
              const SizedBox(height: 28),
              Text(
                '근무 형태',
                style: CafeinTypography.nickname(colors.onSurface),
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
                style: CafeinTypography.nickname(colors.onSurface),
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
              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton(
                  onPressed: _submitting ? null : _save,
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
                      : Text(
                          '저장하기',
                          style: CafeinTypography.button(),
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
      color: selected ? colors.onSurface : Colors.transparent,
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
            style: CafeinTypography.button(
              selected ? colors.surface : colors.onSurface,
            ).copyWith(fontWeight: FontWeight.w500),
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
      color: selected ? colors.onSurface : Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        splashFactory: NoSplash.splashFactory,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Text(
            label,
            style: CafeinTypography.button(
              selected ? colors.surface : colors.onSurface,
            ).copyWith(
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}
