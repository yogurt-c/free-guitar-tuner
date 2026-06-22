import 'dart:io';
import 'dart:ui';

import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/ads/ad_service.dart';
import 'presentation/ads/ad_notifier.dart';
import 'presentation/home_shell.dart';
import 'presentation/tuning_selector/tuning_selection_notifier.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Colors.transparent,
  ));

  final prefs = await SharedPreferences.getInstance();
  final savedDark = prefs.getBool('theme_is_dark');
  final isDark = savedDark ??
      (PlatformDispatcher.instance.platformBrightness == Brightness.dark);

  if (Platform.isIOS) {
    await AppTrackingTransparency.requestTrackingAuthorization();
  }

  await MobileAds.instance.initialize();

  final adService = AdService();
  adService.load();

  runApp(ProviderScope(
    overrides: [
      initialThemeDarkProvider.overrideWithValue(isDark),
      adServiceProvider.overrideWithValue(adService),
    ],
    child: const GuitarTunerApp(),
  ));
}

class GuitarTunerApp extends StatelessWidget {
  const GuitarTunerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'Guitar Tuner',
      debugShowCheckedModeBanner: false,
      home: HomeShell(),
    );
  }
}
