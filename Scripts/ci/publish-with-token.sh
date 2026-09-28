#!/usr/bin/env bash
#
# publish-with-token.sh — push โปรเจกต์ขึ้น GitHub ด้วย Personal Access Token
# แล้วเฝ้าดู GitHub Actions จนจบ และดึงไฟล์ .ipa กลับมาไว้ในเครื่อง
#
#   GITHUB_TOKEN=xxx bash Scripts/ci/publish-with-token.sh <repo-url>           # push + เฝ้า + ดึงไฟล์
#   GITHUB_TOKEN=xxx bash Scripts/ci/publish-with-token.sh --watch <repo-url>   # เฝ้าอย่างเดียว (ไม่ push)
#   GITHUB_TOKEN=xxx bash Scripts/ci/publish-with-token.sh --status <repo-url>  # ดูสถานะรอบล่าสุดแล้วออก
#
# ข้อควรระวังด้านความปลอดภัย:
#   • โทเคนถูกรับผ่าน "ตัวแปรสภาพแวดล้อม" เท่านั้น ไม่ถูกเขียนลงไฟล์ ไม่ถูกพิมพ์ออกจอ
#   • สคริปต์ไม่บันทึกโทเคนลง .git/config (push ด้วย URL ชั่วคราวที่อยู่ในหน่วยความจำ)
#   • ใช้โทเคนอายุสั้น (1–7 วัน) และเพิกถอนทันทีหลังใช้เสร็จ
#
set -uo pipefail

MODE="push"
if [ "${1:-}" = "--watch" ]; then MODE="watch"; shift; fi
if [ "${1:-}" = "--status" ]; then MODE="status"; shift; fi

REPO_URL="${1:-}"
TOKEN="${GITHUB_TOKEN:-}"
OUTPUT_IPA="${OUTPUT_IPA:-/home/user/iOSAgentSandbox.ipa}"

fail() { echo "❌ $*" >&2; exit 1; }
info() { echo "→ $*"; }

[ -n "$REPO_URL" ] || fail "ต้องระบุ repo URL เช่น https://github.com/user/ios-agent-sandbox.git"
[ -n "$TOKEN" ] || fail "ต้องตั้งค่า GITHUB_TOKEN ก่อน"

case "$REPO_URL" in
  https://github.com/*/*|https://github.com/*/*.git|git@github.com:*/*|git@github.com:*/*.git) ;;
  *) fail "รูปแบบ repo URL ไม่ถูกต้อง: $REPO_URL (ต้องเป็น https://github.com/<ผู้ใช้>/<repo>.git)" ;;
esac

# ---- แปลง URL เป็น owner/repo ----
CLEAN_URL="${REPO_URL%.git}"
CLEAN_URL="${CLEAN_URL#https://github.com/}"
CLEAN_URL="${CLEAN_URL#git@github.com:}"
OWNER="${CLEAN_URL%%/*}"
REPO="${CLEAN_URL#*/}"
[ -n "$OWNER" ] && [ -n "$REPO" ] || fail "อ่าน owner/repo จาก URL ไม่ได้: $REPO_URL"
API="https://api.github.com/repos/$OWNER/$REPO"

api() { # api METHOD PATH [DATA]
  local method="$1" path="$2" data="${3:-}"
  if [ -n "$data" ]; then
    curl -sS -X "$method" -H "Authorization: Bearer $TOKEN" \
      -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28" \
      -d "$data" "$API$path"
  else
    curl -sS -X "$method" -H "Authorization: Bearer $TOKEN" \
      -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28" "$API$path"
  fi
}

json_get() { # อ่านค่าจาก JSON ด้วย python3 (ไม่ต้องมี jq)
  python3 -c "
import json,sys
try:
    data = json.load(sys.stdin)
except Exception:
    print(''); sys.exit(0)
path = '$1'.split('.')
value = data
for key in path:
    if isinstance(value, list):
        value = value[int(key)] if key.isdigit() and int(key) < len(value) else None
    elif isinstance(value, dict):
        value = value.get(key)
    else:
        value = None
    if value is None: break
print('' if value is None else value)
"
}

# ---- 0) ตรวจโทเคน ----
info "ตรวจสอบโทเคน…"
WHO="$(curl -sS -H "Authorization: Bearer $TOKEN" https://api.github.com/user | json_get login)"
if [ -z "$WHO" ]; then
  fail "โทเคนไม่ถูกต้องหรือหมดอายุ (ตรวจที่ https://github.com/settings/tokens)"
fi
echo "   เข้าสู่ระบบในชื่อ: $WHO"

REPO_JSON="$(api GET "")"
REPO_NAME="$(printf '%s' "$REPO_JSON" | json_get full_name)"
if [ -z "$REPO_NAME" ]; then
  MESSAGE="$(printf '%s' "$REPO_JSON" | json_get message)"
  fail "เข้าถึง $OWNER/$REPO ไม่ได้: ${MESSAGE:-ไม่ทราบสาเหตุ} (ตรวจว่า repo มีอยู่จริง และโทเคนมีสิทธิ์ใน repo นี้)"
