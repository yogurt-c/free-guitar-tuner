import 'package:flutter/material.dart';

import '../tuning_selector/tuning_selection_notifier.dart';
import 'app_theme.dart';

class SideMenuPanel extends StatelessWidget {
  const SideMenuPanel({
    super.key,
    required this.theme,
    required this.activeMode,
    required this.onSelect,
  });

  final AppTheme theme;
  final AppMode activeMode;
  final void Function(AppMode) onSelect;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: theme.bg,
      child: SizedBox(
        width: 280,
        height: double.infinity,
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 52),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 8),
                child: Text(
                  'TOOLS',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.6,
                    color: theme.textDim,
                  ),
                ),
              ),
              _MenuItem(
                theme: theme,
                label: 'Tuner',
                sub: 'Pitch detection',
                icon: Icons.mic_none_rounded,
                isActive: activeMode == AppMode.tuner,
                onTap: () => onSelect(AppMode.tuner),
              ),
              _MenuItem(
                theme: theme,
                label: 'Metronome',
                sub: 'Tempo & beats',
                icon: Icons.timer_outlined,
                isActive: activeMode == AppMode.metronome,
                onTap: () => onSelect(AppMode.metronome),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  const _MenuItem({
    required this.theme,
    required this.label,
    required this.sub,
    required this.icon,
    required this.isActive,
    required this.onTap,
  });

  final AppTheme theme;
  final String label;
  final String sub;
  final IconData icon;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
        decoration: BoxDecoration(
          border: isActive
              ? Border(left: BorderSide(color: theme.accent, width: 3))
              : const Border(left: BorderSide(color: Colors.transparent, width: 3)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: isActive
                      ? theme.accent.withAlpha(34)
                      : theme.surface2,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  icon,
                  size: 18,
                  color: isActive ? theme.accent : theme.textMuted,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: theme.text,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      sub,
                      style: TextStyle(
                        fontSize: 11,
                        color: theme.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
