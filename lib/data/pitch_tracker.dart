import 'dart:math';

import '../domain/model/pitch_estimate.dart';
import '../domain/model/tracker_state.dart';

/// 청크별 [PitchEstimate] 와 RMS 를 받아 시계열 state machine 으로 어느 현을
/// 튜닝 중인지 결정한다.
///
/// 외부 [YinEstimator] 는 fundamental 1개만 추정한다. tracker 는 그것을 preset 의
/// 6 현 중 **가장 가까운 현 (closestString)** 으로 매핑하고, 그 거리가 일정
/// 임계 안 ([lockMaxCents]) 일 때만 LOCK 후보로 인정한다.
///
/// 상태:
///   IDLE      : 신호 없음 / unvoiced / manual 모드에서 선택 안 한 현 잡힘.
///   SEARCHING : 신호 있고 매핑도 됐지만 아직 LOCK 안 됨. tentative 동봉 (UI 가 dim).
///   LOCKED    : 한 현이 결정됨. 그 현의 freq/cents 만 표시.
///
/// 청크 rate: AudioPipeline 의 sliding window (4096 win / 1024 hop) 로 ≈ 43 Hz.
/// 모든 frame-count 상수는 hop 수 기준 (1 hop ≈ 23 ms).
///
/// 깜빡임 차단:
///   - **2단 RMS hysteresis** ([noiseGateEnter] 0.012 / [noiseGateExit] 0.006)
///   - **idle grace** ([idleGraceFrames] 12 hops ≈ 280ms)
///   - **2단 confidence** (lock 진입 [lockEnterConf] strict / 유지 [lockKeepConf] 관대)
///   - **rise-gated hand-off**: 다른 현으로의 즉시 hand-off 는 signal 상승 시에만
///   - **detectedFreq EMA** ([freqEmaAlpha] 0.10, τ≈220ms) — SEARCHING / LOCKED
///     모두에 적용. 같은 현 유지 중엔 freq history 가 끊기지 않음.
///
/// 매핑 정책:
///   - 자동감지: 어떤 현이든 closestString 으로 매핑 (단 [lockMaxCents] 안).
///   - 수동: closestString 이 [selectedString] 과 다르면 silence (IDLE).
///
/// 전환:
///   ANY → IDLE             : RMS < noiseGateExit / estimate null 이 idleGraceFrames 연속
///                            또는 (수동 + 선택 안 한 현) 이 unlockFrames 연속
///   IDLE → SEARCHING       : voiced + 매핑 OK + (auto 또는 매핑이 selected 와 같음)
///   SEARCHING → LOCKED     : 같은 closestString 이 [lockFrames] 연속 + confidence < lockEnterConf
///   LOCKED(s) 유지         : closestString == s + confidence < lockKeepConf — freq EMA 갱신
///   LOCKED(s) 즉시 hand-off : signal rising + 다른 string + confidence < lockEnterConf
///   LOCKED(s) 점진 해제     : 다른 closestString 이 [unlockFrames] 연속
class PitchTracker {
  // ─ 정책 임계 (hop 단위, hop ≈ 23 ms) ────────────────────────────────────

  /// 신호 있다고 판정할 RMS (SEARCHING / LOCKED 유지).
  static const noiseGateEnter = 0.012;

  /// 신호 사라졌다고 판정할 RMS (IDLE 이탈). Enter 보다 낮아야 hysteresis.
  static const noiseGateExit = 0.006;

  /// 약신호 hop 이 이만큼 연속이어야 IDLE 로 확정. 일시 dip 무시.
  /// 12 hops ≈ 280 ms.
  static const idleGraceFrames = 12;

  /// signal 상승 게이트 — 직전 hop 보다 RMS 가 이 이상 커지면 "새 스트럼".
  /// LOCKED 중 다른 현으로의 hand-off 는 이때만 허용.
  static const rmsRiseThreshold = 0.006;

  /// LOCK 진입 임계 (strict). 이 미만이면 강한 fundamental.
  static const lockEnterConf = 0.20;

  /// LOCKED 유지 임계 (관대). 한 hop 살짝 약해져도 유지.
  static const lockKeepConf = 0.40;

