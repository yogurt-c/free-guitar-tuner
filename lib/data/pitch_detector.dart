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
    final tauEstimateOpt = _findFirstDip(cmndf, tauMin, tauMax, _threshold)
        ?? _findFirstDip(cmndf, tauMin, tauMax, _thresholdRelaxed)
        ?? _findFirstDip(cmndf, tauMin, tauMax, _thresholdFallback);
    if (tauEstimateOpt == null) return null;
    var tauEstimate = tauEstimateOpt; // non-nullable int, 루프에서 재할당 가능

    // Octave correction (반복 적용):
    // first-dip이 2배음·4배음 tau를 기음보다 먼저 발견하는 경우를 교정한다.
    // 예) E2(82 Hz, tau=535)가 2배음(164 Hz, tau=268)으로 오탐.
    //
    // 창 크기 ±25:
    //   first-dip 슬라이딩 후 tauEstimate가 이론값(268)에서 최대 ±12 벗어날 수 있다.
    //   octaveTau = 2 * tauEstimate → 최대 ±24 오차 → ±25 창으로 tau=535 포함 보장.
    //   진단 근거: CMNDF[535]/CMNDF[268] ≈ 0.00인 49개 E2 실패 청크 확인.
    //
    // Octave correction 조건 (둘 중 하나 충족 시 교정 허용):
    //   c0 > 0.001: CMNDF ≈ 0 완벽 감지(순수 사인파)에서 ratio가 부정확해지는 구간 차단.
    //   [경로 A] tauEstimate < tauMin * 4 (감지 주파수 > maxFreq/4 ≈ 350 Hz):
    //     표준 기타 최고음 E4 ≈ 330 Hz 기음은 tau ≥ 134이므로, tau < 128인 감지는
    //     반드시 배음(harmonic)이다. G3 2배음(tau=113, 392 Hz)이 여기에 해당.
    //     E4 정탐(tau=134 ≥ 128): 경로 A에서 제외 → 오탐 방지.
    //   [경로 B] octaveTau > tauMax/2 (교정 목표 주파수 < 140 Hz):
    //     E2 오탐(tau=268→536): octaveTau=536 > 315 → 경로 B 허용.
    //   ratio < 0.75: octaveMin이 c0의 75% 미만일 때만 교정.
    //     진단 근거: G3 오탐 청크 ratio=0.016–0.233, G3/D3 정탐 안전 확인.
    var improved = true;
    while (improved) {
      improved = false;
      final c0 = cmndf[tauEstimate];
      final octaveTau = tauEstimate * 2;
      final inHighHarmonicZone = tauEstimate < tauMin * 4; // 경로 A
      final inLowFreqZone = octaveTau > tauMax ~/ 2; // 경로 B
      if (c0 > 0.001 && octaveTau <= tauMax && (inHighHarmonicZone || inLowFreqZone)) {
        var octaveMin = 1.0;
        for (var t = max(tauMin, octaveTau - 25);
            t <= min(tauMax, octaveTau + 25);
            t++) {
          if (t < cmndf.length && cmndf[t] < octaveMin) octaveMin = cmndf[t];
        }
        if (octaveMin < c0 * 0.75) {
          tauEstimate = octaveTau;
          improved = true;
        }
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
