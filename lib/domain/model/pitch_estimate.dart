/// 한 청크에서 YinEstimator 가 추정한 단일 fundamental.
///
/// - [freq]: 추정 fundamental 주파수 (Hz). 0보다 크다.
/// - [confidence]: YIN paper 의 d'(τ_best). **낮을수록 신뢰**.
///   대략 0.10 미만이면 매우 강한 fundamental, 0.30 이상이면 신뢰 어려움.
///
/// estimator 가 voiced 신호로 인정하지 못하면 [PitchEstimate] 대신 null 을 반환한다.
/// (RMS 게이트 / threshold 미통과 / search range 비어있음)
class PitchEstimate {
  final double freq;
  final double confidence;

  const PitchEstimate({required this.freq, required this.confidence});

  @override
  String toString() =>
      'PitchEstimate(freq=${freq.toStringAsFixed(2)}, conf=${confidence.toStringAsFixed(3)})';
}
