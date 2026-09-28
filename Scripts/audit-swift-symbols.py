#!/usr/bin/env python3
"""
ตัวตรวจเชิงโครงสร้างโค้ด Swift (ไม่ต้องมี Xcode)

ใช้จับปัญหาที่คอมไพเลอร์จะฟ้อง เช่น symbol ที่อ้างอิงผิด, วงเล็บไม่สมดุล,
force unwrap, TODO/placeholder และ type ที่ประกาศซ้ำ/หายไป

    python3 Scripts/audit-swift-symbols.py [โฟลเดอร์โปรเจกต์]
"""
import re, sys, pathlib
from collections import defaultdict

ROOT = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
# verification/Tests ถูกคอมไพล์และรันด้วย swift test จริง (คอมไพเลอร์ตรวจให้แล้ว)
EXCLUDE_PARTS = {"verification/Sources", "verification/Tests", ".build", "build"}
files = [f for f in sorted(ROOT.rglob("*.swift"))
         if not any(part in str(f.relative_to(ROOT)) for part in EXCLUDE_PARTS)]
problems = []

def strip_code(src: str) -> str:
    """ลบสตริงและคอมเมนต์ แต่คงเนื้อหาใน \( ... ) ของ string interpolation ไว้ให้ตรวจสอบ"""
    def keep_interp(m):
        body = m.group(0)
        inner = re.findall(r'\\\(((?:[^()]|\([^()]*\))*)\)', body)
        return " ".join(inner) if inner else '""'

    # raw string ของ Swift: #"..."# (และ ##"..."##) — ตัดทิ้งเช่นเดียวกับสตริงปกติ
    t = re.sub(r'#+"(?:.|\n)*?"#+', keep_interp, src)
    t = re.sub(r'"""(?:.|\n)*?"""', keep_interp, src)
    t = re.sub(r'"(?:[^"\\\n]|\\.)*"', keep_interp, t)
    t = re.sub(r'//[^\n]*', '', t)
    t = re.sub(r'/\*(?:.|\n)*?\*/', '', t)
    return t

# ---------- 1) วงเล็บสมดุล / ไม่มี placeholder ----------
for f in files:
    t = strip_code(f.read_text())
    for open_c, close_c in (("{", "}"), ("(", ")"), ("[", "]")):
        if t.count(open_c) != t.count(close_c):
            problems.append(f"{f.name}: วงเล็บ {open_c}{close_c} ไม่สมดุล ({t.count(open_c)} vs {t.count(close_c)})")
    for bad in ("TODO", "FIXME", "fatalError(", "try!", " as! "):
        if bad in t:
            problems.append(f"{f.name}: พบ '{bad}'")
    for m in re.finditer(r'([A-Za-z_)\]])!(\s*[)\].,])', t):
        problems.append(f"{f.name}: อาจมี force unwrap → {m.group(0)!r}")

# ---------- 2) เก็บ type + สมาชิกที่ประกาศไว้ ----------
type_members = defaultdict(set)
type_static = defaultdict(set)
declared_types = set()
enum_cases = defaultdict(set)

type_re = re.compile(r'^(?:@\w+(?:\([^)]*\))?[ \t]+)*(?:public |internal |private |fileprivate |final )*'
                     r'(struct|class|enum|protocol|extension)[ \t]+([A-Za-z_][A-Za-z0-9_]*)', re.M)
# type ที่ประกาศซ้อนอยู่ (เยื้องเข้าไป เช่น struct ภายใน View) — ใช้เติม declared_types เท่านั้น
nested_type_re = re.compile(r'^[ \t]+(?:@\w+(?:\([^)]*\))?[ \t]+)*(?:public |internal |private |fileprivate |final |static )*'
                            r'(struct|class|enum|protocol)[ \t]+([A-Za-z_][A-Za-z0-9_]*)', re.M)
member_re = re.compile(r'^\s+(?:@\w+(?:\([^)]*\))?\s+)*'
                       r'(?:private\(set\)\s+|private\s+|fileprivate\s+|internal\s+|public\s+|final\s+|static\s+|class\s+|mutating\s+|nonisolated\s+|lazy\s+|weak\s+|unowned\s+)*'
                       r'(var|let|func|init|case|subscript|typealias)\s+([A-Za-z_][A-Za-z0-9_]*)')

for f in files:
    src = strip_code(f.read_text())
    current = None
    depth = 0
    for line in src.split("\n"):
        m = type_re.match(line)
        if m:
            current = m.group(2)
            declared_types.add(current)
            depth = 0
        else:
            nm = nested_type_re.match(line)
            if nm:
                # type ที่ประกาศซ้อนใน View/struct (เช่น QuickPromptsView.QuickPrompt)
                declared_types.add(nm.group(2))
        if current:
            depth += line.count("{") - line.count("}")
            mm = member_re.match(line)
            if mm:
                kind, name = mm.group(1), mm.group(2)
                type_members[current].add(name)
                if kind == "case":
                    enum_cases[current].add(name)
                if "static " in line or re.search(r'\bclass\s+func\b', line):
                    type_static[current].add(name)
            pass  # scope เปลี่ยนเมื่อเจอ type ระดับบนสุดตัวถัดไปเท่านั้น

# ---------- 3) ตรวจการอ้างอิงสมาชิก ----------
UNKNOWN_TYPES = set()

def check(owner: str, typ: str, label: str, src: str, fname: str):
    known = type_members[typ] | type_static[typ] | enum_cases[typ]
    if not known:
        if typ not in UNKNOWN_TYPES:
            UNKNOWN_TYPES.add(typ)
            problems.append(f"ไม่พบการประกาศสมาชิกของ type {typ}")
        return
    for m in re.finditer(r'\b' + owner + r'\.([A-Za-z_][A-Za-z0-9_]*)', src):
        member = m.group(1)
        if member in known or member in declared_types or member in {"objectWillChange", "shared"}:
            continue
        problems.append(f"{fname}: {owner}.{member} — ไม่พบสมาชิก '{member}' ใน {typ}")

