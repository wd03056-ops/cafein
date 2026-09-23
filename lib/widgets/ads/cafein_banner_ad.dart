import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../ads/ad_helper.dart';
import '../../ads/ad_service.dart';

/// Anchored adaptive banner above the shell [NavigationBar].
///
/// Renders only after load succeeds — no reserved empty gap on failure.
/// Does not apply bottom SafeArea; the shell NavigationBar owns system insets.
class CafeinBannerAd extends StatefulWidget {
  const CafeinBannerAd({super.key});

  @override
  State<CafeinBannerAd> createState() => _CafeinBannerAdState();
}

class _CafeinBannerAdState extends State<CafeinBannerAd> {
  BannerAd? _banner;
  bool _loaded = false;
  bool _loading = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadIfNeeded();
  }

  Future<void> _loadIfNeeded() async {
    if (_banner != null || _loading) return;
    _loading = true;

    try {
      if (!AdService.instance.isReady) {
        await AdService.instance.initialize();
      }
      if (!mounted) return;

      final width = MediaQuery.sizeOf(context).width.truncate();
      // Standard adaptive (~50–60dp) sits flush above the nav bar.
      // Large adaptive reserves up to ~150dp and leaves empty space under
      // typical banner creatives. (Marked deprecated in favor of Large.)
      // ignore: deprecated_member_use
      final size = await AdSize.getCurrentOrientationAnchoredAdaptiveBannerAdSize(width);
      if (size == null || !mounted) return;

      final ad = BannerAd(
        adUnitId: AdHelper.bannerAdUnitId,
        size: size,
        request: const AdRequest(),
        listener: BannerAdListener(
          onAdLoaded: (loaded) {
            debugPrint(
              '[CAFEIN_AD] banner loaded '
              '${(loaded as BannerAd).size.width}x${loaded.size.height}',
            );
            if (!mounted) {
              loaded.dispose();
              return;
            }
            setState(() => _loaded = true);
          },
          onAdFailedToLoad: (failed, error) {
            debugPrint(
              '[CAFEIN_AD] banner failed = '
              'code=${error.code} message=${error.message}',
            );
            failed.dispose();
            if (mounted) {
              setState(() {
                _banner = null;
                _loaded = false;
              });
            }
          },
        ),
      );

      _banner = ad;
      await ad.load();
    } finally {
      _loading = false;
    }
  }

  @override
  void dispose() {
    _banner?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ad = _banner;
    if (!_loaded || ad == null) {
      return const SizedBox.shrink();
    }

    final colors = Theme.of(context).colorScheme;
    return ColoredBox(
      color: colors.surface,
      child: SizedBox(
        width: ad.size.width.toDouble(),
        height: ad.size.height.toDouble(),
        child: AdWidget(ad: ad),
      ),
    );
  }
}
