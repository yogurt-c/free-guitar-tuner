import 'dart:async';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

class MetronomeNotifier extends Notifier<MetronomeState> {
  Timer? _timer;
  late final AudioPlayer _accentPlayer;
  late final AudioPlayer _beatPlayer;
  late final Uint8List _accentWav;
  late final Uint8List _beatWav;

  @override
  MetronomeState build() {
    _accentPlayer = AudioPlayer();
    _beatPlayer = AudioPlayer();
    _accentWav = buildClickWav(accent: true);
    _beatWav = buildClickWav(accent: false);

    ref.onDispose(() {
      _stopTimer();
      _accentPlayer.dispose();
      _beatPlayer.dispose();
    });

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
      _playBeat(isAccent: true);
      _startTimer();
    }
  }

  /// 탭 이동 등 외부에서 강제 정지할 때 사용
  void stop() {
    if (!state.isPlaying) return;
    _stopTimer();
    state = state.copyWith(isPlaying: false, currentBeat: -1);
  }

  void _playBeat({required bool isAccent}) {
    final player = isAccent ? _accentPlayer : _beatPlayer;
    final wav = isAccent ? _accentWav : _beatWav;
    player.play(BytesSource(wav));
  }

  void _startTimer() {
    _timer = Timer.periodic(
      Duration(milliseconds: (60000 / state.bpm).round()),
      (_) {
        final next = (state.currentBeat + 1) % state.beatsPerBar;
        state = state.copyWith(currentBeat: next);
        _playBeat(isAccent: next == 0);
      },
    );
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  // BPM/박자 변경 시: 즉시 소리 없이 재시작 (슬라이더 드래그 중 소리 안 남)
  void _restartTimer() {
    _stopTimer();
    state = state.copyWith(currentBeat: -1);
    _startTimer();
  }
}

final metronomeProvider =
    NotifierProvider<MetronomeNotifier, MetronomeState>(MetronomeNotifier.new);