INSTANCE_VARS = {
    "viewModel": "ChatViewModel",
    "settings": "AppSettings",
    "usage": "TokenUsageTracker",
    "backgroundKeeper": "BackgroundTaskKeeper",
    "accumulator": "ToolCallAccumulator",
    "result": None,
}
STATIC_OWNERS = [
    ("OpenRouterService", "OpenRouterService"),
    ("ToolArgumentsSanitizer", "ToolArgumentsSanitizer"),
    ("MarkdownRenderer", "MarkdownRenderer"),
    ("SystemAccessChecker", "SystemAccessChecker"),
    ("SystemPrompt", "SystemPrompt"),
    ("RetryPolicy", "RetryPolicy"),
    ("InputFontProvider", "InputFontProvider"),
    ("SettingsKeys", "SettingsKeys"),
    ("AppAppearance", "AppAppearance"),
    ("KeychainHelper", "KeychainHelper"),
    ("KeychainError", "KeychainError"),
    ("ChatMessage", "ChatMessage"),
    ("TokenUsage", "TokenUsage"),
    ("JSONValue", "JSONValue"),
    ("OpenRouterError", "OpenRouterError"),
    ("ChatStreamEvent", "ChatStreamEvent"),
    ("ChatRole", "ChatRole"),
    ("AppSettings", "AppSettings"),
    ("TokenUsageTracker", "TokenUsageTracker"),
    ("BackgroundTaskKeeper", "BackgroundTaskKeeper"),
]
SKIP_MEMBERS = {"shared", "self", "init", "type", "Type", "allCases", "rawValue", "id", "hashValue"}

for f in files:
    src = strip_code(f.read_text())
    for var, typ in INSTANCE_VARS.items():
        if typ is None:
            continue
        if var == "usage" and "func add(_ usage: TokenUsage?" in src:
            continue  # พารามิเตอร์ชื่อ usage ชนิด TokenUsage บังชื่อคุณสมบัติของคลาส
        check(var, typ, "instance", src, f.name)
    for owner, typ in STATIC_OWNERS:
        known = type_members[typ] | type_static[typ] | enum_cases[typ]
        if not known:
            if typ not in UNKNOWN_TYPES:
                UNKNOWN_TYPES.add(typ)
                problems.append(f"ไม่พบการประกาศสมาชิกของ type {typ}")
            continue
        for m in re.finditer(r'\b' + owner + r'\.([A-Za-z_][A-Za-z0-9_]*)', src):
            member = m.group(1)
            if member in known or member in declared_types or member in SKIP_MEMBERS:
                continue
            problems.append(f"{f.name}: {owner}.{member} — ไม่พบสมาชิก '{member}' ใน {typ}")

# ---------- 4) ตรวจรายชื่อ type สำคัญของโปรเจกต์ ----------
REQUIRED_TYPES = [
    "IOSAgentSandboxApp", "ChatView", "ChatViewModel", "SettingsView", "ModelPickerView",
    "RootTabView", "MessageBubbleView", "MessageContentView", "CodeBlockView", "ShareSheet",
    "MultilineInputField", "InputFontProvider", "SystemPrompt", "MarkdownRenderer",
    "BackgroundTaskKeeper", "AppSettings", "SettingsKeys", "ToolArgumentsSanitizer",
    "RetryPolicy", "OpenRouterService", "OpenRouterError", "KeychainHelper", "KeychainError",
    "TokenUsageTracker", "TokenUsage", "SystemAccessChecker", "SystemAccessReport",
    "AppAppearance", "ChatMessage", "ChatRole", "ToolCall", "FunctionCall", "ToolDefinition",
    "JSONValue", "ChatCompletionChunk", "ChatStreamEvent", "ChatCompletionResult",
    "ConnectionTestResult", "OpenRouterModel", "APIErrorBody", "ToolCallDelta", "ToolCallAccumulator",
    "ChatMessagePayload", "ModelsResponse", "FailableValue", "FlexibleNumber", "ShareableText",
    "FileBrowserView", "FilePreviewView", "AgentLogView", "AgentLogStore", "AgentLogEntry",
    "EntitlementExplanationView", "EntitlementScanResult",
    # เฟส 5: ไฟล์แนบ + หลายห้องสนทนา + ดู/แก้ไฟล์ + คำแนะนำการใช้งาน
    "Attachment", "AttachmentKind", "AttachmentStore", "AttachmentStoreError",
    "AttachmentMessageBuilder", "VisionSupport", "VisionOverride", "ChatRoom", "ChatRoomStore",
    "ImageDownscaler", "AppRouter", "RootTab", "AttachmentChipView", "AttachmentChipRow",
    "AttachmentPickerSheet", "QuickPrompt", "QuickPromptsView", "ChatRoomsView", "OnboardingView",
    "SystemStatusView", "PDFPreviewView", "FileEditorView",
    "PHPickerRepresentable", "DocumentPickerRepresentable", "ImagePickerRepresentable",
]
for name in REQUIRED_TYPES:
    if name not in declared_types:
        problems.append(f"ไม่พบ type ที่ต้องมีในโปรเจกต์: {name}")

print("=== ผลตรวจเชิงโครงสร้าง ===")
print("ไฟล์ Swift:", len(files), "| types:", len(declared_types))
if problems:
    print("\nพบปัญหา:")
    for p in sorted(set(problems)):
        print("  -", p)
    sys.exit(1)
print("\nผ่าน — ไม่พบปัญหาด้านโครงสร้าง")
