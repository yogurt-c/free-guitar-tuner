import 'dart:async';
import 'dart:isolate';
import 'dart:math';

import '../domain/model/pitch_estimate.dart';

/// 표준 YIN single-fundamental 추정기 (de Cheveigné & Kawahara, 2002, JASA).
///
/// 한 청크에서 fundamental 1개만 찾는다. 후보 비교는 외부 (`PitchTracker`) 에서
/// closestString 매핑으로 처리. 옛 PitchAnalyzer 의 후보별 윈도우 + leakage 차단
/// 로직을 버리고 paper 표준 single-pass 로 회귀.
///
/// 알고리즘 (paper Section II 6 단계 중 4 단계):
///   1. d(τ)   : difference function
///   2. d'(τ)  : cumulative mean normalized difference function (CMNDF)
///   3. step 4 : absolute threshold — 처음 d'(τ) < threshold 인 τ 의 local min
///   4. step 5 : parabolic interpolation
///   5. return (sampleRate / τ_best, d'(τ_best))
///
/// step 4 의 "smallest τ" 가 옥타브 ambiguity (특히 too-low / 정수배 dip) 를 차단한다.
/// octave guard 같은 추가 보정은 사인 한 신호에서 paper 의 step 4 효과를 깨므로 두지
/// 않는다. 약한 fundamental + 강 harmonic 으로 인한 too-high error 는 호출자의
/// search range 좁힘 ([tauMin] / [tauMax]) + 후처리 closestString 컷오프로 차단한다.
///
/// search range 는 호출자가 preset 의 최저현 -200c ~ 최고현 +200c 로 산정해 전달.
/// confidence 가 [maxConfidence] 이상이면 unvoiced 로 보고 null.
///
/// 실행 모델: long-lived isolate 1개.
class YinEstimator {
  static const _defaultSampleRate = 44100;

  /// YIN absolute threshold (paper step 4). paper 권장 0.10–0.15.
  /// 실 기타는 inharmonicity / 노이즈로 d' 가 0.10 까지 잘 안 내려가서 0.15.
  static const double defaultYinThreshold = 0.15;

  /// confidence 가 이 이상이면 unvoiced — estimator 가 null 반환.
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

  /// 한 청크에서 fundamental 추정.
  ///
  /// [tauMin] / [tauMax] 는 검색할 lag 범위 (샘플 단위). preset 기반으로
  /// 호출자가 산정: lowest_freq × 2^(-300/1200) ~ highest_freq × 2^(500/1200).
  ///
  /// 결과:
  ///   - voiced + confidence 통과: [PitchEstimate]
  ///   - unvoiced / 신뢰 부족 / 범위 비어있음: null
  Future<PitchEstimate?> estimate(
    List<double> samples, {
    required int tauMin,
    required int tauMax,
    int sampleRate = _defaultSampleRate,
    double threshold = defaultYinThreshold,
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
      threshold: threshold,
      maxConfidence: maxConfidence,
    ));
    return completer.future;
  }

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
    port.listen((msg) {
      if (msg is _EstimateRequest) {
        final est = _estimate(
          msg.samples,
          msg.sampleRate,
          msg.tauMin,
          msg.tauMax,
          msg.threshold,
          msg.maxConfidence,
        );
        mainSend.send(_EstimateResponse(id: msg.id, estimate: est));
      }
    });
  }

  /// 표준 YIN 6 단계 구현. 호출자가 search range 를 좁혀 주면 step 4 의
  /// absolute threshold + octave guard 만으로 stable 한 fundamental 추정 가능.
  static PitchEstimate? _estimate(
    List<double> samples,
    int sampleRate,
    int tauMin,
    int tauMax,
    double threshold,
    double maxConfidence,
  ) {
    final halfN = samples.length ~/ 2;
    final hiCap = halfN - 2;
    final lo = max(2, tauMin);
    final hi = min(hiCap, tauMax);
    if (lo > hi) return null;

    // Step 1: difference function — d(τ) for τ in [1, halfN-1].
    // search range 밖은 안 쓰니까 [1..hi] 까지만 계산.
    final diff = List<double>.filled(halfN, 0.0);
    for (var tau = 1; tau <= hi; tau++) {
      var sum = 0.0;
      for (var j = 0; j < halfN; j++) {
        final delta = samples[j] - samples[j + tau];
        sum += delta * delta;
      }
      diff[tau] = sum;
    }

    // Step 2: CMNDF — d'(τ) = d(τ) · τ / Σ d(j) for j in [1..τ].
    final cmndf = List<double>.filled(halfN, 0.0);
    cmndf[0] = 1.0;
    double runningSum = 0.0;
    for (var tau = 1; tau <= hi; tau++) {
      runningSum += diff[tau];
      cmndf[tau] = runningSum > 0 ? diff[tau] * tau / runningSum : 1.0;
    }

    // Step 3/4: absolute threshold — 첫 d' < threshold τ 의 local min 까지 진행.
    // 통과 못하면 search range 안 global min fallback.
    int bestTau = -1;
    for (var t = lo; t <= hi; t++) {
      if (cmndf[t] < threshold) {
        while (t + 1 <= hi && cmndf[t + 1] < cmndf[t]) {
          t++;
        }
        bestTau = t;
        break;
      }
    }
    if (bestTau < 0) {
      bestTau = lo;
      for (var t = lo + 1; t <= hi; t++) {
        if (cmndf[t] < cmndf[bestTau]) bestTau = t;
      }
    }

    // Step 5: parabolic interpolation — ±0.5 클램프로 평탄 골 폭주 방지.
    final betterTau = _parabolicInterpolation(cmndf, bestTau);
    if (betterTau <= 0) return null;

    final freq = sampleRate / betterTau;
    final conf = cmndf[bestTau];

    if (conf >= maxConfidence) return null;
    if (!freq.isFinite || freq <= 0) return null;

    return PitchEstimate(freq: freq, confidence: conf);
  }

  /// 이산 최솟값 [x] 주위 3점으로 포물선 적합. 평탄한 골에서 shift 가 폭주하지
  /// 않도록 ±0.5 클램프.
  static double _parabolicInterpolation(List<double> array, int x) {
    if (x <= 0 || x >= array.length - 1) return x.toDouble();
    final denom = 2.0 * (array[x - 1] - 2 * array[x] + array[x + 1]);
    if (denom == 0) return x.toDouble();
    final shift = ((array[x - 1] - array[x + 1]) / denom).clamp(-0.5, 0.5);
    return x + shift;
  }
}

class _EstimateRequest {
  final int id;
  final List<double> samples;
  final int sampleRate;
  final int tauMin;
  final int tauMax;
  final double threshold;
  final double maxConfidence;
  _EstimateRequest({
    required this.id,
    required this.samples,
    required this.sampleRate,
    required this.tauMin,
    required this.tauMax,
    required this.threshold,
    required this.maxConfidence,
  });
}

class _EstimateResponse {
  final int id;
  final PitchEstimate? estimate;
  _EstimateResponse({required this.id, required this.estimate});
}
