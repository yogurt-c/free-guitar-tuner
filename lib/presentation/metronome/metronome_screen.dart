import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/app_theme.dart';
import '../tuner/widgets/top_bar.dart';
import '../tuning_selector/tuning_selection_notifier.dart';
import 'metronome_notifier.dart';

class MetronomeScreen extends ConsumerWidget {
  const MetronomeScreen({super.key, required this.onMenuTap});

  final VoidCallback onMenuTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selection = ref.watch(tuningSelectionProvider);
    final selectionNotifier = ref.read(tuningSelectionProvider.notifier);
    final metro = ref.watch(metronomeProvider);
    final notifier = ref.read(metronomeProvider.notifier);

    final theme = AppTheme(isDark: selection.isDark);

    return Scaffold(
      backgroundColor: theme.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            TopBar(
              theme: theme,
              isDark: selection.isDark,
              modeLabel: 'Metronome',
              onMenuTap: onMenuTap,
              onThemeToggle: selectionNotifier.toggleDark,
            ),
            const Spacer(),
            _BpmDisplay(theme: theme, metro: metro),
            const SizedBox(height: 36),
            _BeatDots(theme: theme, metro: metro),
            const SizedBox(height: 28),
            _TimeSignatureSelector(
              theme: theme,
              selected: metro.beatsPerBar,
              onSelect: notifier.setBeatsPerBar,
            ),
            const SizedBox(height: 32),
            _BpmSlider(
              theme: theme,
              metro: metro,
              onChanged: notifier.setBpm,
              onIncrement: notifier.incrementBpm,
              onDecrement: notifier.decrementBpm,
            ),
            const Spacer(),
            _PlayButton(theme: theme, isPlaying: metro.isPlaying, onTap: notifier.togglePlay),
            SizedBox(height: MediaQuery.of(context).padding.bottom + 40),
          ],
        ),
      ),
    );
  }
}

class _BpmDisplay extends StatelessWidget {
  const _BpmDisplay({required this.theme, required this.metro});

  final AppTheme theme;
  final MetronomeState metro;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          '${metro.bpm}',
          style: TextStyle(
            fontSize: 96,
            fontWeight: FontWeight.w200,
            height: 1,
            color: theme.text,
            letterSpacing: -4,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          metro.tempoName.toUpperCase(),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 2.5,
            color: theme.textDim,
          ),
        ),
      ],
    );
  }
}

class _BeatDots extends StatelessWidget {
  const _BeatDots({required this.theme, required this.metro});

  final AppTheme theme;
  final MetronomeState metro;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(metro.beatsPerBar, (i) {
        final isActive = metro.isPlaying && i == metro.currentBeat;
        final isDownbeat = i == 0;
        final size = isDownbeat ? 14.0 : 9.0;

        return AnimatedContainer(
          duration: const Duration(milliseconds: 80),
          margin: const EdgeInsets.symmetric(horizontal: 6),
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isActive ? theme.accent : theme.surface2,
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: theme.accent.withAlpha(120),
                      blurRadius: 12,
                      spreadRadius: 2,
                    ),
                  ]
                : null,
          ),
        );
      }),
    );
  }
}

class _TimeSignatureSelector extends StatelessWidget {
  const _TimeSignatureSelector({
    required this.theme,
    required this.selected,
    required this.onSelect,
  });

