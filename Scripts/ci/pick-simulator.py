#!/usr/bin/env python3
"""
pick-simulator.py — หา UDID ของ iPhone ที่จอเล็กที่สุดที่รันได้ (ใช้ถ่ายภาพหน้าจอตรวจงานออกแบบ)

    python3 Scripts/ci/pick-simulator.py                 # เลือกอัตโนมัติ (เล็กสุดก่อน)
    python3 Scripts/ci/pick-simulator.py "iPhone 16e"    # ระบุชื่อรุ่นเอง

ทำไมต้องเลือกจอเล็ก: ขนาดจอเล็กเป็นด่านที่โหดที่สุดสำหรับข้อความไทย (ตกบรรทัด/ล้นขอบ)
ถ้าใช้ได้บนจอเล็ก จอใหญ่จะไม่มีปัญหา · สคริปต์จะพิมพ์รายการเครื่องทั้งหมดออกทาง stderr
เพื่อให้ตรวจย้อนหลังได้ว่าเลือกเครื่องไหนและมีอะไรให้เลือกบ้าง (ไม่เดา)
"""
import json
import subprocess
import sys

# ลำดับความชอบ: จอเล็ก → ใหญ่ (จำกัดเฉพาะรุ่นที่ไม่ใช่ Plus/Pro Max)
PREFERRED = [
    "iPhone SE (3rd generation)",
    "iPhone SE (2nd generation)",
    "iPhone 16e",
    "iPhone 13 mini",
    "iPhone 12 mini",
    "iPhone 8",
    "iPhone 16",
    "iPhone 15",
    "iPhone 14",
    "iPhone 13",
]


def main() -> int:
    wanted = sys.argv[1] if len(sys.argv) > 1 else None
    raw = subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "-j"])
    devices = json.loads(raw)["devices"]

    catalog: list[tuple[str, str, str]] = []   # (name, udid, runtime)
    for runtime, items in sorted(devices.items()):
        if "iOS" not in runtime:
            continue
        for device in items:
            catalog.append((device["name"], device["udid"], runtime))

    print("== Simulator ที่มีให้เลือก ==", file=sys.stderr)
    for name, udid, runtime in catalog:
        print(f"   {name}  ({runtime.split('.')[-1]})  {udid}", file=sys.stderr)

    if not catalog:
        print("ไม่พบ Simulator ที่พร้อมใช้เลย", file=sys.stderr)
        return 1

    if wanted:
        for name, udid, _ in catalog:
            if name == wanted:
                print(udid)
                return 0
        print(f"ไม่พบรุ่นที่ระบุ: {wanted} — จะเลือกจอเล็กที่สุดที่มีให้แทน", file=sys.stderr)

    for name in PREFERRED:
        for candidate, udid, _ in catalog:
            if candidate == name:
                print(udid)
                return 0

    # ไม่มีรุ่นที่รู้จัก: ใช้เครื่องแรกที่เป็น iPhone (เรียงชื่อให้สั้น/เล็กก่อน)
    iphones = sorted([c for c in catalog if "iPhone" in c[0]], key=lambda c: c[0])
    if iphones:
        print(iphones[0][1])
        return 0

    print(catalog[0][1])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
