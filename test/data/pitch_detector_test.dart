import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:guitar_tuner/data/pitch_detector.dart';

const _sr = 44100;
const _bufSize = 4096; // production buffer

// 표준 튜닝 6현 후보 (auto-detect 모드 시뮬레이션)
const _allStrings = <double>[82.41, 110.00, 146.83, 196.00, 246.94, 329.63];

List<double> _sine(double freq, {int n = _bufSize}) =>
    List<double>.generate(n, (i) => sin(2 * pi * freq * i / _sr));

/// 기타 현 음색 모델: 기음 + 배음 합성.
/// [amps]: 기음, 2배음, 3배음, ... 의 상대 진폭.
List<double> _guitar(double freq, List<double> amps, {int n = _bufSize}) {
  final buf = List<double>.filled(n, 0.0);
  double totalAmp = 0.0;
  for (var h = 0; h < amps.length; h++) {
    final f = freq * (h + 1);
    if (f >= _sr / 2) break; // Nyquist
    for (var i = 0; i < n; i++) {
      buf[i] += amps[h] * sin(2 * pi * f * i / _sr);
    }
    totalAmp += amps[h];
  }
  return buf.map((s) => s / totalAmp).toList();
}

/// 비조화성(inharmonicity) 포함 기타 현 모델.
///   f_m = f₀ * m * sqrt(1 + B * m²)
List<double> _guitarInharmonic(
    double freq, List<double> amps, double B, {int n = _bufSize}) {
  final buf = List<double>.filled(n, 0.0);
  double totalAmp = 0.0;
  for (var h = 0; h < amps.length; h++) {
    final m = h + 1;
    final f = freq * m * sqrt(1 + B * m * m);
    if (f >= _sr / 2) break;
    for (var i = 0; i < n; i++) {
      buf[i] += amps[h] * sin(2 * pi * f * i / _sr);
    }
    totalAmp += amps[h];
  }
  return buf.map((s) => s / totalAmp).toList();
}

