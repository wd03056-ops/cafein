import 'package:flutter_test/flutter_test.dart';

import 'package:cafein/app.dart';
import 'package:cafein/services/auth_service.dart';

void main() {
  testWidgets('비로그인 시 피드(홈) 화면이 보인다', (tester) async {
    await tester.pumpWidget(
      const CafeinApp(initialSession: KakaoSessionStatus.none),
    );
    await tester.pumpAndSettle();

    expect(find.text('홈'), findsOneWidget);
    expect(find.text('글쓰기'), findsOneWidget);
  });
}
