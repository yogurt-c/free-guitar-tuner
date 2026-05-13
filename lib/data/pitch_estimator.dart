import '../domain/model/pitch_estimate.dart';

/// Pitch 추정기 공통 인터페이스. AudioPipeline 이 의존하는 추상.
///
/// 같은 sliding window (4096 sample) + 같은 search range (tauMin/tauMax) 을
/// 받아 동일한 의미의 결과 ([PitchEstimate]? null) 를 반환해야 한다.
/// 그래야 두 구현 (YIN 직접 / pitch_detector_dart 라이브러리) 을 동일한
/// PitchTracker / AudioPipeline 위에서 교체 비교할 수 있다.
abstract class PitchEstimator {
  /// 한 청크에서 fundamental 추정.
  ///
  /// [tauMin] / [tauMax] 는 검색할 lag 범위. 구현체가 native 로 search range
  /// 좁힘을 지원하지 않으면 후처리 freq 필터로 사용 가능.
  ///
  /// voiced + 신뢰 통과 시 [PitchEstimate], 그 외 null.
  Future<PitchEstimate?> estimate(
    List<double> samples, {
    required int tauMin,
    required int tauMax,
    int sampleRate,
  });

  Future<void> dispose();
}
