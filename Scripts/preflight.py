#!/usr/bin/env python3
"""
preflight.py — ตรวจโปรเจกต์ก่อน push ขึ้น GitHub (รันได้ทุก OS ที่มี Python 3.8+ ไม่ต้องติดตั้งอะไรเพิ่ม)

    python3 Scripts/preflight.py            # รันจากโฟลเดอร์โปรเจกต์
    python3 Scripts/preflight.py <โฟลเดอร์>

ตรวจจับปัญหาที่จะทำให้ CI บน macOS ล้มเหลว ก่อนที่คุณจะเสียเวลา 5–10 นาทีรอ build:
  1. ไฟล์/โฟลเดอร์ที่ CI ต้องใช้มีครบ (รวม .github/workflows/build.yml)
  2. YAML ของ workflow และ project.yml valid (ถ้ามี PyYAML)
  3. Info.plist / entitlements เป็น plist ที่อ่านได้ + entitlements ครบ 5 คีย์
  4. ไอคอนแอปมีจริง ขนาด 1024x1024 และเป็น RGB (ไม่มี alpha — App Store/Xcode ไม่รับ)
  5. Asset catalog JSON valid
  6. โค้ด Swift: ไม่มี TODO/force unwrap และไม่ใช้ API ของ iOS 16+
"""

import json
import os
import plistlib
import re
import struct
import sys
from pathlib import Path

PROBLEMS = []
WARNINGS = []
CHECKS = 0


def ok(message: str) -> None:
    global CHECKS
    CHECKS += 1
    print(f"  \u2713 {message}")


def problem(message: str) -> None:
    PROBLEMS.append(message)
    print(f"  \u2717 {message}")


def warn(message: str) -> None:
    WARNINGS.append(message)
    print(f"  ! {message}")


# ---------------------------------------------------------------- 1) ไฟล์ที่ต้องมี

REQUIRED_FILES = [
    "App/iOSAgentSandboxApp.swift",
    "Models/JSONValue.swift",
    "Models/ChatModels.swift",
    "Models/OpenRouterModels.swift",
    "Services/OpenRouterService.swift",
    "Services/OpenRouterCore.swift",
    "Services/KeychainHelper.swift",
    "Services/AppSettings.swift",
    "Services/TokenUsageTracker.swift",
    "Services/SystemAccessChecker.swift",
    "Services/SystemPrompt.swift",
    "Services/BackgroundTaskKeeper.swift",
    "Views/ChatView.swift",
    "Views/ChatViewModel.swift",
    "Views/SettingsView.swift",
    "Views/ModelPickerView.swift",
    "Views/MessageBubbleView.swift",
    "Views/MessageContentView.swift",
    "Views/MarkdownRenderer.swift",
    "Views/MultilineInputField.swift",
    "Views/ShareSheet.swift",
    "Views/RootTabView.swift",
    "Views/FileBrowserView.swift",
    "Views/FilePreviewView.swift",
    "Views/AgentLogView.swift",
    "Views/EntitlementExplanationView.swift",
    "Views/ApprovalSheetView.swift",
    "Views/ToolActivityView.swift",
    "Views/AttachmentChipView.swift",
    "Views/AttachmentPickerSheet.swift",
    "Views/QuickPromptsView.swift",
    "Views/ChatRoomsView.swift",
    "Views/OnboardingView.swift",
    "Views/SystemStatusView.swift",
    "Views/PDFPreviewView.swift",
    "Views/FileEditorView.swift",
    "Views/Pickers/PHPickerRepresentable.swift",
    "Views/Pickers/DocumentPickerRepresentable.swift",
    "Views/Pickers/ImagePickerRepresentable.swift",
    "Models/Attachment.swift",
    "Services/AttachmentStore.swift",
    "Services/AttachmentMessageBuilder.swift",
    "Services/ChatRoomStore.swift",
    "Services/VisionSupport.swift",
    "Services/ImageDownscaler.swift",
    "Services/AppRouter.swift",
    "Services/ChatSearchIndex.swift",
    "Views/ChatSearchView.swift",
    "Services/Tools/FileEditTools.swift",
    "Services/Tools/ContentSearchTool.swift",
    "Services/AgentLogStore.swift",
    "Resources/Info.plist",
    "Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png",
    "Resources/Assets.xcassets/AppIcon.appiconset/Contents.json",
    "Entitlements/iOSAgentSandbox.entitlements",
    "project.yml",
    ".github/workflows/build.yml",
    "Scripts/sign-and-package.sh",
    "Scripts/check-ios15-compat.sh",
    "verification/run-verification.sh",
    "verification/e2e/run-e2e.sh",
]


