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
  static const _noteNames = [
    'C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B',
  ];
  static const _a4Midi = 69;
  static const _a4Freq = 440.0;

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

  // 감지된 주파수에서 가장 가까운 12음 평균율 음을 찾고 cents 편차를 계산한다.
  static TuneResult analyzeFrequency(double detectedFreq) {
    final n = 12 * log(detectedFreq / _a4Freq) / ln2;
    final midiOffset = n.round();
    final midi = _a4Midi + midiOffset;
    final targetFreq = _a4Freq * pow(2, midiOffset / 12.0);
    final cents = (n - midiOffset) * 100;
    final noteIndex = midi % 12;
    final octave = midi ~/ 12 - 1;
    return TuneResult(
      noteName: _noteNames[noteIndex],
      octave: octave,
      targetFreq: targetFreq.toDouble(),
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
