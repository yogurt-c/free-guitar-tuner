// 동일 WAV 시계열에 두 추정기를 흘려 직접 비교한다.
//   - YinEstimator (자체 구현, paper Step 1-4 + parabolic + search range)
//   - PitchDetectorDartEstimator (pitch_detector_dart 0.0.7 어댑터)
//
// 동일한 AudioPipeline 의 sliding window (4096/1024) 와 동일한 PitchTracker
// state machine 을 사용 — 비교 변수는 **추정기 단 하나**.
//
// 메트릭 (현+시나리오별):
//   - aboveGate: RMS noiseGateExit 이상 청크 수 (signal 청크)
//   - locked: TrackerLocked 청크 수
//   - wrong: locked 인데 stringIndex 가 기대와 다른 청크 수 (octave/wrong string error 포함)
//   - medianFreq: locked 청크들 detectedFreq 의 중앙값
//   - centsErr: medianFreq vs expected 의 cents
//   - p95Jitter: locked detectedFreq 의 hop-to-hop |delta| cents 의 p95
//
// 한 자리에서 비교 표 출력 — 알고리즘별 강/약 시각화.

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:guitar_tuner/data/pitch_detector_dart_estimator.dart';
import 'package:guitar_tuner/data/pitch_estimator.dart';
import 'package:guitar_tuner/data/pitch_tracker.dart';
import 'package:guitar_tuner/data/yin_estimator.dart';
import 'package:guitar_tuner/domain/model/tracker_state.dart';

const _windowSize = 4096;
const _hopSize = 1024;
const _sampleRate = 44100;

const _stdStrings = <double>[
  82.41, 110.00, 146.83, 196.00, 246.94, 329.63,
];

// standard preset search range: fmin -200c ~ fmax +200c.
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
  assert(dataOffset != -1);
  final sampleCount = dataSize ~/ 2;
  return List<double>.generate(
    sampleCount,
    (i) => data.getInt16(dataOffset + i * 2, Endian.little) / 32768.0,
  );
}

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
  for (final s in samples) sum += s * s;
  return sqrt(sum / samples.length);
}

typedef _Result = ({
  int totalChunks,
  int aboveGate,
  int locked,
  int wrong,
  double medianFreq,
  double centsErr,
  double p95JitterCents,
});

Future<_Result> _run(
  PitchEstimator estimator,
  List<List<double>> chunks,
  int expectedIdx,
  double expectedFreq,
) async {
  final tracker = PitchTracker()
    ..setStrings(_stdStrings)
    ..setAutoDetect(true);
  var aboveGate = 0, locked = 0, wrong = 0;
  final freqs = <double>[];
  double? prevFreq;
  final jitters = <double>[];
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
      if (prevFreq != null && prevFreq > 0 && state.detectedFreq > 0) {
        final dCents = (1200 * log(state.detectedFreq / prevFreq) / ln2).abs();
        jitters.add(dCents);
      }
      prevFreq = state.detectedFreq;
    } else {
      prevFreq = null;
    }
  }
  freqs.sort();
  jitters.sort();
  final median = freqs.isEmpty ? 0.0 : freqs[freqs.length ~/ 2];
  final centsErr = median > 0 ? 1200 * log(median / expectedFreq) / ln2 : 0.0;
  final p95 = jitters.isEmpty ? 0.0 : jitters[(jitters.length * 0.95).floor().clamp(0, jitters.length - 1)];
  return (
    totalChunks: chunks.length,
    aboveGate: aboveGate,
    locked: locked,
    wrong: wrong,
    medianFreq: median,
    centsErr: centsErr,
    p95JitterCents: p95,
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

void _printHeader(String title) {
  // ignore: avoid_print
  print('\n=== $title ===');
  // ignore: avoid_print
  print(
    '  현/시나리오   |  추정기                   | aboveGate | locked%  | wrong | medianHz  | centsErr | p95 jitter',
  );
  // ignore: avoid_print
  print(
    '  -------------+--------------------------+-----------+----------+-------+-----------+----------+-----------',
  );
}

void _printRow(String label, String est, _Result r) {
  final lockedPct = r.aboveGate == 0 ? 0.0 : r.locked / r.aboveGate * 100;
  // ignore: avoid_print
  print(
    '  ${label.padRight(12)} | ${est.padRight(24)} | '
    '${r.aboveGate.toString().padLeft(9)} | '
    '${lockedPct.toStringAsFixed(0).padLeft(6)}%  | '
    '${r.wrong.toString().padLeft(5)} | '
    '${r.medianFreq.toStringAsFixed(2).padLeft(9)} | '
    '${r.centsErr.toStringAsFixed(1).padLeft(7)}c | '
    '${r.p95JitterCents.toStringAsFixed(1).padLeft(7)}c',
  );
}

void main() {
  late YinEstimator yin;
  late PitchDetectorDartEstimator lib;
  setUpAll(() {
    yin = YinEstimator();
    lib = PitchDetectorDartEstimator();
  });
  tearDownAll(() async {
    await yin.dispose();
    await lib.dispose();
  });

  group('synth — 반복 pluck (실 사용 모델)', () {
    const scenarios = <String, int>{
      'nominal': 0,
      'flat40': -40,
      'sharp30': 30,
    };

    test('전 시나리오 비교', () async {
      _printHeader('synth (반복 pluck, 5s × 4 pluck)');
      for (final s in _strings.entries) {
        for (final sc in scenarios.entries) {
          final path = 'test/audio/synth/${s.key}_${sc.key}.wav';
          if (!File(path).existsSync()) continue;
          final chunks = _chunks(_loadWav(path));
          final expected = s.value.freq * pow(2.0, sc.value / 1200.0);
          final ry = await _run(yin, chunks, s.value.idx, expected);
          final rl = await _run(lib, chunks, s.value.idx, expected);
          final label = '${s.key} ${sc.key}';
          _printRow(label, 'YinEstimator (직접)', ry);
          _printRow(label, 'pitch_detector_dart', rl);
        }
      }
    }, timeout: const Timeout(Duration(minutes: 3)));
  });

  group('real — Iowa MIS 단일 pluck', () {
    test('전 현 비교', () async {
      _printHeader('real (Iowa MIS 단일 pluck)');
      for (final s in _strings.entries) {
        final path = 'test/audio/real/${s.key}.wav';
        if (!File(path).existsSync()) continue;
        final chunks = _chunks(_loadWav(path));
        final ry = await _run(yin, chunks, s.value.idx, s.value.freq);
        final rl = await _run(lib, chunks, s.value.idx, s.value.freq);
        _printRow(s.key, 'YinEstimator (직접)', ry);
        _printRow(s.key, 'pitch_detector_dart', rl);
      }
    }, timeout: const Timeout(Duration(minutes: 2)));
  });

  group('transient — tonejs', () {
    test('전 현 비교', () async {
      _printHeader('transient (tonejs short pluck)');
      for (final s in _strings.entries) {
        final path = 'test/audio/transient/${s.key}.wav';
        if (!File(path).existsSync()) continue;
        final chunks = _chunks(_loadWav(path));
        final ry = await _run(yin, chunks, s.value.idx, s.value.freq);
        final rl = await _run(lib, chunks, s.value.idx, s.value.freq);
        _printRow(s.key, 'YinEstimator (직접)', ry);
        _printRow(s.key, 'pitch_detector_dart', rl);
      }
    }, timeout: const Timeout(Duration(minutes: 2)));
  });
}
