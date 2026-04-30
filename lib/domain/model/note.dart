class Note {
  final String name;
  final int octave;
  final double freq;

  const Note({required this.name, required this.octave, required this.freq});

  String get displayName => '$name$octave';

  @override
  bool operator ==(Object other) =>
      other is Note && name == other.name && octave == other.octave;

  @override
  int get hashCode => Object.hash(name, octave);
}
