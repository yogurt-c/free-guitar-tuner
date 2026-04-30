/// 실제 기타 어쿠스틱 WAV 샘플로 PitchDetector 검증.
///
/// 샘플 출처: github.com/nbrosowsky/tonejs-instruments (MIT)
/// 포맷: PCM16, 44100 Hz, mono
///
/// 파일 준비:
///   test/audio/{E2,A2,D3,G3,B3,E4}.wav
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:guitar_tuner/data/pitch_detector.dart';

// ── WAV 파싱 ──────────────────────────────────────────────────────────────────

/// WAV 파일에서 PCM 샘플 전부를 읽어 [-1, 1] double 로 반환.
/// 표준 PCM16 / 44100 Hz / mono 전용.
List<double> _loadWav(String path) {
  final bytes = File(path).readAsBytesSync();
  final data = ByteData.sublistView(bytes);

  // "RIFF" 체크
  assert(String.fromCharCodes(bytes.sublist(0, 4)) == 'RIFF');
  assert(String.fromCharCodes(bytes.sublist(8, 12)) == 'WAVE');

  int pos = 12;
  int dataOffset = -1;
  int dataSize = -1;

  while (pos < bytes.length - 8) {
    final chunkId = String.fromCharCodes(bytes.sublist(pos, pos + 4));
    final chunkSize = data.getUint32(pos + 4, Endian.little);
    if (chunkId == 'data') {
      dataOffset = pos + 8;
      dataSize = chunkSize;
      break;
    }
    pos += 8 + chunkSize;
  }

  assert(dataOffset != -1, 'data chunk not found');
  final sampleCount = dataSize ~/ 2;
  return List<double>.generate(
    sampleCount,
    (i) => data.getInt16(dataOffset + i * 2, Endian.little) / 32768.0,
  );
}

// ── 헬퍼 ──────────────────────────────────────────────────────────────────────

const _bufSize = 4096;
const _sampleRate = 44100;

/// WAV 전체 샘플을 4096 샘플 청크로 분할 반환.
List<List<double>> _chunks(List<double> samples) {
  final result = <List<double>>[];
  for (var i = 0; i + _bufSize <= samples.length; i += _bufSize) {
    result.add(samples.sublist(i, i + _bufSize));
  }
  return result;
}

/// 모든 청크를 PitchDetector 에 통과시켜 감지된 주파수 목록 반환 (null 제외).
Future<List<double>> _detectAll(
    PitchDetector detector, List<List<double>> chunks) async {
  final results = <double>[];
  for (final chunk in chunks) {
    final freq = await detector.detect(chunk);
    if (freq != null) results.add(freq);
  }
  return results;
}

/// 감지된 주파수들의 중앙값 반환.
double _median(List<double> values) {
  if (values.isEmpty) return 0;
  final sorted = [...values]..sort();
  final mid = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[mid]
      : (sorted[mid - 1] + sorted[mid]) / 2.0;
}

String _audioPath(String note) {
  // 테스트 실행 디렉토리 기준 경로
  return 'test/audio/$note.wav';
}

// ── 테스트 ────────────────────────────────────────────────────────────────────

