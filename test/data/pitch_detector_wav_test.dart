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

// ── 실제 환경 시뮬레이션 헬퍼 ─────────────────────────────────────────────

/// Box-Muller 변환으로 표준 정규분포 난수 생성.
double _gaussian(Random rng) {
  final u1 = rng.nextDouble();
  final u2 = rng.nextDouble();
  return sqrt(-2 * log(u1 + 1e-10)) * cos(2 * pi * u2);
}

/// 지정한 SNR(dB)로 가우시안 노이즈를 청크에 추가.
List<double> _addNoise(List<double> samples, double snrDb, Random rng) {
  final signalRms = _rmsCalc(samples);
  if (signalRms < 1e-6) return samples;
  final noiseAmp = signalRms / pow(10, snrDb / 20.0);
  return [for (final s in samples) (s + _gaussian(rng) * noiseAmp).clamp(-1.0, 1.0)];
}

/// 청크 단위 RMS 정규화 (Android AGC 시뮬레이션).
/// AGC는 파형 형태를 보존하지만 신호 크기를 평탄화한다.
List<double> _applyAgcChunk(List<double> chunk, {double targetRms = 0.1}) {
  final rms = _rmsCalc(chunk);
  if (rms < 1e-6) return chunk;
  final gain = (targetRms / rms).clamp(0.0, 10.0);
  return [for (final s in chunk) (s * gain).clamp(-1.0, 1.0)];
}

