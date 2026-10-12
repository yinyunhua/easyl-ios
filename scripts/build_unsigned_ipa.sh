#!/usr/bin/env bash
# 一键产出「未签名 IPA」，用于 Sideloadly / ESign / TrollStore 等工具自签
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="EasylForIOS"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "缺少 XcodeGen，请先执行：brew install xcodegen"
  exit 1
fi

echo "==> 1/4 生成 Xcode 工程"
xcodegen generate

echo "==> 2/4 编译 Release（关闭签名）"
rm -rf build Payload "${APP_NAME}-unsigned.ipa"
xcodebuild \
  -project "${APP_NAME}.xcodeproj" \
  -scheme "${APP_NAME}" \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  build

echo "==> 3/4 组装 Payload"
mkdir -p Payload
cp -R "build/Build/Products/Release-iphoneos/${APP_NAME}.app" "Payload/${APP_NAME}.app"

echo "==> 4/4 压缩为 IPA"
cd Payload
zip -qry "../${APP_NAME}-unsigned.ipa" "${APP_NAME}.app"
cd ..
rm -rf Payload

echo "完成：$(pwd)/${APP_NAME}-unsigned.ipa"
