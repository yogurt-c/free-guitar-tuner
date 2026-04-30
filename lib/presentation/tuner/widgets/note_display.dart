import 'package:flutter/material.dart';
import '../../shared/app_theme.dart';
import '../../shared/pulse_dot.dart';

class NoteDisplay extends StatelessWidget {
  const NoteDisplay({
    super.key,
    required this.theme,
    required this.noteName,
    required this.octave,
    required this.cents,
    required this.inTune,
    required this.currentFreq,
    required this.targetFreq,
    this.isActive = true,
  });

  final AppTheme theme;
  final String noteName;
  final int octave;
  final double cents;
  final bool inTune;
  final double currentFreq;
  final double targetFreq;
  final bool isActive;

  String get _statusText {
    if (inTune) return 'IN TUNE';
    if (cents < -3) return 'TOO LOW  ♭';
    if (cents > 3) return 'TOO HIGH  ♯';
    return 'NEAR';
  }

  @override
  Widget build(BuildContext context) {
    final noteColor = isActive
        ? theme.noteColor(cents, inTune)
        : theme.textDim;
    final statusColor = theme.statusColor(cents, inTune);

    return Column(
      children: [
        AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: isActive ? 1.0 : 0.0,
          child: _StatusPill(
            text: _statusText,
            statusColor: statusColor,
            inTune: inTune,
            theme: theme,
          ),
        ),
        const SizedBox(height: 12),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: noteName,
                style: TextStyle(
                  fontSize: 96,
                  fontWeight: FontWeight.w300,
                  height: 1.0,
                  letterSpacing: -4,
                  color: noteColor,
                ),
              ),
              WidgetSpan(
                alignment: PlaceholderAlignment.top,
                child: Padding(
                  padding: const EdgeInsets.only(left: 2),
                  child: Text(
                    '$octave',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w400,
                      color: isActive ? theme.textMuted : theme.textDim,
                    ),
                  ),
                ),
              ),
            ],
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 6),
        AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: isActive ? 1.0 : 0.3,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '${currentFreq.toStringAsFixed(2)} Hz',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: theme.textMuted,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text('→', style: TextStyle(color: theme.textDim)),
              ),
              Text(
                '${targetFreq.toStringAsFixed(2)} Hz',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: theme.textDim,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.text,
    required this.statusColor,
    required this.inTune,
    required this.theme,
  });

  final String text;
  final Color statusColor;
  final bool inTune;
  final AppTheme theme;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: inTune
            ? theme.inTune.withValues(alpha: 0.12)
            : theme.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: inTune
              ? theme.inTune.withValues(alpha: 0.33)
              : theme.line,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          PulseDot(color: inTune ? theme.inTune : theme.flat),
          const SizedBox(width: 7),
          Text(
            text,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
              color: statusColor,
            ),
          ),
        ],
      ),
    );
  }
}
