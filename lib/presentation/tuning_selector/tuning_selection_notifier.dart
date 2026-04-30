import 'dart:async';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/analyzer/note_analyzer.dart';
import '../../domain/model/tuning_preset.dart';
import '../metronome/metronome_notifier.dart';
import '../tuner/tuner_notifier.dart';

enum AppMode { tuner, metronome }

// main()에서 overrideWithValue로 실제 초기값 주입
final initialThemeDarkProvider = Provider<bool>((_) => true);

class TuningSelectionState {
  final String presetKey;
  final int selectedString;
  final bool autoDetect;
  final Set<int> tunedStrings;
  final bool isDark;
  final AppMode mode;

  const TuningSelectionState({
    required this.presetKey,
    required this.selectedString,
    required this.autoDetect,
    required this.tunedStrings,
    required this.isDark,
    required this.mode,
  });

  factory TuningSelectionState.initial({required bool isDark}) =>
      TuningSelectionState(
        presetKey: 'standard',
        selectedString: 0,
        autoDetect: false,
        tunedStrings: const {},
        isDark: isDark,
        mode: AppMode.tuner,
      );

  TuningSelectionState copyWith({
    String? presetKey,
    int? selectedString,
    bool? autoDetect,
    Set<int>? tunedStrings,
    bool? isDark,
    AppMode? mode,
  }) =>
      TuningSelectionState(
        presetKey: presetKey ?? this.presetKey,
        selectedString: selectedString ?? this.selectedString,
        autoDetect: autoDetect ?? this.autoDetect,
        tunedStrings: tunedStrings ?? this.tunedStrings,
        isDark: isDark ?? this.isDark,
        mode: mode ?? this.mode,
      );
}

class TuningSelectionNotifier extends Notifier<TuningSelectionState> {
  static const _autoDetectMaxCents = 200.0;

  @override
  TuningSelectionState build() {
    Timer? inTuneTimer;

    ref.listen<TunerState>(tunerProvider, (_, next) {
      if (state.mode != AppMode.tuner) {
        inTuneTimer?.cancel();
        inTuneTimer = null;
        return;
      }

      final tuneResult = next.tuneResult;

      if (tuneResult == null) {
        inTuneTimer?.cancel();
        inTuneTimer = null;
        return;
      }

      if (state.autoDetect && next.detectedFreq != null) {
        _autoDetectString(next.detectedFreq!);
      }

      if (tuneResult.state == TuneState.inTune) {
        inTuneTimer ??= Timer(const Duration(milliseconds: 500), () {
          if (state.mode != AppMode.tuner) {
            inTuneTimer = null;
            return;
          }
          final alreadyTuned = state.tunedStrings.contains(state.selectedString);
          state = state.copyWith(
            tunedStrings: {...state.tunedStrings, state.selectedString},
          );
          if (!alreadyTuned) HapticFeedback.mediumImpact();
          inTuneTimer = null;
        });
      } else {
        inTuneTimer?.cancel();
        inTuneTimer = null;
      }
    });

    ref.onDispose(() => inTuneTimer?.cancel());

    return TuningSelectionState.initial(isDark: ref.read(initialThemeDarkProvider));
  }

  void selectPreset(String key) {
    state = TuningSelectionState(
      presetKey: key,
      selectedString: 0,
      autoDetect: state.autoDetect,
      tunedStrings: const {},
      isDark: state.isDark,
      mode: state.mode,
    );
  }

  void selectString(int index) {
    state = state.copyWith(selectedString: index);
  }

  void toggleAutoDetect() {
    state = state.copyWith(autoDetect: !state.autoDetect);
  }

  void toggleDark() {
    final newValue = !state.isDark;
    SharedPreferences.getInstance()
        .then((p) => p.setBool('theme_is_dark', newValue));
    state = state.copyWith(isDark: newValue);
  }

  void switchMode(AppMode mode) {
    if (state.mode == AppMode.metronome) {
      ref.read(metronomeProvider.notifier).stop();
    }
    state = state.copyWith(mode: mode);
  }

  void _autoDetectString(double detectedFreq) {
    final preset = tuningPresets[state.presetKey]!;
    int? bestIdx;
    var bestCentsAbs = double.infinity;

    for (var i = 0; i < preset.strings.length; i++) {
      final centsAbs =
          (1200 * log(detectedFreq / preset.strings[i].freq) / ln2).abs();
      if (centsAbs < bestCentsAbs) {
        bestCentsAbs = centsAbs;
        bestIdx = i;
      }
    }

    if (bestIdx != null &&
        bestCentsAbs < _autoDetectMaxCents &&
        bestIdx != state.selectedString) {
      state = state.copyWith(selectedString: bestIdx);
    }
  }
}

final tuningSelectionProvider =
    NotifierProvider<TuningSelectionNotifier, TuningSelectionState>(
  TuningSelectionNotifier.new,
);
