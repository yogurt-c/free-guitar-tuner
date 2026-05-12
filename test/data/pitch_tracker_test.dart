// PitchTracker 단위 테스트.
//
// PitchEstimate 시계열을 던지고 state 전환이 의도대로 일어나는지 검증.
// YinEstimator / 실 오디오와 무관, state machine 만 검증.

import 'package:flutter_test/flutter_test.dart';
import 'package:guitar_tuner/data/pitch_tracker.dart';
import 'package:guitar_tuner/domain/model/pitch_estimate.dart';
import 'package:guitar_tuner/domain/model/tracker_state.dart';

PitchEstimate est(double freq, double conf) =>
    PitchEstimate(freq: freq, confidence: conf);

const _e2 = 82.41;
const _a2 = 110.0;
const _d3 = 146.83;
const _g3 = 196.0;
const _b3 = 246.94;
const _e4 = 329.63;

const _stdStrings = <double>[_e2, _a2, _d3, _g3, _b3, _e4];

PitchTracker _newAuto() => PitchTracker()
  ..setStrings(_stdStrings)
  ..setAutoDetect(true);

PitchTracker _newManual(int selected) => PitchTracker()
  ..setStrings(_stdStrings)
  ..setAutoDetect(false)
  ..setSelectedString(selected);

/// 같은 freq/conf 로 lockFrames 만큼 update 해 LOCKED 진입.
void _lockOn(
  PitchTracker t,
  double freq,
  double conf,
  double level,
) {
  for (var i = 0; i < PitchTracker.lockFrames; i++) {
    t.update(est(freq, conf), signalLevel: level);
  }
}

