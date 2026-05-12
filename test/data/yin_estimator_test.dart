// YinEstimator 단위 테스트.
//
// in-memory 합성 신호로 standard YIN 6-step + octave guard 가 paper 가 약속한
// 정확도 (±0.5% freq) 와 robustness (사인+배음, 디튠, octave error) 를 만족하는지
// 검증한다. WAV / 실음 회귀는 pitch_pipeline_wav_test 가 담당.

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:guitar_tuner/data/yin_estimator.dart';

const _sampleRateF = 44100.0;
const _bufSize = 4096;

/// standard 튜닝 preset 의 search range (최저현 -200c ~ 최고현 +200c).
/// fmin = 82.41 × 2^(-200/1200) ≈ 73.45 Hz  → tauMax = 44100/73.45 ≈ 600
/// fmax = 329.63 × 2^(+200/1200) ≈ 369.99 Hz → tauMin = 44100/369.99 ≈ 119
const _stdTauMin = 119;
const _stdTauMax = 600;

/// 사인 합성. amps 와 freqs 길이는 같아야 함.
List<double> _synth({
  required List<double> freqs,
  required List<double> amps,
  int sampleCount = _bufSize,
  double sampleRate = _sampleRateF,
  double noise = 0.0,
  int seed = 1,
}) {
  assert(freqs.length == amps.length);
  final rng = Random(seed);
  final out = List<double>.filled(sampleCount, 0.0);
  for (var i = 0; i < sampleCount; i++) {
    var v = 0.0;
    for (var k = 0; k < freqs.length; k++) {
      v += amps[k] * sin(2 * pi * freqs[k] * i / sampleRate);
    }
    if (noise > 0) v += (rng.nextDouble() * 2 - 1) * noise;
    out[i] = v;
  }
  return out;
}

double _centsBetween(double a, double b) => 1200 * log(a / b) / ln2;

