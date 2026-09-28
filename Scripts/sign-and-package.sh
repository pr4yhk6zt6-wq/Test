#!/usr/bin/env bash
#
# เซ็นไบนารีด้วย ldid (entitlements สำหรับ no-sandbox) แล้วแพ็คเป็น .ipa
#
#   bash Scripts/sign-and-package.sh [path/ไปยัง/.app] [path/entitlements] [โฟลเดอร์ผลลัพธ์]
#
# ค่าเริ่มต้น:
#   .app        = build/Build/Products/Release-iphoneos/iOSAgentSandbox.app
#   entitlements= Entitlements/iOSAgentSandbox.entitlements
#   out         = build-artifacts
#
set -euo pipefail

APP_PATH="${1:-build/Build/Products/Release-iphoneos/iOSAgentSandbox.app}"
ENTITLEMENTS="${2:-Entitlements/iOSAgentSandbox.entitlements}"
OUT_DIR="${3:-build-artifacts}"

if [ ! -d "$APP_PATH" ]; then
  echo "❌ ไม่พบ .app ที่ $APP_PATH"
  exit 1
fi

if [ ! -f "$ENTITLEMENTS" ]; then
  echo "❌ ไม่พบไฟล์ entitlements ที่ $ENTITLEMENTS"
  exit 1
fi

APP_NAME="$(basename "$APP_PATH")"
BINARY_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP_PATH/Info.plist")"
BINARY_PATH="$APP_PATH/$BINARY_NAME"

if [ ! -f "$BINARY_PATH" ]; then
  echo "❌ ไม่พบไบนารีที่ $BINARY_PATH"
  exit 1
fi

echo "== เซ็นด้วย entitlements: $ENTITLEMENTS =="
plutil -lint "$ENTITLEMENTS"

if command -v ldid >/dev/null 2>&1; then
  echo "→ ใช้ ldid"
  ldid -S"$ENTITLEMENTS" "$BINARY_PATH"

  # เซ็นไฟล์ไบนารีอื่นใน .app (dylib/framework/ปลั๊กอิน) ถ้ามี
  while IFS= read -r extra; do
    [ -z "$extra" ] && continue
    [ "$extra" = "$BINARY_PATH" ] && continue
    echo "→ ldid: $(basename "$extra")"
    ldid -S"$ENTITLEMENTS" "$extra" || echo "  (ข้าม: เซ็นไม่สำเร็จ)"
  done < <(find "$APP_PATH" -type f \( -name '*.dylib' -o -name '*.so' \) 2>/dev/null)

  echo "== ตรวจว่า entitlements ถูกฝังในไบนารี =="
  if ldid -e "$BINARY_PATH" | grep -q "platform-application"; then
    echo "✓ พบ platform-application ใน entitlements ที่ฝังอยู่"
  else
    echo "⚠️ ไม่พบ platform-application — ตรวจสอบไฟล์ entitlements อีกครั้ง"
  fi
  ldid -e "$BINARY_PATH" > /tmp/ldid-entitlements-embedded.plist 2>/dev/null || true
else
  echo "→ ไม่พบ ldid ใช้ codesign แบบ ad-hoc แทน"
  codesign --force --sign - --entitlements "$ENTITLEMENTS" --timestamp=none "$BINARY_PATH"
  codesign -d --entitlements - "$BINARY_PATH" || true
fi

echo "== แพ็คเป็น .ipa =="
rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR/Payload"
cp -R "$APP_PATH" "$OUT_DIR/Payload/"
APP_SIZE="$(du -sh "$OUT_DIR/Payload/$APP_NAME" | cut -f1)"

IPA_PATH="$OUT_DIR/iOSAgentSandbox.ipa"
(cd "$OUT_DIR" && zip -qry "$(basename "$IPA_PATH")" Payload)

echo ""
echo "✓ สร้างไฟล์: $IPA_PATH"
echo "  ขนาด .app : $APP_SIZE"
echo "  ขนาด .ipa : $(du -h "$IPA_PATH" | cut -f1)"
echo "  sha256    : $(shasum -a 256 "$IPA_PATH" | cut -d' ' -f1)"
echo ""
echo "ติดตั้งด้วย TrollStore (เปิด .ipa) หรือ Sideloadly (ต้องเซ็นด้วย Apple ID อีกครั้ง แต่จะสูญเสีย entitlements สิทธิ์สูง)"
