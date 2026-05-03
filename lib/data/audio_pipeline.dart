import 'dart:async';
import 'dart:math';

import 'audio_capture.dart';
import 'pitch_detector.dart';

class PitchResult {
  final double? freq;
  final double signalLevel;
  const PitchResult({this.freq, required this.signalLevel});
}

/// AudioCapture 스트림을 PitchDetector에 연결해 pitch + signalLevel을 스트리밍한다.
///
/// 후보 주파수(candidates)는 외부에서 [setCandidates] 로 주입받는다.
/// - 수동 모드: 선택된 현 1개
/// - 자동 감지 모드: preset 의 모든 현
class AudioPipeline {
  static const _smoothingFrames = 5;

  final _capture = AudioCapture();
  final _detector = PitchDetector();
  final _freqBuffer = <double>[];

  List<double> _candidates = const [];

  StreamSubscription<PitchResult>? _subscription;
  final _controller = StreamController<PitchResult>.broadcast();

  Stream<PitchResult> get pitchStream => _controller.stream;

  /// 검색 대상 후보 주파수 갱신.
  /// 후보 셋이 바뀌면 스무딩 버퍼는 초기화한다(이전 현의 값과 섞이지 않도록).
  void setCandidates(List<double> candidates) {
    final changed = !_listEqual(_candidates, candidates);
    _candidates = List.unmodifiable(candidates);
    if (changed) _freqBuffer.clear();
  }

  Future<void> start() async {
    await _capture.start();
    _subscription = _capture.stream
        .asyncMap((samples) async {
          final signalLevel = _rms(samples);
          double? freq;
          if (_candidates.isNotEmpty) {
            final raw = await _detector.detect(
              samples,
              candidates: _candidates,
              sampleRate: AudioCapture.sampleRate,
            );
            if (raw != null) freq = _smooth(raw);
          }
          return PitchResult(freq: freq, signalLevel: signalLevel);
        })
        .listen(_controller.add, onError: _controller.addError);
  }

  double _smooth(double freq) {
    _freqBuffer.add(freq);
    if (_freqBuffer.length > _smoothingFrames) {
      _freqBuffer.removeAt(0);
    }
    final sorted = [..._freqBuffer]..sort();
    final mid = sorted.length ~/ 2;
    return sorted.length.isOdd
        ? sorted[mid]
        : (sorted[mid - 1] + sorted[mid]) / 2.0;
  }

  void resetBuffer() => _freqBuffer.clear();

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    _freqBuffer.clear();
    await _capture.stop();
  }

  Future<void> dispose() async {
    await stop();
    await _capture.dispose();
    await _controller.close();
  }

  static double _rms(List<double> samples) {
    if (samples.isEmpty) return 0.0;
    var sum = 0.0;
    for (final s in samples) { sum += s * s; }
    return sqrt(sum / samples.length);
  }

  static bool _listEqual(List<double> a, List<double> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
