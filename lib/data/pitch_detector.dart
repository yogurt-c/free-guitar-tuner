import 'package:flutter/foundation.dart';

typedef _YinArgs = ({List<double> samples, int sampleRate});

class PitchDetector {
  static const _sampleRate = 44100;
  static const _threshold = 0.1;
  static const _minFreq = 70.0;   // E2 아래
  static const _maxFreq = 1400.0; // 1번현 상한

  Future<double?> detect(List<double> samples) {
    return compute(_runYin, (samples: samples, sampleRate: _sampleRate));
  }

  static double? _runYin(_YinArgs args) =>
      _yin(args.samples, args.sampleRate);

  static double? _yin(List<double> samples, int sampleRate) {
    final halfN = samples.length ~/ 2;
    final diff = List<double>.filled(halfN, 0.0);

    // Step 1: Difference function
    for (var tau = 1; tau < halfN; tau++) {
      for (var j = 0; j < halfN; j++) {
        final delta = samples[j] - samples[j + tau];
        diff[tau] += delta * delta;
      }
    }

    // Step 2: Cumulative mean normalized difference function (CMNDF)
    final cmndf = List<double>.filled(halfN, 0.0);
    cmndf[0] = 1.0;
    double runningSum = 0.0;
    for (var tau = 1; tau < halfN; tau++) {
      runningSum += diff[tau];
      cmndf[tau] = runningSum > 0 ? diff[tau] * tau / runningSum : 1.0;
    }

    // Step 3: Absolute threshold — 임계값 이하 첫 번째 로컬 최솟값
    int? tauEstimate;
    for (var tau = 2; tau < halfN - 1; tau++) {
      if (cmndf[tau] < _threshold) {
        while (tau + 1 < halfN - 1 && cmndf[tau + 1] < cmndf[tau]) {
          tau++;
        }
        tauEstimate = tau;
        break;
      }
    }
    if (tauEstimate == null) return null;

    // Step 4: 포물선 보간으로 서브샘플 정밀도 확보
    final betterTau = _parabolicInterpolation(cmndf, tauEstimate);
    if (betterTau <= 0) return null;

    final freq = sampleRate / betterTau;
    if (freq < _minFreq || freq > _maxFreq) return null;
    return freq;
  }

  static double _parabolicInterpolation(List<double> array, int x) {
    if (x <= 0 || x >= array.length - 1) return x.toDouble();
    final denom = 2.0 * (2 * array[x] - array[x - 1] - array[x + 1]);
    if (denom == 0) return x.toDouble();
    return x + (array[x - 1] - array[x + 1]) / denom;
  }
}
