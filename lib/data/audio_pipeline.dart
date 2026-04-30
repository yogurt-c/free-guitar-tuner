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
class AudioPipeline {
  static const _smoothingFrames = 3;

  final _capture = AudioCapture();
  final _detector = PitchDetector();
  final _freqBuffer = <double>[];

  StreamSubscription<PitchResult>? _subscription;
  final _controller = StreamController<PitchResult>.broadcast();

  Stream<PitchResult> get pitchStream => _controller.stream;

  Future<void> start() async {
    await _capture.start();
    _subscription = _capture.stream
        .asyncMap((samples) async {
          final signalLevel = _rms(samples);
          final freq = await _detector.detect(samples);
          return PitchResult(
            freq: freq != null ? _smooth(freq) : null,
            signalLevel: signalLevel,
          );
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
}
