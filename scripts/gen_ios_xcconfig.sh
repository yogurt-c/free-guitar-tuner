#!/bin/bash
# 사용법: ./scripts/gen_ios_xcconfig.sh dev|prod
ENV=${1:-dev}
JSON_FILE="dart_defines/$ENV.json"

if [ ! -f "$JSON_FILE" ]; then
  echo "Error: $JSON_FILE not found"
  echo "prod 환경: dart_defines/prod.json.example 을 복사 후 실제 ID 입력"
  exit 1
fi

APP_ID=$(python3 -c "import json; d=json.load(open('$JSON_FILE')); print(d['ADMOB_IOS_APP_ID'])")

cat > ios/Flutter/Admob.xcconfig << EOF
// 이 파일은 scripts/gen_ios_xcconfig.sh로 자동 생성됩니다.
// 직접 편집하지 마세요.
ADMOB_IOS_APP_ID = $APP_ID
EOF

echo "ios/Flutter/Admob.xcconfig 생성 완료 ($ENV)"
