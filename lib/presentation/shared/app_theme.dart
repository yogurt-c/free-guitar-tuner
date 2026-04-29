import 'package:flutter/material.dart';

@immutable
class AppTheme {
  const AppTheme({required this.isDark});

  final bool isDark;

  Color get bg => isDark ? const Color(0xFF0B0B0E) : const Color(0xFFF4F2EE);
  Color get surface => isDark ? const Color(0xFF15151A) : Colors.white;
  Color get surface2 => isDark ? const Color(0xFF1F1F26) : const Color(0xFFEBE8E1);
  Color get text => isDark ? const Color(0xFFF5F4F0) : const Color(0xFF15141A);

  // rgba(245,244,240, 0.55) dark / rgba(21,20,26, 0.50) light
  Color get textMuted =>
      isDark ? const Color(0x8CF5F4F0) : const Color(0x8015141A);

  // rgba(245,244,240, 0.32) dark / rgba(21,20,26, 0.32) light
  Color get textDim =>
      isDark ? const Color(0x52F5F4F0) : const Color(0x5215141A);

  // rgba(245,244,240, 0.08) dark / rgba(21,20,26, 0.08) light
  Color get line =>
      isDark ? const Color(0x14F5F4F0) : const Color(0x1415141A);

  Color get accent => const Color(0xFFC8B273);
  Color get inTune => const Color(0xFF7DD3A0);
  Color get flat => const Color(0xFFE0824A);
  Color get sharp => const Color(0xFF5BA3E0);

  Color get onAccent => isDark ? const Color(0xFF0B0B0E) : Colors.white;

  Color noteColor(double cents, bool isInTune) {
    if (isInTune) return inTune;
    if (cents < -3) return flat;
    if (cents > 3) return sharp;
    return text;
  }

  Color statusColor(double cents, bool isInTune) {
    if (isInTune) return inTune;
    if (cents < -3) return flat;
    if (cents > 3) return sharp;
    return textMuted;
  }
}