fi
VISIBILITY="$(printf '%s' "$REPO_JSON" | json_get visibility)"
echo "   พบ repo: $REPO_NAME ($VISIBILITY)"
if [ "$VISIBILITY" != "public" ]; then
  echo "   ! repo เป็น private → ลิงก์ดาวน์โหลด .ipa จาก Releases จะต้องล็อกอิน GitHub"
fi

# ---- 1) push (ยกเว้นโหมด watch/status) ----
if [ "$MODE" = "push" ]; then
  cd "$(dirname "$0")/../.." || fail "เข้าโฟลเดอร์โปรเจกต์ไม่ได้"
  [ -f project.yml ] || fail "ไม่พบ project.yml — รันสคริปต์จากในโฟลเดอร์โปรเจกต์"

  if [ ! -d .git ]; then
    info "เริ่ม git repository"
    git init -q
    git branch -M main 2>/dev/null || git checkout -q -b main
  fi

  info "เตรียมไฟล์ (ตัดไฟล์ที่สร้างชั่วคราวออก)"
  rm -rf verification/Sources/OpenRouterCore verification/.build build build-artifacts .build 2>/dev/null || true
  git add -A

  if git diff --cached --quiet; then
    info "ไม่มีการเปลี่ยนแปลง — ใช้ commit เดิม"
  else
    git -c user.email="agent@local" -c user.name="Arena Agent" \
        commit -q -m "iOS Agent Sandbox: เฟส 4 (ถามอนุมัติทุกครั้ง + แก้สปินเนอร์ค้าง + FileBrowserView/FilePreviewView/AgentLogView + log การใช้ tool)"
    info "commit แล้ว: $(git rev-parse --short HEAD)"
  fi

  git remote remove origin 2>/dev/null || true
  git remote add origin "https://github.com/$OWNER/$REPO.git"

  info "push ขึ้น $OWNER/$REPO …"
  PUSH_URL="https://x-access-token:$TOKEN@github.com/$OWNER/$REPO.git"

  # พยายาม push ปกติก่อน ถ้าปลายทางมีประวัติอยู่ก่อน (แม้ไฟล์จะถูกลบจนว่าง)
  # ให้วางคอมมิตของเราไว้ "บนยอด" ของ main ปลายทาง — ไม่ต้อง force push และไม่ทำประวัติเดิมหาย
  if ! git push "$PUSH_URL" main 2>/tmp/push-error.log; then
    if grep -qiE "rejected|fetch first|non-fast-forward|behind" /tmp/push-error.log; then
      info "ปลายทางมีประวัติ commit อยู่ก่อน — ต่อคอมมิตของเราบนยอด main เดิม"
      if ! git fetch "$PUSH_URL" main >/dev/null 2>&1; then
        tail -20 /tmp/push-error.log
        fail "ดึงประวัติจากปลายทางไม่สำเร็จ"
      fi
      git reset --soft FETCH_HEAD
      if ! git diff --cached --quiet; then
        git -c user.email="agent@local" -c user.name="Arena Agent" \
            commit -q -m "iOS Agent Sandbox: เฟส 4 (ถามอนุมัติทุกครั้ง + แก้สปินเนอร์ค้าง + FileBrowserView/FilePreviewView/AgentLogView + log การใช้ tool)"
      fi
      if ! git push "$PUSH_URL" main 2>>/tmp/push-error.log; then
        echo "---- รายละเอียด error ----"; tail -20 /tmp/push-error.log
        fail "push ไม่สำเร็จ (ตรวจสิทธิ์ Contents/Workflows ของโทเคน)"
      fi
    else
      echo "---- รายละเอียด error ----"; tail -20 /tmp/push-error.log
      if grep -qiE "workflow" /tmp/push-error.log; then
        fail "โทเคนไม่มีสิทธิ์อัปเดตไฟล์ workflow — ต้องมี scope 'workflow' (classic) หรือ 'Workflows: Read and write' (fine-grained)"
      fi
      fail "push ไม่สำเร็จ (มักเกิดจากโทเคนไม่มีสิทธิ์ Contents)"
    fi
  fi
  HEAD_SHA="$(git rev-parse HEAD)"
  echo "   ✓ push สำเร็จ: ${HEAD_SHA:0:7}"
else
  HEAD_SHA=""
fi

# ---- 2) เฝ้าดู run ล่าสุด ----
info "รอ GitHub Actions เริ่มทำงาน…"
RUN_ID=""
RUN_STATUS=""
RUN_CONCLUSION=""
for attempt in $(seq 1 60); do
  RUNS_JSON="$(api GET "/actions/runs?per_page=5")"
  RUN_ID="$(printf '%s' "$RUNS_JSON" | python3 -c "
