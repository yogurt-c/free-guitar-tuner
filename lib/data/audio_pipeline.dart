import 'dart:async';

import 'audio_capture.dart';
import 'pitch_detector.dart';

/// AudioCapture 스트림을 PitchDetector에 연결해 감지 주파수를 스트리밍한다.
class AudioPipeline {
  final _capture = AudioCapture();
  final _detector = PitchDetector();

  StreamSubscription<double?>? _subscription;
  final _controller = StreamController<double?>.broadcast();

  Stream<double?> get freqStream => _controller.stream;

  Future<void> start() async {
    await _capture.start();
    _subscription = _capture.stream.asyncMap(_detector.detect).listen(
      _controller.add,
      onError: _controller.addError,
    );
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
}
