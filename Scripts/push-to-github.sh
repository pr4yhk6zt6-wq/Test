#!/usr/bin/env bash
#
# อัปโปรเจกต์ขึ้น GitHub ในคำสั่งเดียว (แล้ว GitHub Actions จะ build .ipa ให้อัตโนมัติ)
#
#   bash Scripts/push-to-github.sh https://github.com/<ชื่อผู้ใช้>/<ชื่อ-repo>.git
#
# ก่อนใช้: สร้าง repo เปล่า (ไม่ต้องติ๊ก README) บน github.com ก่อน แล้วคัดลอก URL มา
#
set -euo pipefail

if [ $# -lt 1 ]; then
  echo "วิธีใช้: bash Scripts/push-to-github.sh <repo-url>"
  echo "ตัวอย่าง: bash Scripts/push-to-github.sh https://github.com/somchai/ios-agent-sandbox.git"
  exit 1
fi

REMOTE="$1"
cd "$(dirname "$0")/.."

if ! command -v git >/dev/null 2>&1; then
  echo "❌ ไม่พบ git — ติดตั้ง git ก่อน (บน macOS: xcode-select --install)"
  exit 1
fi

if [ ! -d .git ]; then
  echo "→ เริ่ม git repository ใหม่"
  git init -q
  git branch -M main 2>/dev/null || git checkout -q -b main
fi

echo "→ เพิ่มไฟล์ทั้งหมด"
git add -A

if git diff --cached --quiet; then
  echo "→ ไม่มีการเปลี่ยนแปลงที่ต้อง commit"
else
  git -c user.email="agent@local" -c user.name="iOS Agent Sandbox" \
      commit -q -m "Phase 3: root ผ่าน persona + FileSystemService + entitlements (unit 141 / E2E 92 ผ่านในแซนด์บล็อก)"
  echo "→ commit แล้ว"
fi

if git remote get-url origin >/dev/null 2>&1; then
  git remote set-url origin "$REMOTE"
else
  git remote add origin "$REMOTE"
fi

echo "→ กำลัง push ขึ้น $REMOTE (อาจขอรหัสผ่าน/Personal Access Token)"
git push -u origin main

echo ""
echo "✓ push สำเร็จ — GitHub Actions จะเริ่ม build ภายในไม่กี่วินาที"
echo "  ไปดูสถานะ: ${REMOTE%.git}/actions"
echo "  รอ ~5-10 นาที แล้วดาวน์โหลด .ipa ได้ที่: ${REMOTE%.git}/releases/download/latest-build/iOSAgentSandbox.ipa"
