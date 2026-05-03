// 실제 기타 어쿠스틱 WAV 샘플로 PitchDetector 검증.
//
// 샘플 출처: github.com/nbrosowsky/tonejs-instruments (MIT)
// 포맷: PCM16, 44100 Hz, mono
//
// 파일 준비:
//   test/audio/{E2,A2,D3,G3,B3,E4}.wav
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
const _smoothingFrames = 5;       // AudioPipeline._smoothingFrames

// 표준 튜닝 6현 후보 (auto-detect 모드 시뮬레이션 = 실제 사용자 기본 모드)
const _allStrings = <double>[82.41, 110.00, 146.83, 196.00, 246.94, 329.63];

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

/// 실제 오디오 파이프라인을 재현:
///   AudioPipeline: detect() → 5-frame median 스무딩
///   TunerNotifier: 노이즈 게이트(RMS < 0.01) 적용
/// 사용자에게 실제로 표시되는 주파수 목록을 반환.
Future<List<double>> _detectAllPipeline(
  PitchDetector detector,
  List<List<double>> chunks, {
  List<double> candidates = _allStrings,
  List<double> Function(List<double>)? preProcess,
  int sampleRate = _sampleRate,
}) async {
  final freqBuffer = <double>[];
  final results = <double>[];
  for (final raw in chunks) {
    final chunk = preProcess != null ? preProcess(raw) : raw;
    final signalLevel = _rmsCalc(chunk);
    final rawFreq = await detector.detect(
      chunk,
      candidates: candidates,
      sampleRate: sampleRate,
    );
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

String _audioPath(String note) => 'test/audio/$note.wav';

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
  return [
    for (final s in samples) (s + _gaussian(rng) * noiseAmp).clamp(-1.0, 1.0)
  ];
}

/// 청크 단위 RMS 정규화 (Android AGC 시뮬레이션).
List<double> _applyAgcChunk(List<double> chunk, {double targetRms = 0.1}) {
  final rms = _rmsCalc(chunk);
  if (rms < 1e-6) return chunk;
  final gain = (targetRms / rms).clamp(0.0, 10.0);
  return [for (final s in chunk) (s * gain).clamp(-1.0, 1.0)];
}

/// 기타 현의 물리적 특성을 반영한 합성 신호.
///
/// - 비조화성: f_h = f0 × h × √(1 + B×h²)
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

  // target-aware 알고리즘 정답률 임계값.
  // 정상 환경: 모든 음 90%+ (옛 알고리즘 대비 E2 75%→96%, G3/D3 옥타브 다운 사고 0).
  // E2 는 tonejs 샘플 특성상 fundamental 이 약한 청크가 일부 있음.
  const accuracyThreshold = 0.90;

  // ── 기본: 실제 WAV 파일 정답률 ──────────────────────────────────────────
  group('실제 WAV – 정답률 ±5% (auto-detect 모드)', () {
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

        expect(detected, isNotEmpty, reason: '${e.key} – 한 청크도 감지 못함');

        final target = e.value;
        final correct =
            detected.where((f) => (f - target).abs() / target < 0.05).length;
        final correctRatio = correct / detected.length;
        // ignore: avoid_print
        print('  ±5% 이내 정답 비율: '
            '$correct/${detected.length} '
            '(${(correctRatio * 100).toStringAsFixed(0)}%) '
            '기준: ${(accuracyThreshold * 100).toStringAsFixed(0)}%');

        expect(correctRatio, greaterThanOrEqualTo(accuracyThreshold),
            reason: '${e.key} – 정답률 ${(correctRatio * 100).toStringAsFixed(0)}% '
                '< 기준 ${(accuracyThreshold * 100).toStringAsFixed(0)}%');
      });
    }
  });

  // ── 중앙값 정밀도 ──────────────────────────────────────────────────────
  group('실제 WAV – 중앙값 정밀도 (±2%)', () {
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

        if (detected.isEmpty) fail('${e.key} – 감지 결과 없음');

        final med = _median(detected);
        final target = e.value;
        final errorPct = (med - target).abs() / target * 100;

        // ignore: avoid_print
        print('${e.key}: 중앙값=${med.toStringAsFixed(2)} Hz, '
            '오차=${errorPct.toStringAsFixed(2)}%');

        expect(errorPct, lessThan(2.0),
            reason: '${e.key} 중앙값 ${med.toStringAsFixed(2)} Hz, '
                '기대 $target Hz, 오차 ${errorPct.toStringAsFixed(2)}%');
      });
    }
  });

  // ── 단일 후보(수동 모드) 실제 WAV 검증 ────────────────────────────────
  group('실제 WAV – 단일 후보(수동 튜닝 모드)', () {
    for (final e in strings.entries) {
      test(e.key, () async {
        final path = _audioPath(noteFile[e.key]!);
        if (!File(path).existsSync()) {
          markTestSkipped('파일 없음: $path');
          return;
        }
        final samples = _loadWav(path);
        final chunks = _chunks(samples);
        final detected = await _detectAllPipeline(detector, chunks,
            candidates: [e.value]);
        expect(detected, isNotEmpty);
        final target = e.value;
        final correct =
            detected.where((f) => (f - target).abs() / target < 0.05).length;
        final ratio = correct / detected.length;
        // ignore: avoid_print
        print('${e.key} 단일후보: ${(ratio * 100).toStringAsFixed(0)}% '
            '($correct/${detected.length})');
        expect(ratio, greaterThanOrEqualTo(accuracyThreshold));
      });
    }
  });

  // ── 배경 소음 SNR 20 dB (조용한 실내) ────────────────────────────────
  group('실제 환경 시뮬레이션 – SNR 20 dB', () {
    final rng = Random(42);
    const snrDb = 20.0;
    // 노이즈 환경에서 E2 fundamental detection 한계 — 보수적 기준
    const thr = <String, double>{
      'E2 (6현)': 0.55, 'A2 (5현)': 0.85, 'D3 (4현)': 0.85,
      'G3 (3현)': 0.85, 'B3 (2현)': 0.85, 'E4 (1현)': 0.85,
    };
    for (final e in strings.entries) {
      test(e.key, () async {
        final path = _audioPath(noteFile[e.key]!);
        if (!File(path).existsSync()) {
          markTestSkipped('파일 없음: $path');
          return;
        }
        final chunks = _chunks(_loadWav(path));
        final detected = await _detectAllPipeline(
          detector, chunks,
          preProcess: (c) => _addNoise(c, snrDb, rng),
        );
        expect(detected, isNotEmpty, reason: '${e.key} – SNR20dB에서 감지 실패');
        final target = e.value;
        final correct =
            detected.where((f) => (f - target).abs() / target < 0.05).length;
        final ratio = correct / detected.length;
        // ignore: avoid_print
        print('${e.key} SNR20dB: ${(ratio * 100).toStringAsFixed(0)}% '
            '($correct/${detected.length})');
        expect(ratio, greaterThanOrEqualTo(thr[e.key]!),
            reason: '${e.key} – SNR20dB 정답률 부족');
      });
    }
  });

  // ── 배경 소음 SNR 10 dB (시끄러운 환경) ─────────────────────────────
  group('실제 환경 시뮬레이션 – SNR 10 dB', () {
    final rng = Random(42);
    const snrDb = 10.0;
    // 매우 시끄러운 환경 한계 — 매우 보수적 기준
    const thr = <String, double>{
      'E2 (6현)': 0.30, 'A2 (5현)': 0.45, 'D3 (4현)': 0.45,
      'G3 (3현)': 0.40, 'B3 (2현)': 0.50, 'E4 (1현)': 0.50,
    };
    for (final e in strings.entries) {
      test(e.key, () async {
        final path = _audioPath(noteFile[e.key]!);
        if (!File(path).existsSync()) {
          markTestSkipped('파일 없음: $path');
          return;
        }
        final chunks = _chunks(_loadWav(path));
        final detected = await _detectAllPipeline(
          detector, chunks,
          preProcess: (c) => _addNoise(c, snrDb, rng),
        );
        if (detected.isEmpty) {
          // ignore: avoid_print
          print('${e.key} SNR10dB: 감지 없음');
          return;
        }
        final target = e.value;
        final correct =
            detected.where((f) => (f - target).abs() / target < 0.05).length;
        final ratio = correct / detected.length;
        // ignore: avoid_print
        print('${e.key} SNR10dB: ${(ratio * 100).toStringAsFixed(0)}% '
            '($correct/${detected.length})');
        expect(ratio, greaterThanOrEqualTo(thr[e.key]!),
            reason: '${e.key} – SNR10dB 정답률 부족');
      });
    }
  });

  // ── AGC 시뮬레이션 (Android 청크별 자동이득조절) ──────────────────────
  group('실제 환경 시뮬레이션 – AGC', () {
    // AGC 청크별 진폭 정규화로 인한 경계 artifact — E2 약 fundamental 영향
    const thr = <String, double>{
      'E2 (6현)': 0.65, 'A2 (5현)': 0.90, 'D3 (4현)': 0.90,
      'G3 (3현)': 0.90, 'B3 (2현)': 0.90, 'E4 (1현)': 0.90,
    };
    for (final e in strings.entries) {
      test(e.key, () async {
        final path = _audioPath(noteFile[e.key]!);
        if (!File(path).existsSync()) {
          markTestSkipped('파일 없음: $path');
          return;
        }
        final chunks = _chunks(_loadWav(path));
        final detected = await _detectAllPipeline(
          detector, chunks,
          preProcess: _applyAgcChunk,
        );
        expect(detected, isNotEmpty, reason: '${e.key} – AGC 후 감지 실패');
        final target = e.value;
        final correct =
            detected.where((f) => (f - target).abs() / target < 0.05).length;
        final ratio = correct / detected.length;
        // ignore: avoid_print
        print('${e.key} AGC: ${(ratio * 100).toStringAsFixed(0)}% '
            '($correct/${detected.length})');
        expect(ratio, greaterThanOrEqualTo(thr[e.key]!),
            reason: '${e.key} – AGC 후 정답률 부족');
      });
    }
  });

  // ── 샘플레이트 불일치 (48000 Hz 가정) ──────────────────────────────
  group('실제 환경 시뮬레이션 – 샘플레이트 불일치 (48000 Hz)', () {
    // 48 kHz 가정으로 44.1 kHz 데이터를 분석하면 주파수가 +8.8% 높게 계산되어야 함.
    // 알고리즘이 샘플레이트에 무관하게 동작한다면 이 차이가 미미할 것.
    for (final e in strings.entries) {
      test(e.key, () async {
        final path = _audioPath(noteFile[e.key]!);
        if (!File(path).existsSync()) {
          markTestSkipped('파일 없음: $path');
          return;
        }
        final chunks = _chunks(_loadWav(path));

        final det44k =
            await _detectAllPipeline(detector, chunks, sampleRate: 44100);
        final det48k =
            await _detectAllPipeline(detector, chunks, sampleRate: 48000);

        final target = e.value;
        final acc44 = det44k.isEmpty
            ? 0.0
            : det44k.where((f) => (f - target).abs() / target < 0.05).length /
                det44k.length;
        final acc48 = det48k.isEmpty
            ? 0.0
            : det48k.where((f) => (f - target).abs() / target < 0.05).length /
                det48k.length;
        final med48 = det48k.isEmpty ? 0.0 : _median(det48k);

        // ignore: avoid_print
        print('${e.key}: 44.1kHz=${(acc44 * 100).toStringAsFixed(0)}%  '
            '48kHz=${(acc48 * 100).toStringAsFixed(0)}%  '
            '48kHz중앙값=${med48.toStringAsFixed(1)} Hz '
            '(기대: ${target.toStringAsFixed(1)} Hz)');

        expect(acc44, greaterThanOrEqualTo(0.90),
            reason: '${e.key} – 44.1kHz 기준이 부정확함');
        expect(acc48, lessThan(acc44 - 0.20),
            reason: '${e.key} – 48kHz 불일치 효과가 미미함');
      });
    }
  });

  // ── 어택 구간 (첫 5청크 ≈ 460 ms) ─────────────────────────────────
  group('실제 환경 시뮬레이션 – 어택 구간 (첫 5청크)', () {
    // 어택 구간은 피치가 불안정하므로 기준은 보수적.
    const thr = 0.50;
    for (final e in strings.entries) {
      test(e.key, () async {
        final path = _audioPath(noteFile[e.key]!);
        if (!File(path).existsSync()) {
          markTestSkipped('파일 없음: $path');
          return;
        }
        final allChunks = _chunks(_loadWav(path));
        final attackChunks = allChunks.take(5).toList();

        final detected = await _detectAllPipeline(detector, attackChunks);
        if (detected.isEmpty) {
          // ignore: avoid_print
          print('${e.key} 어택: 감지 없음');
          return;
        }
        final target = e.value;
        final correct =
            detected.where((f) => (f - target).abs() / target < 0.05).length;
        final ratio = correct / detected.length;
        // ignore: avoid_print
        print('${e.key} 어택5청크: ${(ratio * 100).toStringAsFixed(0)}% '
            '($correct/${detected.length}) '
            '중앙값=${_median(detected).toStringAsFixed(1)} Hz');
        expect(ratio, greaterThanOrEqualTo(thr),
            reason: '${e.key} – 어택 구간 정답률 부족');
      });
    }
  });

  // ── 합성 기타 신호 – 실제 하모닉 + 비조화성 ────────────────────────
  group('합성 기타 신호 – 정상 하모닉 + 비조화성', () {
    const harmonics = <String, List<double>>{
      'E2 (6현)': [1.0, 0.85, 0.65, 0.50, 0.38, 0.28, 0.20, 0.14],
      'A2 (5현)': [1.0, 0.75, 0.55, 0.40, 0.28, 0.20, 0.14],
      'D3 (4현)': [1.0, 0.65, 0.45, 0.30, 0.20, 0.14],
      'G3 (3현)': [1.0, 0.55, 0.35, 0.22, 0.14],
      'B3 (2현)': [1.0, 0.45, 0.28, 0.16, 0.10],
      'E4 (1현)': [1.0, 0.38, 0.22, 0.12, 0.07],
    };
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
        final detected =
            await _detectAllPipeline(detector, _chunks(synth));
        if (detected.isEmpty) fail('${e.key} – 합성 신호에서 감지 없음');
        final target = e.value;
        final correct =
            detected.where((f) => (f - target).abs() / target < 0.05).length;
        final ratio = correct / detected.length;
        final med = _median(detected);
        // ignore: avoid_print
        print('${e.key} 합성: ${(ratio * 100).toStringAsFixed(0)}% '
            '($correct/${detected.length}) '
            '중앙값=${med.toStringAsFixed(1)} Hz '
            '(기대: ${target.toStringAsFixed(1)} Hz)');
        expect(ratio, greaterThanOrEqualTo(0.95),
            reason: '${e.key} – 합성 신호 정답률 부족');
      });
    }
  });

  // ── 2배음 우세 (강한 발현 / 픽 스트로크) ───────────────────────────
  group('실제 연주 시나리오 – 2배음 우세', () {
    // 2배음이 기음만큼 또는 더 강한 케이스 — 옛 알고리즘에서 옥타브 에러 유발.
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
        final detected = await _detectAllPipeline(detector, _chunks(synth));
        if (detected.isEmpty) fail('${e.key} – 2배음 우세 신호에서 감지 없음');
        final target = e.value;
        final correct =
            detected.where((f) => (f - target).abs() / target < 0.05).length;
        final ratio = correct / detected.length;
        // ignore: avoid_print
        print('${e.key} 2배음우세: ${(ratio * 100).toStringAsFixed(0)}% '
            '중앙값=${_median(detected).toStringAsFixed(1)} Hz '
            '(기대: ${target.toStringAsFixed(1)} Hz)');
        expect(ratio, greaterThanOrEqualTo(0.95),
            reason: '${e.key} – 2배음 우세 조건에서 옥타브 에러 발생 의심');
      });
    }
  });

  // ── 공명 현 간섭 (sympathetic resonance) ─────────────────────────
  group('실제 연주 시나리오 – 공명 현 간섭', () {
    for (final e in strings.entries) {
      test(e.key, () async {
        final target = e.value;
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
            await _detectAllPipeline(detector, _chunks(normalized));
        if (detected.isEmpty) fail('${e.key} – 공명 간섭 신호에서 감지 없음');
        final correct =
            detected.where((f) => (f - target).abs() / target < 0.05).length;
        final ratio = correct / detected.length;
        // ignore: avoid_print
        print('${e.key} 공명간섭: ${(ratio * 100).toStringAsFixed(0)}% '
            '중앙값=${_median(detected).toStringAsFixed(1)} Hz');
        expect(ratio, greaterThanOrEqualTo(0.80),
            reason: '${e.key} – 공명 현 간섭 조건에서 정답률 부족');
      });
    }
  });

  // ── 약한 발현 (진폭 5배 감쇄) ──────────────────────────────────
  group('실제 연주 시나리오 – 약한 발현', () {
    for (final e in strings.entries) {
      test(e.key, () async {
        final full = _synthesizeGuitar(e.value,
            harmonicAmps: const [1.0, 0.7, 0.5, 0.35, 0.25, 0.18]);
        final soft = full.map((s) => s / 5.0).toList();
        final detected = await _detectAllPipeline(detector, _chunks(soft));
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
        print('${e.key} 약발현: ${(ratio * 100).toStringAsFixed(0)}% '
            '($correct/${detected.length})');
        expect(ratio, greaterThanOrEqualTo(0.90),
            reason: '${e.key} – 약한 발현에서 정답률 부족');
      });
    }
  });

  // ── 청크별 분포 요약 (가독성 출력) ───────────────────────────────
  group('실제 WAV – 청크별 분포 요약', () {
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
          print('║  ${e.key.padRight(8)} 파일 없음                         ║');
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
        final correct =
            detected.where((f) => (f - target).abs() / target < 0.05).length;
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
