import 'dart:async';
import 'dart:typed_data';

import 'package:audio_session/audio_session.dart';
import 'package:record/record.dart';

class AudioCapture {
  static const sampleRate = 44100;
  static const bufferSamples = 2048;
  static const _bytesPerSample = 2; // PCM16

  final _recorder = AudioRecorder();
  StreamSubscription<Uint8List>? _subscription;
  final _controller = StreamController<List<double>>.broadcast();
  final _byteBuffer = <int>[];

  Stream<List<double>> get stream => _controller.stream;

  Future<void> start() async {
    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      throw const MicrophonePermissionException();
    }

    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration(
      avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
      avAudioSessionCategoryOptions:
          AVAudioSessionCategoryOptions.defaultToSpeaker,
      avAudioSessionMode: AVAudioSessionMode.measurement,
      androidAudioAttributes: AndroidAudioAttributes(
        contentType: AndroidAudioContentType.speech,
        flags: AndroidAudioFlags.none,
        usage: AndroidAudioUsage.voiceCommunication,
      ),
      androidWillPauseWhenDucked: true,
    ));
    await session.setActive(true);

    final audioStream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: sampleRate,
        numChannels: 1,
      ),
    );

    _subscription = audioStream.listen(_onData);
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    _byteBuffer.clear();
    await _recorder.stop();
    final session = await AudioSession.instance;
    await session.setActive(false);
  }

  Future<void> dispose() async {
    await stop();
    _recorder.dispose();
    await _controller.close();
  }

  void _onData(Uint8List bytes) {
    _byteBuffer.addAll(bytes);
    const chunkBytes = bufferSamples * _bytesPerSample;
    while (_byteBuffer.length >= chunkBytes) {
      final chunk = Uint8List.fromList(_byteBuffer.sublist(0, chunkBytes));
      _byteBuffer.removeRange(0, chunkBytes);
      _controller.add(_pcm16ToDoubles(chunk));
    }
  }

  static List<double> _pcm16ToDoubles(Uint8List bytes) {
    final byteData = ByteData.sublistView(bytes);
    return List<double>.generate(
      bytes.length ~/ 2,
      (i) => byteData.getInt16(i * 2, Endian.little) / 32768.0,
    );
  }
}

class MicrophonePermissionException implements Exception {
  const MicrophonePermissionException();
}

