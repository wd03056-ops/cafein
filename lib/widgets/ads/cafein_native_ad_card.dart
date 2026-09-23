import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../ads/ad_helper.dart';
import '../../ads/ad_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';

/// Native Advanced ad card for the home feed.
///
/// Uses a large enough non-clipping container so AdMob's native ad validator
/// does not flag obscured/clipped assets.
class CafeinNativeAdCard extends StatefulWidget {
  const CafeinNativeAdCard({
    super.key,
    /// Enough room for cafein_native_ad.xml (media + CTA) without clipping.
    this.height = 360,
    this.debugSlot,
  });

  final double height;
  final int? debugSlot;

  @override
  State<CafeinNativeAdCard> createState() => _CafeinNativeAdCardState();
}

class _CafeinNativeAdCardState extends State<CafeinNativeAdCard>
    with AutomaticKeepAliveClientMixin {
  NativeAd? _nativeAd;
  bool _loaded = false;
  bool _failed = false;
  bool _loggedInsert = false;
  bool _triedFactory = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    debugPrint(
      '[CAFEIN_AD] creating native ad slot=${widget.debugSlot ?? '-'}',
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load(useFactory: Platform.isAndroid);
    });
  }

  Future<void> _load({required bool useFactory}) async {
    if (_nativeAd != null || _failed) return;

    debugPrint(
      '[CAFEIN_AD] loading native ad slot=${widget.debugSlot ?? '-'} '
      'unit=${AdHelper.nativeAdUnitId} factory=$useFactory',
    );

    if (!AdService.instance.isReady) {
      debugPrint('[CAFEIN_AD] waiting for Mobile Ads init…');
      await AdService.instance.initialize();
    }
    if (!mounted) return;
    if (!AdService.instance.isReady) {
      debugPrint('[CAFEIN_AD] native ad failed = SDK not initialized');
      setState(() => _failed = true);
      return;
    }

    final colors = Theme.of(context).colorScheme;
    late final NativeAd ad;
    ad = NativeAd(
      adUnitId: AdHelper.nativeAdUnitId,
      factoryId: useFactory ? AdHelper.nativeFactoryId : null,
      request: const AdRequest(),
      listener: NativeAdListener(
        onAdLoaded: (loaded) {
          debugPrint(
            '[CAFEIN_AD] native ad loaded slot=${widget.debugSlot ?? '-'} '
            'factory=$useFactory',
          );
          if (!mounted) {
            loaded.dispose();
            debugPrint('[CAFEIN_AD] disposing native ad (unmounted on load)');
            return;
          }
          setState(() {
            _loaded = true;
            _failed = false;
          });
        },
        onAdFailedToLoad: (failed, error) {
          debugPrint(
            '[CAFEIN_AD] native ad failed = '
            'code=${error.code} domain=${error.domain} '
            'message=${error.message} slot=${widget.debugSlot ?? '-'} '
            'factory=$useFactory',
          );
          failed.dispose();
          if (!mounted) return;

          if (useFactory && !_triedFactory) {
            _triedFactory = true;
            setState(() {
              _nativeAd = null;
              _loaded = false;
            });
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _load(useFactory: false);
            });
            return;
          }

          setState(() {
            _nativeAd = null;
            _loaded = false;
            _failed = true;
          });
        },
        onAdImpression: (_) {
          debugPrint(
            '[CAFEIN_AD] native ad impression slot=${widget.debugSlot ?? '-'}',
          );
        },
      ),
      nativeTemplateStyle: useFactory
          ? null
          : NativeTemplateStyle(
              templateType: TemplateType.medium,
              mainBackgroundColor: colors.surface,
              cornerRadius: 12,
              callToActionTextStyle: NativeTemplateTextStyle(
                textColor: colors.onSurface,
                backgroundColor: colors.fillStrong,
                style: NativeTemplateFontStyle.bold,
                size: 14,
              ),
              primaryTextStyle: NativeTemplateTextStyle(
                textColor: colors.onSurface,
                style: NativeTemplateFontStyle.bold,
                size: 15,
              ),
              secondaryTextStyle: NativeTemplateTextStyle(
                textColor: colors.muted,
                style: NativeTemplateFontStyle.normal,
                size: 13,
              ),
              tertiaryTextStyle: NativeTemplateTextStyle(
                textColor: colors.muted,
                style: NativeTemplateFontStyle.normal,
                size: 12,
              ),
            ),
    );

    _nativeAd = ad;
    try {
      await ad.load();
    } catch (e, st) {
      debugPrint('[CAFEIN_AD] native ad failed = load() threw: $e');
      debugPrint('$st');
      if (mounted) {
        setState(() {
          _nativeAd = null;
          _failed = true;
          _loaded = false;
        });
      }
    }
  }

  @override
  void dispose() {
    debugPrint(
      '[CAFEIN_AD] disposing native ad slot=${widget.debugSlot ?? '-'}',
    );
    _nativeAd?.dispose();
    _nativeAd = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    // Fixed outer height while loading/showing so scroll doesn't jump.
    // Fail → collapse (rare; GlobalKey keeps loaded ads across refresh).
    if (_failed) {
      return const SizedBox.shrink();
    }

    Widget child;
    if (!_loaded || _nativeAd == null) {
      child = const SizedBox.expand();
    } else {
      if (!_loggedInsert) {
        _loggedInsert = true;
        debugPrint(
          '[CAFEIN_AD] inserting native ad into feed '
          'slot=${widget.debugSlot ?? '-'} h=${widget.height}',
        );
      }
      child = Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.screenH,
          vertical: AppSpacing.md,
        ),
        child: AdWidget(ad: _nativeAd!),
      );
    }

    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: child,
    );
  }
}
