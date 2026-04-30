import 'dart:math' as math;
import 'dart:typed_data';

/// Generates a short click WAV in memory — no asset file needed.
/// accent=true → higher pitch (880 Hz, downbeat)
/// accent=false → lower pitch (660 Hz, normal beat)
Uint8List buildClickWav({required bool accent}) {
  const sampleRate = 44100;
  final frequency = accent ? 880.0 : 660.0;
  final numSamples = (sampleRate * 0.04).round(); // 40 ms

  final pcm = Int16List(numSamples);
  for (var i = 0; i < numSamples; i++) {
    final t = i / sampleRate;
    final env = math.exp(-t * 100); // sharp exponential decay
    final s = (math.sin(2 * math.pi * frequency * t) * env * 0.8 * 32767)
        .round()
        .clamp(-32767, 32767);
    pcm[i] = s;
  }

  return _buildWav(pcm, sampleRate);
}

Uint8List _buildWav(Int16List pcm, int sampleRate) {
  final dataSize = pcm.length * 2;
  final buf = ByteData(44 + dataSize);
  var o = 0;

  void ascii(String s) {
    for (final c in s.codeUnits) {
      buf.setUint8(o++, c);
    }
  }

  void u32(int v) {
    buf.setUint32(o, v, Endian.little);
    o += 4;
  }

  void u16(int v) {
    buf.setUint16(o, v, Endian.little);
    o += 2;
  }

  ascii('RIFF');
  u32(36 + dataSize);
  ascii('WAVE');
  ascii('fmt ');
  u32(16);
  u16(1); // PCM
  u16(1); // mono
  u32(sampleRate);
  u32(sampleRate * 2); // byte rate
  u16(2); // block align
  u16(16); // bits per sample
  ascii('data');
  u32(dataSize);

  for (final s in pcm) {
    buf.setInt16(o, s, Endian.little);
    o += 2;
  }

  return buf.buffer.asUint8List();
}
