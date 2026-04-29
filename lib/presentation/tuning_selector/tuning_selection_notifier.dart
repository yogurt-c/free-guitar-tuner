import 'dart:async';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/analyzer/note_analyzer.dart';
import '../../domain/model/tuning_preset.dart';
import '../metronome/metronome_notifier.dart';
import '../tuner/tuner_notifier.dart';

enum AppMode { tuner, metronome }

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

  factory TuningSelectionState.initial() => const TuningSelectionState(
        presetKey: 'standard',
        selectedString: 0,
        autoDetect: false,
        tunedStrings: {},
        isDark: true,
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

    return TuningSelectionState.initial();
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
    state = state.copyWith(isDark: !state.isDark);
  }

  void switchMode(AppMode mode) {
    if (mode == AppMode.tuner) {
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
