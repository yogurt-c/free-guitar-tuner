import 'dart:math';

import 'package:flutter/foundation.dart';

typedef _YinArgs = ({List<double> samples, int sampleRate});

class PitchDetector {
  static const _sampleRate = 44100;
  static const _threshold = 0.15;
  static const _thresholdRelaxed = 0.25;
  static const _thresholdFallback = 0.40;
  static const _minFreq = 70.0;
  static const _maxFreq = 1400.0;

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

    // Step 3: threshold 미만의 첫 번째 지역 최솟값 선택 (YIN 논문 표준).
    // 기음은 가장 짧은 유효 주기(가장 작은 tau)이므로, threshold 이하 dip이
    // 처음 등장하는 지점이 기음에 해당한다. 전역 최솟값 방식은 sub-harmonic
    // (tau의 배수) 최솟값이 더 낮을 때 한 옥타브 낮은 주파수로 튀는 불안정성이 있다.
    final tauMin = max(2, (sampleRate / _maxFreq).ceil());
    final tauMax = min(halfN - 2, (sampleRate / _minFreq).floor());

    // 각 패스는 "첫 번째 지역 최솟값(first-dip)" 방식을 사용한다.
    // 전역 최솟값 방식은 sub-harmonic(기음의 정수배 tau)이 더 낮을 때 옥타브 에러를 유발한다.
    // first-dip은 항상 가장 짧은 유효 주기(= 기음)를 선택하므로 옥타브 안전하다.
    // 3차 패스(0.40)는 pYIN 논문의 신뢰 한계값으로, 이를 초과하면 소음으로 간주한다.
    var tauEstimate = _findFirstDip(cmndf, tauMin, tauMax, _threshold)
        ?? _findFirstDip(cmndf, tauMin, tauMax, _thresholdRelaxed)
        ?? _findFirstDip(cmndf, tauMin, tauMax, _thresholdFallback);
    if (tauEstimate == null) return null;

    // Octave correction: first-dip은 2배음 tau를 기음보다 먼저 발견할 수 있다.
    // 예) E2(82 Hz, tau=535)를 강한 2배음(164 Hz, tau=268)으로 잘못 감지.
    //
    // 조건: CMNDF(2*tau) < CMNDF(tau) * 0.1 (10배 이상 개선될 때만 교정)
    // - E2 오탐 시: CMNDF[535]/CMNDF[268] ≈ 0.003 → 교정 발동 ✓
    // - E4 정탐 시: 두 값 모두 낮고 차이가 작음 → 교정 미발동 ✓
    // ±5 window 없이 정확한 tau 값만 비교해 우발적 dip 회피.
    // Octave correction 조건:
    // 1. c0 > 0.003: 순수 사인파처럼 CMNDF가 0에 근접한 "완벽한" 감지는 보정 불필요.
    //    순수 사인파에서는 c0와 octaveMin 모두 0에 가까워 ratio가 우발적으로 작아질 수 있다.
    // 2. ratio < 0.5: E4(min ratio=0.523), B3(0.753), D3(0.720)는 안전.
    //    E2/G3 옥타브 오탐 시 ratio는 0.001~0.5 범위 → 교정 발동.
    final c0 = cmndf[tauEstimate];
    final octaveTau = tauEstimate * 2;
    if (c0 > 0.003 && octaveTau <= tauMax) {
      var octaveMin = 1.0;
      for (var t = max(tauMin, octaveTau - 3);
          t <= min(tauMax, octaveTau + 3);
          t++) {
        if (t < cmndf.length && cmndf[t] < octaveMin) octaveMin = cmndf[t];
      }
      if (octaveMin < c0 * 0.5) {
        tauEstimate = octaveTau;
      }
    }

    // Step 4: 포물선 보간으로 서브샘플 정밀도 확보
    final betterTau = _parabolicInterpolation(cmndf, tauEstimate);
    if (betterTau <= 0) return null;

    final freq = sampleRate / betterTau;
    if (freq < _minFreq || freq > _maxFreq) return null;
    return freq;
  }

  /// [tau] 인근 ±5 범위에서 CMNDF 지역 최솟값을 반환한다.
  static double _localMin(List<double> cmndf, int tau, int tauMax) {
    var m = cmndf[tau.clamp(0, cmndf.length - 1)];
    for (var t = max(0, tau - 5); t <= min(tauMax, tau + 5); t++) {
      if (t < cmndf.length && cmndf[t] < m) m = cmndf[t];
    }
    return m;
  }

  static int? _findFirstDip(
      List<double> cmndf, int tauMin, int tauMax, double threshold) {
    for (var tau = tauMin + 1; tau < tauMax; tau++) {
      if (cmndf[tau] < threshold) {
        while (tau + 1 < tauMax && cmndf[tau + 1] < cmndf[tau]) {
          tau++;
        }
        return tau;
      }
    }
    return null;
  }

  static double _parabolicInterpolation(List<double> array, int x) {
    if (x <= 0 || x >= array.length - 1) return x.toDouble();
    final denom = 2.0 * (2 * array[x] - array[x - 1] - array[x + 1]);
    if (denom == 0) return x.toDouble();
    return x + (array[x - 1] - array[x + 1]) / denom;
  }
}
