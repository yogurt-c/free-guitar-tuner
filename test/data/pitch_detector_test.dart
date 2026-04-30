import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:guitar_tuner/data/pitch_detector.dart';

const _sr = 44100;
const _bufSize = 4096; // production buffer

List<double> _sine(double freq, {int n = _bufSize}) =>
    List<double>.generate(n, (i) => sin(2 * pi * freq * i / _sr));

/// 기타 현 음색 모델: 기음 + 배음 합성
/// [amps]: 기음, 2배음, 3배음, ... 의 상대 진폭
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
/// 실제 강철 기타줄 배음은 m번째 배음이 m*f₀ 보다 약간 날카롭다.
///   f_m = f₀ * m * sqrt(1 + B * m²)
/// 고음현(plain steel, 1·2번줄): B ≈ 0.0002~0.0005
/// 저음현(wound, 5·6번줄):       B ≈ 0.00003~0.00008
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

// ────────────────────────────── CMNDF 직접 계산 (진단용) ──────────────────────
List<double> _cmndf(List<double> samples) {
  final halfN = samples.length ~/ 2;
  final diff = List<double>.filled(halfN, 0.0);
  for (var tau = 1; tau < halfN; tau++) {
    for (var j = 0; j < halfN; j++) {
      final d = samples[j] - samples[j + tau];
      diff[tau] += d * d;
    }
  }
  final c = List<double>.filled(halfN, 0.0);
  c[0] = 1.0;
  double sum = 0.0;
  for (var tau = 1; tau < halfN; tau++) {
    sum += diff[tau];
    c[tau] = sum > 0 ? diff[tau] * tau / sum : 1.0;
  }
  return c;
}

double _minNear(List<double> c, int tau, {int window = 15}) {
  var m = 1.0;
  for (var t = max(2, tau - window); t <= min(c.length - 1, tau + window); t++) {
    if (c[t] < m) m = c[t];
  }
  return m;
}

// ─────────────────────────────────────────────────────────────────────────────

