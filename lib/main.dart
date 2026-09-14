import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:kakao_flutter_sdk/kakao_flutter_sdk.dart';

import 'app.dart';
import 'firebase_options.dart';

void main() async {
  // 플러터 엔진 바인딩 초기화 (비동기 작업 수행 전 필수)
  WidgetsFlutterBinding.ensureInitialized();

  // 파이어베이스 초기화
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  KakaoSdk.init(
    nativeAppKey: 'fc9167389868d3a13d7621c7ad5ac020',
  );

  runApp(const CafeinApp());
}
