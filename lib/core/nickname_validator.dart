/// Nickname validation for onboarding / profile edit.
bool isValidNickname(String nickname) {
  final cleaned = nickname.replaceAll(RegExp(r'\s+'), '').trim();

  // 1. Length: 2–10 (spaces already stripped)
  if (cleaned.length < 2 || cleaned.length > 10) {
    return false;
  }

  // 2. Block strings made only of Hangul jamo (consonants/vowels)
  // Note: do not put `|` inside `[]` — that would match a literal pipe.
  final onlyConsonantsOrVowels = RegExp(r'^[ㄱ-ㅎㅏ-ㅣ]+$');
  if (onlyConsonantsOrVowels.hasMatch(cleaned)) {
    return false;
  }

  // 3. Block excessive same-character repeats (ㅋㅋㅋ, aaa, ㅠㅠㅠ…)
  final repeatedChar = RegExp(r'(.)\1{2,}');
  if (repeatedChar.hasMatch(cleaned)) {
    return false;
  }

  return true;
}

/// User-facing reason when [isValidNickname] fails.
String? nicknameValidationError(String nickname) {
  final cleaned = nickname.replaceAll(RegExp(r'\s+'), '').trim();

  if (cleaned.isEmpty) {
    return '사용할 닉네임을 입력해주세요.';
  }
  if (cleaned.length < 2) {
    return '닉네임은 공백 제외 2자 이상 입력해주세요.';
  }
  if (cleaned.length > 10) {
    return '닉네임은 10자 이하로 입력해주세요.';
  }
  if (RegExp(r'^[ㄱ-ㅎㅏ-ㅣ]+$').hasMatch(cleaned)) {
    return '자음·모음만으로 이루어진 닉네임은 사용할 수 없어요.';
  }
  if (RegExp(r'(.)\1{2,}').hasMatch(cleaned)) {
    return '같은 문자를 3번 이상 연속으로 쓸 수 없어요.';
  }
  return null;
}
