import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import '../domain/model/tracker_state.dart';
import 'audio_capture.dart';
import 'pitch_tracker.dart';
import 'yin_estimator.dart';

/// 마이크 → sliding window (4096 샘플, 1024 hop) → YinEstimator → PitchTracker
/// → TrackerState 스트림.
///
/// AudioCapture 는 1024 샘플 hop 단위로 emit. AudioPipeline 은 4096 샘플 ring
/// buffer 를 유지하면서 매 hop 마다 마지막 4096 샘플로 YIN 추정.
/// 결과적으로 update rate 는 ≈ 43 Hz (4× overlap). raw freq jitter 가 시각적으로
/// 평균화되어 1, 2번 현 처럼 inherent jitter 가 큰 케이스도 안정적으로 표시됨.
///
/// preset / 모드 / 선택현 은 외부에서 [updateConfig] 로 주입. 이게 바뀌면 tracker
/// 가 reset 되어 이전 LOCK 상태가 새 셋으로 새 나가지 않는다. preset 의 freq 범위
/// 로 YIN search range 도 동적 산정.
///
/// Backpressure: 한 청크 처리 중 새 청크가 들어오면 **최신 청크 1개만 보존**.
class AudioPipeline {
  static const _defaultSampleRate = AudioCapture.sampleRate;

  /// YIN 분석 윈도우 (≈ 93 ms). hop (1024) 보다 4× 커서 75% overlap.
  static const windowSamples = 4096;

  /// preset 의 string freq 들. 비어있으면 stream 에 아무것도 안 흘림.
  List<double> _strings = const [];

  /// 자동감지 / 수동.
  bool _autoDetect = true;

  /// 수동 모드 선택 현.
  int _selectedString = 0;

  /// preset 의 최저현 -200c ~ 최고현 +200c 로 산정한 search range.
  int _tauMin = 0;
  int _tauMax = 0;

  final AudioSource _capture;
  final _estimator = YinEstimator();
  final _tracker = PitchTracker();

  /// 기본은 [AudioCapture]. 테스트에선 [AudioSource] 구현체 주입해 mic 우회.
  AudioPipeline({AudioSource? source}) : _capture = source ?? AudioCapture();

  StreamSubscription<List<double>>? _subscription;
  final _controller = StreamController<TrackerState>.broadcast();

  /// 4096-sample sliding window. hop 들어올 때마다 왼쪽으로 hop 만큼 shift 한 뒤
  /// 새 hop 을 오른쪽 끝에 append.
  final Float64List _window = Float64List(windowSamples);

  /// 윈도우가 처음 채워질 때까지 추적 (warmup). 채워지기 전엔 estimate 안 호출.
  int _windowFill = 0;

  bool _processing = false;
  List<double>? _pendingSamples;

  Stream<TrackerState> get stateStream => _controller.stream;

  /// Preset / 모드 / 선택현 한 번에 갱신.
  /// 값이 바뀌면 tracker reset + search range 재산정.
  void updateConfig({
    required List<double> strings,
    required bool autoDetect,
    required int selectedString,
  }) {
    final stringsChanged = !_freqsEqual(_strings, strings);
    if (stringsChanged) {
      _strings = List.unmodifiable(strings);
      _tracker.setStrings(strings);
      _recomputeSearchRange();
    }
    if (_autoDetect != autoDetect) {
      _autoDetect = autoDetect;
      _tracker.setAutoDetect(autoDetect);
    }
    if (_selectedString != selectedString) {
      _selectedString = selectedString;
      _tracker.setSelectedString(selectedString);
    }
  }

  Future<void> start() async {
    await _capture.start();
    _subscription = _capture.stream.listen(_onSamples);
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    _pendingSamples = null;
    _windowFill = 0;
    _tracker.reset();
    await _capture.stop();
  }

  Future<void> dispose() async {
    await stop();
    await _capture.dispose();
    await _estimator.dispose();
    await _controller.close();
  }

  // ─ 내부 ─────────────────────────────────────────────────────────────────

  /// AudioCapture 에서 hop (1024 샘플) 을 받아 sliding window 에 누적.
  /// 윈도우가 채워지면 마지막 4096 샘플의 snapshot 을 pending 으로 둠.
  void _onSamples(List<double> hop) {
    final hopLen = hop.length;
    if (hopLen == 0) return;
    if (hopLen >= windowSamples) {
      // 비정상적으로 큰 hop — 윈도우 전체 교체 (마지막 windowSamples 만 보존).
      final start = hopLen - windowSamples;
      for (var i = 0; i < windowSamples; i++) {
        _window[i] = hop[start + i];
      }
      _windowFill = windowSamples;
    } else {
      // shift left by hopLen (forward copy, non-overlapping after shift).
      final tail = windowSamples - hopLen;
      for (var i = 0; i < tail; i++) {
        _window[i] = _window[i + hopLen];
      }
      // append new hop at the end.
      for (var i = 0; i < hopLen; i++) {
        _window[tail + i] = hop[i];
      }
      if (_windowFill < windowSamples) {
        _windowFill = min(_windowFill + hopLen, windowSamples);
      }
    }

    // 윈도우 아직 안 채워졌으면 estimate skip — warmup 구간.
    if (_windowFill < windowSamples) return;

    _pendingSamples = List<double>.from(_window);
    _drain();
  }

  Future<void> _drain() async {
    if (_processing) return;
    _processing = true;
    try {
      while (_pendingSamples != null) {
        final s = _pendingSamples!;
        _pendingSamples = null;
        await _process(s);
      }
    } finally {
      _processing = false;
    }
  }

  Future<void> _process(List<double> samples) async {
    if (_strings.isEmpty || _tauMin <= 0 || _tauMax <= _tauMin) return;
    final rms = _rms(samples);
    try {
      final estimate = await _estimator.estimate(
        samples,
        tauMin: _tauMin,
        tauMax: _tauMax,
        sampleRate: _defaultSampleRate,
      );
      final state = _tracker.update(estimate, signalLevel: rms);
      if (_controller.isClosed) return;
      _controller.add(state);
    } catch (e, st) {
      _controller.addError(e, st);
    }
  }

  /// Preset 의 최저현 -200c ~ 최고현 +200c 로 search range 산정.
  /// search 범위 좁힘이 fundamental octave error 의 가장 효과적 차단책.
  void _recomputeSearchRange() {
    if (_strings.isEmpty) {
      _tauMin = 0;
      _tauMax = 0;
      return;
    }
    var fmin = double.infinity;
    var fmax = 0.0;
    for (final f in _strings) {
      if (f < fmin) fmin = f;
      if (f > fmax) fmax = f;
    }
    const detuneFactor = 1.1224620483093729; // 2^(200/1200)
    final lowFreq = fmin / detuneFactor;
    final highFreq = fmax * detuneFactor;
    _tauMin = max(2, (_defaultSampleRate / highFreq).ceil());
    _tauMax = (_defaultSampleRate / lowFreq).floor();
  }

  static double _rms(List<double> samples) {
    if (samples.isEmpty) return 0.0;
    var sum = 0.0;
    for (final s in samples) {
      sum += s * s;
    }
    return sqrt(sum / samples.length);
  }

  static bool _freqsEqual(List<double> a, List<double> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
