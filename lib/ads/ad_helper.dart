import 'dart:io';

/// AdMob unit IDs + factory ids.
///
/// Android uses CAFEIN production App ID + ad units. iOS still uses Google
/// test units / sample App ID until real iOS units are configured.
///
/// See:
/// - https://developers.google.com/admob/android/quick-start
/// - https://developers.google.com/admob/flutter/quick-start
class AdHelper {
  AdHelper._();

  /// CAFEIN AdMob App ID (must match AndroidManifest APPLICATION_ID).
  static const androidAppId = 'ca-app-pub-4352425125830619~5945651696';
  static const iosAppId = 'ca-app-pub-3940256099942544~1458002511';

  /// Must match [MainActivity.NATIVE_FACTORY_ID] on Android.
  static const nativeFactoryId = 'cafeinNative';

  /// Banner — Android production / iOS Google test.
  static const _androidBannerId = 'ca-app-pub-4352425125830619/3750733199';
  static const _iosBannerId = 'ca-app-pub-3940256099942544/2934735716';

  /// Native Advanced — Android production / iOS Google test.
  static const _androidNativeId = 'ca-app-pub-4352425125830619/3932152865';
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
  static const showBottomBannerAd = true;
}
