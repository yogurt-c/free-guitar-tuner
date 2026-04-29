import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/audio_pipeline.dart';
import '../../domain/analyzer/note_analyzer.dart';
import '../../domain/model/tuning_preset.dart';
import '../tuning_selector/tuning_selection_notifier.dart';

class TunerState {
  final double? detectedFreq;
  final TuneResult? tuneResult;
  final double signalLevel;

  const TunerState({
    this.detectedFreq,
    this.tuneResult,
    this.signalLevel = 0.0,
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
      await _pipeline.start();
      _subscription = _pipeline.pitchStream.listen(_onPitchResult);
    });

    ref.onDispose(() async {
      await _subscription?.cancel();
      await _pipeline.dispose();
    });

    return const TunerState();
  }

  void _onPitchResult(PitchResult result) {
    if (result.signalLevel < _noiseGateThreshold || result.freq == null) {
      state = TunerState(signalLevel: result.signalLevel);
      return;
    }

    final selection = ref.read(tuningSelectionProvider);
    final preset = tuningPresets[selection.presetKey]!;
    final targetNote = preset.strings[selection.selectedString];
    final tuneResult = NoteAnalyzer.analyzeAgainstTarget(result.freq!, targetNote);

    state = TunerState(
      detectedFreq: result.freq,
      tuneResult: tuneResult,
      signalLevel: result.signalLevel,
    );
  }
}

final tunerProvider = NotifierProvider<TunerNotifier, TunerState>(
  TunerNotifier.new,
);