def check_files(root: Path) -> None:
    print("\n[1] ไฟล์ที่ CI ต้องใช้")
    missing = [rel for rel in REQUIRED_FILES if not (root / rel).exists()]
    if missing:
        for rel in missing:
            problem(f"ไม่พบไฟล์: {rel}")
    else:
        ok(f"ครบทั้ง {len(REQUIRED_FILES)} ไฟล์")


# ---------------------------------------------------------------- 2) YAML

def check_yaml(root: Path) -> None:
    print("\n[2] ไฟล์ YAML")
    try:
        import yaml  # type: ignore
    except ImportError:
        warn("ไม่มีโมดูล PyYAML — ข้ามการตรวจ syntax ของ YAML (ติดตั้งด้วย: pip install pyyaml)")
        return

    for rel in ("project.yml", ".github/workflows/build.yml"):
        path = root / rel
        if not path.exists():
            continue
        try:
            data = yaml.safe_load(path.read_text(encoding="utf-8"))
            if rel.endswith("build.yml"):
                steps = data["jobs"]["build"]["steps"]
                ok(f"{rel} valid ({len(steps)} ขั้นตอน, runs-on = {data['jobs']['build']['runs-on']})")
            else:
                target = list(data["targets"].keys())[0]
                ok(f"{rel} valid (target = {target}, deployment = {data['targets'][target]['deploymentTarget']})")
        except Exception as error:  # noqa: BLE001
            problem(f"{rel} อ่านไม่ได้: {error}")


# ---------------------------------------------------------------- 3) plist

ENTITLEMENT_KEYS = [
    "platform-application",
    "com.apple.private.security.no-container",
    "com.apple.private.security.no-sandbox",
    "com.apple.private.persona-mgmt",
    "com.apple.private.security.container-required",
]


def check_plists(root: Path) -> None:
    print("\n[3] Info.plist และ entitlements")

    info_path = root / "Resources/Info.plist"
    try:
        with open(info_path, "rb") as handle:
            info = plistlib.load(handle)
        required_keys = ["CFBundleIdentifier", "CFBundleName", "CFBundleShortVersionString", "UILaunchScreen"]
        missing = [key for key in required_keys if key not in info]
        if missing:
            problem(f"Info.plist ขาดคีย์: {', '.join(missing)}")
        elif "UILaunchScreen" not in info:
            problem("Info.plist ไม่มี UILaunchScreen — แอปจะถูกจำกัดเป็นจอเล็ก/มีแถบดำ")
        else:
            ok("Info.plist อ่านได้และมีคีย์จำเป็น")
        if info.get("CFBundleIconName") != "AppIcon":
            warn("Info.plist ไม่ได้ตั้ง CFBundleIconName = AppIcon (ไอคอนอาจไม่แสดง)")
    except Exception as error:  # noqa: BLE001
        problem(f"อ่าน Info.plist ไม่ได้: {error}")

    ent_path = root / "Entitlements/iOSAgentSandbox.entitlements"
    try:
        with open(ent_path, "rb") as handle:
            ent = plistlib.load(handle)
        missing = [key for key in ENTITLEMENT_KEYS if key not in ent]
        if missing:
            problem(f"entitlements ขาดคีย์: {', '.join(missing)}")
        else:
            ok(f"entitlements ครบ {len(ENTITLEMENT_KEYS)} คีย์ (รวม no-sandbox / persona-mgmt)")
    except Exception as error:  # noqa: BLE001
        problem(f"อ่าน entitlements ไม่ได้: {error}")


