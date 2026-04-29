import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  runApp(const ProviderScope(child: GuitarTunerApp()));
}

class GuitarTunerApp extends StatelessWidget {
  const GuitarTunerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'Guitar Tuner',
      home: Scaffold(
        body: Center(child: Text('Guitar Tuner')),
      ),
    );
  }
}
