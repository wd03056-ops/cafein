import 'package:flutter_test/flutter_test.dart';

import 'package:cafein/app.dart';
import 'package:cafein/core/constants.dart';

void main() {
  testWidgets('홈에 카페인과 피드 탭·하단 네비가 보인다', (tester) async {
    await tester.pumpWidget(const CafeinApp());
    await tester.pumpAndSettle();

    expect(find.text('카페인'), findsOneWidget);
    expect(find.text('인기'), findsOneWidget);
    expect(find.text('최신'), findsOneWidget);
    expect(find.text('홈'), findsOneWidget);
    expect(find.text('글쓰기'), findsOneWidget);
    expect(find.text('내정보'), findsOneWidget);

    final nicknameFound = AppConstants.anonymousNicknames
        .any((name) => find.textContaining(name).evaluate().isNotEmpty);
    expect(nicknameFound, isTrue);
  });
}
