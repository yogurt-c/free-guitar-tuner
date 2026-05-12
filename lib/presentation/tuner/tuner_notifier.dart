import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/audio_capture.dart';
import '../../data/audio_pipeline.dart';
import '../../domain/analyzer/note_analyzer.dart';
import '../../domain/model/tracker_state.dart';
import '../../domain/model/tuning_preset.dart';
import '../tuning_selector/tuning_selection_notifier.dart';

class TunerState {
  /// 화면 표시용 결과. LOCKED 면 풀 컬러, [isLocked] false 면 dim.
  final TuneResult? tuneResult;
  final double signalLevel;
  final bool permissionDenied;

  /// true: PitchTracker 가 LOCKED 인 청크 — UI 가 풀 컬러.
  /// false + tuneResult != null: hold timer 안 / tentative — UI 가 dim.
  /// false + tuneResult == null: IDLE.
  final bool isLocked;

  const TunerState({
    this.tuneResult,
    this.signalLevel = 0.0,
    this.permissionDenied = false,
    this.isLocked = false,
  });
}

/// AudioPipeline 의 [TrackerState] 스트림을 [TunerState] 로 변환해 UI 에 전달.
///
/// 자동감지: PitchTracker 가 LOCKED 한 stringIndex 가 현재 selectedString 과
/// 다르면 자동 전환. 단 햅틱/tunedStrings 누적은 **사용자가 명시적으로 선택한
/// 현에 대해서만** 호출 — 자동 전환 직후 1 청크 LOCK 으로 잘못 체크되는 걸 차단.
///
/// 깜빡임 차단:
///   - LOCKED: tuneResult 갱신, isLocked=true, hold timer 취소.
///   - SEARCHING+tentative: tentative obs 로 dim 표시 (isLocked=false).
///     fresh 데이터가 있으니 hold timer 취소.
///   - SEARCHING(tentative 없음) / IDLE: 즉시 클리어 안 함. [_holdDuration] 동안
///     마지막 tuneResult 그대로 dim 유지. 그 안에 LOCKED 복귀 시 깜빡임 0.
///   - cents 색 toggle hysteresis: inTune 진입 |c|<3, 유지 |c|<4 (±1 dead zone).
class TunerNotifier extends Notifier<TunerState> {
  /// LOCKED 이탈 후 마지막 결과를 dim 으로 유지할 시간.
  static const _holdDuration = Duration(milliseconds: 600);

  late final AudioPipeline _pipeline;
  StreamSubscription<TrackerState>? _subscription;
  AppLifecycleListener? _lifecycleListener;

  /// non-LOCKED 진입 시 가동 — 만료되면 화면 클리어.
  Timer? _holdTimer;

  /// inTune 진입(<3) vs 유지(<4) 비대칭 임계용. 직전 청크에서 보낸 TuneState.
  TuneState? _prevTuneState;

  /// start/stop 호출 직렬화.
  Future<void>? _ongoing;
  bool _disposed = false;

  @override
  TunerState build() {
    _pipeline = AudioPipeline();

    _lifecycleListener = AppLifecycleListener(
      onPause: () => _stop(),
      onHide: () => _stop(),
      onResume: () => _start(),
    );

    ref.listen(
      tuningSelectionProvider,
      (prev, next) {
        if (prev?.presetKey != next.presetKey ||
            prev?.selectedString != next.selectedString ||
            prev?.autoDetect != next.autoDetect) {
          _pushConfig(next);
        }
      },
      fireImmediately: true,
    );

    _start();

    ref.onDispose(() async {
      _disposed = true;
      _holdTimer?.cancel();
      _holdTimer = null;
      _lifecycleListener?.dispose();
      _lifecycleListener = null;
      await _subscription?.cancel();
      await _pipeline.dispose();
    });

    return const TunerState();
  }

  void _pushConfig(TuningSelectionState s) {
    final preset = tuningPresets[s.presetKey]!;
    _pipeline.updateConfig(
      strings: [for (final n in preset.strings) n.freq],
      autoDetect: s.autoDetect,
      selectedString: s.selectedString,
    );
  }

  Future<void> _runOp(Future<void> Function() op) {
    final prev = _ongoing ?? Future.value();
    final next = prev.catchError((_) {}).then((_) async {
      if (_disposed) return;
      await op();
    });
    _ongoing = next.catchError((_) {});
    return next;
  }

  Future<void> _start() => _runOp(() async {
        if (_subscription != null) return;
        try {
          await _pipeline.start();
          if (_disposed) return;
          _subscription = _pipeline.stateStream.listen(
            _onTrackerState,
            onError: _onPipelineError,
          );
        } on MicrophonePermissionException {
          state = const TunerState(permissionDenied: true);
        } catch (e) {
          debugPrint('[TunerNotifier] start failed: $e');
        }
      });

  Future<void> _stop() => _runOp(() async {
        await _subscription?.cancel();
        _subscription = null;
        _holdTimer?.cancel();
        _holdTimer = null;
        _prevTuneState = null;
        try {
          await _pipeline.stop();
        } catch (e) {
          debugPrint('[TunerNotifier] stop failed: $e');
        }
        if (!_disposed) {
          state = const TunerState();
          ref.read(tuningSelectionProvider.notifier).onTunerUpdate(tuneResult: null);
        }
      });

