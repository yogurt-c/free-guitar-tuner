# 개발 가이드라인

## 개발 전

- 관련 세부 문서를 먼저 확인한다
  - 오디오 관련 작업 → [`audio.md`](audio.md)
  - 튜닝 프리셋 관련 작업 → [`tunings.md`](tunings.md)
  - 구조/아키텍처 관련 작업 → [`structure.md`](structure.md)
- UI 구현 시 반드시 디자인 파일을 참조한다 (`.claude/design/`)
  - 메인 디자인 → [`Guitar Tuner.html`](../design/Guitar%20Tuner.html) — 전체 화면 레이아웃, 색상, 타이포그래피
  - 튜너 UI 컴포넌트 → [`tuner-app.jsx`](../design/tuner-app.jsx) — BarMeter, 음이름 표시, FretboardView 등
  - iOS 프레임 → [`ios-frame.jsx`](../design/ios-frame.jsx) — 디바이스 프레임 및 전체 구성
  - 트윅 패널 → [`tweaks-panel.jsx`](../design/tweaks-panel.jsx) — 세부 파라미터 조정 UI
  - 디자인 채팅 기록 → [`chat1.md`](../design/chat1.md) — 디자인 의도 및 결정 맥락
- 현재 Phase의 TODO를 `in_progress`로 변경한다

## 개발 중

- 레이어 간 의존 방향을 반드시 준수한다
  ```
  presentation → domain ← data
  ```
  - `domain`은 Flutter 패키지 및 외부 라이브러리에 의존하지 않는다
  - `presentation`과 `data`는 서로 직접 참조하지 않는다
- 파일 구조에 변경이 생기면 즉시 [`structure.md`](structure.md)를 수정한다
- 새 튜닝 프리셋을 추가하면 즉시 [`tunings.md`](tunings.md)를 수정한다
- 커밋은 CLAUDE.md에 정의된 단위로 나눠서 진행한다. 한 Phase를 한 번에 커밋하지 않는다

## 개발 후

- 완료한 Phase의 TODO를 `completed`로 변경한다
- 구현 과정에서 CLAUDE.md의 커밋 계획과 달라진 내용이 있으면 CLAUDE.md를 수정한다

## 커밋 규칙

- 언어: **한글**
- 형식: `<type>: <설명>`
- type 목록: `feat`, `fix`, `refactor`, `docs`, `test`, `chore`, `perf`
- 커밋 메시지는 무엇을 했는지가 아니라 **왜** 했는지 중심으로 작성한다

## 아키텍처 원칙

- 파일당 최대 800줄. 초과 시 모듈 분리
- 함수당 최대 50줄. 초과 시 함수 분리
- 상태는 Riverpod Notifier로만 관리하고, 위젯에 비즈니스 로직을 넣지 않는다
- `domain` 레이어의 모델은 불변(immutable)으로 정의한다

## 오디오 처리 주의사항

- 오디오 버퍼 처리는 별도 isolate 또는 플랫폼 채널에서 수행한다 (UI 스레드 블로킹 금지)
- 피치 감지 파라미터(샘플레이트, 버퍼 크기 등) 변경 시 [`audio.md`](audio.md)에 반영한다
