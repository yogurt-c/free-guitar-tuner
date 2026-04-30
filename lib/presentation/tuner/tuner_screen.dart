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
    final bool isActive = tuneResult != null;
    final double cents = tuneResult?.cents ?? 0.0;
    final bool inTune = tuneResult?.state == TuneState.inTune;
    final String noteName = tuneResult?.noteName ?? targetNote.name;
    final int octave = tuneResult?.octave ?? targetNote.octave;
    final double currentFreq = tuner.tuneResult?.detectedFreq ?? targetNote.freq;

    if (tuner.permissionDenied) {
      return _PermissionDeniedScreen(theme: theme);
    }


    return Scaffold(
      backgroundColor: theme.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
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
                      isActive: isActive,
                    ),
                    const SizedBox(height: 8),
                    BarMeter(
                      theme: theme,
                      cents: cents,
                      inTune: inTune,
                      isActive: isActive,
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
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
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

class _PermissionDeniedScreen extends StatelessWidget {
  const _PermissionDeniedScreen({required this.theme});

  final AppTheme theme;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: theme.bg,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.mic_off_rounded, size: 64, color: theme.textDim),
              const SizedBox(height: 24),
              Text(
                'Microphone Access Required',
                style: TextStyle(
                  color: theme.text,
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'Guitar Tuner needs microphone access to detect pitch.\n'
                'Please enable it in your device Settings.',
                style: TextStyle(color: theme.textMuted, fontSize: 14, height: 1.6),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
