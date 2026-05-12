# 오디오 엔진 스펙

## 오디오 캡처

- 샘플레이트: 44100 Hz
- **hop size**: 1024 샘플 (≈ 23 ms / emit)
- **분석 윈도우**: 4096 샘플 (≈ 93 ms, 75% overlap)
- 채널: 모노 (PCM16)
- 패키지: `record`, `audio_session`

## 파이프라인 구조

```
mic samples (1024-sample hop)
  → AudioPipeline.sliding window (4096 win / 1024 hop)
  → YinEstimator.estimate(window, tauMin, tauMax)
        → PitchEstimate { freq, confidence }   |  null
  → PitchTracker.update(estimate, signalLevel)
        → TrackerState (Idle | Searching | Locked)
  → AudioPipeline.stateStream  (~ 43 Hz update rate)
  → TunerNotifier (UI state 변환)
```

각 책임:
- **AudioCapture**: PCM16 mic stream 을 1024 샘플 hop 단위로 emit.
- **AudioPipeline**: hop 을 4096 sliding window 에 누적, 매 hop 마다 마지막 4096 으로
  YIN 호출. update rate ~43 Hz (overlap 75%). Backpressure (처리 중 도착 hop 은 최신
  1개만). preset/모드/선택현 변경 시 tracker reset + search range 재산정.
- **YinEstimator**: 한 윈도우 정적 분석. 표준 YIN (de Cheveigné & Kawahara, 2002, JASA)
  으로 fundamental 1개 추정. 시계열 정보 사용 안 함, side effect 없음. long-lived
  isolate 1개.
- **PitchTracker**: 시계열 state machine. hop 별 estimate 를 누적해 IDLE / SEARCHING /
  LOCKED 결정. closestString 매핑까지 책임. EMA smoothing 은 SEARCHING / LOCKED 둘
  다에 적용 — 같은 현 유지 중엔 freq history 가 끊기지 않음.

## Overlap 의 의의

비 overlap (이전 설계, 4096 청크) 은 update rate 가 ~10.7 Hz. real-world raw freq
jitter 가 hop 마다 ±25 c (특히 1, 2번 현 의 tau 해상도 13 c/sample 한계) — 한 청크가
그대로 100 ms 동안 화면에 보이므로 사용자에게 ±10 c 진동으로 가시.

overlap 도입 (1024 hop, 75% overlap) 으로 update rate 4× 상승 → EMA 같은 time constant
(τ ≈ 220 ms) 로 4× 더 강한 평활 가능. 실측 p95 hop-to-hop jitter:
- raw: E4 19c, B3 6c
- smoothed (LOCKED.cents): E4 1.3c, B3 1.2c

google archive 의 `audio-processor.js` 가 web audio RAF (~60 Hz) 로 overlapping
autocorrelation 을 자연스럽게 하는 것과 같은 원리.

## YinEstimator

표준 YIN 6단계 중 4단계 구현 (paper Section II):
1. **Difference function** d(τ)
2. **CMNDF** d'(τ) = d(τ)·τ / Σd(j)
3. **Absolute threshold** — 첫 d'(τ) < threshold (= 0.15) 인 τ 의 local min
4. **Parabolic interpolation** (±0.5 shift 클램프)

paper 의 step 6 (best local estimate) 은 시계열 smoothing 으로 PitchTracker 의 EMA 가
대신함. paper 권장 threshold 0.10–0.15 중 0.15 (실 기타는 inharmonicity / 노이즈로 d'
가 0.10 까지 잘 안 내려감).

### Search range

호출자 ([AudioPipeline]) 가 preset 기준으로 동적 산정:
- **fmin = 최저현 freq × 2^(-200/1200)**  → `tauMax = sampleRate / fmin`
- **fmax = 최고현 freq × 2^(+200/1200)**  → `tauMin = sampleRate / fmax`

standard 튜닝 (E2 82.41 ~ E4 329.63) 의 경우:
- fmin ≈ 73.45 Hz, fmax ≈ 369.99 Hz → tauMin = 119, tauMax = 600.