void main() {
  final detector = PitchDetector();

  const strings = <String, double>{
    'E2 (6현)': 82.41,
    'A2 (5현)': 110.00,
    'D3 (4현)': 146.83,
    'G3 (3현)': 196.00,
    'B3 (2현)': 246.94,
    'E4 (1현)': 329.63,
  };

  const noteFile = <String, String>{
    'E2 (6현)': 'E2',
    'A2 (5현)': 'A2',
    'D3 (4현)': 'D3',
    'G3 (3현)': 'G3',
    'B3 (2현)': 'B3',
    'E4 (1현)': 'E4',
  };

  // ── 기본: 어느 청크라도 올바른 음 감지 ────────────────────────────────────
  group('실제 WAV – 감지 여부', () {
    for (final e in strings.entries) {
      test(e.key, () async {
        final path = _audioPath(noteFile[e.key]!);
        if (!File(path).existsSync()) {
          markTestSkipped('파일 없음: $path');
          return;
        }

        final samples = _loadWav(path);
        final chunks = _chunks(samples);
        final detected = await _detectAll(detector, chunks);

        // ignore: avoid_print
        print('\n${e.key}: ${chunks.length}청크 중 ${detected.length}개 감지 '
            '(${(detected.length / chunks.length * 100).toStringAsFixed(0)}%)');

        expect(detected, isNotEmpty,
            reason: '${e.key} – 한 청크도 감지 못함');

        // 감지된 주파수 중 목표 ±5% 이내 비율
        final target = e.value;
        final correct = detected
            .where((f) => (f - target).abs() / target < 0.05)
            .length;
        // ignore: avoid_print
        print('  ±5% 이내 정답 비율: '
            '${correct}/${detected.length} '
            '(${(correct / detected.length * 100).toStringAsFixed(0)}%)');

        expect(correct, greaterThan(0),
            reason: '${e.key} – 감지는 됐으나 전부 오감지');
      });
    }
  });

  // ── 중앙값 정밀도 ──────────────────────────────────────────────────────────
  group('실제 WAV – 중앙값 정밀도 (±5%)', () {
    for (final e in strings.entries) {
      test(e.key, () async {
        final path = _audioPath(noteFile[e.key]!);
        if (!File(path).existsSync()) {
          markTestSkipped('파일 없음: $path');
          return;
        }

        final samples = _loadWav(path);
        final chunks = _chunks(samples);
        final detected = await _detectAll(detector, chunks);

        if (detected.isEmpty) {
          fail('${e.key} – 감지 결과 없음');
        }

        final med = _median(detected);
        final target = e.value;
        final errorPct = (med - target).abs() / target * 100;

        // ignore: avoid_print
        print('${e.key}: 중앙값=${med.toStringAsFixed(2)} Hz, '
            '오차=${errorPct.toStringAsFixed(1)}%');

        expect(errorPct, lessThan(5.0),
            reason: '${e.key} 중앙값 ${med.toStringAsFixed(2)} Hz, '
                '기대 ${target} Hz, 오차 ${errorPct.toStringAsFixed(1)}%');
      });
    }
  });

  // ── CMNDF 값 진단 ─────────────────────────────────────────────────────────
  group('CMNDF 값 진단', () {
    List<double> computeCmndf(List<double> samples) {
      final halfN = samples.length ~/ 2;
      final diff = List<double>.filled(halfN, 0.0);
      for (var tau = 1; tau < halfN; tau++) {
        for (var j = 0; j < halfN; j++) {
          final d = samples[j] - samples[j + tau];
          diff[tau] += d * d;
        }
      }
      final c = List<double>.filled(halfN, 0.0);
      c[0] = 1.0;
      double sum = 0.0;
      for (var tau = 1; tau < halfN; tau++) {
        sum += diff[tau];
        c[tau] = sum > 0 ? diff[tau] * tau / sum : 1.0;
      }
      return c;
    }

    test('E2 오탐 청크의 CMNDF[268] vs CMNDF[535] 분포', () {
      final samples = _loadWav(_audioPath('E2'));
      final chunks = _chunks(samples);
      // ignore: avoid_print
      print('\nE2 오탐 청크 CMNDF 샘플 (최대 5개):');
      int shown = 0;
      for (final chunk in chunks) {
        if (shown >= 5) break;
        final c = computeCmndf(chunk);
        final v268 = c[268];
        final v535 = c[535];
        final freq = _sampleRate / 268.0;
        if (v268 < 0.15) { // first-dip이 268에서 멈춘 청크
          // ignore: avoid_print
          print('  CMNDF[268]=${v268.toStringAsFixed(4)}'
              '  CMNDF[535]=${v535.toStringAsFixed(4)}'
              '  ratio=${(v535/v268).toStringAsFixed(2)}'
              '  → ${freq.toStringAsFixed(0)} Hz');
          shown++;
        }
      }
    });

    test('E4 오탐 청크의 CMNDF[134] vs CMNDF[268] 분포', () {
      final samples = _loadWav(_audioPath('E4'));
      final chunks = _chunks(samples);
      // ignore: avoid_print
      print('\nE4 청크 CMNDF 샘플 (최대 10개):');
      int shown = 0;
      for (final chunk in chunks) {
        if (shown >= 10) break;
        final c = computeCmndf(chunk);
        final v134 = c[134];
        final v268 = c[268];
        // ignore: avoid_print
        print('  CMNDF[134]=${v134.toStringAsFixed(4)}'
            '  CMNDF[268]=${v268.toStringAsFixed(4)}'
            '  c268<c134: ${v268 < v134}');
        shown++;
      }
    });
  });

  // ── 오탐 주파수 분포 ──────────────────────────────────────────────────────
  group('오탐 주파수 분포 진단', () {
    test('E2 오탐 주파수 분포', () async {
      final path = _audioPath('E2');
      final samples = _loadWav(path);
      final chunks = _chunks(samples);
      final target = 82.41;
      final wrong = <double>[];
      for (final chunk in chunks) {
        final freq = await detector.detect(chunk);
        if (freq != null && (freq - target).abs() / target >= 0.05) {
          wrong.add(freq);
        }
      }
      // ignore: avoid_print
      print('E2 오탐 주파수 (총 ${wrong.length}개):');
      final buckets = <int, int>{};
      for (final f in wrong) {
        final bucket = (f / 10).round() * 10;
        buckets[bucket] = (buckets[bucket] ?? 0) + 1;
      }
      for (final e in (buckets.entries.toList()..sort((a,b)=>b.value-a.value)).take(5)) {
        // ignore: avoid_print
        print('  ~${e.key} Hz: ${e.value}회');
      }
    });

    test('G3 오탐 주파수 분포', () async {
      final path = _audioPath('G3');
      final samples = _loadWav(path);
      final chunks = _chunks(samples);
      final target = 196.00;
      final wrong = <double>[];
      for (final chunk in chunks) {
        final freq = await detector.detect(chunk);
        if (freq != null && (freq - target).abs() / target >= 0.05) {
          wrong.add(freq);
        }
      }
      // ignore: avoid_print
      print('G3 오탐 주파수 (총 ${wrong.length}개):');
      final buckets = <int, int>{};
      for (final f in wrong) {
        final bucket = (f / 10).round() * 10;
        buckets[bucket] = (buckets[bucket] ?? 0) + 1;
      }
      for (final e in (buckets.entries.toList()..sort((a,b)=>b.value-a.value)).take(5)) {
        // ignore: avoid_print
        print('  ~${e.key} Hz: ${e.value}회');
      }
    });
  });

  // ── 상세 진단: 청크별 감지 분포 ───────────────────────────────────────────
  group('실제 WAV – 청크별 분포 진단', () {
    test('전 현 분포 출력', () async {
      // ignore: avoid_print
      print('\n╔══════════════════════════════════════════════════════╗');
      // ignore: avoid_print
      print('║  현      기대Hz  감지Hz(중앙값)  정답률  오차   ║');
      // ignore: avoid_print
      print('╠══════════════════════════════════════════════════════╣');

      for (final e in strings.entries) {
        final path = _audioPath(noteFile[e.key]!);
        if (!File(path).existsSync()) {
          // ignore: avoid_print
          print('║  ${e.key.padRight(8)} 파일 없음                           ║');
          continue;
        }

        final samples = _loadWav(path);
        final chunks = _chunks(samples);
        final detected = await _detectAll(detector, chunks);

        if (detected.isEmpty) {
          // ignore: avoid_print
          print('║  ${e.key.padRight(8)} ${e.value.toStringAsFixed(1).padLeft(7)}  '
              '감지 실패                      ║');
          continue;
        }

        final med = _median(detected);
        final target = e.value;
        final correct = detected
            .where((f) => (f - target).abs() / target < 0.05)
            .length;
        final correctPct = correct / detected.length * 100;
        final errorPct = (med - target).abs() / target * 100;

        // ignore: avoid_print
        print('║  ${e.key.padRight(8)} '
            '${target.toStringAsFixed(1).padLeft(7)}  '
            '${med.toStringAsFixed(1).padLeft(13)}  '
            '${correctPct.toStringAsFixed(0).padLeft(5)}%  '
            '${errorPct.toStringAsFixed(1).padLeft(5)}%  ║');
      }

      // ignore: avoid_print
      print('╚══════════════════════════════════════════════════════╝');
    });
  });
}
