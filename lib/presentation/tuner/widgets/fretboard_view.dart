import 'package:flutter/material.dart';
import '../../../domain/model/note.dart';
import '../../shared/app_theme.dart';

class FretboardView extends StatelessWidget {
  const FretboardView({
    super.key,
    required this.theme,
    required this.strings,
    required this.selectedIndex,
    required this.tunedIndices,
    required this.autoMode,
    required this.onSelect,
  });

  final AppTheme theme;
  final List<Note> strings;
  final int selectedIndex;
  final Set<int> tunedIndices;
  final bool autoMode;
  final void Function(int) onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 22),
      padding: const EdgeInsets.only(top: 14, bottom: 10),
      decoration: BoxDecoration(
        color: theme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.line),
      ),
      child: Stack(
        children: [
          // Nut line
          Positioned(
            left: 68,
            top: 0,
            bottom: 0,
            width: 3,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: theme.isDark
                    ? const Color.fromRGBO(245, 244, 240, 0.18)
                    : const Color.fromRGBO(20, 19, 26, 0.18),
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ),
          // Right fret line
          Positioned(
            right: 14,
            top: 0,
            bottom: 0,
            width: 1,
            child: DecoratedBox(
              decoration: BoxDecoration(color: theme.line),
            ),
          ),
          Column(
            children: [
              for (int i = 0; i < strings.length; i++)
                _StringRow(
                  theme: theme,
                  note: strings[i],
                  stringIndex: i,
                  totalStrings: strings.length,
                  isSelected: i == selectedIndex,
                  isTuned: tunedIndices.contains(i),
                  isDisabled: autoMode && i != selectedIndex,
                  onTap: autoMode ? null : () => onSelect(i),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StringRow extends StatelessWidget {
  const _StringRow({
    required this.theme,
    required this.note,
    required this.stringIndex,
    required this.totalStrings,
    required this.isSelected,
    required this.isTuned,
    required this.isDisabled,
    required this.onTap,
  });

  final AppTheme theme;
  final Note note;
  final int stringIndex;
  final int totalStrings;
  final bool isSelected;
  final bool isTuned;
  final bool isDisabled;
  final VoidCallback? onTap;

  // Low strings (index 0) are thickest
  double get _thickness => 1.2 + (totalStrings - 1 - stringIndex) * 0.45;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedOpacity(
        opacity: isDisabled ? 0.55 : 1.0,
        duration: const Duration(milliseconds: 150),
        child: SizedBox(
          height: 26,
          child: Row(
            children: [
              _LabelPill(
                theme: theme,
                note: note,
                stringIndex: stringIndex,
                isSelected: isSelected,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: _StringLine(
                  theme: theme,
                  thickness: _thickness,
                  isSelected: isSelected,
                  isTuned: isTuned,
                ),
              ),
              const SizedBox(width: 14),
            ],
          ),
        ),
      ),
    );
  }
}

class _LabelPill extends StatelessWidget {
  const _LabelPill({
    required this.theme,
    required this.note,
    required this.stringIndex,
    required this.isSelected,
  });

  final AppTheme theme;
  final Note note;
  final int stringIndex;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    final labelColor =
        isSelected ? theme.onAccent : theme.text;
    final numColor =
        isSelected ? theme.onAccent : theme.textDim;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: 52,
      height: 22,
      margin: const EdgeInsets.only(left: 8),
      decoration: BoxDecoration(
        color: isSelected ? theme.accent : Colors.transparent,
        borderRadius: BorderRadius.circular(11),
        border: isSelected ? null : Border.all(color: theme.line),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '${stringIndex + 1}',
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: numColor,
            ),
          ),
          const SizedBox(width: 3),
          Text(
            note.name,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
              color: labelColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _StringLine extends StatelessWidget {
  const _StringLine({
    required this.theme,
    required this.thickness,
    required this.isSelected,
    required this.isTuned,
  });

  final AppTheme theme;
  final double thickness;
  final bool isSelected;
  final bool isTuned;

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: Stack(
        alignment: Alignment.centerLeft,
        children: [
          // The string
          Align(
            alignment: Alignment.centerLeft,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: double.infinity,
              height: thickness,
              decoration: BoxDecoration(
                gradient: isSelected
                    ? LinearGradient(
                        colors: [
                          theme.accent,
                          theme.accent,
                          theme.accent.withValues(alpha: 0.6),
                        ],
                        stops: const [0.0, 0.7, 1.0],
                      )
                    : null,
                color: isSelected
                    ? null
                    : (theme.isDark
                        ? const Color.fromRGBO(245, 244, 240, 0.32)
                        : const Color.fromRGBO(20, 19, 26, 0.40)),
                borderRadius: BorderRadius.circular(2),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: theme.accent.withValues(alpha: 0.4),
                          blurRadius: 8,
                        ),
                      ]
                    : [
                        BoxShadow(
                          color: theme.isDark
                              ? const Color.fromRGBO(0, 0, 0, 0.4)
                              : const Color.fromRGBO(255, 255, 255, 0.6),
                          offset: const Offset(0, 1),
                          blurRadius: 0,
                        ),
                      ],
              ),
            ),
          ),
          // Tuned check badge at right end
          if (isTuned)
            Positioned(
              right: 0,
              child: Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: theme.inTune,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(color: theme.surface, spreadRadius: 3),
                    BoxShadow(
                      color: theme.inTune.withValues(alpha: 0.5),
                      blurRadius: 8,
                    ),
                  ],
                ),
                child: Icon(
                  Icons.check_rounded,
                  size: 8,
                  color: theme.onAccent,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
