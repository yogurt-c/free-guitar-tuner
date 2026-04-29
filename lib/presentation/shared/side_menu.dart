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
    return Container(
      width: 260,
      height: double.infinity,
      color: theme.surface,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 52),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Text(
                'NAVIGATION',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.4,
                  color: theme.textDim,
                ),
              ),
            ),
            _MenuItem(
              theme: theme,
              label: 'Tuner',
              icon: Icons.mic_none_rounded,
              isActive: activeMode == AppMode.tuner,
              onTap: () => onSelect(AppMode.tuner),
            ),
            _MenuItem(
              theme: theme,
              label: 'Metronome',
              icon: Icons.timer_outlined,
              isActive: activeMode == AppMode.metronome,
              onTap: () => onSelect(AppMode.metronome),
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  const _MenuItem({
    required this.theme,
    required this.label,
    required this.icon,
    required this.isActive,
    required this.onTap,
  });

  final AppTheme theme;
  final String label;
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
                      ? theme.accent.withAlpha(38)
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
              Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                  color: isActive ? theme.text : theme.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
