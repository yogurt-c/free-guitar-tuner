# 프로젝트 구조

## 아키텍처: Clean Architecture (3레이어)

```
lib/
├── domain/                  # 순수 비즈니스 로직 (Flutter 의존 없음)
│   ├── model/
│   │   ├── note.dart
│   │   └── tuning_preset.dart
│   └── analyzer/
│       └── note_analyzer.dart
│
├── data/                    # 오디오 캡처, 플랫폼 연동
│   ├── audio_capture.dart
│   └── pitch_detector.dart
│
└── presentation/            # UI, 상태관리
    ├── shared/
    │   ├── app_theme.dart             # 색상 토큰 (dark/light 테마)
    │   └── pulse_dot.dart             # 반복 펄스 애니메이션 도트 위젯
    ├── tuner/
    │   ├── tuner_screen.dart
    │   ├── tuner_notifier.dart
    │   └── widgets/
    │       ├── bar_meter.dart         # 21바 스펙트럼 바 미터 (±50¢)
    │       ├── note_display.dart      # 음이름 + cents + 상태 필
    │       ├── fretboard_view.dart    # 6현 다이어그램 (두께 차등, 튜닝 완료 배지)
    │       ├── top_bar.dart           # 햄버거 메뉴 + 모드 레이블 + 다크/라이트 토글
    │       ├── bottom_controls.dart   # Auto-detect 토글 + Mic live 표시
    │       └── side_menu.dart         # (Phase 6) 슬라이드인 메뉴 (Tuner / Metronome)
    ├── metronome/
    │   └── metronome_screen.dart      # (Phase 6) BPM, 박자 도트, 박자표 선택, Start/Stop
    └── tuning_selector/
        ├── tuning_selector_dropdown.dart
        └── tuning_selection_notifier.dart
```

## 레이어 의존 방향

```
presentation → domain ← data
```

- `data`와 `presentation`은 서로 직접 의존하지 않음
- `domain`은 외부 패키지에 의존하지 않음

## 주요 패키지

| 패키지          | 용도                        |
|----------------|-----------------------------|
| flutter_riverpod | 상태관리                  |
| record           | 마이크 오디오 스트림        |
| audio_session    | 오디오 세션 설정            |
| fftea            | FFT 연산 (YIN 알고리즘 보조) |
