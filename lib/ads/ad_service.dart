import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Initializes Google Mobile Ads SDK once before loading ads.
///
/// Per AdMob docs, call [MobileAds.instance.initialize] early and wait
/// (or use the completion) before requesting ads.
/// https://developers.google.com/admob/android/quick-start
class AdService {
  AdService._();
  static final AdService instance = AdService._();

  bool _initialized = false;
  Future<void>? _initFuture;

  bool get isReady => _initialized;

  Future<void> initialize() {
    final existing = _initFuture;
    if (existing != null) return existing;

    _initFuture = _doInitialize();
    return _initFuture!;
  }

  Future<void> _doInitialize() async {
    try {
      debugPrint('[CAFEIN_AD] Mobile Ads initialize start');
      final status = await MobileAds.instance.initialize();
      _initialized = true;
      debugPrint(
        '[CAFEIN_AD] Mobile Ads initialize done '
        'adapters=${status.adapterStatuses.length}',
      );
      if (kDebugMode) {
        await MobileAds.instance.updateRequestConfiguration(
          RequestConfiguration(
            testDeviceIds: const <String>['EMULATOR'],
          ),
        );
      }
    } catch (e, st) {
      debugPrint('[CAFEIN_AD] Mobile Ads initialize failed: $e');
      debugPrint('$st');
      _initFuture = null;
    }
  }
}
