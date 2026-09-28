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
#   • เฟส 2: ReAct loop จริง 2 รอบ (อ่านไฟล์จริง → ส่งผลกลับ → ได้คำตอบสุดท้าย)
#   • เฟส 2: โหมดอนุมัติ (อนุญาต → shell ทำงานจริง / ไม่อนุญาต → ไม่รันและแจ้งโมเดล)
#   • เฟส 2: เพดาน 20 รอบ และการยกเลิกงานกลางทาง
#
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$HERE/../.." && pwd)"
WORK="${E2E_WORK_DIR:-/tmp/e2e-build}"
# shellcheck source=../hash.sh
source "$HERE/../hash.sh"

# ---- หา swift ----
if ! command -v swift >/dev/null 2>&1; then
  if [ -x "$HOME/.local/swift/usr/bin/swift" ]; then
    export PATH="$HOME/.local/swift/usr/bin:$PATH"
  else
    echo "❌ ไม่พบ swift (บน macOS: ติดตั้ง Xcode / บน Linux: ใช้ toolchain ที่สคริปต์ติดตั้งให้)"
    exit 1
  fi
fi

# ---- หา python เพื่อรันเซิร์ฟเวอร์จำลอง (ชื่อคำสั่งและตำแหน่งต่างกันในแต่ละเครื่อง) ----
PY_BIN="${PYTHON_BIN:-}"
if [ -z "$PY_BIN" ]; then
  for candidate in python3 python /opt/homebrew/bin/python3 /usr/local/bin/python3 /usr/bin/python3; do
    if command -v "$candidate" >/dev/null 2>&1 && "$candidate" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 7) else 1)' >/dev/null 2>&1; then
      PY_BIN="$candidate"
      break
    fi
  done
fi
if [ -z "$PY_BIN" ]; then
  echo "❌ ไม่พบ python3 (>= 3.7) สำหรับรันเซิร์ฟเวอร์จำลอง"
  echo "   บน macOS: brew install python3   |   หรือตั้งค่า PYTHON_BIN=/path/to/python3"
  exit 1
fi
echo "== ใช้ python: $PY_BIN ($("$PY_BIN" --version 2>&1)) =="

# ---- เลือกพอร์ตว่าง (กันพอร์ตชนกันบน runner) ----
PORT=""
for candidate in "${E2E_PORT:-8123}" 18123 28123 38123 48123 58123; do
  if "$PY_BIN" - "$candidate" <<'PY' >/dev/null 2>&1
import socket, sys
port = int(sys.argv[1])
probe = socket.socket()
try:
    probe.bind(("127.0.0.1", port))
except OSError:
    sys.exit(1)
finally:
    probe.close()
PY
  then
    PORT="$candidate"
    break
  fi
done
[ -n "$PORT" ] || { echo "❌ ไม่พบพอร์ตว่างสำหรับเซิร์ฟเวอร์จำลอง"; exit 1; }

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
  # เฟส 2 — engine + tools ทั้งชุด (รันจริงบนเครื่องผู้ทดสอบ: อ่าน/เขียนไฟล์, shell, เครือข่าย)
  "Services/ShellService.swift"
  "Services/AgentEngine.swift"
  "Services/Tools/ToolCore.swift"
  "Services/Tools/ToolArguments.swift"
  "Services/Tools/PathGuard.swift"
  "Services/Tools/RiskyCommandDetector.swift"
  "Services/Tools/ToolOutputLimiter.swift"
  "Services/Tools/GlobMatcher.swift"
  "Services/Tools/HTMLTextExtractor.swift"
  "Services/Tools/NetworkPolicy.swift"
  "Services/Tools/ContextTrimmer.swift"
  "Services/Tools/FileTools.swift"
  "Services/Tools/ShellTool.swift"
  "Services/Tools/HttpTools.swift"
  "Services/Tools/ToolRegistry.swift"
)
for rel in "${FILES[@]}"; do
  cp "$PROJECT_ROOT/$rel" "$WORK/$(basename "$rel")"
  a="$(hash_file "$PROJECT_ROOT/$rel")"
  b="$(hash_file "$WORK/$(basename "$rel")")"
  [ "$a" = "$b" ] || { echo "❌ $(basename "$rel") ไม่ตรงกับต้นฉบับ"; exit 1; }
  echo "  ✓ $(basename "$rel")  ${a:0:12}…"
done

echo "== เริ่มเซิร์ฟเวอร์จำลอง OpenRouter (พอร์ต $PORT) =="
"$PY_BIN" -u "$HERE/mock_openrouter_server.py" "$PORT" > "$WORK/server.log" 2>&1 &
SERVER_PID=$!
cleanup() {
  kill "$SERVER_PID" 2>/dev/null || true
  wait "$SERVER_PID" 2>/dev/null || true
}
trap cleanup EXIT

SERVER_READY=0
for ((attempt = 0; attempt < 100; attempt++)); do
  if ! kill -0 "$SERVER_PID" 2>/dev/null; then
    break   # เซิร์ฟเวอร์ออกไปแล้ว — ออก loop ไปรายงาน error
  fi
  if grep -q "listening" "$WORK/server.log" 2>/dev/null; then
    SERVER_READY=1
    break
  fi
  sleep 0.1
done

if [ "$SERVER_READY" -ne 1 ]; then
  echo "❌ เซิร์ฟเวอร์จำลองไม่เริ่มทำงาน — ข้อมูลวินิจฉัย:"
  echo "   python : $PY_BIN ($("$PY_BIN" --version 2>&1))"
  echo "   พอร์ต  : $PORT"
  echo "   สถานะ  : $(kill -0 "$SERVER_PID" 2>/dev/null && echo 'โปรเซสยังอยู่แต่ไม่ตอบ' || echo 'โปรเซสออกไปแล้ว')"
  echo "   --- server.log ---"
  cat "$WORK/server.log" 2>/dev/null || echo "   (ไม่มีไฟล์ log)"
  echo "   ------------------"
  exit 1
fi
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
