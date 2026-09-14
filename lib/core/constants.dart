/// 앱 전역 상수
class AppConstants {
  static const String appName = '카페인';
  static const String searchHint = '궁금한 걸 검색해보세요';
  static const String emptySearchMessage =
      '아직 관련 글이 없어요. 첫 번째로 질문해보세요.';

  /// 온보딩 근무 경력 옵션
  static const List<String> experienceOptions = [
    '1개월 미만',
    '1개월 이상',
    '3개월 이상',
    '6개월 이상',
    '1~3년',
    '4~5년 이상',
  ];

  static const List<String> cafeTypeOptions = [
    '개인카페',
    '프랜차이즈',
  ];

  /// 익명 별명 풀 (글/댓글마다 무작위로 배정)
  static const List<String> anonymousNicknames = [
    '샷 내린 알바',
    '마감요정',
    '라떼고수',
    '오픈담당',
    '피크생존자',
    '시럽요정',
    '디시세척러',
    '출근5분전',
    '휴게실단골',
    '시급계산기',
    '진상방어막',
    '원두냄새중독',
    '아이스선호',
    '핸드드립러',
    '포스기전사',
    '재고확인러',
    '텀블러환영',
    '야간알바',
    '주말풀타임',
    '프랜탈출러',
    '개인카페러',
    '밀크스티머',
    '에스프레소맨',
    '케이크커터',
    '웨이팅관리',
    '배달앱킬러',
    '청소마스터',
    '스케줄조율러',
    '사장님눈치',
    '동료응원단',
  ];

  /// seed 기준으로 안정적인 익명 별명 선택
  static String nicknameFor(String seed) {
    var hash = 0;
    for (final unit in seed.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return anonymousNicknames[hash % anonymousNicknames.length];
  }

  /// seed 기준으로 안정적인 경력 라벨 선택 (목 데이터용)
  static String experienceFor(String seed) {
    var hash = 0;
    for (final unit in seed.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return experienceOptions[hash % experienceOptions.length];
  }

  /// seed 기준으로 안정적인 근무 형태 선택 (목 데이터용)
  static String cafeTypeFor(String seed) {
    var hash = 0;
    for (final unit in seed.codeUnits) {
      hash = (hash * 33 + unit) & 0x7fffffff;
    }
    return cafeTypeOptions[hash % cafeTypeOptions.length];
  }

  /// 새 글/댓글용 무작위 별명
  static String randomNickname([int? salt]) {
    final t = DateTime.now().microsecondsSinceEpoch ^ (salt ?? 0);
    return anonymousNicknames[t.abs() % anonymousNicknames.length];
  }
}
