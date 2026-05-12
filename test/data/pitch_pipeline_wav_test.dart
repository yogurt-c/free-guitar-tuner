// Production YinEstimator + PitchTracker 를 직접 호출해 실제 WAV 청크 시계열을
// 흘리고 TrackerState 시계열을 검증한다.
//
// **3개 소스로 검증:**
//   1. test/audio/synth/   — Dart 합성 (반복 pluck + ADSR + inharmonicity).
//      실 튜너 사용 패턴에 가장 가까움. nominal + 디튠 변형까지 검증.
//      LOCKED 비율 80%+ 기대.
//   2. test/audio/real/    — Iowa MIS 실 어쿠스틱 기타 녹음 (CC public domain).
//      단일 pluck 의 attack/감쇠 정확성 검증. 짧은 sustain 으로 LOCKED 비율 낮음 —
//      "signal 위 청크" 대비 LOCK 효율로 평가.
//   3. test/audio/transient/ — 옛 tonejs WAV. 회귀 baseline.
//
// 포맷: PCM16, 44100 Hz, mono.

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:guitar_tuner/data/pitch_tracker.dart';
import 'package:guitar_tuner/data/yin_estimator.dart';
import 'package:guitar_tuner/domain/model/tracker_state.dart';

// AudioPipeline 의 sliding window 와 동일한 파라미터.
const _windowSize = 4096;
const _hopSize = 1024;
const _sampleRate = 44100;

const _stdStrings = <double>[
  82.41, // E2
  110.00, // A2
  146.83, // D3
  196.00, // G3
  246.94, // B3
  329.63, // E4
];

/// standard preset search range: fmin -200c ~ fmax +200c.
/// fmin = 82.41 / 1.1224 ≈ 73.45 Hz → tauMax ≈ 600
/// fmax = 329.63 × 1.1224 ≈ 369.99 Hz → tauMin ≈ 119
const _tauMin = 119;
const _tauMax = 600;

