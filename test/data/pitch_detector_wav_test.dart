/// 실제 기타 어쿠스틱 WAV 샘플로 PitchDetector 검증.
///
/// 샘플 출처: github.com/nbrosowsky/tonejs-instruments (MIT)
/// 포맷: PCM16, 44100 Hz, mono
///
/// 파일 준비:
///   test/audio/{E2,A2,D3,G3,B3,E4}.wav
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:guitar_tuner/data/pitch_detector.dart';

// ── WAV 파싱 ──────────────────────────────────────────────────────────────────

/// WAV 파일에서 PCM 샘플 전부를 읽어 [-1, 1] double 로 반환.
/// 표준 PCM16 / 44100 Hz / mono 전용.
List<double> _loadWav(String path) {
  final bytes = File(path).readAsBytesSync();
  final data = ByteData.sublistView(bytes);

  // "RIFF" 체크
  assert(String.fromCharCodes(bytes.sublist(0, 4)) == 'RIFF');
  assert(String.fromCharCodes(bytes.sublist(8, 12)) == 'WAVE');

  int pos = 12;
  int dataOffset = -1;
  int dataSize = -1;

  while (pos < bytes.length - 8) {
    final chunkId = String.fromCharCodes(bytes.sublist(pos, pos + 4));
    final chunkSize = data.getUint32(pos + 4, Endian.little);
    if (chunkId == 'data') {
      dataOffset = pos + 8;
      dataSize = chunkSize;
      break;
    }
    pos += 8 + chunkSize;
  }

  assert(dataOffset != -1, 'data chunk not found');
  final sampleCount = dataSize ~/ 2;
  return List<double>.generate(
    sampleCount,
    (i) => data.getInt16(dataOffset + i * 2, Endian.little) / 32768.0,
  );
}

// ── 헬퍼 ──────────────────────────────────────────────────────────────────────

const _bufSize = 4096;
const _sampleRate = 44100;

// 실제 파이프라인 상수 (AudioPipeline / TunerNotifier 와 동일한 값 유지)
const _noiseGateThreshold = 0.01; // TunerNotifier._noiseGateThreshold
const _smoothingFrames = 3;       // AudioPipeline._smoothingFrames

/// WAV 전체 샘플을 4096 샘플 청크로 분할 반환.
List<List<double>> _chunks(List<double> samples) {
  final result = <List<double>>[];
  for (var i = 0; i + _bufSize <= samples.length; i += _bufSize) {
    result.add(samples.sublist(i, i + _bufSize));
  }
  return result;
}

double _rmsCalc(List<double> samples) {
  if (samples.isEmpty) return 0.0;
  var sum = 0.0;
  for (final s in samples) {
    sum += s * s;
  }
  return sqrt(sum / samples.length);
}

/// 모든 청크를 PitchDetector 에 통과시켜 감지된 주파수 목록 반환 (null 제외).
/// 알고리즘 내부 진단용 — 파이프라인 필터 없음.
Future<List<double>> _detectAll(
    PitchDetector detector, List<List<double>> chunks) async {
  final results = <double>[];
  for (final chunk in chunks) {
    final freq = await detector.detect(chunk);
    if (freq != null) results.add(freq);
  }
  return results;
}

/// 실제 오디오 파이프라인을 재현:
///   AudioPipeline: detect() → 3-frame median 스무딩
///   TunerNotifier: 노이즈 게이트(RMS < 0.01) 적용
/// 사용자에게 실제로 표시되는 주파수 목록을 반환.
Future<List<double>> _detectAllPipeline(
    PitchDetector detector, List<List<double>> chunks) async {
  final freqBuffer = <double>[];
  final results = <double>[];
  for (final chunk in chunks) {
    final signalLevel = _rmsCalc(chunk);
    final rawFreq = await detector.detect(chunk);
    double? smoothed;
    if (rawFreq != null) {
      freqBuffer.add(rawFreq);
      if (freqBuffer.length > _smoothingFrames) freqBuffer.removeAt(0);
      final sorted = [...freqBuffer]..sort();
      final mid = sorted.length ~/ 2;
      smoothed = sorted.length.isOdd
          ? sorted[mid]
          : (sorted[mid - 1] + sorted[mid]) / 2.0;
    }
    if (signalLevel < _noiseGateThreshold || smoothed == null) continue;
    results.add(smoothed);
  }
  return results;
}

