# 기타 튜너 앱

Android / iOS 멀티플랫폼 기타 튜너 앱.
핵심 기능: 세밀한 튜닝(cents 단위), 다양한 튜닝 프리셋(Drop D 등).

## 빌드 방법

환경변수는 `dart_defines/` 디렉토리로 관리한다. 빌드 전 반드시 올바른 환경을 선택해야 한다.

```bash
# 개발 실행 (테스트 광고 ID 사용)
make dev

# 프로덕션 빌드 (최초 1회 설정 필요)
cp dart_defines/prod.json.example dart_defines/prod.json
# dart_defines/prod.json에 실제 AdMob ID 입력 후:
make build-android   # Android APK
make build-ios       # iOS
```

> `dart_defines/prod.json`과 `ios/Flutter/Admob.xcconfig`는 gitignore 처리되어 있다. 절대 커밋하지 않는다.

## 세부 문서

- [개발 가이드라인](.claude/docs/guidelines.md)
- [오디오 엔진 스펙](.claude/docs/audio.md)
- [튜닝 프리셋 목록](.claude/docs/tunings.md)
- [프로젝트 구조](.claude/docs/structure.md)
- [TODO LIST](.claude/docs/todo.md)
