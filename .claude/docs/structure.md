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
    ├── tuner/
    │   ├── tuner_screen.dart
    │   ├── tuner_notifier.dart
    │   └── widgets/
    │       ├── tuner_meter.dart       # CustomPainter 아날로그 미터
    │       ├── note_display.dart
    │       └── string_tab_bar.dart
    └── tuning_selector/
        ├── tuning_selector_sheet.dart
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
