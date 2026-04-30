import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'metronome/metronome_screen.dart';
import 'shared/app_theme.dart';
import 'shared/side_menu.dart';
import 'tuner/tuner_screen.dart';
import 'tuning_selector/tuning_selection_notifier.dart';

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell>
    with SingleTickerProviderStateMixin {
  bool _menuOpen = false;
  late final AnimationController _menuCtrl;
  late final Animation<double> _backdropOpacity;

  @override
  void initState() {
    super.initState();
    _menuCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    _backdropOpacity = CurvedAnimation(
      parent: _menuCtrl,
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    _menuCtrl.dispose();
    super.dispose();
  }

  void _openMenu() {
    setState(() => _menuOpen = true);
    _menuCtrl.forward();
  }

  void _closeMenu() {
    _menuCtrl.reverse().then((_) {
      if (mounted) setState(() => _menuOpen = false);
    });
  }

  void _selectMode(AppMode mode) {
    ref.read(tuningSelectionProvider.notifier).switchMode(mode);
    _closeMenu();
  }

  @override
  Widget build(BuildContext context) {
    final selection = ref.watch(tuningSelectionProvider);
    final theme = AppTheme(isDark: selection.isDark);

    return Stack(
      children: [
        // Active screen
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: selection.mode == AppMode.tuner
              ? TunerScreen(key: const ValueKey('tuner'), onMenuTap: _openMenu)
              : MetronomeScreen(key: const ValueKey('metro'), onMenuTap: _openMenu),
        ),
        // Backdrop
        if (_menuOpen)
          FadeTransition(
            opacity: _backdropOpacity,
            child: GestureDetector(
              onTap: _closeMenu,
              child: Container(color: const Color.fromRGBO(0, 0, 0, 0.52)),
            ),
          ),
        // Side panel (always in tree for slide animation)
        IgnorePointer(
          ignoring: !_menuOpen,
          child: AnimatedSlide(
            offset: _menuOpen ? Offset.zero : const Offset(-1, 0),
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            child: Align(
              alignment: Alignment.centerLeft,
              child: SideMenuPanel(
                theme: theme,
                activeMode: selection.mode,
                onSelect: _selectMode,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