void main() {
  final detector = PitchDetector();

  // ── 1. 순수 사인파: 6현 기본 튜닝 ──────────────────────────────────────────
  group('순수 사인파 – 6현 표준 튜닝 (4096 samples)', () {
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
        final result = await detector.detect(_sine(e.value));
        expect(result, isNotNull,
            reason: '${e.key} 감지 실패 (null 반환)');
        expect(result!, closeTo(e.value, 3.0),
            reason: '${e.key} 오감지: ${result.toStringAsFixed(2)} Hz '
                '(기대 ${e.value} Hz)');
      });
    }
  });

  // ── 2. 배음 포함 기타 현 모델 ──────────────────────────────────────────────
  group('배음 포함 신호 – 고음현이 핵심', () {
    // 저음현(두꺼운 줄): 기음이 강하고 배음이 약함
    test('6현 E2 – 저음현 배음 모델 [1.0, 0.5, 0.3, 0.2]', () async {
      final sig = _guitar(82.41, [1.0, 0.5, 0.3, 0.2]);
      final result = await detector.detect(sig);
      expect(result, isNotNull,
          reason: 'E2 배음 신호 감지 실패');
      expect(result!, closeTo(82.41, 3.0));
    });

    // 고음현(얇은 줄): 배음이 강하고 기음이 상대적으로 약함 ← 문제 현상 재현
    test('2현 B3 – 고음현 배음 모델 [1.0, 0.8, 0.6, 0.4, 0.2]', () async {
      final sig = _guitar(246.94, [1.0, 0.8, 0.6, 0.4, 0.2]);
      final result = await detector.detect(sig);
      expect(result, isNotNull,
          reason: 'B3 고음현 배음 신호 감지 실패 – CMNDF 임계값 문제 가능성');
      expect(result!, closeTo(246.94, 5.0),
          reason: 'B3 오감지 (옥타브 에러 등): ${result?.toStringAsFixed(2)} Hz');
    });

    test('1현 E4 – 고음현 배음 모델 [1.0, 0.8, 0.6, 0.4, 0.2]', () async {
      final sig = _guitar(329.63, [1.0, 0.8, 0.6, 0.4, 0.2]);
      final result = await detector.detect(sig);
      expect(result, isNotNull,
          reason: 'E4 고음현 배음 신호 감지 실패 – CMNDF 임계값 문제 가능성');
      expect(result!, closeTo(329.63, 5.0),
          reason: 'E4 오감지 (옥타브 에러 등): ${result?.toStringAsFixed(2)} Hz');
    });
  });

  // ── 3. 오감지 방지 ──────────────────────────────────────────────────────────
  group('오감지 방지 (묵음/소음)', () {
    test('묵음 → null', () async {
      final result = await detector.detect(List<double>.filled(_bufSize, 0.0));
      expect(result, isNull);
    });

    test('랜덤 노이즈 (RMS≈0.01) → null', () async {
      final rng = Random(42);
      final noise = List<double>.generate(
          _bufSize, (_) => (rng.nextDouble() - 0.5) * 0.02);
      final result = await detector.detect(noise);
      expect(result, isNull,
          reason: '배경 소음이 ${result?.toStringAsFixed(1)} Hz로 오감지됨');
    });
  });

  // ── 4. 비조화성(inharmonicity) 모델 ──────────────────────────────────────
  group('비조화성 포함 신호 (실제 강철 기타줄 시뮬레이션)', () {
    // 고음현(1·2번줄, plain steel): B ≈ 0.0004
    test('1현 E4 – B=0.0004 비조화성', () async {
      final sig = _guitarInharmonic(329.63, [1.0, 0.8, 0.6, 0.4, 0.2], 0.0004);
      final result = await detector.detect(sig);
      expect(result, isNotNull,
          reason: 'E4 비조화성 신호 감지 실패');
      expect(result!, closeTo(329.63, 5.0),
          reason: 'E4 오감지: ${result.toStringAsFixed(2)} Hz');
    });

    test('2현 B3 – B=0.0004 비조화성', () async {
      final sig = _guitarInharmonic(246.94, [1.0, 0.8, 0.6, 0.4, 0.2], 0.0004);
      final result = await detector.detect(sig);
      expect(result, isNotNull,
          reason: 'B3 비조화성 신호 감지 실패');
      expect(result!, closeTo(246.94, 5.0),
          reason: 'B3 오감지: ${result.toStringAsFixed(2)} Hz');
    });

    test('6현 E2 – B=0.00005 비조화성', () async {
      final sig = _guitarInharmonic(82.41, [1.0, 0.5, 0.3, 0.2], 0.00005);
      final result = await detector.detect(sig);
      expect(result, isNotNull);
      expect(result!, closeTo(82.41, 3.0));
    });
  });

  // ── 5. CMNDF 진단 – 비조화성 포함 시 임계값 통과 여부 ─────────────────────
  group('CMNDF 진단', () {
    void printDiag(String label, double freq, List<double> signal) {
      final c = _cmndf(signal);
      final tau = (44100 / freq).round();
      final subTau = tau * 2;
      final fundMin = _minNear(c, tau);
      final subMin = subTau < c.length ? _minNear(c, subTau) : 1.0;

      // ignore: avoid_print
      print('\n─── $label ───');
      // ignore: avoid_print
      print('  기음 tau≈$tau  CMNDF min: ${fundMin.toStringAsFixed(4)}  '
          '│ 서브하모닉 tau≈$subTau CMNDF min: ${subMin.toStringAsFixed(4)}');
      // ignore: avoid_print
      print('  P1(0.15):${fundMin < 0.15}  '
          'P2(0.25):${fundMin < 0.25}  '
          'P3(0.40):${fundMin < 0.40}  '
          '│ subHarm_P3:${subMin < 0.40}');
    }

    test('전체 시나리오 CMNDF 출력', () {
      printDiag('E2 사인파', 82.41, _sine(82.41));
      printDiag('E4 사인파', 329.63, _sine(329.63));
      printDiag('E4 배음 모델', 329.63,
          _guitar(329.63, [1.0, 0.8, 0.6, 0.4, 0.2]));
      printDiag('E4 비조화성 B=0.0004', 329.63,
          _guitarInharmonic(329.63, [1.0, 0.8, 0.6, 0.4, 0.2], 0.0004));
      printDiag('B3 비조화성 B=0.0004', 246.94,
          _guitarInharmonic(246.94, [1.0, 0.8, 0.6, 0.4, 0.2], 0.0004));
      printDiag('E2 비조화성 B=0.00005', 82.41,
          _guitarInharmonic(82.41, [1.0, 0.5, 0.3, 0.2], 0.00005));

      // 0.40 이상이면 감지 불가 → 다른 접근 필요
      final e4Min = _minNear(
          _cmndf(_guitarInharmonic(329.63, [1.0, 0.8, 0.6, 0.4, 0.2], 0.0004)),
          (44100 / 329.63).round());
      final b3Min = _minNear(
          _cmndf(_guitarInharmonic(246.94, [1.0, 0.8, 0.6, 0.4, 0.2], 0.0004)),
          (44100 / 246.94).round());

      // ignore: avoid_print
      print('\n→ E4 비조화성 CMNDF 기음 최솟값: ${e4Min.toStringAsFixed(4)}');
      // ignore: avoid_print
      print('→ B3 비조화성 CMNDF 기음 최솟값: ${b3Min.toStringAsFixed(4)}');
    });
  });
}