/// 감지된 주파수들의 중앙값 반환.
double _median(List<double> values) {
  if (values.isEmpty) return 0;
  final sorted = [...values]..sort();
  final mid = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[mid]
      : (sorted[mid - 1] + sorted[mid]) / 2.0;
}

String _audioPath(String note) {
  // 테스트 실행 디렉토리 기준 경로
  return 'test/audio/$note.wav';
}

List<double> computeCmndf(List<double> samples) {
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

// ── 테스트 ────────────────────────────────────────────────────────────────────

void main() {
  final detector = PitchDetector();

  const strings = <String, double>{
    'E2 (6현)': 82.41,
    'A2 (5현)': 110.00,
    'D3 (4현)': 146.83,
    'G3 (3현)': 196.00,
    'B3 (2현)': 246.94,
    'E4 (1현)': 329.63,
  };

  const noteFile = <String, String>{
    'E2 (6현)': 'E2',
    'A2 (5현)': 'A2',
    'D3 (4현)': 'D3',
    'G3 (3현)': 'G3',
    'B3 (2현)': 'B3',
    'E4 (1현)': 'E4',
  };

  // 음별 최소 정답률 (감지된 청크 중 ±5% 이내 비율).
  // E2·G3는 배음 오탐 특성상 목표값이 낮게 설정.
  const accuracyThreshold = <String, double>{
    'E2 (6현)': 0.75,
    'A2 (5현)': 0.90,
    'D3 (4현)': 0.90,
    'G3 (3현)': 0.85,
    'B3 (2현)': 0.90,
    'E4 (1현)': 0.90,
  };

  // ── 기본: 어느 청크라도 올바른 음 감지 ────────────────────────────────────
  group('실제 WAV – 감지 여부', () {
    for (final e in strings.entries) {
      test(e.key, () async {
        final path = _audioPath(noteFile[e.key]!);
        if (!File(path).existsSync()) {
          markTestSkipped('파일 없음: $path');
          return;
        }

        final samples = _loadWav(path);
        final chunks = _chunks(samples);
        final detected = await _detectAllPipeline(detector, chunks);

        // ignore: avoid_print
        print('\n${e.key}: ${chunks.length}청크 중 ${detected.length}개 감지 '
            '(${(detected.length / chunks.length * 100).toStringAsFixed(0)}%)');

        expect(detected, isNotEmpty,
            reason: '${e.key} – 한 청크도 감지 못함');

        // 감지된 주파수 중 목표 ±5% 이내 비율
        final target = e.value;
        final correct = detected
            .where((f) => (f - target).abs() / target < 0.05)
            .length;
        final correctRatio = correct / detected.length;
        // ignore: avoid_print
        print('  ±5% 이내 정답 비율: '
            '${correct}/${detected.length} '
            '(${(correctRatio * 100).toStringAsFixed(0)}%) '
            '기준: ${(accuracyThreshold[e.key]! * 100).toStringAsFixed(0)}%');

        expect(
          correctRatio,
          greaterThanOrEqualTo(accuracyThreshold[e.key]!),
          reason: '${e.key} – 정답률 ${(correctRatio * 100).toStringAsFixed(0)}% '
              '< 기준 ${(accuracyThreshold[e.key]! * 100).toStringAsFixed(0)}%',
        );
      });
    }
  });

  // ── 중앙값 정밀도 ──────────────────────────────────────────────────────────
  group('실제 WAV – 중앙값 정밀도 (±5%)', () {
    for (final e in strings.entries) {
      test(e.key, () async {
        final path = _audioPath(noteFile[e.key]!);
        if (!File(path).existsSync()) {
          markTestSkipped('파일 없음: $path');
          return;
        }

        final samples = _loadWav(path);
        final chunks = _chunks(samples);
        final detected = await _detectAllPipeline(detector, chunks);

        if (detected.isEmpty) {
          fail('${e.key} – 감지 결과 없음');
        }

        final med = _median(detected);
        final target = e.value;
        final errorPct = (med - target).abs() / target * 100;

        // ignore: avoid_print
        print('${e.key}: 중앙값=${med.toStringAsFixed(2)} Hz, '
            '오차=${errorPct.toStringAsFixed(1)}%');

        expect(errorPct, lessThan(5.0),
            reason: '${e.key} 중앙값 ${med.toStringAsFixed(2)} Hz, '
                '기대 ${target} Hz, 오차 ${errorPct.toStringAsFixed(1)}%');
      });
    }
  });

  // ── CMNDF 값 진단 ─────────────────────────────────────────────────────────
  group('CMNDF 값 진단', () {
    test('E2 오탐 청크의 CMNDF[268] vs CMNDF[535] 분포', () {
      final samples = _loadWav(_audioPath('E2'));
      final chunks = _chunks(samples);
      // ignore: avoid_print
      print('\nE2 오탐 청크 CMNDF 샘플 (최대 5개):');
      int shown = 0;
      for (final chunk in chunks) {
        if (shown >= 5) break;
        final c = computeCmndf(chunk);
        final v268 = c[268];
        final v535 = c[535];
        final freq = _sampleRate / 268.0;
        if (v268 < 0.15) { // first-dip이 268에서 멈춘 청크
          // ignore: avoid_print
          print('  CMNDF[268]=${v268.toStringAsFixed(4)}'
              '  CMNDF[535]=${v535.toStringAsFixed(4)}'
              '  ratio=${(v535/v268).toStringAsFixed(2)}'
              '  → ${freq.toStringAsFixed(0)} Hz');
          shown++;
        }
      }
    });

    test('E4 오탐 청크의 CMNDF[134] vs CMNDF[268] 분포', () {
      final samples = _loadWav(_audioPath('E4'));
      final chunks = _chunks(samples);
      // ignore: avoid_print
      print('\nE4 청크 CMNDF 샘플 (최대 10개):');
      int shown = 0;
      for (final chunk in chunks) {
        if (shown >= 10) break;
        final c = computeCmndf(chunk);
        final v134 = c[134];
        final v268 = c[268];
        // ignore: avoid_print
        print('  CMNDF[134]=${v134.toStringAsFixed(4)}'
            '  CMNDF[268]=${v268.toStringAsFixed(4)}'
            '  c268<c134: ${v268 < v134}');
        shown++;
      }
    });
  });

  // ── 오탐 주파수 분포 ──────────────────────────────────────────────────────
  group('오탐 주파수 분포 진단', () {
    test('E2 오탐 주파수 분포', () async {
      final path = _audioPath('E2');
      final samples = _loadWav(path);
      final chunks = _chunks(samples);
      final target = 82.41;
      final wrong = <double>[];
      for (final chunk in chunks) {
        final freq = await detector.detect(chunk);
        if (freq != null && (freq - target).abs() / target >= 0.05) {
          wrong.add(freq);
        }
      }
      // ignore: avoid_print
      print('E2 오탐 주파수 (총 ${wrong.length}개):');
      final buckets = <int, int>{};
      for (final f in wrong) {
        final bucket = (f / 10).round() * 10;
        buckets[bucket] = (buckets[bucket] ?? 0) + 1;
      }
      for (final e in (buckets.entries.toList()..sort((a,b)=>b.value-a.value)).take(5)) {
        // ignore: avoid_print
        print('  ~${e.key} Hz: ${e.value}회');
      }
    });

    test('G3 오탐 주파수 분포', () async {
      final path = _audioPath('G3');
      final samples = _loadWav(path);
      final chunks = _chunks(samples);
      final target = 196.00;
      final wrong = <double>[];
      for (final chunk in chunks) {
        final freq = await detector.detect(chunk);
        if (freq != null && (freq - target).abs() / target >= 0.05) {
          wrong.add(freq);
        }
      }
      // ignore: avoid_print
      print('G3 오탐 주파수 (총 ${wrong.length}개):');
      final buckets = <int, int>{};
      for (final f in wrong) {
        final bucket = (f / 10).round() * 10;
        buckets[bucket] = (buckets[bucket] ?? 0) + 1;
      }
      for (final e in (buckets.entries.toList()..sort((a,b)=>b.value-a.value)).take(5)) {
        // ignore: avoid_print
        print('  ~${e.key} Hz: ${e.value}회');
      }
    });

    // ── Step 1: G3 실패 원인 실증 ───────────────────────────────────────────
    // 가설: 2배음(tau≈113)에서 first-dip이 잡혔을 때 c0 < 0.003 가드가
    //        옥타브 교정을 막아 392 Hz를 반환.
    // 검증: 오탐 청크에서 CMNDF[113] 값을 출력해 가드 발동 여부 확인.
    test('G3 오탐 청크의 CMNDF[113] c0 분포 진단', () async {
      final path = _audioPath('G3');
      final samples = _loadWav(path);
      final chunks = _chunks(samples);
      final target = 196.00;
      // ignore: avoid_print
      print('\nG3 오탐 청크 CMNDF 분석:');
      int guardBlocked = 0; // c0 < 0.003으로 가드 발동된 청크
      int ratioFailed = 0;  // c0 >= 0.003이지만 ratio 조건 미충족
      int shown = 0;
      for (final chunk in chunks) {
        final freq = await detector.detect(chunk);
        if (freq == null || (freq - target).abs() / target < 0.05) continue;
        final c = computeCmndf(chunk);
        final c0 = c[113]; // 2배음 tau
        final cFund = c[225]; // 기음 tau
        if (c0 < 0.003) {
          guardBlocked++;
        } else if (cFund >= c0 * 0.5) {
          ratioFailed++;
        }
        if (shown < 7) {
          // ignore: avoid_print
          print('  CMNDF[113]=${c0.toStringAsFixed(4)}'
              '  CMNDF[225]=${cFund.toStringAsFixed(4)}'
              '  ratio=${(cFund / (c0 > 0 ? c0 : 1)).toStringAsFixed(3)}'
              '  guard_blocked=${c0 < 0.003}');
          shown++;
        }
      }
      // ignore: avoid_print
      print('  → 가드(c0<0.003) 차단: ${guardBlocked}청크 / '
          'ratio 조건 미충족: ${ratioFailed}청크');
    });
  });

  // ── Step 2 디버그: E2 실패 청크 알고리즘 내부 추적 ───────────────────────
  // compute() isolate 안쪽이라 외부에서 관찰 불가 → 테스트에서 알고리즘 재현.
  group('E2 알고리즘 내부 추적', () {
    // pitch_detector.dart 의 _findFirstDip 를 그대로 복제
    int? findFirstDip(List<double> c, int tauMin, int tauMax, double threshold) {
      for (var tau = tauMin + 1; tau < tauMax; tau++) {
        if (c[tau] < threshold) {
          while (tau + 1 < tauMax && c[tau + 1] < c[tau]) tau++;
          return tau;
        }
      }
      return null;
    }

    // ratio 분포 파악: 0.5 임계값을 어느 수준까지 완화하면 몇 개 더 잡히는지 확인
    test('E2 실패 청크 ratio 전체 분포', () async {
      final samples = _loadWav(_audioPath('E2'));
      final chunks = _chunks(samples);
      final target = 82.41;
      const sampleRate = 44100;
      const maxFreq = 1400.0;
      const minFreq = 70.0;
      final halfN = chunks.first.length ~/ 2;
      final tauMin = max(2, (sampleRate / maxFreq).ceil());
      final tauMax = min(halfN - 2, (sampleRate / minFreq).floor());

      int? findFirstDip2(List<double> c, int mn, int mx, double thr) {
        for (var tau = mn + 1; tau < mx; tau++) {
          if (c[tau] < thr) {
            while (tau + 1 < mx && c[tau + 1] < c[tau]) tau++;
            return tau;
          }
        }
        return null;
      }

      final ratios = <double>[];
      int guardBlocked = 0;
      for (final chunk in chunks) {
        final freq = await detector.detect(chunk);
        if (freq == null || (freq - target).abs() / target < 0.05) continue;
        final c = computeCmndf(chunk);
        final tau = findFirstDip2(c, tauMin, tauMax, 0.15)
            ?? findFirstDip2(c, tauMin, tauMax, 0.25)
            ?? findFirstDip2(c, tauMin, tauMax, 0.40);
        if (tau == null) continue;
        final c0 = c[tau];
        if (c0 <= 0.001) { guardBlocked++; continue; }
        final octaveTau = tau * 2;
        if (octaveTau > tauMax) continue;
        var octaveMin = 1.0;
        for (var t = max(tauMin, octaveTau - 25); t <= min(tauMax, octaveTau + 25); t++) {
          if (c[t] < octaveMin) octaveMin = c[t];
        }
        ratios.add(octaveMin / c0);
      }
      ratios.sort();
      // ignore: avoid_print
      print('\nE2 실패 청크 중 가드 통과 후 ratio 분포 (${ratios.length}개):');
      // ignore: avoid_print
      print('  가드(c0<=0.001) 차단: ${guardBlocked}개');
      for (final threshold in [0.5, 0.6, 0.65, 0.7, 0.75, 0.8]) {
        final fixable = ratios.where((r) => r < threshold).length;
        // ignore: avoid_print
        print('  ratio < $threshold: ${fixable}/${ratios.length}개 교정 가능');
      }
      // ignore: avoid_print
      print('  ratio 값: ${ratios.map((r) => r.toStringAsFixed(3)).join(', ')}');
    });

    test('첫 번째 E2 실패 청크: first-dip 결과 및 옥타브 교정 경로', () async {
      final samples = _loadWav(_audioPath('E2'));
      final chunks = _chunks(samples);
      final target = 82.41;
      int traced = 0;
      for (final chunk in chunks) {
        final freq = await detector.detect(chunk);
        if (freq == null || (freq - target).abs() / target < 0.05) continue;
        if (traced >= 3) break;
        traced++;

        final c = computeCmndf(chunk);
        const sampleRate = 44100;
        const maxFreq = 1400.0;
        const minFreq = 70.0;
        final halfN = chunk.length ~/ 2;
        final tauMin = max(2, (sampleRate / maxFreq).ceil());
        final tauMax = min(halfN - 2, (sampleRate / minFreq).floor());

        final tau1 = findFirstDip(c, tauMin, tauMax, 0.15)
            ?? findFirstDip(c, tauMin, tauMax, 0.25)
            ?? findFirstDip(c, tauMin, tauMax, 0.40);

        // ignore: avoid_print
        print('\n─── E2 실패 청크 #$traced (감지=${freq.toStringAsFixed(1)} Hz) ───');
        // ignore: avoid_print
        print('  first-dip tau=$tau1  (${(sampleRate/(tau1??1)).toStringAsFixed(1)} Hz)');
        if (tau1 != null) {
          // ignore: avoid_print
          print('  CMNDF[$tau1]=${c[tau1].toStringAsFixed(4)}');
          final octaveTau = tau1 * 2;
          // ignore: avoid_print
          print('  octaveTau=$octaveTau  (<= tauMax=$tauMax: ${octaveTau <= tauMax})');
          if (octaveTau <= tauMax) {
            var octaveMin25 = 1.0;
            for (var t = max(tauMin, octaveTau - 25);
                t <= min(tauMax, octaveTau + 25); t++) {
              if (c[t] < octaveMin25) octaveMin25 = c[t];
            }
            // ignore: avoid_print
            print('  ±25 창 CMNDF 최솟값=${octaveMin25.toStringAsFixed(6)}'
                '  임계값=${(c[tau1] * 0.5).toStringAsFixed(6)}'
                '  교정발동=${octaveMin25 < c[tau1] * 0.5}');
          }
          // ignore: avoid_print
          print('  CMNDF[535]=${c[535].toStringAsFixed(6)}'
              '  CMNDF[536]=${c[536].toStringAsFixed(6)}');
        }
      }
    });
  });

  // ── E4 회귀 추적 ─────────────────────────────────────────────────────────
  group('E4 회귀 추적', () {
    test('E4 실패 청크 CMNDF[134] vs ±25창 최솟값', () async {
      final samples = _loadWav(_audioPath('E4'));
      final chunks = _chunks(samples);
      final target = 329.63;
      int shown = 0;
      // ignore: avoid_print
      print('\nE4 실패 청크 분석:');
      for (final chunk in chunks) {
        final freq = await detector.detect(chunk);
        if (freq == null || (freq - target).abs() / target < 0.05) continue;
        if (shown >= 5) break;
        shown++;
        final c = computeCmndf(chunk);
        final tauFund = 134;
        final c0 = c[tauFund];
        var octaveMin = 1.0;
        int octaveMinTau = 268;
        for (var t = max(32, 268 - 25); t <= min(630, 268 + 25); t++) {
          if (t < c.length && c[t] < octaveMin) {
            octaveMin = c[t];
            octaveMinTau = t;
          }
        }
        // ignore: avoid_print
        print('  감지=${freq.toStringAsFixed(1)} Hz  '
            'CMNDF[134]=${c0.toStringAsFixed(4)}  '
            'octaveMin=${octaveMin.toStringAsFixed(4)}(tau=$octaveMinTau)  '
            'ratio=${(octaveMin / (c0 > 0 ? c0 : 1)).toStringAsFixed(3)}  '
            'c0*0.75=${(c0 * 0.75).toStringAsFixed(4)}  '
            '교정=${octaveMin < c0 * 0.75}');
      }
    });

    test('E4 정탐 청크의 CMNDF[268±25최솟값]/CMNDF[134] 분포', () async {
      final samples = _loadWav(_audioPath('E4'));
      final chunks = _chunks(samples);
      final target = 329.63;
      final ratios = <double>[];
      for (final chunk in chunks) {
        final freq = await detector.detect(chunk);
        if (freq == null || (freq - target).abs() / target >= 0.05) continue;
        final c = computeCmndf(chunk);
        if (c[134] <= 0) continue;
        var octaveMin = 1.0;
        for (var t = max(32, 243); t <= min(630, 293); t++) {
          if (t < c.length && c[t] < octaveMin) octaveMin = c[t];
        }
        ratios.add(octaveMin / c[134]);
      }
      ratios.sort();
      // ignore: avoid_print
      print('\nE4 정탐 CMNDF[243-293최솟값]/CMNDF[134] (${ratios.length}개):');
      for (final threshold in [0.5, 0.6, 0.65, 0.7, 0.75, 0.8]) {
        final risky = ratios.where((r) => r < threshold).length;
        // ignore: avoid_print
        print('  ratio < $threshold: ${risky}개 오탐 위험');
      }
      // ignore: avoid_print
      print('  min=${ratios.first.toStringAsFixed(3)} max=${ratios.last.toStringAsFixed(3)}');
    });
  });

  // ── Step 2 추가: ratio 임계값 완화 시 G3·D3 정탐 회귀 여부 확인 ──────────
  group('ratio 임계값 완화 회귀 체크 (G3·D3)', () {
    // 전체 G3 청크 기준으로 측정 (회귀된 8개 포함)
    test('G3 전체 청크의 ±창별 최솟값/CMNDF[225] 분포', () async {
      final samples = _loadWav(_audioPath('G3'));
      final chunks = _chunks(samples);
      // ignore: avoid_print
      print('\nG3 전체 ${chunks.length}청크: 창 크기별 oMinc225 risky 개수:');
      for (final window in [3, 5, 8, 10, 12, 15, 20, 25]) {
        int risky75 = 0, risky70 = 0, risky65 = 0;
        for (final chunk in chunks) {
          final c = computeCmndf(chunk);
          final c0 = c[225];
          if (c0 <= 0.001) continue; // 가드 범위 안 청크만
          var octaveMin = 1.0;
          for (var t = max(32, 450 - window); t <= min(630, 450 + window); t++) {
            if (t < c.length && c[t] < octaveMin) octaveMin = c[t];
          }
          final ratio = octaveMin / c0;
          if (ratio < 0.75) risky75++;
          if (ratio < 0.70) risky70++;
          if (ratio < 0.65) risky65++;
        }
        // ignore: avoid_print
        print('  ±$window: r<0.65=${risky65} / r<0.70=${risky70} / r<0.75=${risky75}');
      }
    });

    test('D3 정탐 청크의 CMNDF[602]/CMNDF[301] 분포', () async {
      final samples = _loadWav(_audioPath('D3'));
      final chunks = _chunks(samples);
      final target = 146.83;
      final ratios = <double>[];
      for (final chunk in chunks) {
        final freq = await detector.detect(chunk);
        if (freq == null || (freq - target).abs() / target >= 0.05) continue;
        final c = computeCmndf(chunk);
        if (c[301] > 0) ratios.add(c[602] / c[301]);
      }
      ratios.sort();
      // ignore: avoid_print
      print('\nD3 정탐 청크 CMNDF[602]/CMNDF[301] (${ratios.length}개):');
      for (final threshold in [0.5, 0.6, 0.65, 0.7, 0.75, 0.8]) {
        final risky = ratios.where((r) => r < threshold).length;
        // ignore: avoid_print
        print('  ratio < $threshold: ${risky}개 → ratio 완화 시 오탐 위험');
      }
      // ignore: avoid_print
      print('  min ratio: ${ratios.first.toStringAsFixed(3)}  max: ${ratios.last.toStringAsFixed(3)}');
    });
  });

  // ── Step 1 추가 진단: ratio 임계값 변경 시 전 음 영향 ─────────────────────
  // G3 수정을 위해 ratio 0.5 → 0.X로 완화할 경우,
  // 정확도가 높은 타 음(E4, B3, D3, A2)에서 오탐이 생기지 않는지 확인.
  group('ratio 임계값 안전성 진단', () {
    test('오탐 청크의 2배음→기음 ratio 분포 (전 음)', () async {
      // ignore: avoid_print
      print('\n─── ratio 분포 (오탐 청크에서 first-dip이 잡은 2배음 tau 기준) ───');
      for (final e in strings.entries) {
        final path = _audioPath(noteFile[e.key]!);
        if (!File(path).existsSync()) continue;
        final samples = _loadWav(path);
        final chunks = _chunks(samples);
        final target = e.value;
        final tauFund = (_sampleRate / target).round();
        final tauHarm = (tauFund / 2).round(); // 2배음 tau
        final ratios = <double>[];
        for (final chunk in chunks) {
          final freq = await detector.detect(chunk);
          if (freq == null || (freq - target).abs() / target < 0.05) continue;
          // 오탐 청크만: 2배음 영역 CMNDF[tauHarm] vs 기음 CMNDF[tauFund]
          final c = computeCmndf(chunk);
          if (tauHarm < c.length && tauFund < c.length && c[tauHarm] > 0) {
            ratios.add(c[tauFund] / c[tauHarm]);
          }
        }
        if (ratios.isEmpty) {
          // ignore: avoid_print
          print('  ${e.key.padRight(10)}: 오탐 없음');
        } else {
          ratios.sort();
          // ignore: avoid_print
          print('  ${e.key.padRight(10)}: 오탐 ${ratios.length}청크 '
              'ratio min=${ratios.first.toStringAsFixed(3)} '
              'max=${ratios.last.toStringAsFixed(3)}');
        }
      }

      // ── 정탐 청크에서 ratio가 낮은 케이스 확인 (오탐 위험 체크) ──
      // ignore: avoid_print
      print('\n─── 정탐 청크 중 ratio < 0.9인 케이스 (오탐 위험) ───');
      for (final e in strings.entries) {
        final path = _audioPath(noteFile[e.key]!);
        if (!File(path).existsSync()) continue;
        final samples = _loadWav(path);
        final chunks = _chunks(samples);
        final target = e.value;
        final tauFund = (_sampleRate / target).round();
        final tauHarm = (tauFund / 2).round();
        int risky = 0;
        for (final chunk in chunks) {
          final freq = await detector.detect(chunk);
          if (freq == null || (freq - target).abs() / target >= 0.05) continue;
          // 정탐 청크: octaveTau 방향의 ratio 확인
          final c = computeCmndf(chunk);
          final octaveTau = tauFund * 2;
          if (tauFund < c.length && octaveTau < c.length && c[tauFund] > 0) {
            final r = c[octaveTau] / c[tauFund];
            if (r < 0.9) risky++;
          }
          // 2배음이 있는 경우도 체크 (first-dip이 tauHarm을 찾을 수 있는 케이스)
          if (tauHarm > 0 && tauHarm < c.length && tauFund < c.length && c[tauHarm] > 0) {
            final r = c[tauFund] / c[tauHarm];
            if (r < 0.9) risky++;
          }
        }
        if (risky > 0) {
          // ignore: avoid_print
          print('  ${e.key.padRight(10)}: ratio<0.9인 정탐 청크 ${risky}개 → 임계값 완화 시 오탐 위험');
        } else {
          // ignore: avoid_print
          print('  ${e.key.padRight(10)}: 안전');
        }
      }
    });
  });

  // ── 상세 진단: 청크별 감지 분포 ───────────────────────────────────────────
  group('실제 WAV – 청크별 분포 진단', () {
    test('전 현 분포 출력', () async {
      // ignore: avoid_print
      print('\n╔══════════════════════════════════════════════════════╗');
      // ignore: avoid_print
      print('║  현      기대Hz  감지Hz(중앙값)  정답률  오차   ║');
      // ignore: avoid_print
      print('╠══════════════════════════════════════════════════════╣');

      for (final e in strings.entries) {
        final path = _audioPath(noteFile[e.key]!);
        if (!File(path).existsSync()) {
          // ignore: avoid_print
          print('║  ${e.key.padRight(8)} 파일 없음                           ║');
          continue;
        }

        final samples = _loadWav(path);
        final chunks = _chunks(samples);
        final detected = await _detectAllPipeline(detector, chunks);

        if (detected.isEmpty) {
          // ignore: avoid_print
          print('║  ${e.key.padRight(8)} ${e.value.toStringAsFixed(1).padLeft(7)}  '
              '감지 실패                      ║');
          continue;
        }

        final med = _median(detected);
        final target = e.value;
        final correct = detected
            .where((f) => (f - target).abs() / target < 0.05)
            .length;
        final correctPct = correct / detected.length * 100;
        final errorPct = (med - target).abs() / target * 100;

        // ignore: avoid_print
        print('║  ${e.key.padRight(8)} '
            '${target.toStringAsFixed(1).padLeft(7)}  '
            '${med.toStringAsFixed(1).padLeft(13)}  '
            '${correctPct.toStringAsFixed(0).padLeft(5)}%  '
            '${errorPct.toStringAsFixed(1).padLeft(5)}%  ║');
      }

      // ignore: avoid_print
      print('╚══════════════════════════════════════════════════════╝');
    });
  });
}
