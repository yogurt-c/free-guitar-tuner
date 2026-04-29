import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'presentation/home_shell.dart';

void main() {
  runApp(const ProviderScope(child: GuitarTunerApp()));
}

class GuitarTunerApp extends StatelessWidget {
  const GuitarTunerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'Guitar Tuner',
      debugShowCheckedModeBanner: false,
      home: HomeShell(),
    );
  }
}
