#!/usr/bin/env bash
#
# สคริปต์สำหรับ build บนเครื่อง Mac ของผู้ใช้เอง (xcodebuild + xcodegen)
#
#   bash Scripts/build-local.sh
#
set -euo pipefail

cd "$(dirname "$0")/.."

echo "== ตรวจ API ของ iOS 16+ =="
bash Scripts/check-ios15-compat.sh .

echo "== ตรวจว่ามี XcodeGen =="
if ! command -v xcodegen >/dev/null 2>&1; then
  echo "ไม่พบ xcodegen — ติดตั้งด้วย: brew install xcodegen"
  exit 1
fi

echo "== สร้าง iOSAgentSandbox.xcodeproj =="
xcodegen generate

echo "== Build แบบไม่ลงนาม (CODE_SIGNING_ALLOWED=NO) =="
xcodebuild \
  -project iOSAgentSandbox.xcodeproj \
  -scheme iOSAgentSandbox \
  -configuration Release \
  -sdk iphoneos \
  -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  IPHONEOS_DEPLOYMENT_TARGET=15.0 \
  build

echo "== ตรวจ deployment target ของผลลัพธ์ =="
/usr/libexec/PlistBuddy -c 'Print :MinimumOSVersion' build/Build/Products/Release-iphoneos/iOSAgentSandbox.app/Info.plist || true

echo "== เซ็นด้วย ldid และแพ็ค IPA =="
bash Scripts/sign-and-package.sh
