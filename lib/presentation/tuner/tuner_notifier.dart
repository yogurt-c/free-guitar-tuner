import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/audio_capture.dart';
import '../../data/audio_pipeline.dart';
import '../../domain/analyzer/note_analyzer.dart';
import '../../domain/model/tuning_preset.dart';
import '../tuning_selector/tuning_selection_notifier.dart';

class TunerState {
  final TuneResult? tuneResult;
  final double signalLevel;
  final bool permissionDenied;

  const TunerState({
    this.tuneResult,
    this.signalLevel = 0.0,
    this.permissionDenied = false,
  });
}

class TunerNotifier extends Notifier<TunerState> {
  static const _noiseGateThreshold = 0.01;
  // 신호 소실 후 gray로 전환하기까지의 대기 시간 (순간 dip으로 인한 깜빡임 방지)
  static const _resultHoldDuration = Duration(milliseconds: 300);

  late final AudioPipeline _pipeline;
  StreamSubscription<PitchResult>? _subscription;
  Timer? _clearTimer;
  AppLifecycleListener? _lifecycleListener;

  /// start/stop 호출을 직렬화하여 race를 차단한다.
  /// 화면 잠금/해제가 빠르게 토글되어도 마지막 의도가 일관되게 적용됨.
  Future<void>? _ongoing;
  bool _disposed = false;

  @override
  TunerState build() {
    _pipeline = AudioPipeline();

    // 화면 off/background 진입 시 마이크/오디오 세션을 명시적으로 stop 한다.
    // OS가 mic 스트림을 끊은 뒤 복귀해도 자동 재시작되지 않던 문제 해결.
    _lifecycleListener = AppLifecycleListener(
      onPause: () => _stop(),
      onHide: () => _stop(),
      onResume: () => _start(),
    );

    // 선택된 현/preset/자동감지 모드 변경에 따라 후보 주파수 갱신.
    ref.listen(
      tuningSelectionProvider,
      (prev, next) {
        if (prev?.presetKey != next.presetKey ||
            prev?.selectedString != next.selectedString ||
            prev?.autoDetect != next.autoDetect) {
          _pipeline.setCandidates(_candidatesFor(next));
        }
      },
      fireImmediately: true,
    );

    _start();

    ref.onDispose(() async {
      _disposed = true;
      _lifecycleListener?.dispose();
      _lifecycleListener = null;
      _clearTimer?.cancel();
      await _subscription?.cancel();
      await _pipeline.dispose();
    });

    return const TunerState();
  }

  List<double> _candidatesFor(TuningSelectionState s) {
    final preset = tuningPresets[s.presetKey]!;
    if (s.autoDetect) {
      return [for (final note in preset.strings) note.freq];
    }
    return [preset.strings[s.selectedString].freq];
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
          _subscription = _pipeline.pitchStream.listen(_onPitchResult);
        } on MicrophonePermissionException {
          state = const TunerState(permissionDenied: true);
        } catch (e) {
          debugPrint('[TunerNotifier] start failed: $e');
        }
      });

  Future<void> _stop() => _runOp(() async {
        _clearTimer?.cancel();
        _clearTimer = null;
        await _subscription?.cancel();
        _subscription = null;
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

  void _onPitchResult(PitchResult result) {
    final selectionNotifier = ref.read(tuningSelectionProvider.notifier);

    if (result.signalLevel < _noiseGateThreshold || result.freq == null) {
      // 마지막 유효 결과를 잠시 유지한 후 gray로 전환
      if (_clearTimer == null || !_clearTimer!.isActive) {
        _clearTimer = Timer(_resultHoldDuration, () {
          state = const TunerState();
          selectionNotifier.onTunerUpdate(tuneResult: null);
        });
      }
      return;
    }

    _clearTimer?.cancel();
    _clearTimer = null;

    final selection = ref.read(tuningSelectionProvider);
    final preset = tuningPresets[selection.presetKey]!;
    final targetNote = preset.strings[selection.selectedString];
    final tuneResult = NoteAnalyzer.analyzeAgainstTarget(result.freq!, targetNote);

    state = TunerState(
      tuneResult: tuneResult,
      signalLevel: result.signalLevel,
    );
    selectionNotifier.onTunerUpdate(tuneResult: tuneResult);
  }
}

final tunerProvider = NotifierProvider<TunerNotifier, TunerState>(
  TunerNotifier.new,
);
