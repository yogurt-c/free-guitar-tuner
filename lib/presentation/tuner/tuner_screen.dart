import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/analyzer/note_analyzer.dart';
import '../../domain/model/tuning_preset.dart';
import '../shared/app_theme.dart';
import '../tuning_selector/tuning_selection_notifier.dart';
import '../tuning_selector/tuning_selector_dropdown.dart';
import 'tuner_notifier.dart';
import 'widgets/bar_meter.dart';
import 'widgets/bottom_controls.dart';
import 'widgets/fretboard_view.dart';
import 'widgets/note_display.dart';
import 'widgets/top_bar.dart';

class TunerScreen extends ConsumerWidget {
  const TunerScreen({super.key, required this.onMenuTap});

  final VoidCallback onMenuTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tuner = ref.watch(tunerProvider);
    final selection = ref.watch(tuningSelectionProvider);
    final notifier = ref.read(tuningSelectionProvider.notifier);

    final theme = AppTheme(isDark: selection.isDark);
    final preset = tuningPresets[selection.presetKey]!;
    final targetNote = preset.strings[selection.selectedString];

    final tuneResult = tuner.tuneResult;
    final double cents = tuneResult?.cents ?? 0.0;
    final bool inTune = tuneResult?.state == TuneState.inTune;
    final String noteName = tuneResult?.noteName ?? targetNote.name;
    final int octave = tuneResult?.octave ?? targetNote.octave;
    final double currentFreq = tuner.detectedFreq ?? targetNote.freq;

    return Scaffold(
      backgroundColor: theme.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            TopBar(
              theme: theme,
              isDark: selection.isDark,
              modeLabel: 'Tuner',
              onMenuTap: onMenuTap,
              onThemeToggle: notifier.toggleDark,
            ),
            const SizedBox(height: 18),
            NoteDisplay(
              theme: theme,
              noteName: noteName,
              octave: octave,
              cents: cents,
              inTune: inTune,
              currentFreq: currentFreq,
              targetFreq: targetNote.freq,
            ),
            const SizedBox(height: 8),
            BarMeter(
              theme: theme,
              cents: cents,
              inTune: inTune,
            ),
            const SizedBox(height: 28),
            TuningSelectorDropdown(theme: theme),
            const SizedBox(height: 16),
            FretboardView(
              theme: theme,
              strings: preset.strings,
              selectedIndex: selection.selectedString,
              tunedIndices: selection.tunedStrings,
              autoMode: selection.autoDetect,
              onSelect: notifier.selectString,
            ),
            const Spacer(),
            BottomControls(
              theme: theme,
              autoDetect: selection.autoDetect,
              onToggle: notifier.toggleAutoDetect,
            ),
          ],
        ),
      ),
    );
  }
}
