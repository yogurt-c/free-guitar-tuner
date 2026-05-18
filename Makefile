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
	flutter build ios --dart-define-from-file=dart_defines/prod.json
