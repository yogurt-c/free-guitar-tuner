import 'dart:async';
import 'dart:isolate';

import 'package:pitch_detector_dart/pitch_detector.dart';

import '../domain/model/pitch_estimate.dart';
import 'pitch_estimator.dart';

/// pitch_detector_dart 0.0.7 (tarsosDSP YIN 포트) 어댑터.
///
/// 라이브러리 API:
///   `PitchDetector(sampleRate, bufferSize).getPitchFromFloatBuffer(samples)`
///   → `PitchDetectorResult(pitch, probability, pitched)`
///
/// 차이점 ( [YinEstimator] 대비 ):
/// - **threshold**: 라이브러리 hardcoded 0.20 (직접 구현은 0.15)
/// - **search range**: 라이브러리는 tauMin/tauMax 미지원. tau 가 전 범위 [2, bufferSize/2-1] 에서
///   탐색됨 → octave-too-high error 발생 가능. 어댑터에서 **결과 freq 가 [tauMin, tauMax] 밖이면
///   null 로 폐기** 하는 후처리로 보완.
/// - **fallback**: 라이브러리는 threshold 통과 못하면 즉시 -1 반환. 직접 구현은 global min fallback.
/// - **confidence 의미**: 라이브러리 probability = 1 - CMNDF[tau] (높을수록 신뢰).
///   PitchEstimate.confidence 는 낮을수록 신뢰 → `confidence = 1 - probability` 로 변환해 매핑.
///
/// 실행 모델: [YinEstimator] 와 동일하게 long-lived isolate 1개.
class PitchDetectorDartEstimator implements PitchEstimator {
  static const _defaultSampleRate = 44100;

  /// confidence 가 이 이상이면 unvoiced — null 반환. [YinEstimator] 와 동일 기준.
  static const double defaultMaxConfidence = 0.40;

  Isolate? _isolate;
  SendPort? _sendPort;
  ReceivePort? _receivePort;
  final _pending = <int, Completer<PitchEstimate?>>{};
  int _nextId = 0;
  Future<void>? _spawning;
  bool _disposed = false;

  Future<void> _ensureSpawned() {
    if (_sendPort != null) return Future.value();
    return _spawning ??= _spawn();
  }

  Future<void> _spawn() async {
    final ready = Completer<SendPort>();
    _receivePort = ReceivePort();
    _receivePort!.listen((msg) {
      if (msg is SendPort) {
        ready.complete(msg);
      } else if (msg is _EstimateResponse) {
        _pending.remove(msg.id)?.complete(msg.estimate);
      }
    });
    _isolate = await Isolate.spawn(_isolateMain, _receivePort!.sendPort);
    _sendPort = await ready.future;
  }

  @override
  Future<PitchEstimate?> estimate(
    List<double> samples, {
    required int tauMin,
    required int tauMax,
    int sampleRate = _defaultSampleRate,
    double maxConfidence = defaultMaxConfidence,
  }) async {
    if (_disposed) return null;
    await _ensureSpawned();
    if (_disposed) return null;
    final id = _nextId++;
    final completer = Completer<PitchEstimate?>();
    _pending[id] = completer;
    _sendPort!.send(_EstimateRequest(
      id: id,
      samples: samples,
      sampleRate: sampleRate,
      tauMin: tauMin,
      tauMax: tauMax,
      maxConfidence: maxConfidence,
    ));
    return completer.future;
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    for (final c in _pending.values) {
      if (!c.isCompleted) c.complete(null);
    }
    _pending.clear();
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _sendPort = null;
    _receivePort?.close();
    _receivePort = null;
    _spawning = null;
  }

  // ─── isolate side ─────────────────────────────────────────────────────────

  static void _isolateMain(SendPort mainSend) {
    final port = ReceivePort();
    mainSend.send(port.sendPort);
    // bufferSize 별 PitchDetector 인스턴스 캐시 (재구성 비용 회피).
    final detectorCache = <_DetectorKey, PitchDetector>{};
    port.listen((msg) async {
      if (msg is _EstimateRequest) {
        final est = await _estimate(msg, detectorCache);
        mainSend.send(_EstimateResponse(id: msg.id, estimate: est));
      }
    });
  }

  static Future<PitchEstimate?> _estimate(
    _EstimateRequest req,
    Map<_DetectorKey, PitchDetector> cache,
  ) async {
    final bufferSize = req.samples.length;
    if (bufferSize < 2) return null;
    final key = _DetectorKey(req.sampleRate, bufferSize);
    final detector = cache.putIfAbsent(
      key,
      () => PitchDetector(
        audioSampleRate: req.sampleRate.toDouble(),
        bufferSize: bufferSize,
      ),
    );

    final result = await detector.getPitchFromFloatBuffer(req.samples);

    if (!result.pitched) return null;
    if (!result.pitch.isFinite || result.pitch <= 0) return null;

    // 라이브러리 probability 가 높을수록 신뢰. 우리 PitchEstimate.confidence 는 반대.
    final confidence = (1.0 - result.probability).clamp(0.0, 1.0);
    if (confidence >= req.maxConfidence) return null;

    // search range 후처리 필터. 라이브러리가 narrow search 미지원이라 결과로 컷.
    // tauMin/tauMax 가 유효할 때만 (음수/0 이면 미적용 — 테스트 도구가 비활성화 가능).
    if (req.tauMin > 0 && req.tauMax > req.tauMin) {
      final tau = req.sampleRate / result.pitch;
      if (tau < req.tauMin || tau > req.tauMax) return null;
    }

    return PitchEstimate(freq: result.pitch, confidence: confidence);
  }
}

class _DetectorKey {
  final int sampleRate;
  final int bufferSize;
  const _DetectorKey(this.sampleRate, this.bufferSize);
  @override
  bool operator ==(Object other) =>
      other is _DetectorKey &&
      sampleRate == other.sampleRate &&
      bufferSize == other.bufferSize;
  @override
  int get hashCode => Object.hash(sampleRate, bufferSize);
}

class _EstimateRequest {
  final int id;
  final List<double> samples;
  final int sampleRate;
  final int tauMin;
  final int tauMax;
  final double maxConfidence;
  _EstimateRequest({
    required this.id,
    required this.samples,
    required this.sampleRate,
    required this.tauMin,
    required this.tauMax,
    required this.maxConfidence,
  });
}

class _EstimateResponse {
  final int id;
  final PitchEstimate? estimate;
  _EstimateResponse({required this.id, required this.estimate});
}
