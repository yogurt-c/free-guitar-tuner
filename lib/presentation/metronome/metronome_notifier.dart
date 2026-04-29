import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

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

class MetronomeNotifier extends Notifier<MetronomeState> {
  Timer? _timer;

  @override
  MetronomeState build() {
    ref.onDispose(_stopTimer);
    return MetronomeState.initial();
  }

  void setBpm(int bpm) {
    state = state.copyWith(bpm: bpm);
    if (state.isPlaying) _restartTimer();
  }

  void setBeatsPerBar(int beats) {
    state = state.copyWith(beatsPerBar: beats, currentBeat: -1);
    if (state.isPlaying) _restartTimer();
  }

  void togglePlay() {
    if (state.isPlaying) {
      _stopTimer();
      state = state.copyWith(isPlaying: false, currentBeat: -1);
    } else {
      state = state.copyWith(isPlaying: true, currentBeat: 0);
      _startTimer();
    }
  }

  void _startTimer() {
    _timer = Timer.periodic(
      Duration(milliseconds: (60000 / state.bpm).round()),
      (_) {
        final next = (state.currentBeat + 1) % state.beatsPerBar;
        state = state.copyWith(currentBeat: next);
      },
    );
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  void _restartTimer() {
    _stopTimer();
    state = state.copyWith(currentBeat: 0);
    _startTimer();
  }
}

final metronomeProvider =
    NotifierProvider<MetronomeNotifier, MetronomeState>(MetronomeNotifier.new);
