import 'package:flutter/material.dart';
import '../../shared/app_theme.dart';

class BarMeter extends StatelessWidget {
  const BarMeter({
    super.key,
    required this.theme,
    required this.cents,
    required this.inTune,
    this.isActive = true,
  });

  final AppTheme theme;
  final double cents;
  final bool inTune;
  final bool isActive;

  static const _numBars = 21;
  static const _center = 10;
  static const _barAreaHeight = 96.0;

  @override
  Widget build(BuildContext context) {
    final clamped = cents.clamp(-50.0, 50.0);
    final activePos = _center + (clamped / 50.0) * 10.0;

    final bars = List.generate(_numBars, (i) {
      if (!isActive) {
        return _BarData(
          height: 0.28 * _barAreaHeight,
          color: theme.line,
          opacity: 0.55,
          isActive: false,
        );
      }

      final distFromActive = (i - activePos).abs();
      final distFromCenter = (i - _center).abs().toDouble();
      final inActiveRegion = distFromActive < 3.0;

      final peakHeight = 1.0 - (distFromActive / 3.5).clamp(0.0, 1.0);
      final heightRatio = 0.28 + peakHeight * 0.72;

      final Color color;
      if (inTune) {
        color = theme.inTune;
      } else if (inActiveRegion) {
        color = activePos < _center ? theme.flat : theme.sharp;
      } else if (i == _center) {
        color = theme.textMuted;
      } else {
        color = theme.line;
      }

      final double opacity;
      if (inTune) {
        opacity = (1.0 - distFromCenter * 0.05).clamp(0.45, 1.0);
      } else if (inActiveRegion) {
        opacity = (1.0 - distFromActive * 0.18).clamp(0.0, 1.0);
      } else if (i == _center) {
        opacity = 1.0;
      } else {
        opacity = 0.55;
      }

      return _BarData(
        height: heightRatio * _barAreaHeight,
        color: color,
        opacity: opacity,
        isActive: distFromActive < 1.2,
      );
    });

    final hairlineColor = isActive && inTune
        ? theme.inTune.withValues(alpha: 0.4)
        : theme.line;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Fixed-height slot for locked badge — prevents layout shift
          SizedBox(
            height: 30,
            child: Center(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 280),
                transitionBuilder: (child, animation) => ScaleTransition(
                  scale: CurvedAnimation(
                    parent: animation,
                    curve: const Cubic(0.34, 1.56, 0.64, 1.0),
                  ),
                  child: FadeTransition(opacity: animation, child: child),
                ),
                child: isActive && inTune
                    ? _LockedBadge(
                        key: const ValueKey('locked'),
                        theme: theme,
                      )
                    : const SizedBox.shrink(key: ValueKey('empty')),
              ),
            ),
          ),
          // Bar visualization
          SizedBox(
            height: _barAreaHeight,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // Radial halo (extends beyond bounds)
                Positioned(
                  top: -12, bottom: -12, left: -8, right: -8,
                  child: AnimatedOpacity(
                    opacity: isActive && inTune ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 250),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          colors: [
                            theme.inTune.withValues(alpha: 0.16),
                            theme.inTune.withValues(alpha: 0.0),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                // Center hairline (overflows 4px top/bottom)
                Align(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 1,
                    height: _barAreaHeight + 8,
                    color: hairlineColor,
                  ),
                ),
                // Bars
                Positioned.fill(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (int i = 0; i < bars.length; i++) ...[
                        if (i > 0) const SizedBox(width: 3),
                        Expanded(child: _Bar(data: bars[i], theme: theme)),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          if (isActive)
            _CentsLabels(theme: theme, cents: cents, inTune: inTune)
          else
            const SizedBox(height: 23),
        ],
      ),
    );
  }
}

class _BarData {
  const _BarData({
    required this.height,
    required this.color,
    required this.opacity,
    required this.isActive,
  });

  final double height;
  final Color color;
  final double opacity;
  final bool isActive;
}

class _Bar extends StatelessWidget {
  const _Bar({required this.data, required this.theme});

  final _BarData data;
  final AppTheme theme;

  @override
  Widget build(BuildContext context) {
    final shadow = data.isActive && !data.color.a.isNaN
        ? BoxShadow(
            color: data.color.withValues(alpha: 0.4),
            blurRadius: 12,
          )
        : null;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: const Cubic(0.4, 0.0, 0.2, 1.0),
      height: data.height,
      decoration: BoxDecoration(
        color: data.color.withValues(alpha: data.opacity),
        borderRadius: BorderRadius.circular(3),
        boxShadow: shadow != null ? [shadow] : null,
      ),
    );
  }
}

class _LockedBadge extends StatelessWidget {
  const _LockedBadge({super.key, required this.theme});

  final AppTheme theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: theme.inTune,
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: theme.inTune.withValues(alpha: 0.33),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_rounded, size: 9, color: theme.onAccent),
          const SizedBox(width: 5),
          Text(
            'LOCKED',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: theme.onAccent,
            ),
          ),
        ],
      ),
    );
  }
}

class _CentsLabels extends StatelessWidget {
  const _CentsLabels({
    required this.theme,
    required this.cents,
    required this.inTune,
  });

  final AppTheme theme;
  final double cents;
  final bool inTune;

  Color get _centsColor {
    if (inTune) return theme.inTune;
    if (cents.abs() < 8) return theme.text;
    return cents < 0 ? theme.flat : theme.sharp;
  }

  @override
  Widget build(BuildContext context) {
    final sign = cents > 0.5 ? '+' : '';
    final dimStyle = TextStyle(
      fontFamily: 'monospace',
      fontSize: 10,
      letterSpacing: 0.5,
      color: theme.textDim,
    );
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text('−50¢', style: dimStyle),
        AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 200),
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: _centsColor,
          ),
          child: Text('$sign${cents.toStringAsFixed(1)}¢'),
        ),
        Text('+50¢', style: dimStyle),
      ],
    );
  }
}
