import 'dart:io';

/// AdMob unit IDs + factory ids.
///
/// Currently Google official **test** IDs for device testing.
/// Replace with real CAFEIN units before Play/App Store release.
///
/// See:
/// - https://developers.google.com/admob/android/quick-start
/// - https://developers.google.com/admob/flutter/quick-start
class AdHelper {
  AdHelper._();

  /// Google sample AdMob App ID (must match AndroidManifest / Info.plist).
  static const androidAppId = 'ca-app-pub-3940256099942544~3347511713';
  static const iosAppId = 'ca-app-pub-3940256099942544~1458002511';

  /// Must match [MainActivity.NATIVE_FACTORY_ID] on Android.
  static const nativeFactoryId = 'cafeinNative';

  /// Banner — Google test unit.
  static const _androidBannerId = 'ca-app-pub-3940256099942544/6300978111';
  static const _iosBannerId = 'ca-app-pub-3940256099942544/2934735716';

  /// Native Advanced — Google test unit.
  static const _androidNativeId = 'ca-app-pub-3940256099942544/2247696110';
  static const _iosNativeId = 'ca-app-pub-3940256099942544/3986624511';

  static String get bannerAdUnitId {
    if (Platform.isAndroid) return _androidBannerId;
    if (Platform.isIOS) return _iosBannerId;
    throw UnsupportedError('Unsupported platform for AdMob');
  }

  static String get nativeAdUnitId {
    if (Platform.isAndroid) return _androidNativeId;
    if (Platform.isIOS) return _iosNativeId;
    throw UnsupportedError('Unsupported platform for AdMob');
  }

  /// Insert a native ad after every N posts in the feed.
  static const nativeAdInterval = 4;

  /// Bottom banner above [NavigationBar]. Set `true` to show again.
  static const showBottomBannerAd = false;
}