import json,sys
try: runs = json.load(sys.stdin).get('workflow_runs', [])
except Exception: runs = []
sha = '${HEAD_SHA}'
if sha:
    # โหมด push: ต้องเป็น run ของคอมมิตเราเท่านั้น (กันสับสนกับ run เก่าในเรพ)
    pick = next((r for r in runs if r.get('head_sha','').startswith(sha[:7])), None)
else:
    pick = runs[0] if runs else None
print(pick['id'] if pick else '')
")"
  if [ -n "$RUN_ID" ]; then
    echo "   (run ตรงกับคอมมิตที่ push: ${HEAD_SHA:0:7})"
    break
  fi
  sleep 5
done
[ -n "$RUN_ID" ] || fail "ไม่พบ workflow run (ตรวจว่าไฟล์ .github/workflows/build.yml ถูก push แล้วจริง)"

echo "   run id: $RUN_ID"

for attempt in $(seq 1 180); do   # ~30 นาที (10 วินาที/รอบ)
  RUN_JSON="$(api GET "/actions/runs/$RUN_ID")"
  RUN_STATUS="$(printf '%s' "$RUN_JSON" | json_get status)"
  RUN_CONCLUSION="$(printf '%s' "$RUN_JSON" | json_get conclusion)"
  if [ "$RUN_STATUS" = "completed" ]; then break; fi
  sleep 10
  if [ $((attempt % 6)) -eq 0 ]; then
    echo "   … กำลังทำงาน (สถานะ: ${RUN_STATUS:-queued})"
  fi
done

if [ "$RUN_STATUS" != "completed" ]; then
  fail "รอเกิน 30 นาที — ไปดูที่ https://github.com/$OWNER/$REPO/actions"
fi

echo ""
if [ "$RUN_CONCLUSION" != "success" ]; then
  echo "❌ build ไม่ผ่าน (conclusion: $RUN_CONCLUSION)"
  echo "---- ขั้นตอนที่ไม่ผ่าน ----"
  api GET "/actions/runs/$RUN_ID/jobs" | python3 -c "
import json,sys
try: jobs = json.load(sys.stdin).get('jobs', [])
except Exception: jobs = []
for job in jobs:
    for step in job.get('steps', []):
        if step.get('conclusion') not in (None, 'success', 'skipped'):
            print(f\"  ✗ {step['name']} → {step['conclusion']}\")
"
  echo ""
  echo "ลิงก์: https://github.com/$OWNER/$REPO/actions/runs/$RUN_ID"
  exit 1
fi

echo "✅ build สำเร็จ (conclusion: success)"
if [ "$MODE" = "status" ]; then exit 0; fi

# ---- 3) ดึงไฟล์ .ipa ----
info "ดาวน์โหลด .ipa จาก Releases…"
IPA_URL="https://github.com/$OWNER/$REPO/releases/download/latest-build/iOSAgentSandbox.ipa"
if [ "$VISIBILITY" != "public" ]; then
  curl -sSL -H "Authorization: Bearer $TOKEN" -o "$OUTPUT_IPA" "$IPA_URL" || fail "ดาวน์โหลด .ipa ไม่สำเร็จ"
else
  curl -sSL -o "$OUTPUT_IPA" "$IPA_URL" || fail "ดาวน์โหลด .ipa ไม่สำเร็จ"
fi

if ! unzip -l "$OUTPUT_IPA" >/dev/null 2>&1; then
  head -c 300 "$OUTPUT_IPA"; echo ""
  fail "ไฟล์ที่ได้ไม่ใช่ .ipa (อาจเป็นหน้า HTML ของ error)"
fi

SIZE="$(du -h "$OUTPUT_IPA" | cut -f1)"
SHA="$(python3 - <<'PY'
import hashlib, sys, os
path = os.environ.get("OUTPUT_IPA", "")
h = hashlib.sha256()
with open(path, "rb") as fh:
    for chunk in iter(lambda: fh.read(1 << 20), b""):
        h.update(chunk)
print(h.hexdigest())
PY
)"
APP_BINARY="$(unzip -l "$OUTPUT_IPA" | grep -E "Payload/.*/iOSAgentSandbox$" | awk '{print $4}' | head -1)"

echo ""
echo "=================== ผลลัพธ์ ==================="
echo "ไฟล์      : $OUTPUT_IPA"
echo "ขนาด      : $SIZE"
echo "sha256    : $SHA"
echo "ไบนารี    : ${APP_BINARY:-ไม่พบ (ตรวจสอบไฟล์)}"
echo "ติดตั้ง    : ส่งไฟล์นี้เข้า iPhone (AirDrop/อีเมล) แล้วเปิดด้วย TrollStore"
echo "=============================================="
