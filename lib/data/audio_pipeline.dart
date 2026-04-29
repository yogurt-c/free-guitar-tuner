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
  final _capture = AudioCapture();
  final _detector = PitchDetector();

  StreamSubscription<PitchResult>? _subscription;
  final _controller = StreamController<PitchResult>.broadcast();

  Stream<PitchResult> get pitchStream => _controller.stream;

  Future<void> start() async {
    await _capture.start();
    _subscription = _capture.stream
        .asyncMap((samples) async {
          final signalLevel = _rms(samples);
          final freq = await _detector.detect(samples);
          return PitchResult(freq: freq, signalLevel: signalLevel);
        })
        .listen(_controller.add, onError: _controller.addError);
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
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
