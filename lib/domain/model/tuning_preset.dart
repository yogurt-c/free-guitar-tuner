import 'note.dart';

class TuningPreset {
  final String name;
  final List<Note> strings; // index 0 = 6번현(lowest), index 5 = 1번현(highest)

  const TuningPreset({required this.name, required this.strings});
}

// ─── Note constants ────────────────────────────────────────────────────────────

const _c2  = Note(name: 'C',  octave: 2, freq: 65.41);
const _d2  = Note(name: 'D',  octave: 2, freq: 73.42);
const _eb2 = Note(name: 'Eb', octave: 2, freq: 77.78);
const _e2  = Note(name: 'E',  octave: 2, freq: 82.41);
const _g2  = Note(name: 'G',  octave: 2, freq: 98.00);
const _ab2 = Note(name: 'Ab', octave: 2, freq: 103.83);
const _a2  = Note(name: 'A',  octave: 2, freq: 110.00);

const _c3  = Note(name: 'C',  octave: 3, freq: 130.81);
const _db3 = Note(name: 'Db', octave: 3, freq: 138.59);
const _d3  = Note(name: 'D',  octave: 3, freq: 146.83);
const _f3  = Note(name: 'F',  octave: 3, freq: 174.61);
const _fs3 = Note(name: 'F#', octave: 3, freq: 185.00);
const _gb3 = Note(name: 'Gb', octave: 3, freq: 185.00);
const _g3  = Note(name: 'G',  octave: 3, freq: 196.00);
const _a3  = Note(name: 'A',  octave: 3, freq: 220.00);
const _bb3 = Note(name: 'Bb', octave: 3, freq: 233.08);
const _b3  = Note(name: 'B',  octave: 3, freq: 246.94);

const _d4  = Note(name: 'D',  octave: 4, freq: 293.66);
const _eb4 = Note(name: 'Eb', octave: 4, freq: 311.13);
const _e4  = Note(name: 'E',  octave: 4, freq: 329.63);

// ─── Presets ───────────────────────────────────────────────────────────────────

const Map<String, TuningPreset> tuningPresets = {
  'standard': TuningPreset(
    name: 'Standard',
    strings: [_e2, _a2, _d3, _g3, _b3, _e4],
  ),
  'drop_d': TuningPreset(
    name: 'Drop D',
    strings: [_d2, _a2, _d3, _g3, _b3, _e4],
  ),
  'drop_c': TuningPreset(
    name: 'Drop C',
    strings: [_c2, _g2, _c3, _f3, _a3, _d4],
  ),
  'half_step_down': TuningPreset(
    name: 'Half Step Down',
    strings: [_eb2, _ab2, _db3, _gb3, _bb3, _eb4],
  ),
  'open_g': TuningPreset(
    name: 'Open G',
    strings: [_d2, _g2, _d3, _g3, _b3, _d4],
  ),
  'open_d': TuningPreset(
    name: 'Open D',
    strings: [_d2, _a2, _d3, _fs3, _a3, _d4],
  ),
  'dadgad': TuningPreset(
    name: 'DADGAD',
    strings: [_d2, _a2, _d3, _g3, _a3, _d4],
  ),
};
