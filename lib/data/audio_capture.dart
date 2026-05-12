import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:audio_session/audio_session.dart';
import 'package:record/record.dart';

/// AudioPipeline 이 의존하는 최소 인터페이스 — 테스트 시 FakeSource 주입 가능.
abstract class AudioSource {
  Stream<List<double>> get stream;
  Future<void> start();
  Future<void> stop();
  Future<void> dispose();
}

class AudioCapture implements AudioSource {
  static const sampleRate = 44100;

  /// emit 단위 (≈ 23 ms). AudioPipeline 이 이걸 sliding window 로 누적해
  /// 4096 샘플 분석 윈도우를 만들어 update rate 를 hop rate (~43 Hz) 까지 끌어올린다.
  static const hopSamples = 1024;
  static const _bytesPerSample = 2; // PCM16
  static const _chunkBytes = hopSamples * _bytesPerSample;

  final _recorder = AudioRecorder();
  StreamSubscription<Uint8List>? _subscription;
  final _controller = StreamController<List<double>>.broadcast();

  /// hop 경계에 정렬되지 않은 잔여 바이트. mic emit 사이즈가 hop 의 정수배가 아니어도
  /// (record 패키지는 보통 큰 청크로 줌) 다음 호출에서 합쳐 처리.
  Uint8List _tail = Uint8List(0);

  @override
  Stream<List<double>> get stream => _controller.stream;

  @override
  Future<void> start() async {
    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      throw const MicrophonePermissionException();
    }

    if (Platform.isIOS) {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
        avAudioSessionCategoryOptions:
            AVAudioSessionCategoryOptions.defaultToSpeaker,
        avAudioSessionMode: AVAudioSessionMode.measurement,
      ));
      await session.setActive(true);
    }

    final audioStream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: sampleRate,
        numChannels: 1,
      ),
    );

    _subscription = audioStream.listen(_onData);
  }

  @override
  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    _tail = Uint8List(0);
    await _recorder.stop();
    if (Platform.isIOS) {
      final session = await AudioSession.instance;
      await session.setActive(false);
    }
  }

  @override
  Future<void> dispose() async {
    await stop();
    _recorder.dispose();
    await _controller.close();
  }

  /// mic emit 청크 → hop 단위 `List<double>` 로 잘라 emit.
  /// 잔여 바이트는 [_tail] (Uint8List view) 로 다음 호출까지 보존.
  void _onData(Uint8List bytes) {
    final tail = _tail;
    final totalLen = tail.length + bytes.length;

    // 한 chunk 도 안 되면 accumulate 만.
    if (totalLen < _chunkBytes) {
      final next = Uint8List(totalLen);
      if (tail.isNotEmpty) next.setRange(0, tail.length, tail);
      next.setRange(tail.length, totalLen, bytes);
      _tail = next;
      return;
    }

    // tail + bytes 합쳐 한 번에 처리. tail 이 비었으면 bytes 직접 사용 (copy 회피).
    final Uint8List combined;
    if (tail.isEmpty) {
      combined = bytes;
    } else {
      combined = Uint8List(totalLen)
        ..setRange(0, tail.length, tail)
        ..setRange(tail.length, totalLen, bytes);
    }

    var offset = 0;
    while (offset + _chunkBytes <= combined.length) {
      final chunk =
          Uint8List.sublistView(combined, offset, offset + _chunkBytes);
      _controller.add(_pcm16ToDoubles(chunk));
      offset += _chunkBytes;
    }
    _tail = offset < combined.length
        ? Uint8List.sublistView(combined, offset)
        : Uint8List(0);
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

