// 합성 기타 톤 WAV 생성기.
//
// 목적: 실 튜너 사용 패턴(사용자가 줄을 반복적으로 침)을 정확히 모델링한 테스트
// 데이터. Iowa MIS 단일 pluck 와 달리 한 파일에 여러 pluck 가 들어 있어 튜너
// 알고리즘이 실 사용 시나리오에서 어떻게 동작하는지 검증.
//
// 모델:
//   - sinusoid sum: fundamental + 5~6 배음, 어쿠스틱 기타 특성 amplitude.
//   - ADSR envelope per pluck:  attack 8ms, decay 60ms to 70%, sustain
//     ~1.2s linear decay, release exponential.
//   - 다중 pluck: 5초 안에 3-4 번 (실 튜너 사용 패턴).
//   - 약한 gaussian 노이즈.
//   - 디튠 변형: ±30~50 cents.
//
// 출력: test/audio/synth/{string}_{scenario}.wav  (44.1kHz mono PCM16)
//
// 실행: dart run tool/generate_synth_wavs.dart

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

const _sampleRate = 44100;
const _totalSeconds = 5.0;

/// 한 pluck 의 ADSR 시간 (s).
const _attack = 0.008;
const _decay = 0.060;
const _sustain = 1.2; // 이 구간 linear decay to ~50% peak
const _release = 1.5; // 이후 exponential tail

/// 어쿠스틱 기타 배음 amplitude (fundamental 기준 비율).
/// 실 측정값에 가까운 분포 — 2nd harmonic 이 fund 와 비슷, 3rd 4th 가 중간 강도.
const _harmonics = <double>[
  1.0,   // f1 (fundamental)
  0.85,  // f2 (octave)
  0.55,  // f3
  0.40,  // f4
  0.25,  // f5
  0.15,  // f6
];

/// String inharmonicity coefficient. 실 강철현 기타 측정값 0.0001 ~ 0.001 범위
/// (저음현 ~0.0001, 고음현 ~0.001). 배음 freq = n × f1 × sqrt(1 + B × n²).
/// 고차 배음이 정수배에서 sharp 방향 드리프트.
/// 이게 없으면 합성 톤이 너무 깨끗해서 sub-harmonic 모호성 (예: 3×E2 ≈ B3) 으로
/// 잘못된 string 으로 LOCK 됨. 실 기타는 inharmonicity 로 자연스럽게 풀림.
/// 살짝 강하게 (0.0008) 잡아서 sub-octave 모호성도 잡힘.
const _inharmonicity = 0.0008;

/// 백그라운드 노이즈 표준편차 (PCM 스케일 [-1, 1]).
const _noiseStd = 0.002;

/// pluck 시간 (s). 5초 안에 3-4 번.
const _pluckTimes = <double>[0.10, 1.4, 2.8, 4.0];

class Tone {
  final String name;
  final double freq;
  const Tone(this.name, this.freq);
}

const _tones = <Tone>[
  Tone('E2', 82.41),
  Tone('A2', 110.00),
  Tone('D3', 146.83),
  Tone('G3', 196.00),
  Tone('B3', 246.94),
  Tone('E4', 329.63),
];

void main() async {
  final outDir = Directory('test/audio/synth');
  outDir.createSync(recursive: true);

  final rng = Random(42); // 고정 시드 → 재현 가능
  final scenarios = <String, double>{
    'nominal': 0.0, // 정확한 nominal pitch
    'flat40': -40.0, // -40 cents (사용자가 풀어줘야 하는 상태)
    'sharp30': 30.0, // +30 cents (살짝 조여진 상태)
  };

  for (final tone in _tones) {
    for (final entry in scenarios.entries) {
      final cents = entry.value;
      final actualFreq = tone.freq * pow(2.0, cents / 1200.0);
      final samples = _synthesize(actualFreq, rng);
      final path = 'test/audio/synth/${tone.name}_${entry.key}.wav';
      _writeWav(path, samples);
      stdout.writeln(
          '${tone.name} ${entry.key.padRight(8)} freq=${actualFreq.toStringAsFixed(2)} Hz '
          '→ $path (${samples.length ~/ _sampleRate}s)');
    }
  }
}

/// 멀티 pluck 합성. freq 는 실 fundamental (디튠 적용 후).
Float32List _synthesize(double freq, Random rng) {
  final totalSamples = (_sampleRate * _totalSeconds).round();
  final out = Float32List(totalSamples);

  // 각 pluck 위치에서 ADSR + 합성파 누적.
  for (final pluckTime in _pluckTimes) {
    final startSample = (pluckTime * _sampleRate).round();
    _addPluck(out, startSample, freq, rng);
  }

  // 백그라운드 노이즈 추가.
  for (var i = 0; i < totalSamples; i++) {
    out[i] += _gaussian(rng, _noiseStd);
  }

  // 클리핑 방지 정규화 (peak 0.9).
  double peak = 0.0;
  for (final v in out) {
    final a = v.abs();
    if (a > peak) peak = a;
  }
  if (peak > 0.9) {
    final s = 0.9 / peak;
    for (var i = 0; i < totalSamples; i++) {
      out[i] *= s;
    }
  }
  return out;
}

