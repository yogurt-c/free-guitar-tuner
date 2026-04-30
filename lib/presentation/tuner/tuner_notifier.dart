import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/audio_capture.dart';
import '../../data/audio_pipeline.dart';
import '../../domain/analyzer/note_analyzer.dart';
import '../../domain/model/tuning_preset.dart';
import '../tuning_selector/tuning_selection_notifier.dart';

class TunerState {
  final TuneResult? tuneResult;
  final double signalLevel;
  final bool permissionDenied;

  const TunerState({
    this.tuneResult,
    this.signalLevel = 0.0,
    this.permissionDenied = false,
  });
}

class TunerNotifier extends Notifier<TunerState> {
  static const _noiseGateThreshold = 0.01;

  late final AudioPipeline _pipeline;
  StreamSubscription<PitchResult>? _subscription;

  @override
  TunerState build() {
    _pipeline = AudioPipeline();

    Future.microtask(() async {
      try {
        await _pipeline.start();
        _subscription = _pipeline.pitchStream.listen(_onPitchResult);
      } on MicrophonePermissionException {
        state = const TunerState(permissionDenied: true);
      } catch (e) {
        debugPrint('[TunerNotifier] audio init failed: $e');
      }
    });

    ref.onDispose(() async {
      await _subscription?.cancel();
      await _pipeline.dispose();
    });

    return const TunerState();
  }

  void _onPitchResult(PitchResult result) {
    final selectionNotifier = ref.read(tuningSelectionProvider.notifier);

    if (result.signalLevel < _noiseGateThreshold || result.freq == null) {
      state = TunerState(signalLevel: result.signalLevel);
      selectionNotifier.onTunerUpdate(tuneResult: null);
      return;
    }

    final selection = ref.read(tuningSelectionProvider);
    final preset = tuningPresets[selection.presetKey]!;
    final targetNote = preset.strings[selection.selectedString];
    final tuneResult = NoteAnalyzer.analyzeAgainstTarget(result.freq!, targetNote);

    state = TunerState(
      tuneResult: tuneResult,
      signalLevel: result.signalLevel,
    );
    selectionNotifier.onTunerUpdate(tuneResult: tuneResult);
  }
}

final tunerProvider = NotifierProvider<TunerNotifier, TunerState>(
  TunerNotifier.new,
);