List<double> _loadWav(String path) {
  final bytes = File(path).readAsBytesSync();
  final data = ByteData.sublistView(bytes);
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

/// AudioPipeline 의 sliding window 와 동일 — 4096 윈도우, 1024 hop (75% overlap).
List<List<double>> _chunks(List<double> samples) {
  final result = <List<double>>[];
  for (var i = 0; i + _windowSize <= samples.length; i += _hopSize) {
    result.add(samples.sublist(i, i + _windowSize));
  }
  return result;
}

double _rms(List<double> samples) {
  if (samples.isEmpty) return 0.0;
  var sum = 0.0;
  for (final s in samples) {
    sum += s * s;
  }
  return sqrt(sum / samples.length);
}

typedef _Result = ({
  int totalChunks,
  int aboveGate,
  int locked,
  int wrong,
  double medianFreq,
});

Future<_Result> _runPipeline(
  YinEstimator estimator,
  List<List<double>> chunks,
  int expectedIdx,
) async {
  final tracker = PitchTracker()
    ..setStrings(_stdStrings)
    ..setAutoDetect(true);
  var aboveGate = 0, locked = 0, wrong = 0;
  final freqs = <double>[];
  for (final chunk in chunks) {
    final rms = _rms(chunk);
    if (rms >= PitchTracker.noiseGateExit) aboveGate++;
    final est = await estimator.estimate(
      chunk,
      tauMin: _tauMin,
      tauMax: _tauMax,
      sampleRate: _sampleRate,
    );
    final state = tracker.update(est, signalLevel: rms);
    if (state is TrackerLocked) {
      locked++;
      freqs.add(state.detectedFreq);
      if (state.stringIndex != expectedIdx) wrong++;
    }
  }
  freqs.sort();
  return (
    totalChunks: chunks.length,
    aboveGate: aboveGate,
    locked: locked,
    wrong: wrong,
    medianFreq: freqs.isEmpty ? 0.0 : freqs[freqs.length ~/ 2],
  );
}

const _strings = <String, ({int idx, double freq})>{
  'E2': (idx: 0, freq: 82.41),
  'A2': (idx: 1, freq: 110.00),
  'D3': (idx: 2, freq: 146.83),
  'G3': (idx: 3, freq: 196.00),
  'B3': (idx: 4, freq: 246.94),
  'E4': (idx: 5, freq: 329.63),
};

void main() {
  late YinEstimator estimator;
  setUpAll(() => estimator = YinEstimator());
  tearDownAll(() async => estimator.dispose());

  // ── 1. 합성 WAV — 반복 pluck 시나리오 ────────────────────────────────────
  group('synth — 반복 pluck (실 사용 모델)', () {
    const minLockedRatio = 0.80;
    const maxFreqErrPct = 1.0; // ±1% ≈ ±17 cents (inharmonicity 포함)
    const scenarios = <String, int>{
      'nominal': 0,
      'flat40': -40,
      'sharp30': 30,
    };

    for (final s in _strings.entries) {
      for (final sc in scenarios.entries) {
        test('${s.key} ${sc.key}', () async {
          final path = 'test/audio/synth/${s.key}_${sc.key}.wav';
          if (!File(path).existsSync()) {
            markTestSkipped('파일 없음: $path');
            return;
          }
          final chunks = _chunks(_loadWav(path));
          final r = await _runPipeline(estimator, chunks, s.value.idx);

          final lockedRatio = r.locked / r.totalChunks;
          final wrongRatio = r.wrong / r.totalChunks;
          final expected = s.value.freq * pow(2.0, sc.value / 1200.0);
          final freqErrPct = r.medianFreq > 0
              ? (r.medianFreq - expected).abs() / expected * 100
              : double.infinity;

          expect(lockedRatio, greaterThanOrEqualTo(minLockedRatio),
              reason:
                  '${s.key} ${sc.key}: LOCKED ${(lockedRatio * 100).toStringAsFixed(0)}% < ${(minLockedRatio * 100).toInt()}%');
          expect(wrongRatio, lessThan(0.05),
              reason:
                  '${s.key} ${sc.key}: 잘못된 LOCK ${(wrongRatio * 100).toStringAsFixed(1)}%');
          expect(freqErrPct, lessThan(maxFreqErrPct),
              reason:
                  '${s.key} ${sc.key}: freq 오차 ${freqErrPct.toStringAsFixed(2)}%');
        });
      }
    }

    test('전 시나리오 요약', () async {
      // ignore: avoid_print
      print('\n╔══════════════════════════════════════════════════════════════════╗');
      // ignore: avoid_print
      print('║  현+시나리오  expectedHz  LOCKED%  wrong  detectedHz  err%   ║');
      // ignore: avoid_print
      print('╠══════════════════════════════════════════════════════════════════╣');
      for (final s in _strings.entries) {
        for (final sc in scenarios.entries) {
          final path = 'test/audio/synth/${s.key}_${sc.key}.wav';
          if (!File(path).existsSync()) continue;
          final chunks = _chunks(_loadWav(path));
          final r = await _runPipeline(estimator, chunks, s.value.idx);
          final expected = s.value.freq * pow(2.0, sc.value / 1200.0);
          final errPct = r.medianFreq > 0
              ? (r.medianFreq - expected).abs() / expected * 100
              : 0.0;
          // ignore: avoid_print
          print(
              '║  ${s.key} ${sc.key.padRight(8)}  ${expected.toStringAsFixed(2).padLeft(7)}  '
              '${(r.locked / r.totalChunks * 100).toStringAsFixed(0).padLeft(4)}%  '
              '${r.wrong.toString().padLeft(4)}  '
              '${r.medianFreq.toStringAsFixed(2).padLeft(8)}  '
              '${errPct.toStringAsFixed(2).padLeft(4)}% ║');
        }
      }
      // ignore: avoid_print
      print('╚══════════════════════════════════════════════════════════════════╝');
    });
  });

  // ── 2. real WAV (Iowa MIS) — 실 어쿠스틱 기타 단일 pluck ─────────────────
  group('real (Iowa MIS) — 단일 pluck 정확성', () {
    const maxWrongRatio = 0.05;
    const maxCentsFromNominal = 100.0;

    for (final s in _strings.entries) {
      test(s.key, () async {
        final path = 'test/audio/real/${s.key}.wav';
        if (!File(path).existsSync()) {
          markTestSkipped('파일 없음: $path');
          return;
        }
        final chunks = _chunks(_loadWav(path));
        final r = await _runPipeline(estimator, chunks, s.value.idx);

        expect(r.locked, greaterThan(0), reason: '${s.key}: LOCK 도달 못 함');
        expect(r.wrong / r.totalChunks, lessThan(maxWrongRatio),
            reason: '${s.key}: 잘못된 LOCK ${r.wrong}/${r.totalChunks}');
        if (r.medianFreq > 0) {
          final cents = 1200 * log(r.medianFreq / s.value.freq) / ln2;
          expect(cents.abs(), lessThan(maxCentsFromNominal),
              reason: '${s.key}: ${cents.toStringAsFixed(0)} cents — 윈도우 밖');
        }
      });
    }
  });

  // ── 3. transient WAV (tonejs) — 레거시 회귀 baseline ─────────────────────
  group('transient (tonejs) — 레거시 회귀 baseline', () {
    const maxWrongRatio = 0.08;
    const maxFreqErrPct = 2.0;

    for (final s in _strings.entries) {
      test(s.key, () async {
        final path = 'test/audio/transient/${s.key}.wav';
        if (!File(path).existsSync()) {
          markTestSkipped('파일 없음: $path');
          return;
        }
        final chunks = _chunks(_loadWav(path));
        final r = await _runPipeline(estimator, chunks, s.value.idx);

        expect(r.locked, greaterThan(0), reason: '${s.key}: LOCK 도달 못 함');
        expect(r.wrong / r.totalChunks, lessThan(maxWrongRatio),
            reason:
                '${s.key}: 잘못된 LOCK ${(r.wrong / r.totalChunks * 100).toStringAsFixed(1)}%');
        if (r.medianFreq > 0) {
          final errPct =
              (r.medianFreq - s.value.freq).abs() / s.value.freq * 100;
          expect(errPct, lessThan(maxFreqErrPct),
              reason: '${s.key}: freq 오차 ${errPct.toStringAsFixed(2)}%');
        }
      });
    }
  });
}