이 좁힘이 strong harmonic 으로 인한 too-high octave error 의 가장 효과적 차단. 광범위
search 안 하면 fundamental 의 정수배 (예: E2 2배음 165Hz) lag 이 search range 밖에 있어
잡히지 않음.

### Octave error 정책

- **too-high** (fundamental 약하고 harmonic 강함): search range 좁힘으로 차단.
- **too-low** (subharmonic 위치 dip 잡힘): paper step 4 의 "smallest τ" 가 차단.
  → 옛 코드의 정수비 leakage 차단 / sub-octave threshold 같은 추가 보정은 두지 않음.
  사인 같은 신호에서 paper step 4 효과를 깨므로.

### Confidence

CMNDF 최저값 (d'(τ_best)). **낮을수록 신뢰**. `maxConfidence` (= 0.40) 이상이면
unvoiced 로 보고 null 반환.

## PitchTracker (state machine)

청크 rate: AudioPipeline overlap 으로 ~43 Hz. 모든 frame-count 상수는 hop 단위 (1 hop ≈ 23 ms).

상태:
- **IDLE**: 신호 없음 (노이즈 게이트 아래) / 매핑 miss / 수동 모드에서 선택 안 한 현 잡힘.
- **SEARCHING**: 신호 있고 매핑은 OK. tentative obs 동봉 (UI 가 dim 표시). EMA 적용.
- **LOCKED(stringIndex)**: 한 후보가 결정됨. 그 현의 freq/cents 표시. EMA 적용.

### closestString 매핑

estimator 결과 freq 를 preset 의 6 현 중 가장 가까운 현으로 매핑:
- `cents = 1200 · log₂(freq / target)` 의 절댓값이 최소인 현
- 그 거리가 `lockMaxCents` (= 100) 초과면 매핑 miss → SEARCHING (tentative 없음)

자동감지: 모든 현 후보. LOCKED stringIndex 가 사용자 선택과 다르면 [TunerNotifier] 가
자동 전환.

수동 모드: closestString 이 선택된 현과 다르면 silence (IDLE). 다른 현의 정보를 보여주지
않아서 manual 모드의 의도 (이 현만 본다) 보존.

### 깜빡임 차단 설계

1. **2단 RMS hysteresis**
   - `noiseGateEnter = 0.012` — 신호 있다고 판정
   - `noiseGateExit = 0.006` — 신호 사라졌다고 판정 (낮게)

2. **idleGraceFrames = 12 hops (≈ 280 ms)**
   - `noiseGateExit` 미만 / estimate null / 매핑 miss / 수동 모드 다른 현 이 idleGrace
     연속이어야 IDLE 확정.

3. **2단 confidence**
   - `lockEnterConf = 0.20` — 진입 strict
   - `lockKeepConf = 0.40` — 유지 관대 (한 hop 살짝 약해져도 OK)

4. **lockFrames = 4 hops (≈ 93 ms)**
   - SEARCHING 중 같은 closestString 이 4 hops 연속 + confidence < 0.20 이면 LOCK.
     overlap (75%) 때문에 4 hops ≈ 1 개의 fully-independent 윈도우 검증.

5. **rise-gated hand-off**
   - LOCKED 중 다른 현으로의 즉시 hand-off 는 **signalLevel 이 rmsRiseThreshold(0.006)
     이상 상승할 때만** 허용. 감쇠 구간에서 다른 현 일시 dip 으로 string 이 바뀌는 거 차단.

6. **점진 해제 (unlockFrames = 12 hops, ≈ 280 ms)**
   - rise-gated 가 안 일어나도 다른 closestString hop 이 unlockFrames 연속이면 SEARCHING.

7. **detectedFreq EMA (α = 0.10, τ ≈ 220 ms)**
   - **SEARCHING / LOCKED 둘 다에 적용**. 같은 string 유지 중엔 freq history 끊기지
     않고 계속 평활. tentative ↔ locked 전환에서 cents 점프 없음.
   - α=0.10 + 23ms hop 의 time constant 는 이전 청크 모델 (α=0.35 + 93ms 청크) 과 동일
     ≈ 220 ms. 즉 사용자 응답성은 그대로, smoothing 은 4× 더 강해짐.
   - **새 현 후보가 등장하면 (`_resetSmoothing`) freq 초기화** — 이전 현 EMA 가 새 현으로
     leak 되지 않음.

### 전환 표

| from → to | 조건 |
|---|---|
| ANY → IDLE | (RMS < noiseGateExit OR estimate null) 이 idleGraceFrames(12) 연속 |
| IDLE → SEARCHING | voiced + 매핑 OK + (auto 또는 selected 와 같음) |
| SEARCHING → LOCKED | 같은 closestString 이 lockFrames(4) 연속 + confidence < lockEnterConf |
| LOCKED(s) 유지 | closestString==s + confidence < lockKeepConf — freq EMA 갱신 |
| LOCKED(s) 즉시 hand-off | signalRising + 다른 closestString + confidence < lockEnterConf |
| LOCKED(s) 점진 해제 | 다른 closestString / 매핑 miss / 수동 다른 현 이 unlockFrames(12) 연속 |

## UI 레이어 — display state (별도)

PitchTracker state 와 화면 표시 상태는 **분리**.

- `TunerNotifier` 가 600 ms **hold timer** 보유.
- LOCKED → 풀 컬러 표시, 타이머 취소.
- SEARCHING(tentative 있음) → 즉시 그 값을 **dim 컬러** 로 표시, 타이머 취소.
  tentative.detectedFreq / cents 는 LOCKED 와 같은 EMA chain 으로 평활 — tentative ↔
  locked 전환에서 값 점프 없음.
- SEARCHING(tentative 없음) / IDLE → 마지막 결과 dim 유지하다 600 ms 타임아웃 시 클리어.
- cents 색 toggle: inTune **진입** |c|<3, **유지** |c|<4 (±1 dead zone, 경계 토글 차단).

핵심: tracker 가 잠깐 SEARCHING/IDLE 로 빠져도 화면은 hold timer 만료 전까진 유지.
flicker 거의 0.

### 자동 전환 + 햅틱 누적 정책

자동감지에서 LOCKED stringIndex 가 사용자 선택과 다르면 [TunerNotifier] 가 `selectString`
호출. 단 **그 청크의 햅틱/tunedStrings 누적은 보내지 않음** (`onTunerUpdate(null)`).
자동 전환 직후 1청크 LOCK 으로 잘못된 체크마크가 생기는 걸 차단. 다음 청크부터 같은 string
LOCK 이어야 누적 시작.

## Cents 표시 기준

- 범위: -50 ~ +50 cents 표시
- |cents| < 3 → inTune (초록)
- cents < -3 → flat (오렌지)
- cents > 3 → sharp (파랑)

## 회귀 방어

### 단위 — yin_estimator_test
순수 사인 6 현, fundamental + 배음, 디튠 ±100c, 노이즈, search range 동작.

### 단위 — pitch_tracker_test
state machine 전환 / hysteresis / grace / EMA / rise-gated hand-off / 100c 컷 / 매핑 miss /
수동 silence / setter / reset 모두 cover.

### 통합 — pitch_pipeline_wav_test
**3개 WAV 소스** 로 production YinEstimator + PitchTracker 시계열 검증:

| 디렉토리 | 출처 | 모델 | 용도 / 기대치 |
|---|---|---|---|
| `test/audio/synth/` | Dart 생성기 ([tool/generate_synth_wavs.dart]) | 4 pluck × 5s, ADSR + 6 배음 + inharmonicity (B=0.0008) + 노이즈 | **실 튜너 사용 시나리오** 회귀. nominal / -40c / +30c. LOCKED 80%+, freq 오차 < 1%, wrong < 5% |
| `test/audio/real/` | University of Iowa MIS (public domain) | 실 어쿠스틱 기타 단일 pluck (첫 5s) | 실 톤 회귀. LOCK 도달 + 올바른 string + ±100c 안 |
| `test/audio/transient/` | tonejs-instruments (MIT) | 짧은 pluck-and-decay | 레거시 baseline |

합성 파일 갱신:
```
dart run tool/generate_synth_wavs.dart
```