  final AppTheme theme;
  final int selected;
  final void Function(int) onSelect;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [3, 4, 6, 8].map((beats) {
        final isSelected = beats == selected;
        return GestureDetector(
          onTap: () => onSelect(beats),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            margin: const EdgeInsets.symmetric(horizontal: 5),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            decoration: BoxDecoration(
              color: isSelected
                  ? theme.accent.withAlpha(30)
                  : theme.surface2,
              borderRadius: BorderRadius.circular(10),
              border: isSelected
                  ? Border.all(color: theme.accent.withAlpha(180))
                  : null,
            ),
            child: Text(
              '$beats/4',
              style: TextStyle(
                fontSize: 14,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                color: isSelected ? theme.accent : theme.textMuted,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _BpmSlider extends StatelessWidget {
  const _BpmSlider({
    required this.theme,
    required this.metro,
    required this.onChanged,
    required this.onIncrement,
    required this.onDecrement,
  });

  final AppTheme theme;
  final MetronomeState metro;
  final void Function(int) onChanged;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          Row(
            children: [
              _BpmAdjustButton(theme: theme, isIncrement: false, onStep: onDecrement),
              const SizedBox(width: 4),
              Expanded(
                child: SliderTheme(
                  data: SliderThemeData(
                    trackHeight: 2,
                    activeTrackColor: theme.accent,
                    inactiveTrackColor: theme.surface2,
                    thumbColor: theme.accent,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                    overlayColor: theme.accent.withAlpha(30),
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
                  ),
                  child: Slider(
                    value: metro.bpm.toDouble(),
                    min: 40,
                    max: 220,
                    divisions: 180,
                    onChanged: (v) => onChanged(v.round()),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              _BpmAdjustButton(theme: theme, isIncrement: true, onStep: onIncrement),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('40', style: TextStyle(fontSize: 10, color: theme.textDim)),
                Text('BPM', style: TextStyle(fontSize: 10, letterSpacing: 1, color: theme.textDim)),
                Text('220', style: TextStyle(fontSize: 10, color: theme.textDim)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BpmAdjustButton extends StatefulWidget {
  const _BpmAdjustButton({
    required this.theme,
    required this.isIncrement,
    required this.onStep,
  });

  final AppTheme theme;
  final bool isIncrement;
  final VoidCallback onStep;

  @override
  State<_BpmAdjustButton> createState() => _BpmAdjustButtonState();
}

class _BpmAdjustButtonState extends State<_BpmAdjustButton> {
  Timer? _delayTimer;
  Timer? _rapidTimer;
  bool _isPressed = false;

  @override
  void dispose() {
    _delayTimer?.cancel();
    _rapidTimer?.cancel();
    super.dispose();
  }

  void _onTapDown(TapDownDetails _) {
    setState(() => _isPressed = true);
    widget.onStep();
    _delayTimer = Timer(const Duration(milliseconds: 400), () {
      _rapidTimer = Timer.periodic(const Duration(milliseconds: 80), (_) {
        widget.onStep();
      });
    });
  }

  void _onTapUp(TapUpDetails _) => _release();
  void _onTapCancel() => _release();

  void _release() {
    setState(() => _isPressed = false);
    _delayTimer?.cancel();
    _rapidTimer?.cancel();
    _delayTimer = null;
    _rapidTimer = null;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 80),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: _isPressed ? widget.theme.accent.withAlpha(30) : widget.theme.surface2,
          borderRadius: BorderRadius.circular(10),
          border: _isPressed
              ? Border.all(color: widget.theme.accent.withAlpha(180))
              : null,
        ),
        child: Text(
          widget.isIncrement ? '+' : '−',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            height: 1,
            color: _isPressed ? widget.theme.accent : widget.theme.textMuted,
          ),
        ),
      ),
    );
  }
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({
    required this.theme,
    required this.isPlaying,
    required this.onTap,
  });

  final AppTheme theme;
  final bool isPlaying;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isPlaying ? theme.surface2 : theme.accent,
          boxShadow: isPlaying
              ? null
              : [
                  BoxShadow(
                    color: theme.accent.withAlpha(80),
                    blurRadius: 24,
                    spreadRadius: 4,
                  ),
                ],
        ),
        child: Icon(
          isPlaying ? Icons.stop_rounded : Icons.play_arrow_rounded,
          size: 32,
          color: isPlaying ? theme.textMuted : theme.onAccent,
        ),
      ),
    );
  }
}
