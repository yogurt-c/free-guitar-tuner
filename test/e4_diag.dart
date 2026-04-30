// E2 vs E4 옥타브 교정 임계값 분포 진단
import 'dart:io';
import 'dart:typed_data';
import 'dart:math';

List<double> loadWav(String path) {
  final bytes = File(path).readAsBytesSync();
  final data = ByteData.sublistView(bytes);
  int pos = 12, dataOffset = -1, dataSize = -1;
  while (pos < bytes.length - 8) {
    final id = String.fromCharCodes(bytes.sublist(pos, pos + 4));
    final sz = data.getUint32(pos + 4, Endian.little);
    if (id == 'data') { dataOffset = pos + 8; dataSize = sz; break; }
    pos += 8 + sz;
  }
  return List<double>.generate(
    dataSize ~/ 2,
    (i) => data.getInt16(dataOffset + i * 2, Endian.little) / 32768.0,
  );
}

({int? tau0, double c0, int octaveTau, double octaveMin}) yinAnalyze(
    List<double> samples, int sr) {
  final halfN = samples.length ~/ 2;
  final diff = List<double>.filled(halfN, 0.0);
  for (var tau = 1; tau < halfN; tau++) {
    for (var j = 0; j < halfN; j++) {
      final d = samples[j] - samples[j + tau];
      diff[tau] += d * d;
    }
  }
  final cmndf = List<double>.filled(halfN, 0.0);
  cmndf[0] = 1.0;
  double sum = 0.0;
  for (var tau = 1; tau < halfN; tau++) {
    sum += diff[tau];
    cmndf[tau] = sum > 0 ? diff[tau] * tau / sum : 1.0;
  }
  final tauMin = (sr / 1400.0).ceil();
  final tauMax = min(halfN - 2, (sr / 70.0).floor());

  int? tau0;
  for (final th in [0.15, 0.25, 0.40]) {
    for (var tau = tauMin + 1; tau < tauMax; tau++) {
      if (cmndf[tau] < th) {
        while (tau + 1 < tauMax && cmndf[tau + 1] < cmndf[tau]) tau++;
        tau0 = tau;
        break;
      }
    }
    if (tau0 != null) break;
  }
  if (tau0 == null) return (tau0: null, c0: 1.0, octaveTau: 0, octaveMin: 1.0);

  final c0 = cmndf[tau0];
  final octaveTau = tau0 * 2;
  var octaveMin = 1.0;
  if (octaveTau <= tauMax) {
    for (var t = max(tauMin, octaveTau - 3);
        t <= min(tauMax, octaveTau + 3);
        t++) {
      if (t < cmndf.length && cmndf[t] < octaveMin) octaveMin = cmndf[t];
    }
  }
  return (tau0: tau0, c0: c0, octaveTau: octaveTau, octaveMin: octaveMin);
}

void analyzeNote(String note, double target, int sr, int bufSize) {
  final samples = loadWav('test/audio/$note.wav');
  final nChunks = samples.length ~/ bufSize;
  final ratios = <double>[];
  int nullCount = 0;
  for (var i = 0; i < nChunks; i++) {
    final chunk = samples.sublist(i * bufSize, (i + 1) * bufSize);
    final r = yinAnalyze(chunk, sr);
    if (r.tau0 == null) { nullCount++; continue; }
    ratios.add(r.octaveMin / r.c0);
  }
  ratios.sort();
  final median = ratios[ratios.length ~/ 2];
  final max_ = ratios.last;
  final min_ = ratios.first;
  final above1 = ratios.where((r) => r >= 1.0).length;
  print('$note (기대 ${target}Hz): ${ratios.length}청크, ratio: '
      'min=${min_.toStringAsFixed(3)}, '
      'median=${median.toStringAsFixed(3)}, '
      'max=${max_.toStringAsFixed(3)}, '
      'ratio≥1.0: $above1/${ratios.length}');
  // 분포 버킷
  final buckets = <String, int>{};
  for (final r in ratios) {
    final b = r < 0.1 ? '<0.1' : r < 0.5 ? '0.1-0.5' : r < 1.0 ? '0.5-1.0' : '≥1.0';
    buckets[b] = (buckets[b] ?? 0) + 1;
  }
  for (final e in ['<0.1', '0.1-0.5', '0.5-1.0', '≥1.0']) {
    if (buckets.containsKey(e)) print('  ratio${e}: ${buckets[e]}');
  }
}

void main() {
  const sr = 44100;
  const bufSize = 4096;
  print('=== 옥타브 교정 ratio(octaveMin/c0) 분포 ===');
  print('(이 ratio가 threshold보다 낮아야 교정 발동)\n');
  for (final e in [
    ('E2', 82.41), ('A2', 110.0), ('D3', 146.83),
    ('G3', 196.0), ('B3', 246.94), ('E4', 329.63),
  ]) {
    analyzeNote(e.$1, e.$2, sr, bufSize);
  }
}
