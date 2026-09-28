#!/usr/bin/env python3
"""
pick-simulator.py — หา UDID ของเครื่อง iPhone ที่เล็กที่สุดที่รันได้ (ใช้ถ่ายภาพหน้าจอตรวจงานออกแบบ)

    python3 Scripts/ci/pick-simulator.py            # หา iPhone SE (3rd generation)
    python3 Scripts/ci/pick-simulator.py "iPhone 16"  # ระบุชื่อรุ่นเอง

เลือกเครื่องจอเล็ก (375x667 pt) เพราะเป็นขนาดที่ใกล้เคียง iPhone 7 ของผู้ใช้มากที่สุด
และเป็นขนาดที่ตรวจปัญหาข้อความไทยล้นได้ดีที่สุด · ไม่พบรุ่นที่ขอจะคืนค่าว่างพร้อม exit 1
"""
import json
import subprocess
import sys


def main() -> int:
    wanted = sys.argv[1] if len(sys.argv) > 1 else "iPhone SE (3rd generation)"
    raw = subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "-j"])
    devices = json.loads(raw)["devices"]

    fallbacks = [wanted, "iPhone SE (2nd generation)", "iPhone 8", "iPhone 13 mini"]
    for name in fallbacks:
        for runtime, items in sorted(devices.items()):
            if "iOS" not in runtime:
                continue
            for device in items:
                if device["name"] == name:
                    print(device["udid"])
                    return 0

    print("", end="")
    print(f"ไม่พบ Simulator ที่ต้องการ: {wanted}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
