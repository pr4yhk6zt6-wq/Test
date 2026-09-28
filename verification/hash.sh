#!/usr/bin/env bash
#
# ฟังก์ชันแฮชไฟล์แบบพกพา — ใช้ได้ทั้ง Linux (sha256sum) และ macOS (shasum)
# เลือกใช้จากสคริปต์อื่นด้วย:  source "$(dirname "$0")/hash.sh"
#

hash_file() {
  local file="$1"
  if [ ! -f "$file" ]; then
    echo "ไม่พบไฟล์: $file" >&2
    return 1
  fi
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" | cut -d' ' -f1
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$file" | cut -d' ' -f1
  elif command -v openssl >/dev/null 2>&1; then
    openssl dgst -sha256 "$file" | awk '{print $NF}'
  else
    echo "ไม่พบเครื่องมือคำนวณ sha256 (sha256sum / shasum / openssl)" >&2
    return 1
  fi
}

# คืนค่า 0 ถ้าแฮชของสองไฟล์ตรงกัน
hash_equal() {
  local first second
  first="$(hash_file "$1")" || return 1
  second="$(hash_file "$2")" || return 1
  [ "$first" = "$second" ]
}