# ---------------------------------------------------------------- 4) ไอคอน

def png_size(path: Path):
    """อ่านขนาดจาก PNG header โดยไม่ต้องใช้ไลบรารีภายนอก"""
    with open(path, "rb") as handle:
        header = handle.read(33)
    if header[:8] != b"\x89PNG\r\n\x1a\n":
        return None
    width, height = struct.unpack(">II", header[16:24])
    color_type = header[25]
    return width, height, color_type


def check_icon(root: Path) -> None:
    print("\n[4] ไอคอนแอป")
    path = root / "Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"
    if not path.exists():
        problem("ไม่พบ AppIcon-1024.png")
        return
    size = png_size(path)
    if size is None:
        problem("AppIcon-1024.png ไม่ใช่ไฟล์ PNG ที่ถูกต้อง")
        return
    width, height, color_type = size
    if (width, height) != (1024, 1024):
        problem(f"ไอคอนต้องเป็น 1024x1024 แต่ได้ {width}x{height}")
    elif color_type not in (2, 6):
        problem(f"ชนิดสีของ PNG ไม่คาดคิด (color type {color_type})")
    elif color_type == 6:
        problem("ไอคอนมีช่อง alpha — Xcode ไม่รับไอคอน App Store ที่มี alpha (ต้องเป็น RGB)")
    else:
        ok(f"ไอคอน 1024x1024 RGB ไม่มี alpha ({(path.stat().st_size / 1024):.0f} KB)")


# ---------------------------------------------------------------- 5) Asset catalog

def check_assets(root: Path) -> None:
    print("\n[5] Asset catalog")
    paths = [
        root / "Resources/Assets.xcassets/Contents.json",
        root / "Resources/Assets.xcassets/AppIcon.appiconset/Contents.json",
    ]
    for path in paths:
        if not path.exists():
            problem(f"ไม่พบ {path.relative_to(root)}")
            continue
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
            if path.name == "Contents.json" and "AppIcon" in str(path) and not data.get("images"):
                problem("AppIcon.appiconset/Contents.json ไม่มีรายการ images")
            else:
                ok(f"{path.relative_to(root)} valid")
        except Exception as error:  # noqa: BLE001
            problem(f"{path.relative_to(root)} อ่านไม่ได้: {error}")


# ---------------------------------------------------------------- 6) โค้ด Swift

IOS16_RULES = [
    r"NavigationStack", r"NavigationSplitView", r"PhotosPicker", r"scrollDismissesKeyboard",
    r"presentationDetents", r"toolbarBackground", r"scrollContentBackground",
    r"axis: \.vertical", r"lineLimit\([0-9]+\.\.\.", r"\.fontWeight\(",
    r"gridCellColumns", r"sensoryFeedback", r"onChange\(of:.*initial:",
]


