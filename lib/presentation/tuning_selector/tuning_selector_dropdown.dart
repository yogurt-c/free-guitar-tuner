import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/model/tuning_preset.dart';
import '../shared/app_theme.dart';
import 'tuning_selection_notifier.dart';

class TuningSelectorDropdown extends ConsumerStatefulWidget {
  const TuningSelectorDropdown({super.key, required this.theme});

  final AppTheme theme;

  @override
  ConsumerState<TuningSelectorDropdown> createState() =>
      _TuningSelectorDropdownState();
}

class _TuningSelectorDropdownState
    extends ConsumerState<TuningSelectorDropdown> {
  bool _open = false;

  AppTheme get _t => widget.theme;

  @override
  Widget build(BuildContext context) {
    final selection = ref.watch(tuningSelectionProvider);
    final preset = tuningPresets[selection.presetKey]!;
    final noteString = preset.strings.map((s) => s.name).join(' ');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GestureDetector(
            onTap: () => setState(() => _open = !_open),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: BoxDecoration(
                color: _t.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _t.line),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'TUNING PRESET',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1.2,
                            color: _t.textDim,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            Text(
                              preset.name,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: _t.text,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              noteString,
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                letterSpacing: 0.5,
                                color: _t.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  AnimatedRotation(
                    turns: _open ? 0.5 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: _t.textMuted,
                      size: 20,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 180),
            firstCurve: Curves.easeIn,
            secondCurve: Curves.easeOut,
            crossFadeState:
                _open ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            firstChild: const SizedBox.shrink(),
            secondChild: _DropdownList(
              theme: _t,
              selectedKey: selection.presetKey,
              onSelect: (key) {
                ref.read(tuningSelectionProvider.notifier).selectPreset(key);
                setState(() => _open = false);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _DropdownList extends StatelessWidget {
  const _DropdownList({
    required this.theme,
    required this.selectedKey,
    required this.onSelect,
  });

  final AppTheme theme;
  final String selectedKey;
  final void Function(String) onSelect;

  @override
  Widget build(BuildContext context) {
    final keys = tuningPresets.keys.toList();
    return Container(
      margin: const EdgeInsets.only(top: 6),
      decoration: BoxDecoration(
        color: theme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.line),
        boxShadow: [
          BoxShadow(
            color: theme.isDark
                ? const Color.fromRGBO(0, 0, 0, 0.6)
                : const Color.fromRGBO(0, 0, 0, 0.12),
            blurRadius: 32,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Column(
          children: [
            for (int i = 0; i < keys.length; i++)
              _PresetItem(
                theme: theme,
                preset: tuningPresets[keys[i]]!,
                isSelected: keys[i] == selectedKey,
                showDivider: i > 0,
                onTap: () => onSelect(keys[i]),
              ),
          ],
        ),
      ),
    );
  }
}

class _PresetItem extends StatelessWidget {
  const _PresetItem({
    required this.theme,
    required this.preset,
    required this.isSelected,
    required this.showDivider,
    required this.onTap,
  });

  final AppTheme theme;
  final TuningPreset preset;
  final bool isSelected;
  final bool showDivider;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? theme.surface2 : Colors.transparent,
          border: showDivider
              ? Border(top: BorderSide(color: theme.line))
              : null,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    preset.name,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: theme.text,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    preset.strings.map((s) => s.name).join(' '),
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      letterSpacing: 0.5,
                      color: theme.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: theme.accent,
                  shape: BoxShape.circle,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