  /// SEARCHING 중 같은 현이 연속 나와야 LOCK 진입할 hop 수.
  /// overlap (75%) 때문에 consecutive hop 들이 고도로 correlated — 4 hops 면
  /// 사실상 1 개의 fully-independent 윈도우 검증 (≈ 93 ms wall time).
  static const lockFrames = 4;

  /// LOCKED 중 다른 현이 이만큼 연속이면 (signal 평탄해도) SEARCHING.
  /// rise-gated hand-off 가 안 일어나도 점진 해제 보장. 12 hops ≈ 280 ms.
  static const unlockFrames = 12;

  /// closestString 거리 (cents) 임계. 이보다 멀면 LOCK 후보로 인정 안 함 — SEARCHING
  /// (tentative 없음). 광범위 search 광범위 freq → 안전한 wrong-string 차단.
  static const lockMaxCents = 100.0;

  /// detectedFreq EMA 가중치 (새 값). 1 - α 가 이전 값 비중.
  /// α=0.10, hop=23ms → τ ≈ 220 ms (이전 청크 모델 0.35 / 93ms 와 동일 time constant).
  /// SEARCHING / LOCKED 둘 다 적용 — 같은 현 유지 중엔 freq 가 계속 smooth 됨.
  static const freqEmaAlpha = 0.10;

  // ─ 동적 입력 (외부에서 setter 로 갱신) ────────────────────────────────────

  /// preset 의 각 현 nominal freq. 6 elements 가 일반적이지만 어떤 길이도 OK.
  List<double> _stringFreqs = const [];

  /// 사용자가 선택한 현 인덱스. 자동감지 모드에선 의미 없음 (LOCK 후 외부에서 동기).
  int _selectedString = 0;

  /// true 면 모든 현 후보, false 면 [_selectedString] 만 후보.
  bool _autoDetect = true;

  // ─ 시계열 상태 ──────────────────────────────────────────────────────────

  TrackerState _state = const TrackerIdle();
  int _lastClosest = -1;
  int _sameStringFrames = 0;
  int _otherStringFrames = 0;
  int _lowSignalFrames = 0;
  double _prevSignalLevel = 0.0;

  double? _smoothedFreq;
  int _smoothedStringIndex = -1;

  TrackerState get state => _state;

  // ─ Public API ──────────────────────────────────────────────────────────

  void setStrings(List<double> freqs) {
    final changed = !_freqsEqual(_stringFreqs, freqs);
    _stringFreqs = List.unmodifiable(freqs);
    if (changed) reset();
  }

  void setSelectedString(int idx) {
    if (_selectedString == idx) return;
    _selectedString = idx;
    // 모드/현 전환 시 LOCK 상태 초기화 — 이전 현의 lock 이 새 현으로 새지 않도록.
    if (!_autoDetect) reset();
  }

  void setAutoDetect(bool v) {
    if (_autoDetect == v) return;
    _autoDetect = v;
    reset();
  }

  void reset() {
    _state = const TrackerIdle();
    _lastClosest = -1;
    _sameStringFrames = 0;
    _otherStringFrames = 0;
    _lowSignalFrames = 0;
    _prevSignalLevel = 0.0;
    _smoothedFreq = null;
    _smoothedStringIndex = -1;
  }

