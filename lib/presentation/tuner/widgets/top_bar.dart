import 'package:flutter/material.dart';
import '../../shared/app_theme.dart';

class TopBar extends StatelessWidget {
  const TopBar({
    super.key,
    required this.theme,
    required this.isDark,
    required this.modeLabel,
    required this.onMenuTap,
    required this.onThemeToggle,
  });

  final AppTheme theme;
  final bool isDark;
  final String modeLabel;
  final VoidCallback onMenuTap;
  final VoidCallback onThemeToggle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 8, 22, 8),
      child: Row(
        children: [
          _CircleButton(
            theme: theme,
            onTap: onMenuTap,
            child: _HamburgerIcon(color: theme.textMuted),
          ),
          Expanded(
            child: Center(
              child: Text(
                modeLabel.toUpperCase(),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.5,
                  color: theme.textMuted,
                ),
              ),
            ),
          ),
          _CircleButton(
            theme: theme,
            onTap: onThemeToggle,
            child: Icon(
              isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
              size: 16,
              color: theme.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({
    required this.theme,
    required this.onTap,
    required this.child,
  });

  final AppTheme theme;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: theme.surface2,
          shape: BoxShape.circle,
        ),
        child: Center(child: child),
      ),
    );
  }
}

class _HamburgerIcon extends StatelessWidget {
  const _HamburgerIcon({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(width: 16, height: 1.5, color: color),
        const SizedBox(height: 3),
        Container(width: 12, height: 1.5, color: color),
        const SizedBox(height: 3),
        Container(width: 14, height: 1.5, color: color),
      ],
    );
  }
}
