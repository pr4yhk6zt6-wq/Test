#!/usr/bin/env python3
"""
pick-xcode.py — พิมพ์รายชื่อ Xcode ที่ติดตั้งในเครื่อง เรียงจาก "ใหม่ไปเก่า"

ใช้ใน CI เพื่อเลือก Xcode ตัวใหม่สุดที่ยังคอมไพล์ให้ iOS 15.0 ได้จริง
(ตัวใหม่สุดจะอ่าน project format ใหม่ ๆ ได้ ไม่เจอปัญหา "future project file format")

หมายเหตุ: สคริปต์นี้แค่จัดเรียง ไม่ได้ทดสอบการคอมไพล์ — การทดสอบทำใน shell
เพราะต้องเรียก `sudo xcode-select` + `swiftc`
"""

import os
import plistlib
import sys


def version_of(app_path: str) -> tuple:
    plist_path = os.path.join(app_path, "Contents", "version.plist")
    try:
        with open(plist_path, "rb") as handle:
            data = plistlib.load(handle)
        raw = str(data.get("CFBundleShortVersionString", "0"))
    except Exception:  # noqa: BLE001
        raw = "0"
    parts = []
    for piece in raw.split(".")[:3]:
        try:
            parts.append(int(piece))
        except ValueError:
            parts.append(0)
    while len(parts) < 3:
        parts.append(0)
    return tuple(parts)


def main() -> int:
    applications = "/Applications"
    try:
        names = sorted(os.listdir(applications))
    except OSError as error:
        print(f"อ่าน {applications} ไม่ได้: {error}", file=sys.stderr)
        return 1

    found = []
    for name in names:
        if not name.startswith("Xcode") or not name.endswith(".app"):
            continue
        app_path = os.path.join(applications, name)
        found.append((version_of(app_path), app_path))

    # เรียงใหม่ -> เก่า (ถ้าเวอร์ชันเท่ากันให้ชื่อสั้นกว่ามาก่อน เช่น Xcode.app)
    found.sort(key=lambda item: (item[0], -len(item[1])), reverse=True)

    for version, app_path in found:
        print(f"{app_path}\t{'.'.join(str(part) for part in version)}")

    if not found:
        print("ไม่พบ Xcode ใน /Applications", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
