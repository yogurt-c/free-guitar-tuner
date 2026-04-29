# TODO LIST

## Phase 1 — 프로젝트 셋업
- [x] `chore: 클린 아키텍처 구조로 플러터 프로젝트 초기화`
- [x] `chore: 핵심 의존성 추가 (riverpod, record, audio_session, fftea)`
- [x] `chore: Android/iOS 마이크 권한 설정`

## Phase 2 — 도메인 레이어
- [x] `feat: Note, Tuning 도메인 모델 정의`
  - `Note` — note(String), octave(int), freq(double) 불변 모델
  - `TuningPreset` — name, strings(List<Note>) 불변 모델
- [x] `feat: 튜닝 프리셋 추가`
  - Standard / Drop D / Drop C / Half Step Down / Open G / Open D / DADGAD
  - 각 프리셋: 6번현(낮음) → 1번현(높음) 순서로 정의
- [x] `feat: 주파수 → 음이름 + cents 변환 로직 구현`
  - cents = 1200 × log₂(detectedFreq / targetFreq)
  - |cents| < 3 → inTune, cents < -3 → flat, cents > 3 → sharp

## Phase 3 — 오디오 엔진
- [ ] `feat: 마이크 오디오 캡처 스트림 구현`
  - PCM16 모노, 44100Hz, 버퍼 2048샘플
  - `record` 패키지 사용, `audio_session` 세션 설정
- [ ] `feat: YIN 피치 감지 알고리즘 구현`
  - Difference function → CMNDF → 절대 임계값(0.1) → 포물선 보간
  - `compute()`로 별도 isolate 실행 (UI 스레드 블로킹 금지)
- [ ] `feat: 오디오 스트림과 피치 감지 연결`
  - PCM16 bytes → double samples 변환 후 YIN 입력

## Phase 4 — 상태관리
- [ ] `feat: Riverpod으로 TunerNotifier 구현 (감지 음, cents, 주파수)`
  - state: detectedFreq, cents, inTune, signalLevel
  - 노이즈 게이트: 신호 강도 임계값 이하 무시
- [ ] `feat: TuningSelectionNotifier 구현 (프리셋 선택, 현 선택)`
  - state: presetKey, selectedString(0~5), autoDetect, tunedStrings(Set<int>), isDark
  - 프리셋 변경 시 tunedStrings, selectedString 초기화
  - inTune 500ms 유지 시 tunedStrings에 해당 현 추가
- [ ] `feat: 현 자동 감지 로직 구현`
  - autoDetect ON 시 detectedFreq와 가장 가까운 현(cents 거리 최소)으로 자동 전환
  - 거리 200¢ 이내일 때만 전환

## Phase 5 — 핵심 UI
- [ ] `feat: 바 미터 위젯 구현 (21바, ±50¢ 스펙트럼)`
  - 21개 바, 중앙(0¢) 기준 좌우로 ±50¢ 매핑
  - 활성 바에서 멀어질수록 높이·불투명도 감소 (peakHeight = 1 - dist/3.5)
  - flat → orange(#E0824A), sharp → blue(#5BA3E0), inTune → 전체 green(#7DD3A0) + 글로우
  - inTune 시 상단 "Locked" 알약 뱃지, 방사형 halo 배경 표시
  - 중앙 세로 기준선(hairline), 하단 −50¢ / cents값 / +50¢ 레이블
- [ ] `feat: 음이름 표시 및 cents 인디케이터 구현`
  - 96px 폰트 음이름 + 상단 octave 숫자
  - 상태 필 (IN TUNE / TOO LOW · ♭ / TOO HIGH · ♯ / NEAR) + 펄스 도트
  - currentFreq Hz → targetFreq Hz 표시
- [ ] `feat: 프레트보드 현 다이어그램 위젯 구현`
  - 6현을 세로로 나열, 6번현(두꺼움) → 1번현(얇음) 순서
  - 왼쪽 너트 세로선 + 현 번호·음이름 pill (선택 시 accent 색)
  - 현 선: thickness = 1.2 + (5 - idx) × 0.45, 선택 현 accent 컬러 + 글로우
  - 튜닝 완료된 현 오른쪽 끝에 초록 체크 원형 배지
  - autoDetect ON 시 비선택 현 비활성(opacity 0.55), 탭 불가
- [ ] `feat: TopBar 구현`
  - 좌측: 햄버거 메뉴 버튼 (SideMenu 열기)
  - 중앙: 현재 모드 레이블 (Tuner / Metronome)
  - 우측: 다크/라이트 토글 버튼
- [ ] `feat: 메인 튜너 화면 조합 (TunerScreen)`
  - 상단: TopBar → BarMeter → PresetDropdown → FretboardView → BottomControls

## Phase 6 — 튜닝 선택 UI
- [ ] `feat: 튜닝 프리셋 드롭다운 구현`
  - 선택된 프리셋 이름 + 음열(E A D G B E) 한 줄 표시
  - 펼치면 전체 프리셋 목록, 활성 항목 우측에 accent 도트
- [ ] `feat: 사이드 메뉴 구현`
  - 좌측에서 슬라이드인, 배경 딤 처리
  - 메뉴 항목: Tuner(마이크 아이콘) / Metronome(메트로놈 아이콘)
  - 활성 항목 좌측 accent 세로선 + 아이콘 배경 accent 틴트
- [ ] `feat: 메트로놈 화면 구현`
  - BPM 숫자(124px), 템포 이름(Largo~Presto), BPM 슬라이더(40~220)
  - 박자 도트 (downbeat 크게, 나머지 작게), 현재 박자 accent 컬러 + 글로우
  - 박자표 선택: 3/4 · 4/4 · 6/4 · 8/4, Start/Stop 버튼
- [ ] `feat: BottomControls 구현`
  - Auto-detect 토글 스위치 + 레이블
  - 우측: 펄스 도트 + "Mic live · A = 440 Hz"

## Phase 7 — 완성도
- [ ] `feat: 다중 프레임 평균으로 감지 안정화 구현`
- [ ] `feat: 튜닝 완료 시 햅틱 피드백 추가`
- [ ] `fix: 마이크 권한 거부 상태 처리`
- [ ] `chore: 앱 아이콘 및 표시 이름 설정`
