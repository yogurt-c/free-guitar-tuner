import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:guitar_tuner/data/pitch_detector.dart';

List<double> _sine(double freq, {int samples = 2048, int sampleRate = 44100}) {
  return List<double>.generate(
    samples,
    (i) => sin(2 * pi * freq * i / sampleRate),
  );
}

void main() {
  final detector = PitchDetector();

  group('PitchDetector', () {
    test('E2 (82.41 Hz) 검출', () async {
      final result = await detector.detect(_sine(82.41));
      expect(result, isNotNull);
      expect(result!, closeTo(82.41, 1.0));
    });

    test('A4 (440 Hz) 검출', () async {
      final result = await detector.detect(_sine(440.0));
      expect(result, isNotNull);
      expect(result!, closeTo(440.0, 2.0));
    });

    test('E4 (329.63 Hz) 검출', () async {
      final result = await detector.detect(_sine(329.63));
      expect(result, isNotNull);
      expect(result!, closeTo(329.63, 2.0));
    });

    test('묵음(0) 신호는 null 반환', () async {
      final silence = List<double>.filled(2048, 0.0);
      final result = await detector.detect(silence);
      expect(result, isNull);
    });

    test('범위 밖 주파수(50 Hz)는 null 반환', () async {
      final result = await detector.detect(_sine(50.0));
      expect(result, isNull);
    });

    test('범위 밖 주파수(2000 Hz)는 null 반환', () async {
      final result = await detector.detect(_sine(2000.0));
      expect(result, isNull);
    });
  });
}