  TrackerState update(
    PitchEstimate? estimate, {
    required double signalLevel,
  }) {
    final signalRising =
        signalLevel > _prevSignalLevel + rmsRiseThreshold;
    _prevSignalLevel = signalLevel;

    // 1) 신호 약함 / estimate 없음 → idle grace 누적.
    final lowSignal = signalLevel < noiseGateExit || estimate == null;
    if (lowSignal) {
      _lowSignalFrames++;
      if (_lowSignalFrames >= idleGraceFrames) {
        _state = const TrackerIdle();
        _resetCounters();
        _resetSmoothing();
      }
      // grace 안: 이전 state 유지.
      return _state;
    }
    _lowSignalFrames = 0;

    // 2) closestString 매핑. ±lockMaxCents 안만 인정.
    final mapped = _mapToString(estimate.freq);
    if (mapped == null) {
      // 매핑 miss — SEARCHING (tentative 없음). hold timer 가 깜빡임 막음.
      _sameStringFrames = 0;
      _lastClosest = -1;
      // LOCKED 였으면 grace 안에선 유지 + 점진 해제 카운트.
      // 카운터는 _maybeUnlock 이 ++ 하므로 여기서 reset 하지 않는다.
      if (_state is TrackerLocked) {
        return _maybeUnlock();
      }
      _otherStringFrames = 0;
      _state = const TrackerSearching();
      return _state;
    }

    // 3) 수동 모드 + 선택 안 한 현 → silence (IDLE).
    if (!_autoDetect && mapped.stringIndex != _selectedString) {
      _sameStringFrames = 0;
      _lastClosest = -1;
      if (_state is TrackerLocked) {
        return _maybeUnlock();
      }
      _otherStringFrames = 0;
      _state = const TrackerIdle();
      return _state;
    }

    // 4) 유효 후보 — LOCKED 분기 or SEARCHING 분기.
    final cur = _state;
    if (cur is TrackerLocked) {
      return _handleLocked(cur, mapped, estimate, signalLevel,
          signalRising: signalRising);
    }
    return _handleSearching(mapped, estimate, signalLevel);
  }

  // ─ 내부 ─────────────────────────────────────────────────────────────────

  TrackerState _handleSearching(
    _Mapped mapped,
    PitchEstimate est,
    double signalLevel,
  ) {
    if (mapped.stringIndex == _lastClosest) {
      _sameStringFrames++;
    } else {
      // 새 현 후보 — freq smoothing 도 리셋 (이전 현 EMA 가 새 현으로 새지 않게).
      _lastClosest = mapped.stringIndex;
      _sameStringFrames = 1;
      _resetSmoothing();
    }
    _otherStringFrames = 0;

    // SEARCHING tentative 도 LOCKED 와 같은 EMA 사용. tentative ↔ locked 전환에서
    // detectedFreq 가 부드럽게 이어짐. raw freq jitter (특히 고음현 13 c/sample) 가
    // UI 에 그대로 노출되는 게 1, 2번 현 진동의 핵심 원인이라 여기서 차단.
    final smoothFreq = _applySmoothing(mapped.stringIndex, est.freq);
    final smoothCents = 1200 * log(smoothFreq / mapped.targetFreq) / ln2;
    final tentative = TentativePitch(
      stringIndex: mapped.stringIndex,
      targetFreq: mapped.targetFreq,
      detectedFreq: smoothFreq,
      cents: smoothCents,
      confidence: est.confidence,
    );

    if (_sameStringFrames >= lockFrames && est.confidence < lockEnterConf) {
      _state = TrackerLocked(
        stringIndex: mapped.stringIndex,
        targetFreq: mapped.targetFreq,
        detectedFreq: smoothFreq,
        cents: smoothCents,
        confidence: est.confidence,
        signalLevel: signalLevel,
      );
    } else {
      _state = TrackerSearching(tentative: tentative);
    }
    return _state;
  }

  TrackerState _handleLocked(
    TrackerLocked cur,
    _Mapped mapped,
    PitchEstimate est,
    double signalLevel, {
    required bool signalRising,
  }) {
    if (mapped.stringIndex == cur.stringIndex) {
      // 자기 현 — 유지 + EMA 갱신.
      _otherStringFrames = 0;
      if (est.confidence < lockKeepConf) {
        _state = _updateLocked(mapped, est, signalLevel);
      }
      // confidence ≥ lockKeepConf 면 raw freq 안 받음 (이전 EMA 그대로 유지).
      return _state;
    }

    // 다른 현 후보.
    // 즉시 hand-off: signal rising + 새 후보 confidence strong.
    if (signalRising && est.confidence < lockEnterConf) {
      _lastClosest = mapped.stringIndex;
      _sameStringFrames = 1;
      _otherStringFrames = 0;
      _resetSmoothing();
      _state = TrackerSearching(tentative: _tentativeWithSmoothing(mapped, est));
      return _state;
    }

    // 점진 해제 카운트.
    _otherStringFrames++;
    if (_otherStringFrames >= unlockFrames) {
      _lastClosest = mapped.stringIndex;
      _sameStringFrames = 1;
      _otherStringFrames = 0;
      _resetSmoothing();
      _state = TrackerSearching(tentative: _tentativeWithSmoothing(mapped, est));
      return _state;
    }
    // grace 안 — LOCKED 유지.
    return _state;
  }