  /// estimator isolate 예외 등 pipeline 스트림 error 처리.
  /// 마지막 표시 클리어 + 햅틱 누적 중단. pipeline 자체는 살아있으면 다음 hop 부터 복귀.
  void _onPipelineError(Object error, StackTrace st) {
    debugPrint('[TunerNotifier] pipeline error: $error');
    if (_disposed) return;
    _holdTimer?.cancel();
    _holdTimer = null;
    _prevTuneState = null;
    state = const TunerState();
    ref.read(tuningSelectionProvider.notifier).onTunerUpdate(tuneResult: null);
  }

  void _onTrackerState(TrackerState trackerState) {
    switch (trackerState) {
      case TrackerLocked():
        _onLocked(trackerState);
      case TrackerSearching(:final tentative):
        if (tentative != null) {
          _onTentative(tentative);
        } else {
          _onWeak();
        }
      case TrackerIdle():
        _onWeak();
    }
  }

  void _onLocked(TrackerLocked locked) {
    _holdTimer?.cancel();
    _holdTimer = null;

    final selectionNotifier = ref.read(tuningSelectionProvider.notifier);
    final selection = ref.read(tuningSelectionProvider);
    final preset = tuningPresets[selection.presetKey]!;

    // 자동감지: LOCKED 후보가 현재 selectedString 과 다르면 자동 전환.
    // 단 같은 청크에 햅틱/tunedStrings 누적은 보내지 않음 (자동 전환 직후
    // 1청크 LOCK 으로 잘못 체크되는 거 차단). 다음 청크부터 사용자 명시 선택과
    // 같아진 후에 햅틱 누적 시작.
    final autoSwitched = selection.autoDetect &&
        selection.selectedString != locked.stringIndex;
    if (autoSwitched) {
      selectionNotifier.selectString(locked.stringIndex);
    }

    final note = preset.strings[locked.stringIndex];
    final tuneState = _tuneStateFromCents(locked.cents);
    _prevTuneState = tuneState;

    final tuneResult = TuneResult(
      noteName: note.name,
      octave: note.octave,
      targetFreq: locked.targetFreq,
      detectedFreq: locked.detectedFreq,
      cents: locked.cents,
      state: tuneState,
    );

    state = TunerState(
      tuneResult: tuneResult,
      signalLevel: locked.signalLevel,
      isLocked: true,
    );

    // 자동 전환 직후 청크엔 누적 안 함. 다음 청크부터 같은 string LOCK 이어야 누적.
    if (autoSwitched) {
      selectionNotifier.onTunerUpdate(tuneResult: null);
    } else {
      selectionNotifier.onTunerUpdate(tuneResult: tuneResult);
    }
  }

  /// SEARCHING + tentative — 신호 있고 closestString 매핑까지 했지만 LOCK 안 됨.
  /// UI 는 dim 으로 표시. 새 데이터 들어왔으니 hold timer 취소.
  void _onTentative(TentativePitch tentative) {
    _holdTimer?.cancel();
    _holdTimer = null;

    final selection = ref.read(tuningSelectionProvider);
    final preset = tuningPresets[selection.presetKey]!;
    final stringIdx = tentative.stringIndex;
    if (stringIdx < 0 || stringIdx >= preset.strings.length) {
      _onWeak();
      return;
    }
    final note = preset.strings[stringIdx];
    final tuneState = _tuneStateFromCents(tentative.cents);
    _prevTuneState = tuneState;

    final tuneResult = TuneResult(
      noteName: note.name,
      octave: note.octave,
      targetFreq: tentative.targetFreq,
      detectedFreq: tentative.detectedFreq,
      cents: tentative.cents,
      state: tuneState,
    );

    state = TunerState(
      tuneResult: tuneResult,
      signalLevel: 0.0,
      isLocked: false,
    );
    // tentative 동안엔 햅틱/tunedStrings 누적 안 함.
    ref.read(tuningSelectionProvider.notifier).onTunerUpdate(tuneResult: null);
  }

  /// IDLE 또는 SEARCHING(tentative 없음) — 마지막 결과 dim 으로 유지하다 timeout.
  void _onWeak() {
    if (state.tuneResult == null) {
      if (state.isLocked || _prevTuneState != null) {
        _prevTuneState = null;
        state = const TunerState();
        ref.read(tuningSelectionProvider.notifier).onTunerUpdate(tuneResult: null);
      }
      return;
    }

    // LOCKED 였다면 dim 으로 전환하고 timer 시작.
    if (state.isLocked) {
      state = TunerState(
        tuneResult: state.tuneResult,
        signalLevel: 0.0,
        isLocked: false,
      );
      // LOCKED 이탈 즉시 햅틱 누적 중단.
      ref.read(tuningSelectionProvider.notifier).onTunerUpdate(tuneResult: null);
    }

    _holdTimer ??= Timer(_holdDuration, () {
      _holdTimer = null;
      if (_disposed) return;
      _prevTuneState = null;
      state = const TunerState();
      ref.read(tuningSelectionProvider.notifier).onTunerUpdate(tuneResult: null);
    });
  }

  /// inTune 진입은 |c| < 3, 유지는 |c| < 4 (±1 dead zone).
  TuneState _tuneStateFromCents(double cents) {
    final abs = cents.abs();
    if (_prevTuneState == TuneState.inTune ? abs < 4 : abs < 3) {
      return TuneState.inTune;
    }
    return cents < 0 ? TuneState.flat : TuneState.sharp;
  }
}

final tunerProvider = NotifierProvider<TunerNotifier, TunerState>(
  TunerNotifier.new,
);
