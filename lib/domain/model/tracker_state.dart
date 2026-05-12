/// PitchTracker 의 시계열 상태.
///
/// 셋 중 하나:
/// - [TrackerIdle]: 신호 없음 / unvoiced. UI 는 회색.
/// - [TrackerSearching]: 신호는 있지만 어떤 현인지 아직 결정 안 됨. [tentative] 가
///   있으면 UI 는 그 값을 **dim 으로** 표시. 없으면 회색 + hold-timer 사용.
/// - [TrackerLocked]: 한 현이 결정됨. UI 는 그 현의 freq/cents 를 풀 컬러로 표시.
///
/// [TrackerSearching.tentative] 는 항상 **현재 청크에서 갓 만든** TentativePitch.
/// 누적값이 아니라 fresh 데이터라서 stale freq 가 새 나가지 않는다.
sealed class TrackerState {
  const TrackerState();
}

class TrackerIdle extends TrackerState {
  const TrackerIdle();
}

class TrackerSearching extends TrackerState {
  /// 신호 있고 closestString 매핑 성공했을 때 동봉. UI 가 dim 으로 표시.
  /// null 이면 신호는 있지만 어떤 string 으로도 매핑 못함 (예: ±100c 밖) 또는
  /// 첫 청크.
  final TentativePitch? tentative;
  const TrackerSearching({this.tentative});
}

class TrackerLocked extends TrackerState {
  final int stringIndex;
  final double targetFreq;
  final double detectedFreq;
  final double cents;
  final double confidence;
  final double signalLevel;

  const TrackerLocked({
    required this.stringIndex,
    required this.targetFreq,
    required this.detectedFreq,
    required this.cents,
    required this.confidence,
    required this.signalLevel,
  });

  @override
  String toString() =>
      'TrackerLocked(string=$stringIndex, target=${targetFreq.toStringAsFixed(2)}, '
      'detected=${detectedFreq.toStringAsFixed(2)}, cents=${cents.toStringAsFixed(1)}, '
      'conf=${confidence.toStringAsFixed(3)})';
}

/// SEARCHING 중 UI 가 dim 으로 표시할 값. YinEstimator 결과를 가장 가까운 현으로
/// 매핑한 후처리 결과.
class TentativePitch {
  final int stringIndex;
  final double targetFreq;
  final double detectedFreq;
  final double cents;
  final double confidence;

  const TentativePitch({
    required this.stringIndex,
    required this.targetFreq,
    required this.detectedFreq,
    required this.cents,
    required this.confidence,
  });

  @override
  String toString() =>
      'TentativePitch(string=$stringIndex, target=${targetFreq.toStringAsFixed(2)}, '
      'detected=${detectedFreq.toStringAsFixed(2)}, cents=${cents.toStringAsFixed(1)}, '
      'conf=${confidence.toStringAsFixed(3)})';
}
