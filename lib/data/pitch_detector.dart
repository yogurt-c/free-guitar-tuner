import 'dart:math';

import 'package:flutter/foundation.dart';

typedef _YinArgs = ({
  List<double> samples,
  int sampleRate,
  List<double> candidates,
});

/// 다중 후보 기반 YIN 피치 감지기.
///
/// 사용자가 튜닝하려는 후보 주파수 목록(현 1개 또는 preset 전체)을 받아,
/// **각 후보의 ±반옥타브 윈도우를 합집합**으로 묶은 tau 영역에서만 검색한다.
///
/// 검색 방식은 표준 YIN 의 first-dip:
///   가장 짧은 tau 부터 스캔하며 CMNDF 가 임계값(0.15→0.25→0.40 캐스케이드)
///   미만으로 떨어지는 첫 지역 최솟값을 fundamental 로 간주.
///
/// 이렇게 하면:
/// 1. 윈도우 합집합 밖(예: 70 Hz 미만, 거의 1.4 kHz 이상)은 검색하지 않아
///    노이즈/배음 오탐을 차단.
/// 2. first-dip 원리에 의해 fundamental 의 정수배 tau (2T, 3T...) 인 sub-harmonic
///    dip 은 무시되므로 옥타브-다운 오탐(-1200 cents)이 발생하지 않는다.
class PitchDetector {
  static const _sampleRate = 44100;

  /// 후보 윈도우 반폭 = √2 (±반옥타브, ±600 cents).
  static final double _windowFactor = sqrt2;

  /// CMNDF 임계값 캐스케이드.
  /// 0.15 (표준) → 0.25 (완화) → 0.40 (pYIN 한계).
  static const _thresholds = <double>[0.15, 0.25, 0.40];

  /// 감지 실행. [candidates]는 비어 있으면 안 된다.
  ///
  /// - 수동 모드: 선택된 현 1개의 주파수만 전달
  /// - 자동 감지 모드: preset 의 모든 현 주파수 전달
  Future<double?> detect(
    List<double> samples, {
    required List<double> candidates,
    int sampleRate = _sampleRate,
  }) {
    assert(candidates.isNotEmpty, 'candidates must not be empty');
    return compute(_runYin, (
      samples: samples,
      sampleRate: sampleRate,
      candidates: candidates,
    ));
  }

  static double? _runYin(_YinArgs args) =>
      _yin(args.samples, args.sampleRate, args.candidates);

  static double? _yin(
      List<double> samples, int sampleRate, List<double> candidates) {
    final halfN = samples.length ~/ 2;

    // Step 1: Difference function
    final diff = List<double>.filled(halfN, 0.0);
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

    // Step 3: 후보 윈도우 합집합 계산.
    // 각 후보 [target/√2, target×√2] tau 범위를 합집합으로.
    final allowed = List<bool>.filled(halfN, false);
    var unionLo = halfN;
    var unionHi = 0;
    for (final target in candidates) {
      final lo = max(2, (sampleRate / (target * _windowFactor)).ceil());
      final hi =
          min(halfN - 2, (sampleRate / (target / _windowFactor)).floor());
      if (lo > hi) continue;
      for (var t = lo; t <= hi; t++) {
        allowed[t] = true;
      }
      if (lo < unionLo) unionLo = lo;
      if (hi > unionHi) unionHi = hi;
    }
    if (unionLo > unionHi) return null;

    // Step 4: 합집합 안에서 first-dip 검색 (가장 짧은 tau 우선).
    int? bestTau;
    for (final threshold in _thresholds) {
      bestTau = _findFirstDip(cmndf, unionLo, unionHi, threshold, allowed);
      if (bestTau != null) break;
    }
    if (bestTau == null) return null;

    // Step 5: 약한 fundamental 보정.
    //
    // 어쿠스틱 기타 저음현(E2 등)은 2배음이 fundamental보다 강한 경우가 흔해서
    // first-dip 이 2배음 tau 를 잡을 수 있다. 이 케이스만 골라 보정한다.
    //
    // 트리거 조건 (둘 다 만족):
    //   ① first-dip 이 어느 후보 nominal 과도 ±100 cents 이상 떨어져 있다
    //      → 윈도우 가장자리에 있는 dip = 그 후보의 fundamental 이 아닐 가능성
    //   ② octaveTau (= 2 × bestTau) 의 CMNDF 가 bestTau 의 70% 미만으로 더 깊다
    //      → 진짜 fundamental 의 증거 (노이즈 환경에서도 견디도록 완화)
    //
    // G3/D3/B3 등 fundamental 이 정확히 잡힌 경우는 ①을 위반해 trigger 자체가 안 됨.
    // 이로써 옛 알고리즘의 −1200 cents 옥타브 다운 오발동을 구조적으로 차단.
    final detectedFreq = sampleRate / bestTau.toDouble();
    var minCentsAbs = double.infinity;
    for (final target in candidates) {
      final c = (1200 * log(detectedFreq / target) / ln2).abs();
      if (c < minCentsAbs) minCentsAbs = c;
    }

    if (minCentsAbs > 100) {
      final octaveTau = bestTau * 2;
      if (octaveTau <= unionHi && allowed[octaveTau]) {
        var octaveMin = cmndf[octaveTau];
        var octaveMinTau = octaveTau;
        final lo = max(0, octaveTau - 5);
        final hi = min(halfN - 1, octaveTau + 5);
        for (var t = lo; t <= hi; t++) {
          if (allowed[t] && cmndf[t] < octaveMin) {
            octaveMin = cmndf[t];
            octaveMinTau = t;
          }
        }
        if (octaveMin < cmndf[bestTau] * 0.7) {
          bestTau = octaveMinTau;
        }
      }
    }

    // Step 6: 포물선 보간으로 서브샘플 정밀도 확보
    final betterTau = _parabolicInterpolation(cmndf, bestTau);
    if (betterTau <= 0) return null;

    return sampleRate / betterTau;
  }

  /// [unionLo..unionHi] 범위에서 [allowed] 가 true 인 tau 들 중,
  /// CMNDF 가 [threshold] 미만으로 처음 떨어지는 지점을 찾고
  /// 그 dip 의 지역 최솟값까지 descend 한 tau 를 반환한다.
  static int? _findFirstDip(
    List<double> cmndf,
    int unionLo,
    int unionHi,
    double threshold,
    List<bool> allowed,
  ) {
    for (var tau = unionLo + 1; tau <= unionHi; tau++) {
      if (!allowed[tau]) continue;
      if (cmndf[tau] < threshold) {
        // 같은 dip 의 바닥까지 descend (allowed 범위 안에서만)
        while (tau + 1 <= unionHi &&
            allowed[tau + 1] &&
            cmndf[tau + 1] < cmndf[tau]) {
          tau++;
        }
        return tau;
      }
    }
    return null;
  }

  /// 이산 최솟값 [x] 주위 3점으로 포물선 적합해 서브샘플 정밀도 tau 반환.
  ///
  /// 표준 공식:  t* = x + (y[x-1] - y[x+1]) / (2·(y[x-1] - 2·y[x] + y[x+1]))
  /// (분모는 second difference, 최솟값에서 양수)
  static double _parabolicInterpolation(List<double> array, int x) {
    if (x <= 0 || x >= array.length - 1) return x.toDouble();
    final denom = 2.0 * (array[x - 1] - 2 * array[x] + array[x + 1]);
    if (denom == 0) return x.toDouble();
    return x + (array[x - 1] - array[x + 1]) / denom;
  }
}
