import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/ads/ad_service.dart';

final adServiceProvider = Provider<AdService>((ref) => AdService());

final adNotifierProvider = NotifierProvider<AdNotifier, bool>(AdNotifier.new);

class AdNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  Future<void> showOnce() async {
    if (state) return;
    final shown = await ref.read(adServiceProvider).show();
    if (shown) state = true;
  }
}
