import 'package:flutter/material.dart';
import '../../shared/app_theme.dart';
import '../../shared/pulse_dot.dart';

class BottomControls extends StatelessWidget {
  const BottomControls({
    super.key,
    required this.theme,
    required this.autoDetect,
    required this.onToggle,
    this.refPitch = 440,
  });

  final AppTheme theme;
  final bool autoDetect;
  final VoidCallback onToggle;
  final int refPitch;

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(22, 14, 22, 14 + bottomPad),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: theme.line)),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: onToggle,
            behavior: HitTestBehavior.opaque,
            child: Row(
              children: [
                _ToggleSwitch(theme: theme, value: autoDetect),
                const SizedBox(width: 8),
                Text(
                  'Auto-detect',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: theme.textMuted,
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          Row(
            children: [
              PulseDot(color: theme.inTune),
              const SizedBox(width: 6),
              Text(
                'Mic live · A = $refPitch Hz',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  letterSpacing: 0.5,
                  color: theme.textMuted,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ToggleSwitch extends StatelessWidget {
  const _ToggleSwitch({required this.theme, required this.value});

  final AppTheme theme;
  final bool value;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: 28,
      height: 16,
      decoration: BoxDecoration(
        color: value ? theme.accent : theme.surface2,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Stack(
        children: [
          AnimatedPositioned(
            duration: const Duration(milliseconds: 150),
            left: value ? 14.0 : 2.0,
            top: 2,
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: theme.isDark
                    ? Colors.white
                    : (value ? Colors.white : theme.textMuted),
                shape: BoxShape.circle,
                boxShadow: const [
                  BoxShadow(
                    color: Color.fromRGBO(0, 0, 0, 0.2),
                    blurRadius: 2,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