void main() {
  group('IDLE / SEARCHING / LOCKED 진입', () {
    test('signal 약하면 grace 안에는 IDLE 유지 (초기 상태)', () {
      final t = _newAuto();
      final s = t.update(est(_g3, 0.05), signalLevel: 0.003);
      expect(s, isA<TrackerIdle>());
    });

    test('lockFrames 미만은 SEARCHING(tentative 동봉), lockFrames 연속이면 LOCKED',
        () {
      final t = _newAuto();
      // lockFrames-1 까지는 SEARCHING.
      for (var i = 0; i < PitchTracker.lockFrames - 1; i++) {
        final s = t.update(est(_g3, 0.05), signalLevel: 0.1);
        expect(s, isA<TrackerSearching>(), reason: 'hop=$i');
        expect((s as TrackerSearching).tentative, isNotNull);
        expect(s.tentative!.stringIndex, 3);
      }
      // lockFrames 번째 hop 에서 LOCKED.
      final last = t.update(est(_g3, 0.05), signalLevel: 0.1);
      expect(last, isA<TrackerLocked>());
      final locked = last as TrackerLocked;
      expect(locked.stringIndex, 3);
      expect(locked.detectedFreq, closeTo(_g3, 0.1));
      expect(locked.cents.abs(), lessThan(1.0));
    });

    test('confidence 가 lockEnterConf 이상이면 LOCK 안 됨, SEARCHING 유지', () {
      final t = _newAuto();
      for (var i = 0; i < PitchTracker.lockFrames + 2; i++) {
        final s = t.update(est(_g3, 0.25), signalLevel: 0.1);
        expect(s, isA<TrackerSearching>(),
            reason: '약 confidence 는 LOCK 안 됨 ($i)');
      }
    });

    test('estimate null 이 grace 연속이면 IDLE', () {
      final t = _newAuto();
      _lockOn(t, _g3, 0.05, 0.1);
      expect(t.state, isA<TrackerLocked>());

      // estimate null 이지만 신호 충분 — grace 안에선 LOCKED 유지.
      for (var i = 0; i < PitchTracker.idleGraceFrames - 1; i++) {
        t.update(null, signalLevel: 0.1);
        expect(t.state, isA<TrackerLocked>(), reason: 'grace 안 LOCKED 유지 ($i)');
      }
      t.update(null, signalLevel: 0.1);
      expect(t.state, isA<TrackerIdle>());
    });
  });

  group('noiseGate hysteresis + grace', () {
    test('LOCKED 후 한 hop quiet 은 LOCKED 유지', () {
      final t = _newAuto();
      _lockOn(t, _g3, 0.05, 0.1);

      t.update(est(_g3, 0.05), signalLevel: 0.003);
      expect(t.state, isA<TrackerLocked>());
    });

    test('quiet hop 이 idleGraceFrames 연속이면 IDLE', () {
      final t = _newAuto();
      _lockOn(t, _g3, 0.05, 0.1);

      for (var i = 0; i < PitchTracker.idleGraceFrames; i++) {
        t.update(est(_g3, 0.05), signalLevel: 0.003);
      }
      expect(t.state, isA<TrackerIdle>());
    });

    test('quiet 중간에 loud 들어오면 grace 카운터 reset', () {
      final t = _newAuto();
      _lockOn(t, _g3, 0.05, 0.1);

      // grace 의 절반 정도 quiet → loud 1번 → 다시 절반 quiet. grace 안.
      final half = PitchTracker.idleGraceFrames ~/ 2;
      for (var i = 0; i < half; i++) {
        t.update(est(_g3, 0.05), signalLevel: 0.003);
      }
      t.update(est(_g3, 0.05), signalLevel: 0.1);
      for (var i = 0; i < half; i++) {
        t.update(est(_g3, 0.05), signalLevel: 0.003);
      }
      expect(t.state, isA<TrackerLocked>());
    });
  });

  group('closestString 매핑 + 100c 컷', () {
    test('freq 가 100c 안 → tentative 동봉', () {
      final t = _newAuto();
      // G3 +50c ≈ 201.7 — 100c 안.
      final s = t.update(est(201.7, 0.10), signalLevel: 0.1);
      expect(s, isA<TrackerSearching>());
      expect((s as TrackerSearching).tentative?.stringIndex, 3);
    });

    test('freq 가 100c 초과 (현 사이) → SEARCHING tentative null', () {
      final t = _newAuto();
      // G3 196 ~ B3 247 의 중간 ≈ 220 — D3 와 G3 모두 100c 이상.
      // ln(220/196)/ln2*1200 = 199c, ln(220/247)/ln2*1200 = -200c.
      final s = t.update(est(220.0, 0.05), signalLevel: 0.1);
      expect(s, isA<TrackerSearching>());
      expect((s as TrackerSearching).tentative, isNull);
    });

    test('LOCKED 후 매핑 miss 가 unlockFrames 연속 → IDLE', () {
      final t = _newAuto();
      _lockOn(t, _g3, 0.05, 0.1);
      expect(t.state, isA<TrackerLocked>());

      for (var i = 0; i < PitchTracker.unlockFrames; i++) {
        t.update(est(220.0, 0.05), signalLevel: 0.1);
      }
      expect(t.state, isA<TrackerIdle>());
    });
  });

  group('Manual 모드 — silence 보존', () {
    test('Manual + 선택 안 한 현 → IDLE (tentative 없음)', () {
      final t = _newManual(3); // G3 선택
      // 사용자가 A2 침.
      final s = t.update(est(_a2, 0.05), signalLevel: 0.1);
      expect(s, isA<TrackerIdle>(),
          reason: 'Manual 에서 다른 현은 silence');
    });

    test('Manual + 선택 현 정확히 침 → LOCK 정상', () {
      final t = _newManual(3);
      _lockOn(t, _g3, 0.05, 0.1);
      expect(t.state, isA<TrackerLocked>());
      expect((t.state as TrackerLocked).stringIndex, 3);
    });

    test('Manual LOCKED 후 다른 현 unlockFrames 연속 → IDLE (SEARCHING 거치지 않음)', () {
      final t = _newManual(3);
      _lockOn(t, _g3, 0.05, 0.1);
      expect(t.state, isA<TrackerLocked>());

      for (var i = 0; i < PitchTracker.unlockFrames; i++) {
        t.update(est(_a2, 0.05), signalLevel: 0.1);
      }
      expect(t.state, isA<TrackerIdle>());
    });

    test('setSelectedString 시 LOCK 초기화', () {
      final t = _newManual(3);
      _lockOn(t, _g3, 0.05, 0.1);
      expect(t.state, isA<TrackerLocked>());

      t.setSelectedString(1);
      expect(t.state, isA<TrackerIdle>());
    });
  });

  group('LOCKED 유지 / EMA / 점진 해제', () {
    test('자기 현 freq 흔들림 → EMA 평활', () {
      final t = _newAuto();
      _lockOn(t, _g3, 0.05, 0.1);
      // lockFrames hops 의 EMA 가 정확히 _g3 으로 수렴 — 모두 같은 값이라.
      expect((t.state as TrackerLocked).detectedFreq, closeTo(_g3, 0.01));

      // 다음 hop 197.5 → EMA = α·197.5 + (1-α)·_g3.
      final s = t.update(est(197.5, 0.04), signalLevel: 0.1) as TrackerLocked;
      final expected =
          PitchTracker.freqEmaAlpha * 197.5 +
              (1 - PitchTracker.freqEmaAlpha) * _g3;
      expect(s.detectedFreq, closeTo(expected, 0.01));
    });

    test('LOCKED EMA 가 여러 hop 후 새 freq 로 수렴', () {
      final t = _newAuto();
      _lockOn(t, _g3, 0.05, 0.1);

      // α=0.10 의 99% 수렴은 약 -ln(0.01)/(-ln(1-α)) ≈ 44 hops.
      late TrackerLocked last;
      for (var i = 0; i < 80; i++) {
        last = t.update(est(197.5, 0.04), signalLevel: 0.1) as TrackerLocked;
      }
      expect(last.detectedFreq, closeTo(197.5, 0.05));
    });

    test('LOCKED 중 일시적 다른 현 (< unlockFrames) → LOCKED 유지', () {
      final t = _newAuto();
      _lockOn(t, _g3, 0.05, 0.1);

      final s = t.update(est(_a2, 0.30), signalLevel: 0.1);
      expect(s, isA<TrackerLocked>());
      expect((s as TrackerLocked).stringIndex, 3);
    });

    test('LOCKED 중 다른 현 unlockFrames 연속 → SEARCHING (rise 무관)', () {
      final t = _newAuto();
      _lockOn(t, _g3, 0.10, 0.1);
      expect(t.state, isA<TrackerLocked>());

      // signal 평탄 (rise 없음) — 점진 해제만 작동해야.
      for (var i = 0; i < PitchTracker.unlockFrames; i++) {
        t.update(est(_a2, 0.25), signalLevel: 0.1);
      }
      expect(t.state, isA<TrackerSearching>());
    });
  });

  group('rise-gated hand-off', () {
    test('rms 평탄 + 다른 현 strong → 즉시 hand-off 안 함', () {
      final t = _newAuto();
      _lockOn(t, _g3, 0.10, 0.1);

      final s = t.update(est(_a2, 0.05), signalLevel: 0.1);
      expect(s, isA<TrackerLocked>(),
          reason: 'rms 평탄이면 다른 현 strong 이어도 LOCKED 유지');
    });

    test('rms 상승 + 다른 현 strong → 즉시 SEARCHING(tentative)', () {
      final t = _newAuto();
      _lockOn(t, _g3, 0.10, 0.05);
      expect(t.state, isA<TrackerLocked>());

      final s = t.update(est(_a2, 0.05), signalLevel: 0.10);
      expect(s, isA<TrackerSearching>());
      expect((s as TrackerSearching).tentative?.stringIndex, 1);
    });

    test('rise + 다른 현 strong → 같은 현 재 LOCK', () {
      final t = _newAuto();
      _lockOn(t, _g3, 0.10, 0.05);

      // rise 로 hand-off → SEARCHING(A2 tentative). 이후 A2 가 lockFrames 연속이면 LOCK.
      for (var i = 0; i < PitchTracker.lockFrames; i++) {
        t.update(est(_a2, 0.05), signalLevel: 0.10);
      }
      final s = t.state;
      expect(s, isA<TrackerLocked>());
      expect((s as TrackerLocked).stringIndex, 1);
    });
  });

  group('setter 동작', () {
    test('setStrings 변경 시 reset', () {
      final t = _newAuto();
      _lockOn(t, _g3, 0.05, 0.1);
      expect(t.state, isA<TrackerLocked>());

      t.setStrings(const [73.42, 110.0, 146.83, 196.0, 246.94, 329.63]); // drop D
      expect(t.state, isA<TrackerIdle>());
    });

    test('setAutoDetect 토글 시 reset', () {
      final t = _newAuto();
      _lockOn(t, _g3, 0.05, 0.1);
      expect(t.state, isA<TrackerLocked>());

      t.setAutoDetect(false);
      expect(t.state, isA<TrackerIdle>());
    });

    test('reset 후 IDLE', () {
      final t = _newAuto();
      _lockOn(t, _g3, 0.05, 0.1);
      t.reset();
      expect(t.state, isA<TrackerIdle>());

      final s = t.update(est(_b3, 0.05), signalLevel: 0.1);
      expect(s, isA<TrackerSearching>(), reason: '재 LOCK 필요');
    });
  });

  group('자동감지 — 어느 현이든 LOCK', () {
    for (final stringInfo in [
      (3, _g3),
      (0, _e2),
      (1, _a2),
      (2, _d3),
      (4, _b3),
      (5, _e4),
    ]) {
      test('Auto: stringIndex=${stringInfo.$1} (${stringInfo.$2} Hz) LOCK', () {
        final t = _newAuto();
        _lockOn(t, stringInfo.$2, 0.05, 0.1);
        expect(t.state, isA<TrackerLocked>());
        expect((t.state as TrackerLocked).stringIndex, stringInfo.$1);
      });
    }
  });
}
