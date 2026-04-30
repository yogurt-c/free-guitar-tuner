import 'dart:math';

import '../model/note.dart';

enum TuneState { flat, inTune, sharp }

class TuneResult {
  final String noteName;
  final int octave;
  final double targetFreq;
  final double detectedFreq;
  final double cents;
  final TuneState state;

  const TuneResult({
    required this.noteName,
    required this.octave,
    required this.targetFreq,
    required this.detectedFreq,
    required this.cents,
    required this.state,
  });

  String get displayNoteName => '$noteName$octave';
}

class NoteAnalyzer {
  // 감지된 주파수를 특정 타겟 음과 비교해 cents 편차를 계산한다.
  static TuneResult analyzeAgainstTarget(double detectedFreq, Note target) {
    final cents = 1200 * log(detectedFreq / target.freq) / ln2;
    return TuneResult(
      noteName: target.name,
      octave: target.octave,
      targetFreq: target.freq,
      detectedFreq: detectedFreq,
      cents: cents,
      state: _tuneState(cents),
    );
  }

  static TuneState _tuneState(double cents) {
    if (cents.abs() < 3) return TuneState.inTune;
    return cents < 0 ? TuneState.flat : TuneState.sharp;
  }
}