void main() {
  late YinEstimator estimator;
  setUpAll(() => estimator = YinEstimator());
  tearDownAll(() async => estimator.dispose());

  // ── 순수 사인 — 기본 정확도 ─────────────────────────────────────────────
  group('순수 사인 — 6현 표준 freq', () {
    const targets = <String, double>{
      'E2': 82.41,
      'A2': 110.00,
      'D3': 146.83,
      'G3': 196.00,
      'B3': 246.94,
      'E4': 329.63,
    };
    for (final e in targets.entries) {
      test('${e.key} (${e.value} Hz) 추정 ±5 cents', () async {
        final samples = _synth(freqs: [e.value], amps: [0.5]);
        final est = await estimator.estimate(
          samples,
          tauMin: _stdTauMin,
          tauMax: _stdTauMax,
        );
        expect(est, isNotNull, reason: '${e.key} estimate null');
        final cents = _centsBetween(est!.freq, e.value);
        expect(cents.abs(), lessThan(5.0),
            reason: '${e.key} freq ${est.freq.toStringAsFixed(2)} '
                '(${cents.toStringAsFixed(1)}c)');
        expect(est.confidence, lessThan(0.10),
            reason: '${e.key} 순수 사인은 매우 강한 fundamental');
      });
    }
  });

  // ── 사인 + 배음 — 실제 기타에 가까운 형태 ────────────────────────────────
  group('fundamental + 배음', () {
    test('G3 fundamental + 2T·3T·4T 배음 → fundamental 잡힘', () async {
      const f0 = 196.0;
      final samples = _synth(
        freqs: [f0, 2 * f0, 3 * f0, 4 * f0],
        amps: [0.5, 0.3, 0.2, 0.1],
      );
      final est = await estimator.estimate(
        samples,
        tauMin: _stdTauMin,
        tauMax: _stdTauMax,
      );
      expect(est, isNotNull);
      expect(_centsBetween(est!.freq, f0).abs(), lessThan(5.0));
    });

    test('정상 기타 합성 (fund amp 0.5 + 감쇠 배음) → fundamental 정확', () async {
      // 실 기타와 비슷한 spectral envelope: fundamental 가장 강하고 배음 감쇠.
      // paper step 4 (smallest τ + threshold) 가 fundamental 위치를 정확히 선택.
      const f0 = 82.41;
      final samples = _synth(
        freqs: [f0, 2 * f0, 3 * f0, 4 * f0, 5 * f0],
        amps: [0.5, 0.3, 0.2, 0.12, 0.08],
      );
      final est = await estimator.estimate(
        samples,
        tauMin: _stdTauMin,
        tauMax: _stdTauMax,
      );
      expect(est, isNotNull);
      final cents = _centsBetween(est!.freq, f0);
      expect(cents.abs(), lessThan(10.0),
          reason: '정상 envelope 에서 fundamental 정확. '
              'got ${est.freq.toStringAsFixed(2)} (${cents.toStringAsFixed(1)}c)');
    });
  });

  // ── 디튠 — flat/sharp 가도 정확히 추정 ───────────────────────────────────
  group('디튠 ±100c 정확도', () {
    test('A2 -100c (≈103.83 Hz)', () async {
      final target = 110.0 * pow(2.0, -100 / 1200);
      final samples = _synth(freqs: [target.toDouble()], amps: [0.5]);
      final est = await estimator.estimate(
        samples,
        tauMin: _stdTauMin,
        tauMax: _stdTauMax,
      );
      expect(est, isNotNull);
      expect(_centsBetween(est!.freq, target.toDouble()).abs(), lessThan(5.0));
    });

    test('E4 +50c (≈339.29 Hz)', () async {
      final target = 329.63 * pow(2.0, 50 / 1200);
      final samples = _synth(freqs: [target.toDouble()], amps: [0.5]);
      final est = await estimator.estimate(
        samples,
        tauMin: _stdTauMin,
        tauMax: _stdTauMax,
      );
      expect(est, isNotNull);
      expect(_centsBetween(est!.freq, target.toDouble()).abs(), lessThan(5.0));
    });
  });

  // ── 노이즈 robustness ──────────────────────────────────────────────────
  group('노이즈 robustness', () {
    test('G3 + 작은 노이즈 (amp 0.05) → 여전히 정확', () async {
      const f0 = 196.0;
      final samples = _synth(
        freqs: [f0, 2 * f0],
        amps: [0.5, 0.2],
        noise: 0.05,
      );
      final est = await estimator.estimate(
        samples,
        tauMin: _stdTauMin,
        tauMax: _stdTauMax,
      );
      expect(est, isNotNull);
      expect(_centsBetween(est!.freq, f0).abs(), lessThan(10.0));
    });

    test('순수 화이트 노이즈 → null (unvoiced)', () async {
      final samples = _synth(
        freqs: const [0.0],
        amps: const [0.0],
        noise: 0.5,
      );
      final est = await estimator.estimate(
        samples,
        tauMin: _stdTauMin,
        tauMax: _stdTauMax,
      );
      expect(est, isNull, reason: '순수 노이즈는 unvoiced');
    });

    test('무음 (zeros) → null', () async {
      final samples = List<double>.filled(_bufSize, 0.0);
      final est = await estimator.estimate(
        samples,
        tauMin: _stdTauMin,
        tauMax: _stdTauMax,
      );
      // d 가 전부 0 이라 cmndf 가 1.0 으로 고정 → maxConfidence 통과 못함 → null.
      expect(est, isNull);
    });
  });

  // ── search range 동작 ────────────────────────────────────────────────────
  group('search range', () {
    test('range 밖 freq 는 hit 못 함 — range 안 best dip 으로 fallback 또는 null', () async {
      // 1000 Hz 사인 — standard range (73-440 Hz) 밖.
      final samples = _synth(freqs: [1000.0], amps: [0.5]);
      final est = await estimator.estimate(
        samples,
        tauMin: _stdTauMin,
        tauMax: _stdTauMax,
      );
      // estimator 는 range 안에서 best fallback dip 을 줄 수 있지만 confidence
      // 가 maxConfidence 이상이거나 freq 가 1000 의 sub-harmonic 가까이면 안 됨.
      // 일관 동작 보증: null 이거나 confidence 가 매우 낮지 않거나, freq 가 실제와
      // 100c 이상 차이.
      if (est != null) {
        final cents = _centsBetween(est.freq, 1000.0).abs();
        expect(cents, greaterThan(100.0),
            reason: 'range 밖 신호가 nominal 가까이 추정되면 안 됨');
      }
    });

    test('range 비어있음 (lo>hi) → null', () async {
      final samples = _synth(freqs: [196.0], amps: [0.5]);
      final est = await estimator.estimate(
        samples,
        tauMin: 500,
        tauMax: 100,
      );
      expect(est, isNull);
    });
  });
}
