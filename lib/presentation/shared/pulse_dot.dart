import 'package:flutter/material.dart';

class PulseDot extends StatefulWidget {
  const PulseDot({super.key, required this.color});

  final Color color;

  @override
  State<PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _opacity;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);
    final curved = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
    _opacity = Tween<double>(begin: 0.4, end: 1.0).animate(curved);
    _scale = Tween<double>(begin: 0.7, end: 1.0).animate(curved);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, _) => Opacity(
        opacity: _opacity.value,
        child: Transform.scale(
          scale: _scale.value,
          child: Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: widget.color,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }
}