void main() {
  final detector = PitchDetector();

  // ── 1. 순수 사인파: 6현 표준 튜닝 (auto-detect 후보 전체) ────────────────
  group('순수 사인파 – 6현 표준 튜닝 (auto-detect 후보 전체)', () {
    const strings = {
      '6현 E2': 82.41,
      '5현 A2': 110.00,
      '4현 D3': 146.83,
      '3현 G3': 196.00,
      '2현 B3': 246.94,
      '1현 E4': 329.63,
    };
    for (final e in strings.entries) {
      test(e.key, () async {
        final result = await detector.detect(
          _sine(e.value),
          candidates: _allStrings,
        );
        expect(result, isNotNull, reason: '${e.key} 감지 실패 (null 반환)');
        expect(result!, closeTo(e.value, 1.0),
            reason: '${e.key} 오감지: ${result.toStringAsFixed(2)} Hz '
                '(기대 ${e.value} Hz)');
      });
    }
  });

  // ── 2. 단일 후보(수동 모드) – 사인파 ────────────────────────────────────
  group('단일 후보 – 수동 튜닝 모드', () {
    const strings = {
      'E2': 82.41,
      'G3': 196.00,
      'E4': 329.63,
    };
    for (final e in strings.entries) {
      test(e.key, () async {
        final result = await detector.detect(
          _sine(e.value),
          candidates: [e.value],
        );
        expect(result, isNotNull);
        expect(result!, closeTo(e.value, 1.0));
      });
    }
  });

  // ── 3. 배음 포함 신호 – 2배음이 강한 케이스(고음현 특성) ─────────────────
  group('배음 포함 신호 – 2배음 우세', () {
    test('B3 – [1.0, 0.8, 0.6, 0.4, 0.2]', () async {
      final sig = _guitar(246.94, [1.0, 0.8, 0.6, 0.4, 0.2]);
      final result = await detector.detect(sig, candidates: _allStrings);
      expect(result, isNotNull);
      expect(result!, closeTo(246.94, 3.0));
    });

    test('E4 – [1.0, 0.8, 0.6, 0.4, 0.2]', () async {
      final sig = _guitar(329.63, [1.0, 0.8, 0.6, 0.4, 0.2]);
      final result = await detector.detect(sig, candidates: _allStrings);
      expect(result, isNotNull);
      expect(result!, closeTo(329.63, 3.0));
    });

    test('E2 – 저음현 [1.0, 0.5, 0.3, 0.2]', () async {
      final sig = _guitar(82.41, [1.0, 0.5, 0.3, 0.2]);
      final result = await detector.detect(sig, candidates: _allStrings);
      expect(result, isNotNull);
      expect(result!, closeTo(82.41, 1.5));
    });
  });

  // ── 4. 비조화성 모델 – 실제 강철 기타줄 시뮬레이션 ──────────────────────
  group('비조화성 포함 신호', () {
    test('E4 B=0.0004', () async {
      final sig =
          _guitarInharmonic(329.63, [1.0, 0.8, 0.6, 0.4, 0.2], 0.0004);
      final result = await detector.detect(sig, candidates: _allStrings);
      expect(result, isNotNull);
      expect(result!, closeTo(329.63, 3.0));
    });

    test('B3 B=0.0004', () async {
      final sig =
          _guitarInharmonic(246.94, [1.0, 0.8, 0.6, 0.4, 0.2], 0.0004);
      final result = await detector.detect(sig, candidates: _allStrings);
      expect(result, isNotNull);
      expect(result!, closeTo(246.94, 3.0));
    });

    test('E2 B=0.00005', () async {
      final sig =
          _guitarInharmonic(82.41, [1.0, 0.5, 0.3, 0.2], 0.00005);
      final result = await detector.detect(sig, candidates: _allStrings);
      expect(result, isNotNull);
      expect(result!, closeTo(82.41, 1.5));
    });
  });

  // ── 5. 오감지 방지 ──────────────────────────────────────────────────────
  group('오감지 방지', () {
    test('묵음 → null', () async {
      final result = await detector.detect(
        List<double>.filled(_bufSize, 0.0),
        candidates: _allStrings,
      );
      expect(result, isNull);
    });

    test('낮은 노이즈 (RMS≈0.01) → null', () async {
      final rng = Random(42);
      final noise = List<double>.generate(
          _bufSize, (_) => (rng.nextDouble() - 0.5) * 0.02);
      final result = await detector.detect(noise, candidates: _allStrings);
      expect(result, isNull,
          reason: '배경 소음이 ${result?.toStringAsFixed(1)} Hz로 오감지됨');
    });

    test('후보 범위 밖 주파수(C5 523Hz) → null 또는 후보 근처', () async {
      // C5는 어떤 표준 현의 ±반옥타브 윈도우 안에도 들어가지 않아야 한다.
      // (E4 ±√2 = [233, 466] → C5(523)는 윈도우 밖)
      final sig = _sine(523.25);
      final result = await detector.detect(sig, candidates: _allStrings);
      // 신뢰 임계값을 통과하지 못해 null이 나오거나,
      // 어떤 후보의 윈도우에도 강한 dip이 생기지 않으면 null.
      // 만에 하나 검출되더라도 어떤 후보의 ±반옥타브 안이어야 함.
      if (result != null) {
        final inAnyWindow = _allStrings.any((c) =>
            result >= c / sqrt2 && result <= c * sqrt2);
        expect(inAnyWindow, isTrue,
            reason: 'C5 sine이 어떤 후보 윈도우에도 속하지 않는 ${result.toStringAsFixed(1)} Hz로 검출됨');
      }
    });
  });

  // ── 6. 옥타브 에러 회귀 방지 ───────────────────────────────────────────
  // 윈도우 ±√2 이내에는 ×2/÷2가 모두 윈도우 밖이므로 옥타브 에러는 구조적으로 불가능.
  // 이 테스트는 그 invariant 가 깨지지 않는지 회귀 방어용.
  group('옥타브 에러 회귀 방지', () {
    test('G3 강한 2배음 신호에서 G2(98Hz)로 절대 오탐 안 함', () async {
      // 2배음을 1.5배 강하게 — 이전 알고리즘에서 옥타브 캐스케이드 유발하던 케이스
      final sig = _guitar(196.00, [1.0, 1.5, 0.8, 0.5, 0.3]);
      final result = await detector.detect(sig, candidates: _allStrings);
      expect(result, isNotNull);
      // 196 Hz의 옥타브 아래 = 98 Hz / 위 = 392 Hz
      // 결과는 G3(196) 또는 그 인접 후보 윈도우 안이어야 하고,
      // 절대로 G2(98) 근처여서는 안 됨.
      expect((result! - 98.0).abs(), greaterThan(20.0),
          reason: 'G2(98Hz)로 옥타브 다운 오탐: ${result.toStringAsFixed(1)} Hz');
      expect(result, closeTo(196.0, 10.0));
    });

    test('D3 강한 2배음 신호에서 D2(73Hz)로 절대 오탐 안 함', () async {
      final sig = _guitar(146.83, [1.0, 1.5, 0.8, 0.5, 0.3]);
      final result = await detector.detect(sig, candidates: _allStrings);
      expect(result, isNotNull);
      expect((result! - 73.42).abs(), greaterThan(15.0),
          reason: 'D2(73Hz)로 옥타브 다운 오탐: ${result.toStringAsFixed(1)} Hz');
      expect(result, closeTo(146.83, 8.0));
    });
  });
}
