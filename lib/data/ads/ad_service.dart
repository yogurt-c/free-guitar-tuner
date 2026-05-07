import 'dart:async';
import 'dart:io';

import 'package:google_mobile_ads/google_mobile_ads.dart';

class AdService {
  InterstitialAd? _ad;
  Completer<void>? _loadCompleter;

  static String get _adUnitId => Platform.isAndroid
      ? const String.fromEnvironment('ADMOB_ANDROID_UNIT_ID')
      : const String.fromEnvironment('ADMOB_IOS_UNIT_ID');

  void load() {
    _loadCompleter = Completer<void>();
    InterstitialAd.load(
      adUnitId: _adUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _ad = ad;
          _loadCompleter?.complete();
        },
        onAdFailedToLoad: (_) {
          _loadCompleter?.complete();
        },
      ),
    );
  }

  Future<bool> show() async {
    final completer = _loadCompleter;
    if (completer != null && !completer.isCompleted) {
      await completer.future;
    }
    if (_ad == null) return false;

    _ad!.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _ad = null;
      },
      onAdFailedToShowFullScreenContent: (ad, _) {
        ad.dispose();
        _ad = null;
      },
    );
    _ad!.show();
    return true;
  }
}