def check_swift(root: Path) -> None:
    print("\n[6] โค้ด Swift")
    files = []
    for path in root.rglob("*.swift"):
        rel = str(path.relative_to(root))
        if any(part in rel for part in (".build/", "build/", "verification/Sources/")):
            continue
        files.append(path)

    todo_hits, force_hits, api_hits = [], [], []
    for path in files:
        text = path.read_text(encoding="utf-8")
        rel = path.relative_to(root)
        for number, line in enumerate(text.splitlines(), 1):
            code = line.split("//", 1)[0]
            if re.search(r"\b(TODO|FIXME)\b", code):
                todo_hits.append(f"{rel}:{number}")
            if re.search(r"try!|as!|fatalError\(", code) or re.search(r"[A-Za-z0-9_\)\]]!\s*[\),\.]", code):
                force_hits.append(f"{rel}:{number}")
            for rule in IOS16_RULES:
                if re.search(rule, code):
                    api_hits.append(f"{rel}:{number} → {rule}")

    if todo_hits:
        problem(f"พบ TODO/FIXME: {', '.join(todo_hits[:5])}")
    if force_hits:
        problem(f"พบ force unwrap/try!/as!: {', '.join(force_hits[:5])}")
    if api_hits:
        problem(f"พบ API ของ iOS 16+: {', '.join(api_hits[:5])}")
    if not (todo_hits or force_hits or api_hits):
        ok(f"สแกน {len(files)} ไฟล์: ไม่มี TODO / force unwrap / API ของ iOS 16+")


THAI_COMBINING = "\u0e31\u0e34-\u0e3a\u0e47-\u0e4e"
# อักษรละติน/ตัวเลขที่ตามด้วยวรรณยุกต์หรือสระบน-ล่างของไทย = พิมพ์ผิดแน่นอน (เกิดจากสลับ keyboard)
MIXED_SCRIPT_RULE = rf"[A-Za-z0-9][{THAI_COMBINING}]"
MIXED_SCRIPT_FILES = (".swift", ".md", ".sh", ".py", ".yml", ".yaml", ".entitlements", ".json", ".plist")


def check_thai_text(root: Path) -> None:
    """ตรวจคำไทยที่มีอักษรละตินปนอยู่ (บั๊กการพิมพ์ที่ตาเปล่ามองข้ามได้ง่ายมาก)"""
    print("\n[7] ข้อความไทย (อักษรละตินปนคำ)")

    hits = []
    for path in sorted(root.rglob("*")):
        if not path.is_file() or path.suffix not in MIXED_SCRIPT_FILES:
            continue
        rel = str(path.relative_to(root))
        if any(part in rel for part in (".git/", ".build/", "build/", "verification/Sources/", "node_modules/")):
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except (UnicodeDecodeError, OSError):
            continue
        for number, line in enumerate(text.splitlines(), 1):
            if "mixed-script-allow" in line:
                continue   # บรรทัดที่จงใจยกตัวอย่างข้อความผิด (เช่นในรายงานผล)
            for match in re.finditer(MIXED_SCRIPT_RULE, line):
                snippet = line[max(0, match.start() - 8):match.end() + 8]
                hits.append(f"{rel}:{number} → …{snippet}…")

    if hits:
        problem(f"พบอักษรละตินปนคำไทย: {', '.join(hits[:5])}")
    else:
        ok("ไม่พบอักษรละตินปนคำไทยในไฟล์ข้อความทั้งหมด")


# ---------------------------------------------------------------- main

def main() -> int:
    root = Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
    print("=" * 62)
    print(f"Preflight check — {root}")
    print("=" * 62)

    if not (root / "project.yml").exists():
        print("\nไม่พบ project.yml — รันจากโฟลเดอร์โปรเจกต์ (iOSAgentSandbox) หรือส่ง path มาเป็นอาร์กิวเมนต์")
        return 2

    check_files(root)
    check_yaml(root)
    check_plists(root)
    check_icon(root)
    check_assets(root)
    check_swift(root)
    check_thai_text(root)

    print("\n" + "=" * 62)
    if PROBLEMS:
        print(f"ผลลัพธ์: พบ {len(PROBLEMS)} ปัญหาที่ต้องแก้ก่อน push")
        for item in PROBLEMS:
            print(f"  - {item}")
        return 1
    print(f"ผลลัพธ์: ผ่านทุกข้อ ({CHECKS} การตรวจ)" + (f" • คำเตือน {len(WARNINGS)}" if WARNINGS else ""))
    print("พร้อม push ขึ้น GitHub ได้เลย")
    return 0


if __name__ == "__main__":
    sys.exit(main())
