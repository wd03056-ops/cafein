import 'package:flutter_test/flutter_test.dart';

import 'package:cafein/app.dart';
import 'package:cafein/services/auth_service.dart';

void main() {
  testWidgets('비로그인 시 로그인 화면이 보인다', (tester) async {
    await tester.pumpWidget(
      const CafeinApp(initialSession: KakaoSessionStatus.none),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('카페인'), findsWidgets);
  });
}
