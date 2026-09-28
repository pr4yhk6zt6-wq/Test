#!/usr/bin/env bash
#
# คัดลอกไฟล์ต้นฉบับของโปรเจกต์เข้ามาในแพ็กเกจนี้ (ตรวจ sha256 ว่าตรงกัน 100%)
# แล้วรัน unit test ของแกนกลางเฟส 1
#
#   bash verification/run-verification.sh
#
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$HERE/.." && pwd)"
# shellcheck source=hash.sh
source "$HERE/hash.sh"
cd "$HERE"

# หา swift: ใช้จาก PATH ก่อน ถ้าไม่มีให้ใช้ toolchain ที่ติดตั้งไว้ในเครื่องนี้
if ! command -v swift >/dev/null 2>&1; then
  if [ -x "$HOME/.local/swift/usr/bin/swift" ]; then
    export PATH="$HOME/.local/swift/usr/bin:$PATH"
  else
    echo "❌ ไม่พบ swift — ติดตั้ง toolchain ก่อน (บน macOS: ติดตั้ง Xcode)"
    exit 1
  fi
fi

ORIGINALS=(
  "Models/JSONValue.swift"
  "Models/ChatModels.swift"
  "Models/OpenRouterModels.swift"
  "Services/OpenRouterCore.swift"
  # เฟส 2 — แกนกลางของ tools ที่ทดสอบได้โดยไม่ต้องมี iOS SDK
  "Services/Tools/ToolCore.swift"
  "Services/Tools/ToolArguments.swift"
  "Services/Tools/PathGuard.swift"
  "Services/Tools/RiskyCommandDetector.swift"
  "Services/Tools/ToolOutputLimiter.swift"
  "Services/Tools/GlobMatcher.swift"
  "Services/Tools/HTMLTextExtractor.swift"
  "Services/Tools/NetworkPolicy.swift"
  "Services/Tools/ContextTrimmer.swift"
  # เฟส 3 — สิทธิ์ระดับระบบ (ไม่มี UIKit จึงทดสอบได้ทุกแพลตฟอร์ม)
  "Services/Tools/PrivilegePolicy.swift"
  "Services/FileSystemService.swift"
  "Services/EntitlementProbe.swift"
  "Services/ShellService.swift"
  "Services/PrivilegeService.swift"
  # ShellTool ต้องทดสอบว่าผลลัพธ์รายงาน "รันในนามใคร" (เฟส 3)
  "Services/Tools/ShellTool.swift"
  # เฟส 4 — การจัดการคีย์ (ต้นเหตุบั๊ก 401 ที่ผู้ใช้เจอบนเครื่อง)
  "Services/APIKeySanitizer.swift"
  # เฟส 5 — ไฟล์แนบ หลายห้องสนทนา และการส่งออก (Foundation ล้วน)
  "Models/Attachment.swift"
  "Services/AttachmentStore.swift"
  "Services/AttachmentMessageBuilder.swift"
  "Services/VisionSupport.swift"
  "Services/ChatRoomStore.swift"
)

echo "== คัดลอกไฟล์ต้นฉบับที่ต้องทดสอบ =="
mkdir -p Sources/OpenRouterCore
for rel in "${ORIGINALS[@]}"; do
  base="$(basename "$rel")"
  cp "$PROJECT_ROOT/$rel" "Sources/OpenRouterCore/$base"
  echo "  • $rel"
done

echo "== ตรวจว่าไฟล์ที่ทดสอบตรงกับต้นฉบับ 100% (sha256) =="
for rel in "${ORIGINALS[@]}"; do
  base="$(basename "$rel")"
  a="$(hash_file "$PROJECT_ROOT/$rel")"
  b="$(hash_file "Sources/OpenRouterCore/$base")"
  if [ "$a" != "$b" ]; then
    echo "❌ $base ไม่ตรงกับต้นฉบับ — หยุดเพื่อไม่ให้ทดสอบโค้ดคนละชุด"
    exit 1
  fi
  echo "  ✓ $base  ${a:0:16}…"
done

echo ""
echo "== รัน swift test (Swift $(swift --version 2>/dev/null | head -1 | sed 's/.*version //;s/ .*//')) =="
swift test --scratch-path /tmp/swiftpm-build 2>&1 | tee /tmp/swift-test-output.log | grep -E "Executed|passed|failed \\(|error:" | tail -n 25

echo ""
if grep -qE "[0-9]+ tests?, with 0 failures" /tmp/swift-test-output.log; then
  TOTAL="$(grep -oE "Executed [0-9]+ tests" /tmp/swift-test-output.log | tail -1 | grep -oE "[0-9]+")"
  echo "✓ รันทดสอบแกนกลาง (เฟส 1 + 2 + 3) ผ่านทั้งหมด ${TOTAL:-?} เคส"
else
  echo "⚠️ มีเคสที่ไม่ผ่าน:"
  grep -E "error:" /tmp/swift-test-output.log | sed 's/^/   /' | head -20
  exit 1
fi
