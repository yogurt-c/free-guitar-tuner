import 'package:flutter/material.dart';

enum AppBreakpoint {
  compact,
  medium,
  expanded;

  static AppBreakpoint of(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width >= 900) return expanded;
    if (width >= 600) return medium;
    return compact;
  }

  bool get isCompact => this == compact;
  bool get isMediumOrLarger => this != compact;
  bool get isExpanded => this == expanded;
}

class AppDimens {
  AppDimens._();

  static double barAreaHeight(BuildContext context) =>
      switch (AppBreakpoint.of(context)) {
        AppBreakpoint.compact  => 96,
        AppBreakpoint.medium   => 108,
        AppBreakpoint.expanded => 120,
      };

  static double stringRowHeight(BuildContext context) =>
      AppBreakpoint.of(context).isCompact ? 26 : 30;

  // labelMargin(8) + pillWidth + gap(4) + nut overlap(4) = 16 + pillWidth
  static double labelPillWidth(BuildContext context) =>
      AppBreakpoint.of(context).isCompact ? 52 : 58;

  static double nutLineLeft(BuildContext context) =>
      16 + labelPillWidth(context);

  static double playButtonSize(BuildContext context) =>
      AppBreakpoint.of(context).isCompact ? 72 : 80;
}
