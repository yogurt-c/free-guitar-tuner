// AudioPipeline 통합 테스트.
//
// FakeSource 로 mic 우회. 실 YinEstimator + PitchTracker 와 함께 pipeline 의
// sliding window / warmup / backpressure / config reset / search range 동작 검증.
//
// pitch_pipeline_wav_test 가 chunk 단위로 estimator+tracker 만 보던 사각지대를
// AudioPipeline._onSamples 시프트 로직 + updateConfig 동작까지 cover.

import 'dart:async';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:guitar_tuner/data/audio_capture.dart';
import 'package:guitar_tuner/data/audio_pipeline.dart';
import 'package:guitar_tuner/domain/model/tracker_state.dart';

class _FakeSource implements AudioSource {
  final _ctrl = StreamController<List<double>>.broadcast();
  bool startCalled = false;
  bool stopCalled = false;
  bool disposeCalled = false;

  @override
  Stream<List<double>> get stream => _ctrl.stream;

  @override
  Future<void> start() async => startCalled = true;

  @override
  Future<void> stop() async => stopCalled = true;

  @override
  Future<void> dispose() async {
    disposeCalled = true;
    if (!_ctrl.isClosed) await _ctrl.close();
  }

  void emit(List<double> samples) {
    if (!_ctrl.isClosed) _ctrl.add(samples);
  }
}

const _stdStrings = <double>[82.41, 110.0, 146.83, 196.0, 246.94, 329.63];
const _hopSamples = 1024;
const _sampleRate = 44100;

/// 시간 연속성 유지한 sine hop — 위상이 hop 사이에 끊기지 않음.
List<double> _sineHop(double freq, int hopIdx, {double amp = 0.5}) {
  return List<double>.generate(
    _hopSamples,
    (i) => amp * sin(2 * pi * freq * (hopIdx * _hopSamples + i) / _sampleRate),
  );
}

