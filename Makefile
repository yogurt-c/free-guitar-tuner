.PHONY: dev build-android build-aab build-ios

dev:
	./scripts/gen_ios_xcconfig.sh dev
	flutter run --dart-define-from-file=dart_defines/dev.json

build-android:
	flutter build apk --dart-define-from-file=dart_defines/prod.json

build-aab:
	flutter build appbundle --dart-define-from-file=dart_defines/prod.json

build-ios:
	./scripts/gen_ios_xcconfig.sh prod
	flutter build ios --release --dart-define-from-file=dart_defines/prod.json
	@echo ""
	@echo "✅ iOS 빌드 완료. 지금 바로 Xcode에서 Product > Archive 진행."
	@echo "⚠️  Archive 전에 'make dev' 를 실행하면 dart-define이 초기화되므로 주의."
