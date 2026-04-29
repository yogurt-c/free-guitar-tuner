# 기타 튜너 앱

Android / iOS 멀티플랫폼 기타 튜너 앱.
핵심 기능: 세밀한 튜닝(cents 단위), 다양한 튜닝 프리셋(Drop D 등).

## 세부 문서

- [개발 가이드라인](.claude/docs/guidelines.md)
- [오디오 엔진 스펙](.claude/docs/audio.md)
- [튜닝 프리셋 목록](.claude/docs/tunings.md)
- [프로젝트 구조](.claude/docs/structure.md)

## 구현 단계

### Phase 1 — 프로젝트 셋업
```
chore: 클린 아키텍처 구조로 플러터 프로젝트 초기화
chore: 핵심 의존성 추가 (riverpod, record, audio_session, fftea)
chore: Android/iOS 마이크 권한 설정
```

### Phase 2 — 도메인 레이어
```
feat: Note, Tuning 도메인 모델 정의
feat: 튜닝 프리셋 추가
feat: 주파수 → 음이름 + cents 변환 로직 구현
```

### Phase 3 — 오디오 엔진
```
feat: 마이크 오디오 캡처 스트림 구현
feat: YIN 피치 감지 알고리즘 구현
feat: 오디오 스트림과 피치 감지 연결
```

### Phase 4 — 상태관리
```
feat: Riverpod으로 TunerNotifier 구현 (감지 음, cents, 주파수)
feat: TuningSelectionNotifier 구현 (프리셋 선택, 현 선택)
feat: 현 자동 감지 로직 구현
```

### Phase 5 — 핵심 UI
```
feat: CustomPainter로 아날로그 튜너 미터 구현
feat: 음이름 표시 및 cents 인디케이터 구현
feat: 현 선택 탭바 구현
feat: 메인 튜너 화면 조합
```

### Phase 6 — 튜닝 선택 UI
```
feat: 튜닝 프리셋 선택 바텀시트 구현
feat: 튜닝별 현 구성 상세 뷰 추가
```

### Phase 7 — 완성도
```
feat: 다중 프레임 평균으로 감지 안정화 구현
feat: 튜닝 완료 시 햅틱 피드백 추가
fix: 마이크 권한 거부 상태 처리
chore: 앱 아이콘 및 표시 이름 설정
```
