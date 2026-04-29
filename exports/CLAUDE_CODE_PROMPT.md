# Guitar Tuner — App Icon 적용 프롬프트 (Claude Code용)

아래를 그대로 Claude Code에 붙여넣으세요. 마스터 파일은 `app-icon-master.svg` (또는 `app-icon-1024.png`) 한 장입니다.

---

## 프롬프트

> 첨부한 `app-icon-master.svg` (1024×1024)를 우리 기타 튜너 앱의 iOS / Android 앱 아이콘으로 등록해줘. 다음 작업을 진행해줘:
>
> **iOS (Xcode 프로젝트):**
> 1. `app-icon-master.svg`를 1024×1024 PNG로 export (이미 `app-icon-1024.png`가 있으면 그대로 사용)
> 2. `AppIcon.appiconset` 폴더에 모든 필요한 사이즈 PNG 생성:
>    - 1024×1024 (App Store)
>    - 180×180, 120×120 (iPhone)
>    - 167×167, 152×152, 76×76 (iPad)
>    - 87×87, 58×58, 29×29 (Settings)
>    - 80×80, 60×60, 40×40 (Spotlight)
>    - 모서리 마스킹은 적용하지 마. iOS가 자체적으로 squircle 마스크를 씌움.
> 3. `Contents.json` 업데이트
>
> **Android (Adaptive Icon, Pixel 런처 기준 원형 마스크):**
> 1. `app-icon-master.svg`에서 두 레이어 분리:
>    - **Background 레이어**: 다크 그라데이션 배경만 (#1F1F26 → #0B0B0E, 155° linear)
>    - **Foreground 레이어**: 바 스펙트럼 마크만 (66dp safe zone 안에 들어가도록 중앙 60% 영역만 사용)
> 2. 다음 파일 생성:
>    - `res/mipmap-anydpi-v26/ic_launcher.xml` — adaptive-icon (background + foreground 참조)
>    - `res/mipmap-anydpi-v26/ic_launcher_round.xml` — 동일
>    - `res/drawable/ic_launcher_background.xml` (또는 vector)
>    - `res/drawable/ic_launcher_foreground.xml` (또는 vector)
>    - `res/mipmap-{mdpi,hdpi,xhdpi,xxhdpi,xxxhdpi}/ic_launcher.png` (legacy fallback, 48/72/96/144/192px)
>    - Play Store용 `ic_launcher-playstore.png` (512×512)
> 3. `AndroidManifest.xml`에 아이콘이 이미 등록되어 있는지 확인하고, 없으면 추가
>
> 작업 후 두 플랫폼 빌드 모두 정상 컴파일되는지 확인해줘.

---

## 디자인 정보 (필요 시 참고)

- **컨셉**: Bar Spectrum (Green Trio) — 튜너 센트 미터의 9개 바
- **컬러 팔레트**:
  - 배경: 다크 그라데이션 #1F1F26 → #0B0B0E
  - 중앙 3바 (in-tune): #7DD3A0 (그린)
  - 다음 2바: #C8B273 (골드)
  - 페이드 골드: rgba(200,178,115,0.5)
  - 외곽 dim: rgba(245,244,240,0.18)
- **세이프존**: 모든 핵심 요소(중앙 그린 트리오 + 골드 바)는 1024 캔버스 기준 중앙 60% (≈ 614px) 안에 위치 → 어떤 OEM 마스크에서도 잘리지 않음

## 첨부 파일

- `app-icon-master.svg` — 1024×1024 마스터 (편집/리사이즈 가능)
- `app-icon-1024.png` — 1024×1024 래스터 (그대로 사용 가능)
