#!/usr/bin/env bash
#
# ตรวจว่าโค้ด Swift ไม่ใช้ API ของ iOS 16 ขึ้นไป (deployment target = iOS 15.0)
# ใช้ทั้งบนเครื่อง Mac และใน GitHub Actions
#
#   bash Scripts/check-ios15-compat.sh [โฟลเดอร์ที่ต้องการสแกน]
#
set -uo pipefail

SCAN_DIR="${1:-.}"
FAILED=0

# รูปแบบ: "regex|คำอธิบาย|API แทนที่"
RULES=(
  'NavigationStack|SwiftUI NavigationStack (iOS 16)|ใช้ NavigationView + NavigationLink'
  'NavigationSplitView|NavigationSplitView (iOS 16)|ใช้ NavigationView'
  'NavigationPath|NavigationPath (iOS 16)|ใช้ Array + NavigationLink'
  'PhotosPicker|PhotosPicker (iOS 16)|ใช้ PHPickerViewController'
  'PhotosPickerItem|PhotosPickerItem (iOS 16)|ใช้ PHPickerViewController'
  'scrollDismissesKeyboard|scrollDismissesKeyboard (iOS 16)|ใช้ ScrollView + onTapGesture ปิดคีย์บอร์ด'
  'presentationDetents|presentationDetents (iOS 16)|ไม่ใช้ bottom sheet แบบกำหนดความสูง'
  'presentationDragIndicator|presentationDragIndicator (iOS 16)|–'
  'toolbarBackground|toolbarBackground (iOS 16)|ใช้ UIColor ของ NavigationView'
  'scrollContentBackground|scrollContentBackground (iOS 16)|ใช้ UITableView.appearance()'
  'containerRelativeFrame|containerRelativeFrame (iOS 17)|ใช้ GeometryReader'
  'sensoryFeedback|sensoryFeedback (iOS 17)|ใช้ UIImpactFeedbackGenerator'
  'onChange\(of:.+initial:|onChange(of:initial:) (iOS 17)|ใช้ onChange(of:)perform: แบบ iOS 15'
  'axis: \.vertical|TextField(axis:) (iOS 16)|ใช้ MultilineInputField (ห่อ UITextView)'
  'lineLimit\([0-9]+\.\.\.|lineLimit(ค่าเริ่มต้น...) (iOS 16)|กำหนดจำนวนบรรทัดคงที่'
  '\.fontWeight\(|View.fontWeight (iOS 16)|ใช้ Font.weight(...)'
  '\.bold\(\)|View.bold() (iOS 16)|ใช้ Font.bold() หรือ .fontWeight บน Font'
  '\.italic\(\)|View.italic() (iOS 16)|ใช้ Font.italic()'
  '^import Charts|Charts framework (iOS 16)|ไม่ใช้กราฟ'
  'Grid \{|SwiftUI Grid (iOS 16)|ใช้ LazyVGrid (iOS 14)'
  'GridRow|GridRow (iOS 16)|ใช้ LazyVGrid (iOS 14)'
  '\.listRowSeparator|listRowSeparator (iOS 15 – ใช้ได้ แต่ต้อง List)|ตรวจสอบว่าใช้ใน List'
  '\.searchScopes|searchScopes (iOS 16)|ไม่ใช้ตัวกรองขอบเขตการค้นหา'
  'ImageRenderer|ImageRenderer (iOS 16)|ไม่ใช้การเรนเดอร์ภาพ'
  '\.formatted\(\)|FormatStyle .formatted() (iOS 15 – ใช้ได้)|ตรวจสอบว่าไม่มีพารามิเตอร์ของ iOS 16'
  '\.refreshable|refreshable (iOS 15 – ใช้ได้)|ตรวจสอบ signature'
  'Task\.sleep\(for:|Task.sleep(for:) (iOS 16)|ใช้ Task.sleep(nanoseconds:)'
)

echo "== ตรวจความเข้ากันได้กับ iOS 15 (สแกน: $SCAN_DIR) =="

# ใช้ find สร้างรายการไฟล์แทน --include ของ GNU grep (macOS ใช้ BSD grep)
SWIFT_FILES="$(find "$SCAN_DIR" -name '*.swift' \
  -not -path '*/.git/*' -not -path '*/.build/*' -not -path '*/build/*' \
  -not -path '*/verification/Sources/*' 2>/dev/null || true)"

if [ -z "$SWIFT_FILES" ]; then
  echo "ไม่พบไฟล์ .swift ใน $SCAN_DIR"
  exit 0
fi
echo "(ตรวจ $(printf '%s\n' "$SWIFT_FILES" | wc -l | tr -d ' ') ไฟล์)"

for rule in "${RULES[@]}"; do
  pattern="${rule%%|*}"
  rest="${rule#*|}"
  description="${rest%%|*}"
  fix="${rest#*|}"
  # ข้ามกฎที่ระบุว่าใช้ได้บน iOS 15
  case "$description" in
    *"ใช้ได้"*) continue ;;
  esac

  raw_matches="$(printf '%s\n' "$SWIFT_FILES" | xargs grep -nE "$pattern" 2>/dev/null | grep -v '/\.build/' || true)"
  matches=""
  # ตัดคอมเมนต์ออกก่อนตัดสิน — ข้อความในคอมเมนต์ (เช่นคำอธิบายว่าห้ามใช้ API ตัวไหน) ไม่ถือเป็นการใช้งานจริง
  if [ -n "$raw_matches" ]; then
    while IFS= read -r match_line; do
      [ -z "$match_line" ] && continue
      code_part="${match_line#*:*:}"
      code_part="${code_part#*:}"
      stripped="$(printf '%s' "$code_part" | sed 's|//.*||')"
      if printf '%s' "$stripped" | grep -qE "$pattern"; then
        matches="${matches}${match_line}"$'\n'
      fi
    done <<< "$raw_matches"
    matches="$(printf '%s' "$matches" | sed '/^$/d')"
  fi
  if [ -n "$matches" ]; then
    echo ""
    echo "❌ พบ API ที่ใช้ไม่ได้กับ iOS 15: $description"
    echo "$matches" | sed 's/^/    /'
    echo "    → แก้เป็น: $fix"
    FAILED=1
  fi
done

if [ "$FAILED" -ne 0 ]; then
  echo ""
  echo "ผลลัพธ์: ไม่ผ่าน — มีการใช้ API ของ iOS 16+ ในโค้ด"
  exit 1
fi

echo "ผลลัพธ์: ผ่าน — ไม่พบ API ของ iOS 16+ (เฉพาะรูปแบบที่ตรวจได้ด้วย grep)"
exit 0
