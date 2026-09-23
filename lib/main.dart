import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:kakao_flutter_sdk/kakao_flutter_sdk.dart';

import 'ads/ad_service.dart';
import 'app.dart';
import 'firebase_options.dart';
import 'services/auth_service.dart';
import 'services/fcm_service.dart';

Future<void> main() async {
  final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  KakaoSdk.init(
    nativeAppKey: 'fc9167389868d3a13d7621c7ad5ac020',
  );

  await FcmService.instance.init();

  // AdMob: initialize before loading ads (Android/iOS only).
  // https://developers.google.com/admob/flutter/quick-start
  if (Platform.isAndroid || Platform.isIOS) {
    await AdService.instance.initialize();
  }

  // Session restore under native splash — no Flutter loading screen after.
  final session = await AuthService.instance.tryRestoreKakaoSession();
  if (session == KakaoSessionStatus.authenticated) {
    unawaited(FcmService.instance.registerForUser());
  }

  runApp(CafeinApp(initialSession: session));
  FlutterNativeSplash.remove();
}