Future<void> _waitUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 3),
}) async {
  final end = DateTime.now().add(timeout);
  while (!condition() && DateTime.now().isBefore(end)) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

/// 연속 hop 을 일정 간격으로 emit — 매 emit 후 짧게 yield 해 isolate 가 따라잡게.
Future<void> _emitContinuous(
  _FakeSource source,
  double freq,
  int hopCount, {
  Duration spacing = const Duration(milliseconds: 25),
  int startHopIdx = 0,
}) async {
  for (var i = 0; i < hopCount; i++) {
    source.emit(_sineHop(freq, startHopIdx + i));
    await Future<void>.delayed(spacing);
  }
}

void main() {
  group('AudioPipeline', () {
    late _FakeSource source;
    late AudioPipeline pipeline;
    late List<TrackerState> states;
    late StreamSubscription<TrackerState> sub;

    setUp(() async {
      source = _FakeSource();
      pipeline = AudioPipeline(source: source);
      states = <TrackerState>[];
      sub = pipeline.stateStream.listen(states.add);
      pipeline.updateConfig(
        strings: _stdStrings,
        autoDetect: true,
        selectedString: 3,
      );
      await pipeline.start();
    });

    tearDown(() async {
      await sub.cancel();
      await pipeline.dispose();
    });

    test('start() 가 source.start() 호출', () {
      expect(source.startCalled, isTrue);
    });

    test('warmup: window 채워지기 전 hop 들은 emission 안 함', () async {
      // windowSamples / hopSamples = 4 — 3 hop 까지는 emission 없음.
      final warmupHops = AudioPipeline.windowSamples ~/ _hopSamples - 1;
      for (var i = 0; i < warmupHops; i++) {
        source.emit(_sineHop(196.0, i));
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(states, isEmpty,
          reason: '$warmupHops hops 만으론 window 미달 → emission 없어야');

      // 4th hop 으로 window 채워짐 → emission 발생.
      source.emit(_sineHop(196.0, warmupHops));
      await _waitUntil(() => states.isNotEmpty);
      expect(states, isNotEmpty);
    });

    test('연속 G3 hops → 결국 G3 (idx 3) 로 LOCKED', () async {
      await _emitContinuous(source, 196.0, 20);
      await _waitUntil(() => states.any((s) => s is TrackerLocked));

      final locked = states.whereType<TrackerLocked>().firstOrNull;
      expect(locked, isNotNull, reason: 'LOCKED 도달 못 함');
      expect(locked!.stringIndex, 3);
      expect(locked.detectedFreq, closeTo(196.0, 2.0));
    });

    test('updateConfig 의 strings 변경 시 tracker reset — 이전 LOCK 즉시 잔존 안 함',
        () async {
      // 먼저 G3 로 LOCK.
      await _emitContinuous(source, 196.0, 20);
      await _waitUntil(() => states.any((s) => s is TrackerLocked));
      states.clear();

      // preset 변경 (drop D: E2 → D2). G3 idx 는 3 유지.
      pipeline.updateConfig(
        strings: const [73.42, 110.0, 146.83, 196.0, 246.94, 329.63],
        autoDetect: true,
        selectedString: 3,
      );

      // 같은 G3 한 hop emit. window 는 G3 가득찬 상태지만 tracker 가 reset 됐으면
      // 첫 결과는 SEARCHING (lockFrames 누적 안 됐으므로).
      source.emit(_sineHop(196.0, 100));
      await _waitUntil(() => states.isNotEmpty);

      expect(states.first, isA<TrackerSearching>(),
          reason: 'updateConfig 가 tracker reset 안 하면 이전 LOCK 이 새 preset 으로 leak');
    });

    test('updateConfig 동일 strings 면 reset 안 일어남 — LOCK 유지', () async {
      await _emitContinuous(source, 196.0, 20);
      await _waitUntil(() => states.any((s) => s is TrackerLocked));

      // 같은 strings, autoDetect 만 바꿈.
      pipeline.updateConfig(
        strings: _stdStrings,
        autoDetect: true,
        selectedString: 3,
      );
      states.clear();

      source.emit(_sineHop(196.0, 100));
      await _waitUntil(() => states.isNotEmpty);

      expect(states.first, isA<TrackerLocked>(),
          reason: '동일 strings 면 reset 안 일어나고 LOCK 유지');
    });

    test('windowSamples 이상 크기 hop — 마지막 windowSamples 만 분석', () async {
      // 한 번에 5000 샘플 emit (windowSamples 4096 보다 큼).
      final bigHop = List<double>.generate(
        AudioPipeline.windowSamples + 500,
        (i) => 0.5 * sin(2 * pi * 196.0 * i / _sampleRate),
      );
      source.emit(bigHop);
      await _waitUntil(() => states.isNotEmpty);

      expect(states, isNotEmpty, reason: '큰 hop 한 번으로 window 즉시 채워져야');
    });

    test('stop() 이 source.stop() 호출 + _windowFill 리셋 — 재 start 시 warmup 필요',
        () async {
      // 먼저 LOCK 까지 도달.
      await _emitContinuous(source, 196.0, 20);
      await _waitUntil(() => states.any((s) => s is TrackerLocked));

      await pipeline.stop();
      expect(source.stopCalled, isTrue);

      states.clear();
      await pipeline.start();

      // stop 으로 _windowFill=0 — 1 hop 으론 warmup 미달.
      source.emit(_sineHop(196.0, 0));
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(states, isEmpty,
          reason: 'stop 이 _windowFill 안 리셋하면 warmup skip 돼 즉시 emission');
    });

    test('dispose() 가 source.dispose() 호출', () async {
      // tearDown 이 dispose 호출 후 disposeCalled 확인 — 별도 pipeline 만들어 검증.
      final s = _FakeSource();
      final p = AudioPipeline(source: s);
      p.updateConfig(
          strings: _stdStrings, autoDetect: true, selectedString: 0);
      await p.start();
      await p.dispose();
      expect(s.disposeCalled, isTrue);
    });
  });
}
