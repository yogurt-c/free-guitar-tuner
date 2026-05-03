# 오디오 엔진 스펙

## 오디오 캡처

- 샘플레이트: 44100 Hz
- 버퍼 크기: 4096 샘플 (≈ 93 ms / 청크)
- 채널: 모노 (PCM16)
- 패키지: `record`, `audio_session`

## 피치 감지 알고리즘: Target-Aware YIN

기존 first-dip + octave-correction 방식은 자연스럽게 발생하는 CMNDF 서브하모닉 dip
때문에 G3·D3 등에서 옥타브 캐스케이드(−1200 cents 점프)를 일으켰다.
이를 구조적으로 차단하기 위해 **다중 후보 + ±반옥타브 윈도우 검색** 방식으로 전환.

### 동작

1. CMNDF (cumulative mean normalized difference function) 계산은 표준 YIN 그대로.
2. 외부에서 후보 주파수 목록을 주입받는다:
   - **수동 모드** (`autoDetect=false`): 선택된 현 1개의 주파수
   - **자동 감지 모드** (`autoDetect=true`, 기본): preset 의 모든 현
3. 각 후보 `f_target` 에 대해 tau 윈도우 `[f_target/√2, f_target×√2]` 안에서만
   CMNDF 최솟값을 찾는다.
4. 모든 후보 중 가장 낮은 CMNDF 값을 가진 tau 를 선택한다.
5. CMNDF 가 0.4 (pYIN 신뢰 한계값)를 넘으면 null 반환.
6. 포물선 보간으로 서브샘플 정밀도 확보 후 `freq = sampleRate / tau` 반환.

### 옥타브 에러 차단 원리

윈도우 폭 ±√2 = ±600 cents 이므로 한 옥타브 위(×2)·아래(÷2)는 항상 윈도우 밖이다.
따라서 **단일 후보 윈도우 안에서는 옥타브 에러가 구조적으로 발생할 수 없다.**
별도의 옥타브 보정 로직(Path A / Path B / 이전 fix 들) 모두 불필요.

## Cents 표시 기준

- 범위: −50 ~ +50 cents
- |cents| < 3 → 초록 inTune (#7DD3A0)
- cents < −3 → 오렌지 flat (#E0824A) — 음정 낮음
- cents > 3 → 파랑 sharp (#5BA3E0) — 음정 높음

## 안정화 처리

- 노이즈 게이트: RMS 신호 강도 0.01 미만 무시
- 다중 프레임 중앙값: 연속 5 프레임 주파수 중앙값으로 떨림 방지
  (옥타브 에러가 사라져 짧은 윈도우로 충분, 응답성과 안정성 균형)
- 후보 변경(현 선택 / preset 변경 / autoDetect 토글) 시 스무딩 버퍼 초기화
