#!/usr/bin/env bash
#
# ทดสอบ end-to-end ของชั้น OpenRouter: ไคลเอนต์จริง (ไฟล์ของแอป) ↔ เซิร์ฟเวอร์จำลอง
#
#   bash verification/e2e/run-e2e.sh
#
# สิ่งที่พิสูจน์ด้วยการรันจริง:
#   • URLSession.bytes(for:) อ่าน SSE ทีละไบต์ และประกอบบรรทัดข้าม TCP packet ได้
#   • ข้าม comment keep-alive (": OPENROUTER PROCESSING") และบรรทัด JSON ที่พังได้
#   • รวม tool_calls delta ที่ถูกหั่นกลาง JSON เป็น 4 chunk → ได้ arguments ที่ parse ได้
#   • อ่าน usage (prompt/completion/total/cost/cached) จาก chunk สุดท้ายก่อน [DONE]
#   • 429 → retry ด้วย backoff แล้วสำเร็จ (ยิง 2 ครั้ง) ; 503 → ลองใหม่ครบ 3 ครั้งแล้วหยุด
#   • 404/401 → ไม่ retry (ยิงครั้งเดียว) พร้อมข้อความที่ถูกต้อง
#   • GET /models กรองรายการที่เสียออกโดยไม่ทำให้ทั้งลิสต์พัง
#
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$HERE/../.." && pwd)"
# shellcheck source=../hash.sh
source "$HERE/../hash.sh"
WORK="/tmp/e2e-build"
PORT="${E2E_PORT:-8123}"

if ! command -v swift >/dev/null 2>&1; then
  if [ -x "$HOME/.local/swift/usr/bin/swift" ]; then
    export PATH="$HOME/.local/swift/usr/bin:$PATH"
  else
    echo "❌ ไม่พบ swift"
    exit 1
  fi
fi

rm -rf "$WORK"
mkdir -p "$WORK"
cd "$WORK"

echo "== คัดลอกไฟล์ต้นฉบับของแอป (พร้อมตรวจ sha256) =="
FILES=(
  "Models/JSONValue.swift"
  "Models/ChatModels.swift"
  "Models/OpenRouterModels.swift"
  "Services/OpenRouterCore.swift"
  "Services/OpenRouterService.swift"
)
for rel in "${FILES[@]}"; do
  cp "$PROJECT_ROOT/$rel" "$WORK/$(basename "$rel")"
  a="$(hash_file "$PROJECT_ROOT/$rel")"
  b="$(hash_file "$WORK/$(basename "$rel")")"
  [ "$a" = "$b" ] || { echo "❌ $(basename "$rel") ไม่ตรงกับต้นฉบับ"; exit 1; }
  echo "  ✓ $(basename "$rel")  ${a:0:12}…"
done

echo "== เริ่มเซิร์ฟเวอร์จำลอง OpenRouter (พอร์ต $PORT) =="
python3 "$HERE/mock_openrouter_server.py" "$PORT" > "$WORK/server.log" 2>&1 &
SERVER_PID=$!
cleanup() {
  kill "$SERVER_PID" 2>/dev/null || true
  wait "$SERVER_PID" 2>/dev/null || true
}
trap cleanup EXIT

for ((attempt = 0; attempt < 50; attempt++)); do
  if grep -q "listening" "$WORK/server.log" 2>/dev/null; then break; fi
  sleep 0.1
done
grep -q "listening" "$WORK/server.log" || { echo "❌ เซิร์ฟเวอร์จำลองไม่เริ่มทำงาน"; cat "$WORK/server.log"; exit 1; }
echo "  ✓ เซิร์ฟเวอร์พร้อม"

echo "== คอมไพล์ไคลเอนต์ทดสอบ (ใช้ไฟล์จริงของแอป) =="
cp "$HERE/main.swift" "$WORK/main.swift"
# shim เฉพาะ Linux: เติม URLSession.bytes(for:) ที่ corelibs-foundation ยังไม่มี (บน macOS จะกลายเป็นไฟล์ว่าง)
cp "$HERE/LinuxAsyncBytesShim.swift" "$WORK/LinuxAsyncBytesShim.swift"
swiftc -O -o "$WORK/e2e-harness" "$WORK"/*.swift 2>&1 | head -40

echo "== รันการทดสอบ =="
set +e
"$WORK/e2e-harness" "$PORT" | tee "$WORK/harness.log"
STATUS=${PIPESTATUS[0]}
set -e

echo ""
if [ "$STATUS" -eq 0 ] && grep -q "✓ E2E ทั้งหมดผ่าน" "$WORK/harness.log"; then
  echo "✓ E2E ผ่านทั้งหมด (ไฟล์บันทึกผล: $WORK/harness.log)"
  exit 0
fi

echo "❌ E2E ไม่ผ่าน — ดูรายละเอียดด้านบน"
exit 1