  /// LOCKED 인데 매핑 실패 / 수동 선택 안 한 현 등 후보 자격 잃은 케이스.
  /// otherFrames 카운트하면서 grace 안에선 유지.
  TrackerState _maybeUnlock() {
    _otherStringFrames++;
    if (_otherStringFrames >= unlockFrames) {
      _resetCounters();
      _resetSmoothing();
      _state = const TrackerIdle();
    }
    return _state;
  }

  TrackerLocked _updateLocked(_Mapped mapped, PitchEstimate est, double sig) {
    final freq = _applySmoothing(mapped.stringIndex, est.freq);
    final cents = 1200 * log(freq / mapped.targetFreq) / ln2;
    return TrackerLocked(
      stringIndex: mapped.stringIndex,
      targetFreq: mapped.targetFreq,
      detectedFreq: freq,
      cents: cents,
      confidence: est.confidence,
      signalLevel: sig,
    );
  }

  /// hand-off / 점진 해제 시 새 현으로 SEARCHING 으로 빠질 때 부르는 헬퍼.
  /// _resetSmoothing 이 직전에 호출됐다고 가정 — est.freq 가 첫 EMA 값이 됨.
  TentativePitch _tentativeWithSmoothing(_Mapped mapped, PitchEstimate est) {
    final freq = _applySmoothing(mapped.stringIndex, est.freq);
    final cents = 1200 * log(freq / mapped.targetFreq) / ln2;
    return TentativePitch(
      stringIndex: mapped.stringIndex,
      targetFreq: mapped.targetFreq,
      detectedFreq: freq,
      cents: cents,
      confidence: est.confidence,
    );
  }

  /// 같은 현 유지면 EMA, 다른 현으로 바뀐 직후면 est.freq 가 첫 값이 됨.
  /// 호출자가 string 전환 시 [_resetSmoothing] 을 먼저 부르도록 보장해야 함.
  double _applySmoothing(int stringIndex, double rawFreq) {
    final double freq;
    if (_smoothedStringIndex == stringIndex && _smoothedFreq != null) {
      freq = freqEmaAlpha * rawFreq + (1 - freqEmaAlpha) * _smoothedFreq!;
    } else {
      freq = rawFreq;
    }
    _smoothedFreq = freq;
    _smoothedStringIndex = stringIndex;
    return freq;
  }

  /// freq 를 가장 가까운 현으로 매핑. 거리가 [lockMaxCents] 초과면 null.
  _Mapped? _mapToString(double freq) {
    if (_stringFreqs.isEmpty || freq <= 0) return null;
    var bestIdx = 0;
    var bestAbsCents = double.infinity;
    var bestSignedCents = 0.0;
    for (var i = 0; i < _stringFreqs.length; i++) {
      final target = _stringFreqs[i];
      if (target <= 0) continue;
      final signed = 1200 * log(freq / target) / ln2;
      final abs = signed.abs();
      if (abs < bestAbsCents) {
        bestAbsCents = abs;
        bestSignedCents = signed;
        bestIdx = i;
      }
    }
    if (bestAbsCents > lockMaxCents) return null;
    return _Mapped(
      stringIndex: bestIdx,
      targetFreq: _stringFreqs[bestIdx],
      cents: bestSignedCents,
    );
  }

  void _resetCounters() {
    _lastClosest = -1;
    _sameStringFrames = 0;
    _otherStringFrames = 0;
    _lowSignalFrames = 0;
  }

  void _resetSmoothing() {
    _smoothedFreq = null;
    _smoothedStringIndex = -1;
  }

  static bool _freqsEqual(List<double> a, List<double> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

class _Mapped {
  final int stringIndex;
  final double targetFreq;
  final double cents;
  const _Mapped(
      {required this.stringIndex,
      required this.targetFreq,
      required this.cents});
}