/// 실제 파이프라인 재현 – 전처리 함수와 sampleRate를 주입 가능.
/// 노이즈 게이트는 전처리 후 신호 레벨 기준으로 동작한다
/// (실제 디바이스에서 AGC/노이즈 처리가 앱 이전에 적용되기 때문).
Future<List<double>> _detectAllPipelineExt(
  PitchDetector detector,
  List<List<double>> chunks, {
  List<double> Function(List<double>)? preProcess,
  int sampleRate = _sampleRate,
}) async {
  final freqBuffer = <double>[];
  final results = <double>[];
  for (final raw in chunks) {
    final chunk = preProcess != null ? preProcess(raw) : raw;
    final signalLevel = _rmsCalc(chunk);
    final rawFreq = await detector.detect(chunk, sampleRate: sampleRate);
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

/// 기타 현의 물리적 특성을 반영한 합성 신호.
///
/// - 비조화성: f_h = f0 × h × √(1 + B×h²)
///   B = 0 이면 순수 조화음, 실제 기타 저음 현은 B ≈ 0.0005~0.001
/// - 진폭 포락선: 어택(5 ms) + 지수감쇄
/// - harmonicAmps: 기음(h=1)을 1.0 기준으로 각 배음의 상대 진폭
List<double> _synthesizeGuitar(
  double freqHz, {
  double durationSec = 1.5,
  int sampleRate = _sampleRate,
  double inharmonicity = 0.0003,
  List<double> harmonicAmps = const [1.0, 0.7, 0.5, 0.35, 0.25, 0.18, 0.12],
  double decayRate = 4.0,
}) {
  final n = (durationSec * sampleRate).round();
  final signal = List<double>.filled(n, 0.0);
  const attackSec = 0.005;
  for (var h = 1; h <= harmonicAmps.length; h++) {
    final fh = freqHz * h * sqrt(1.0 + inharmonicity * h * h);
    for (var i = 0; i < n; i++) {
      final t = i / sampleRate;
      final attack = t < attackSec ? t / attackSec : 1.0;
      final env = attack * exp(-decayRate * t);
      signal[i] += harmonicAmps[h - 1] * env * sin(2 * pi * fh * t);
    }
  }
  final maxAmp = signal.map((s) => s.abs()).reduce(max);
  if (maxAmp < 1e-6) return signal;
  return signal.map((s) => s / maxAmp * 0.9).toList();
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

  // ── 실제 환경 시뮬레이션 ──────────────────────────────────────────────────
  //
  // 각 그룹은 실제 디바이스에서 발생하는 조건을 WAV 샘플에 적용한다.
  // 테스트 통과 → 알고리즘이 해당 조건에 강인함.
  // 테스트 실패 → 실제 앱에서 같은 조건에서 오감지가 발생한다는 증거.

  // ── 배경 소음 SNR 20 dB (조용한 방) ─────────────────────────────────────
  group('실제 환경 시뮬레이션 – 배경 소음 SNR 20 dB', () {
    // SNR 20 dB ≈ 조용한 실내. 이 조건에서도 정확도를 유지해야 한다.
    final rng = Random(42);
    const snrDb = 20.0;
    const noiseThr = <String, double>{
      'E2 (6현)': 0.65,
      'A2 (5현)': 0.80,
      'D3 (4현)': 0.80,
      'G3 (3현)': 0.75,
      'B3 (2현)': 0.80,
      'E4 (1현)': 0.80,
    };
    for (final e in strings.entries) {
      test(e.key, () async {
        final path = _audioPath(noteFile[e.key]!);
        if (!File(path).existsSync()) { markTestSkipped('파일 없음: $path'); return; }
        final chunks = _chunks(_loadWav(path));
        final detected = await _detectAllPipelineExt(
          detector, chunks,
          preProcess: (c) => _addNoise(c, snrDb, rng),
        );
        expect(detected, isNotEmpty, reason: '${e.key} – SNR20dB에서 감지 실패');
        final target = e.value;
        final correct = detected.where((f) => (f - target).abs() / target < 0.05).length;
        final ratio = correct / detected.length;
        // ignore: avoid_print
        print('${e.key} SNR20dB: ${(ratio * 100).toStringAsFixed(0)}%'
            ' (${correct}/${detected.length})');
        expect(ratio, greaterThanOrEqualTo(noiseThr[e.key]!),
            reason: '${e.key} – SNR20dB 정답률 부족');
      });
    }
  });

  // ── 배경 소음 SNR 10 dB (시끄러운 환경) ─────────────────────────────────
  group('실제 환경 시뮬레이션 – 배경 소음 SNR 10 dB', () {
    // SNR 10 dB ≈ 시끄러운 카페/스튜디오. 알고리즘 한계를 확인하는 경계 조건.
    final rng = Random(42);
    const snrDb = 10.0;
    const noiseThr = <String, double>{
      'E2 (6현)': 0.35,
      'A2 (5현)': 0.45,
      'D3 (4현)': 0.45,
      'G3 (3현)': 0.40,
      'B3 (2현)': 0.50,
      'E4 (1현)': 0.50,
    };
    for (final e in strings.entries) {
      test(e.key, () async {
        final path = _audioPath(noteFile[e.key]!);
        if (!File(path).existsSync()) { markTestSkipped('파일 없음: $path'); return; }
        final chunks = _chunks(_loadWav(path));
        final detected = await _detectAllPipelineExt(
          detector, chunks,
          preProcess: (c) => _addNoise(c, snrDb, rng),
        );
        if (detected.isEmpty) {
          // ignore: avoid_print
          print('${e.key} SNR10dB: 감지 없음');
          return;
        }
        final target = e.value;
        final correct = detected.where((f) => (f - target).abs() / target < 0.05).length;
        final ratio = correct / detected.length;
        // ignore: avoid_print
        print('${e.key} SNR10dB: ${(ratio * 100).toStringAsFixed(0)}%'
            ' (${correct}/${detected.length})');
        expect(ratio, greaterThanOrEqualTo(noiseThr[e.key]!),
            reason: '${e.key} – SNR10dB 정답률 부족');
      });
    }
  });

  // ── AGC 시뮬레이션 (Android 청크별 자동이득조절) ─────────────────────────
  group('실제 환경 시뮬레이션 – AGC (청크별 RMS 정규화)', () {
    // AGC는 파형 형태를 보존하므로 이상적으로는 정확도가 크게 줄지 않아야 한다.
    // 실패 시: 노이즈 게이트 레벨 기준이 AGC 이후 변해서 문제가 발생함을 의미.
    const agcThr = <String, double>{
      'E2 (6현)': 0.70,
      'A2 (5현)': 0.85,
      'D3 (4현)': 0.85,
      'G3 (3현)': 0.80,
      'B3 (2현)': 0.85,
      'E4 (1현)': 0.85,
    };
    for (final e in strings.entries) {
      test(e.key, () async {
        final path = _audioPath(noteFile[e.key]!);
        if (!File(path).existsSync()) { markTestSkipped('파일 없음: $path'); return; }
        final chunks = _chunks(_loadWav(path));
        final detected = await _detectAllPipelineExt(
          detector, chunks,
          preProcess: _applyAgcChunk,
        );
        expect(detected, isNotEmpty, reason: '${e.key} – AGC 후 감지 실패');
        final target = e.value;
        final correct = detected.where((f) => (f - target).abs() / target < 0.05).length;
        final ratio = correct / detected.length;
        // ignore: avoid_print
        print('${e.key} AGC: ${(ratio * 100).toStringAsFixed(0)}%'
            ' (${correct}/${detected.length})');
        expect(ratio, greaterThanOrEqualTo(agcThr[e.key]!),
            reason: '${e.key} – AGC 후 정답률 부족');
      });
    }
  });

  // ── 샘플레이트 불일치 진단 (48000 Hz 디바이스) ─────────────────────────────
  group('실제 환경 시뮬레이션 – 샘플레이트 불일치 진단 (48000 Hz)', () {
    // 많은 Android 기기는 48000 Hz로 녹음한다.
    // 앱이 44100 Hz로 가정하면 주파수가 +8.8% 높게 계산된다.
    //
    // 이 테스트는 두 가지를 검증한다:
    //   1. 44100 Hz (올바른 가정) → 정확도가 높아야 함
    //   2. 48000 Hz 가정 → 정확도가 현저히 낮아야 함 (≥20%p 차이)
    //      → 불일치 차이가 없다면 알고리즘이 샘플레이트에 무관하게 안정적이라는 의미
    for (final e in strings.entries) {
      test(e.key, () async {
        final path = _audioPath(noteFile[e.key]!);
        if (!File(path).existsSync()) { markTestSkipped('파일 없음: $path'); return; }
        final chunks = _chunks(_loadWav(path));

        final det44k = await _detectAllPipelineExt(detector, chunks, sampleRate: 44100);
        final det48k = await _detectAllPipelineExt(detector, chunks, sampleRate: 48000);

        final target = e.value;
        final acc44 = det44k.isEmpty ? 0.0 :
            det44k.where((f) => (f - target).abs() / target < 0.05).length / det44k.length;
        final acc48 = det48k.isEmpty ? 0.0 :
            det48k.where((f) => (f - target).abs() / target < 0.05).length / det48k.length;
        final med48 = det48k.isEmpty ? 0.0 : _median(det48k);

        // ignore: avoid_print
        print('${e.key}: 44.1kHz=${(acc44 * 100).toStringAsFixed(0)}%  '
            '48kHz=${(acc48 * 100).toStringAsFixed(0)}%  '
            '48kHz중앙값=${med48.toStringAsFixed(1)} Hz'
            ' (기대: ${target.toStringAsFixed(1)} Hz)');

        // 올바른 44100 Hz 가정은 정확해야 함
        expect(acc44, greaterThanOrEqualTo(0.70),
            reason: '${e.key} – 44.1kHz 기준이 이미 부정확함');
        // 48kHz 불일치 시 정확도가 확연히 낮아야 함 (문제 재현)
        expect(acc48, lessThan(acc44 - 0.20),
            reason: '${e.key} – 48kHz 불일치 효과가 미미함'
                ' (실제 디바이스가 44.1kHz를 제대로 지원하거나, 알고리즘이 샘플레이트에 둔감)');
      });
    }
  });

  // ── 어택 구간 (첫 5청크 ≈ 460 ms) ────────────────────────────────────────
  group('실제 환경 시뮬레이션 – 어택 구간 (첫 5청크 ≈ 460 ms)', () {
    // 실제 앱에서 사용자가 줄을 퉁기자마자 표시되는 결과가 이 구간이다.
    // 어택 구간은 피치가 불안정하므로 기준을 낮게 설정한다.
    const attackThr = <String, double>{
      'E2 (6현)': 0.30,
      'A2 (5현)': 0.50,
      'D3 (4현)': 0.50,
      'G3 (3현)': 0.40,
      'B3 (2현)': 0.55,
      'E4 (1현)': 0.55,
    };
    for (final e in strings.entries) {
      test(e.key, () async {
        final path = _audioPath(noteFile[e.key]!);
        if (!File(path).existsSync()) { markTestSkipped('파일 없음: $path'); return; }
        final allChunks = _chunks(_loadWav(path));
        final attackChunks = allChunks.take(5).toList();

        final detected = await _detectAllPipelineExt(detector, attackChunks);
        if (detected.isEmpty) {
          // ignore: avoid_print
          print('${e.key} 어택: 감지 없음 (5청크 모두 무신호 또는 미감지)');
          return;
        }
        final target = e.value;
        final correct = detected.where((f) => (f - target).abs() / target < 0.05).length;
        final ratio = correct / detected.length;
        // ignore: avoid_print
        print('${e.key} 어택5청크: ${(ratio * 100).toStringAsFixed(0)}%'
            ' (${correct}/${detected.length})'
            ' 중앙값=${_median(detected).toStringAsFixed(1)} Hz');
        expect(ratio, greaterThanOrEqualTo(attackThr[e.key]!),
            reason: '${e.key} – 어택 구간 정답률 부족');
      });
    }
  });

  // ── 합성 기타 신호 – 실제 하모닉 + 비조화성 ─────────────────────────────
  //
  // tonejs-instruments WAV보다 실제 기타에 훨씬 가까운 하모닉 구조.
  // 저음 현(E2~G3)은 2배음이 기음만큼 강하고, 비조화성으로 배음 주파수가
  // 정수 배보다 살짝 높다 (실제 현 물리학).
  //
  // 이 테스트 실패 시:
  //   → YIN의 first-dip이 강한 2배음을 기음으로 오탐하고 있음.
  //   → octave correction 조건이 실제 기타 신호를 커버하지 못함.
  group('합성 기타 신호 – 실제 하모닉 + 비조화성', () {
    // 각 현의 실측 기반 하모닉 진폭 비율.
    // 저음 현일수록 2배음이 강하고, 고음 현은 기음이 지배적.
    const harmonics = <String, List<double>>{
      'E2 (6현)': [1.0, 0.85, 0.65, 0.50, 0.38, 0.28, 0.20, 0.14],
      'A2 (5현)': [1.0, 0.75, 0.55, 0.40, 0.28, 0.20, 0.14],
      'D3 (4현)': [1.0, 0.65, 0.45, 0.30, 0.20, 0.14],
      'G3 (3현)': [1.0, 0.55, 0.35, 0.22, 0.14],
      'B3 (2현)': [1.0, 0.45, 0.28, 0.16, 0.10],
      'E4 (1현)': [1.0, 0.38, 0.22, 0.12, 0.07],
    };
    // 비조화성 계수 B (저음 현이 클수록 높음).
    const inharmonicity = <String, double>{
      'E2 (6현)': 0.0008,
      'A2 (5현)': 0.0006,
      'D3 (4현)': 0.0004,
      'G3 (3현)': 0.0003,
      'B3 (2현)': 0.0002,
      'E4 (1현)': 0.0001,
    };

    for (final e in strings.entries) {
      test(e.key, () async {
        final synth = _synthesizeGuitar(
          e.value,
          harmonicAmps: harmonics[e.key]!,
          inharmonicity: inharmonicity[e.key]!,
        );
        final chunks = _chunks(synth);
        final detected = await _detectAllPipelineExt(detector, chunks);

        if (detected.isEmpty) {
          fail('${e.key} – 합성 신호에서 감지 없음');
        }
        final target = e.value;
        final correct =
            detected.where((f) => (f - target).abs() / target < 0.05).length;
        final ratio = correct / detected.length;
        final med = _median(detected);
        // ignore: avoid_print
        print('${e.key} 합성: ${(ratio * 100).toStringAsFixed(0)}%'
            ' (${correct}/${detected.length})'
            ' 중앙값=${med.toStringAsFixed(1)} Hz'
            ' (기대: ${target.toStringAsFixed(1)} Hz)');
        expect(
          ratio,
          greaterThanOrEqualTo(0.80),
          reason: '${e.key} – 실제 하모닉 구조에서 정답률 부족. '
              '2배음 오탐 가능성: 중앙값=${med.toStringAsFixed(1)} Hz',
        );
      });
    }
  });

  // ── 실제 연주 시나리오 시뮬레이션 ───────────────────────────────────────
  group('실제 연주 시나리오 – 2배음 우세 (강한 발현)', () {
    // 강한 발현(픽 스트로크) 또는 특정 마이크 위치에서 2배음이 기음보다 강해짐.
    // tonejs-instruments 샘플엔 없는 조건.
    // 실패 시: octave correction이 이 케이스를 커버하지 못함.
    const dominantHarmonics = <String, List<double>>{
      'E2 (6현)': [1.0, 1.30, 0.80, 0.55, 0.40, 0.28],
      'A2 (5현)': [1.0, 1.20, 0.70, 0.45, 0.30, 0.20],
      'D3 (4현)': [1.0, 1.10, 0.60, 0.38, 0.24],
      'G3 (3현)': [1.0, 1.05, 0.50, 0.30, 0.18],
      'B3 (2현)': [1.0, 0.90, 0.45, 0.25],
      'E4 (1현)': [1.0, 0.75, 0.35, 0.18],
    };
    const inharmonicity = <String, double>{
      'E2 (6현)': 0.0008, 'A2 (5현)': 0.0006, 'D3 (4현)': 0.0004,
      'G3 (3현)': 0.0003, 'B3 (2현)': 0.0002, 'E4 (1현)': 0.0001,
    };
    for (final e in strings.entries) {
      test(e.key, () async {
        final synth = _synthesizeGuitar(
          e.value,
          harmonicAmps: dominantHarmonics[e.key]!,
          inharmonicity: inharmonicity[e.key]!,
        );
        final detected = await _detectAllPipelineExt(detector, _chunks(synth));
        if (detected.isEmpty) { fail('${e.key} – 2배음 우세 신호에서 감지 없음'); }
        final target = e.value;
        final correct =
            detected.where((f) => (f - target).abs() / target < 0.05).length;
        final ratio = correct / detected.length;
        // ignore: avoid_print
        print('${e.key} 2배음우세: ${(ratio * 100).toStringAsFixed(0)}%'
            ' 중앙값=${_median(detected).toStringAsFixed(1)} Hz'
            ' (기대: ${target.toStringAsFixed(1)} Hz)');
        expect(ratio, greaterThanOrEqualTo(0.80),
            reason: '${e.key} – 2배음 우세 조건에서 octave correction 실패');
      });
    }
  });

  group('실제 연주 시나리오 – 공명 현 간섭 (sympathetic resonance)', () {
    // 목표 현을 튕기면 다른 현도 공명한다. 혼합 신호에서 기음을 정확히 찾아야 함.
    for (final e in strings.entries) {
      test(e.key, () async {
        final target = e.value;
        // 목표 현 합성
        final main = _synthesizeGuitar(target, durationSec: 1.5,
            harmonicAmps: const [1.0, 0.7, 0.5, 0.35, 0.25]);
        // 다른 현들이 10% 진폭으로 공명 (빠르게 감쇄)
        final resonant = strings.values
            .where((f) => (f - target).abs() / target > 0.05)
            .toList();
        final n = main.length;
        final signal = [...main];
        for (final rf in resonant) {
          for (var i = 0; i < n; i++) {
            final t = i / _sampleRate;
            signal[i] += 0.10 * exp(-8.0 * t) * sin(2 * pi * rf * t);
          }
        }
        final maxAmp = signal.map((s) => s.abs()).reduce(max);
        final normalized = signal.map((s) => s / maxAmp * 0.9).toList();

        final detected =
            await _detectAllPipelineExt(detector, _chunks(normalized));
        if (detected.isEmpty) { fail('${e.key} – 공명 간섭 신호에서 감지 없음'); }
        final correct =
            detected.where((f) => (f - target).abs() / target < 0.05).length;
        final ratio = correct / detected.length;
        // ignore: avoid_print
        print('${e.key} 공명간섭: ${(ratio * 100).toStringAsFixed(0)}%'
            ' 중앙값=${_median(detected).toStringAsFixed(1)} Hz');
        expect(ratio, greaterThanOrEqualTo(0.80),
            reason: '${e.key} – 공명 현 간섭 조건에서 정답률 부족');
      });
    }
  });

  group('실제 연주 시나리오 – 약한 발현 (진폭 5배 감쇄)', () {
    // 소프트 피킹이나 핑거피킹 시 진폭이 낮아진다.
    // 노이즈 게이트 경계 근처에서의 감지 안정성을 검증.
    for (final e in strings.entries) {
      test(e.key, () async {
        final full = _synthesizeGuitar(e.value,
            harmonicAmps: const [1.0, 0.7, 0.5, 0.35, 0.25, 0.18]);
        // 진폭 5배 감쇄 → 피크 ≈ 0.18, RMS ≈ 0.06 (노이즈 게이트 0.01 이상)
        final soft = full.map((s) => s / 5.0).toList();
        final detected = await _detectAllPipelineExt(detector, _chunks(soft));
        if (detected.isEmpty) {
          // ignore: avoid_print
          print('${e.key} 약발현: 감지 없음 (노이즈 게이트 이하)');
          return;
        }
        final target = e.value;
        final correct =
            detected.where((f) => (f - target).abs() / target < 0.05).length;
        final ratio = correct / detected.length;
        // ignore: avoid_print
        print('${e.key} 약발현: ${(ratio * 100).toStringAsFixed(0)}%'
            ' (${correct}/${detected.length})');
        expect(ratio, greaterThanOrEqualTo(0.80),
            reason: '${e.key} – 약한 발현에서 정답률 부족');
      });
    }
  });

  // ── B3 공명 간섭 실패 원인 진단 ──────────────────────────────────────────
  group('B3 공명 간섭 – 오탐 주파수 & 간섭 레벨 민감도', () {
    test('오탐 주파수 분포 및 레벨별 정확도', () async {
      const target = 246.94; // B3
      // ignore: avoid_print
      print('\n─── B3 공명 간섭 레벨별 정확도 ───');

      for (final level in [0.02, 0.05, 0.08, 0.10, 0.15]) {
        final main = _synthesizeGuitar(target, durationSec: 1.5,
            harmonicAmps: const [1.0, 0.7, 0.5, 0.35, 0.25]);
        final n = main.length;
        final signal = [...main];
        // E4 (329.63 Hz) 만 집중 분석
        for (var i = 0; i < n; i++) {
          final t = i / _sampleRate;
          signal[i] += level * exp(-8.0 * t) * sin(2 * pi * 329.63 * t);
        }
        final maxAmp = signal.map((s) => s.abs()).reduce(max);
        final normalized = signal.map((s) => s / maxAmp * 0.9).toList();
        final detected =
            await _detectAllPipelineExt(detector, _chunks(normalized));
        final correct =
            detected.where((f) => (f - target).abs() / target < 0.05).length;
        final wrong = detected.where((f) => (f - target).abs() / target >= 0.05).toList();
        final ratio = detected.isEmpty ? 0.0 : correct / detected.length;
        // 오탐 주파수 버킷
        final buckets = <int, int>{};
        for (final f in wrong) {
          final b = (f / 10).round() * 10;
          buckets[b] = (buckets[b] ?? 0) + 1;
        }
        final topBuckets = (buckets.entries.toList()
            ..sort((a, b) => b.value - a.value))
            .take(3)
            .map((e) => '~${e.key}Hz:${e.value}')
            .join(', ');
        // ignore: avoid_print
        print('  E4 공명 ${(level * 100).toStringAsFixed(0)}%:'
            ' 정답률=${(ratio * 100).toStringAsFixed(0)}%'
            ' (${correct}/${detected.length})'
            ' 오탐=${topBuckets.isEmpty ? "없음" : topBuckets}');
      }
    });

    test('B3 + E4 공명 CMNDF 분석 (tau=134 vs tau=179)', () {
      const target = 246.94;
      const e4Freq = 329.63;
      // ignore: avoid_print
      print('\n─── B3+E4 공명 CMNDF tau 비교 ───');
      const tauB3 = 179; // 44100/246.94 ≈ 179
      const tauE4 = 134; // 44100/329.63 ≈ 134
      for (final level in [0.0, 0.05, 0.10]) {
        final n = _bufSize;
        final signal = List<double>.filled(n, 0.0);
        for (var i = 0; i < n; i++) {
          final t = i / _sampleRate;
          signal[i] = sin(2 * pi * target * t)
              + 0.7 * sin(2 * pi * target * 2 * t)
              + 0.5 * sin(2 * pi * target * 3 * t);
          if (level > 0) {
            signal[i] += level * sin(2 * pi * e4Freq * t);
          }
        }
        final c = computeCmndf(signal);
        // ignore: avoid_print
        print('  E4 ${(level * 100).toStringAsFixed(0)}%:'
            ' CMNDF[${tauE4}]=${c[tauE4].toStringAsFixed(4)}'
            ' CMNDF[${tauB3}]=${c[tauB3].toStringAsFixed(4)}'
            ' → first-dip=${c[tauE4] < c[tauB3] ? "E4(오탐)" : "B3(정탐)"}');
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