void _addPluck(Float32List buf, int startSample, double freq, Random rng) {
  final n = buf.length;
  // 위상 랜덤 (배음 사이) — 보다 자연스러운 톤.
  final phases = List<double>.generate(
      _harmonics.length, (_) => rng.nextDouble() * 2 * pi);

  // 각 배음의 초기 amplitude (pluck 마다 살짝 다른 강도 — 실제 연주 흉내).
  final pluckGain = 0.5 + rng.nextDouble() * 0.3; // 0.5 ~ 0.8

  final attackSamples = (_attack * _sampleRate).round();
  final decaySamples = (_decay * _sampleRate).round();
  final sustainSamples = (_sustain * _sampleRate).round();
  final releaseSamples = (_release * _sampleRate).round();
  final totalPluckSamples =
      attackSamples + decaySamples + sustainSamples + releaseSamples;

  for (var t = 0; t < totalPluckSamples; t++) {
    final i = startSample + t;
    if (i >= n) break;

    // ADSR amplitude factor.
    double env;
    if (t < attackSamples) {
      env = t / attackSamples; // linear attack
    } else if (t < attackSamples + decaySamples) {
      final p = (t - attackSamples) / decaySamples;
      env = 1.0 - p * 0.30; // decay to 70%
    } else if (t < attackSamples + decaySamples + sustainSamples) {
      final p = (t - attackSamples - decaySamples) / sustainSamples;
      env = 0.70 - p * 0.20; // sustain decay 70% → 50%
    } else {
      final p = (t - attackSamples - decaySamples - sustainSamples) /
          releaseSamples;
      env = 0.50 * exp(-3.0 * p); // exponential release
    }
    env *= pluckGain;

    // 배음별 sin 합성. 고배음은 더 빨리 감쇠 — 시간 따라 amplitude 감쇠 ratio 부여.
    double sample = 0.0;
    final timeS = t / _sampleRate;
    for (var h = 0; h < _harmonics.length; h++) {
      final n = h + 1; // 배음 번호 (1-indexed)
      // Inharmonicity: f_n = n × f1 × sqrt(1 + B × n²)
      final harmonicFreq = n * freq * sqrt(1.0 + _inharmonicity * n * n);
      if (harmonicFreq > _sampleRate / 2) break; // nyquist
      // 고배음 추가 감쇠: 시간에 따라 더 빨리 사라짐.
      final harmonicDecay = exp(-timeS * (h * 0.4));
      sample += _harmonics[h] *
          harmonicDecay *
          sin(2 * pi * harmonicFreq * timeS + phases[h]);
    }
    buf[i] += env * sample * 0.15; // 전체 음량 스케일
  }
}

double _gaussian(Random rng, double std) {
  // Box-Muller.
  final u1 = max(1e-9, rng.nextDouble());
  final u2 = rng.nextDouble();
  return sqrt(-2 * log(u1)) * cos(2 * pi * u2) * std;
}

/// 44.1kHz mono PCM16 WAV 출력.
void _writeWav(String path, Float32List samples) {
  final byteCount = samples.length * 2;
  final header = ByteData(44);
  header.setUint8(0, 0x52); // 'R'
  header.setUint8(1, 0x49); // 'I'
  header.setUint8(2, 0x46); // 'F'
  header.setUint8(3, 0x46); // 'F'
  header.setUint32(4, 36 + byteCount, Endian.little);
  header.setUint8(8, 0x57); // 'W'
  header.setUint8(9, 0x41); // 'A'
  header.setUint8(10, 0x56); // 'V'
  header.setUint8(11, 0x45); // 'E'
  header.setUint8(12, 0x66); // 'f'
  header.setUint8(13, 0x6d); // 'm'
  header.setUint8(14, 0x74); // 't'
  header.setUint8(15, 0x20); // ' '
  header.setUint32(16, 16, Endian.little); // fmt chunk size
  header.setUint16(20, 1, Endian.little); // PCM
  header.setUint16(22, 1, Endian.little); // mono
  header.setUint32(24, _sampleRate, Endian.little);
  header.setUint32(28, _sampleRate * 2, Endian.little); // byte rate
  header.setUint16(32, 2, Endian.little); // block align
  header.setUint16(34, 16, Endian.little); // bits per sample
  header.setUint8(36, 0x64); // 'd'
  header.setUint8(37, 0x61); // 'a'
  header.setUint8(38, 0x74); // 't'
  header.setUint8(39, 0x61); // 'a'
  header.setUint32(40, byteCount, Endian.little);

  final data = ByteData(byteCount);
  for (var i = 0; i < samples.length; i++) {
    final clamped = samples[i].clamp(-1.0, 1.0);
    data.setInt16(i * 2, (clamped * 32767).round(), Endian.little);
  }

  final file = File(path);
  file.writeAsBytesSync([
    ...header.buffer.asUint8List(),
    ...data.buffer.asUint8List(),
  ]);
}
