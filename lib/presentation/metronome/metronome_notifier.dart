import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

import '../../data/metronome_sound.dart';

class MetronomeState {
  final int bpm;
  final bool isPlaying;
  final int beatsPerBar;
  final int currentBeat;

  const MetronomeState({
    required this.bpm,
    required this.isPlaying,
    required this.beatsPerBar,
    required this.currentBeat,
  });

  factory MetronomeState.initial() => const MetronomeState(
        bpm: 120,
        isPlaying: false,
        beatsPerBar: 4,
        currentBeat: -1,
      );

  MetronomeState copyWith({
    int? bpm,
    bool? isPlaying,
    int? beatsPerBar,
    int? currentBeat,
  }) =>
      MetronomeState(
        bpm: bpm ?? this.bpm,
        isPlaying: isPlaying ?? this.isPlaying,
        beatsPerBar: beatsPerBar ?? this.beatsPerBar,
        currentBeat: currentBeat ?? this.currentBeat,
      );

  String get tempoName {
    if (bpm < 60) return 'Largo';
    if (bpm < 76) return 'Adagio';
    if (bpm < 108) return 'Andante';
    if (bpm < 120) return 'Moderato';
    if (bpm < 156) return 'Allegro';
    if (bpm < 176) return 'Vivace';
    return 'Presto';
  }
}

/// Lookahead Scheduler 방식의 메트로놈.
///
/// Timer.periodic은 25ms 간격으로 스케줄러만 구동하고,
/// 실제 비트 타이밍은 Stopwatch 기반 절댓값으로 계산한다.
/// 각 비트는 Future.delayed로 정확한 시점에 독립 발사된다.
/// Generation 카운터로 stop/restart 시 미결 콜백을 무효화한다.
class MetronomeNotifier extends Notifier<MetronomeState> {
  static const _schedulerTickMs = 25;
  static const _scheduleAheadSec = 0.1; // 100 ms 앞을 내다보고 예약

  AudioSource? _accentSource;
  AudioSource? _beatSource;
  bool _audioReady = false;

  Timer? _schedulerTimer;
  final _stopwatch = Stopwatch();
  double _nextBeatSec = 0.0;
  int _nextBeat = 0;

  // 이 값이 바뀌면 이전에 예약된 모든 Future.delayed 콜백이 무효화된다.
  int _generation = 0;

  @override
  MetronomeState build() {
    Future.microtask(_loadSounds);

    ref.onDispose(() {
      _killScheduler();
      if (_accentSource != null) SoLoud.instance.disposeSource(_accentSource!);
      if (_beatSource != null) SoLoud.instance.disposeSource(_beatSource!);
    });

    return MetronomeState.initial();
  }

  Future<void> _loadSounds() async {
    _accentSource = await SoLoud.instance.loadMem(
      'click_accent',
      buildClickWav(accent: true),
    );
    _beatSource = await SoLoud.instance.loadMem(
      'click_beat',
      buildClickWav(accent: false),
    );
    _audioReady = true;
  }

  // ─── Public API ──────────────────────────────────────────────────────────

  void togglePlay() {
    if (state.isPlaying) {
      _killScheduler();
      state = state.copyWith(isPlaying: false, currentBeat: -1);
    } else {
      state = state.copyWith(isPlaying: true);
      _launchScheduler();
    }
  }

  /// 탭 이동 등 외부에서 강제 정지.
  void stop() {
    if (!state.isPlaying) return;
    _killScheduler();
    state = state.copyWith(isPlaying: false, currentBeat: -1);
  }

  void setBpm(int bpm) {
    state = state.copyWith(bpm: bpm);
    // 재시작 불필요 — 스케줄러가 state.bpm을 실시간으로 참조함
  }

  void setBeatsPerBar(int beats) {
    state = state.copyWith(beatsPerBar: beats);
    if (state.isPlaying) _resetBar();
  }

  // ─── Scheduler internals ─────────────────────────────────────────────────

  void _launchScheduler() {
    _stopwatch
      ..reset()
      ..start();
    _nextBeatSec = 0.0;
    _nextBeat = 0;

    final gen = ++_generation;

    _schedulerTimer = Timer.periodic(
      const Duration(milliseconds: _schedulerTickMs),
      (_) => _tick(gen),
    );
  }

  void _killScheduler() {
    _generation++; // 미결 Future.delayed 콜백 무효화
    _schedulerTimer?.cancel();
    _schedulerTimer = null;
    _stopwatch
      ..stop()
      ..reset();
  }

  /// 박자표 변경 시: generation만 올리고 타이머는 유지, 다음 틱부터 새 bar.
  void _resetBar() {
    _generation++;
    _nextBeatSec = _stopwatch.elapsedMicroseconds / 1e6;
    _nextBeat = 0;
    state = state.copyWith(currentBeat: -1);

    final gen = ++_generation; // launchScheduler 없이 generation 재발급
    // 기존 타이머가 이미 실행 중이므로 새 gen으로 교체
    _schedulerTimer?.cancel();
    _schedulerTimer = Timer.periodic(
      const Duration(milliseconds: _schedulerTickMs),
      (_) => _tick(gen),
    );
  }

  void _tick(int gen) {
    if (gen != _generation) return;

    final nowSec = _stopwatch.elapsedMicroseconds / 1e6;

    while (_nextBeatSec < nowSec + _scheduleAheadSec) {
      final beat = _nextBeat;
      final delayUs = ((_nextBeatSec - nowSec) * 1e6).round().clamp(0, 500000);

      if (delayUs == 0) {
        _fireBeat(beat: beat, gen: gen);
      } else {
        Future.delayed(Duration(microseconds: delayUs), () {
          _fireBeat(beat: beat, gen: gen);
        });
      }

      _nextBeat = (_nextBeat + 1) % state.beatsPerBar;
      _nextBeatSec += 60.0 / state.bpm;
    }
  }

  void _fireBeat({required int beat, required int gen}) {
    if (gen != _generation) return;
    _emitSound(beat: beat);
    state = state.copyWith(currentBeat: beat);
  }

  void _emitSound({required int beat}) {
    if (!_audioReady) return;
    final source = beat == 0 ? _accentSource : _beatSource;
    if (source == null) return;
    SoLoud.instance.play(source); // fire-and-forget; 40 ms 클릭은 자동 종료
  }
}

final metronomeProvider =
    NotifierProvider<MetronomeNotifier, MetronomeState>(MetronomeNotifier.new);
