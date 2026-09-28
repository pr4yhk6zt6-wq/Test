# iOS Agent Sandbox

AI Agent สำหรับ iPhone 7 (iOS 15.8.x) ที่เข้าถึงไฟล์ทั้งเครื่อง รันคำสั่ง shell และใช้อินเทอร์เน็ตได้
ติดตั้งผ่าน **TrollStore** หรือ **palera1n** (rootful/rootless)

| ข้อกำหนด | ค่าที่ใช้ |
|---|---|
| Deployment target | **iOS 15.0** (ห้าม API ของ iOS 16+) |
| UI | SwiftUI, ภาษาไทย, `NavigationView` (ไม่ใช้ `NavigationStack`) |
| รูปแบบงาน | Swift Concurrency (`async/await`), ไม่ใช้ library ภายนอก |
| เป้าหมาย | iPhone 7 — RAM 2GB, จอ 4.7", ไม่ใช้ Dynamic Island / Live Activities / Face ID |

---

## สถานะการพัฒนา

| เฟส | ขอบเขต | สถานะ |
|---|---|---|
| **1** | Settings + OpenRouterService (Keychain, Model ID, streaming SSE, รวม tool_calls delta, retry/error handling, Token Usage) | ✅ **เสร็จ + ผ่าน unit 33/33 และ E2E 26/26 (รันจริงในแซนด์บล็อก)** |
| 2 | AgentEngine (ReAct loop) + Tools 9 ตัว + โหมดขออนุมัติ + ประวัติแชท JSON | ⏳ รอเริ่ม |
| 3 | ShellService (`posix_spawn`) + FileSystemService + entitlements/ldid | ⏳ รอเริ่ม |
| 4 | ChatView/FileBrowserView/AgentLogView ฉบับเต็ม + background task | ⏳ ต่อจากเฟส 1–3 |
| 5 | แนบไฟล์/รูป, Markdown + code block, หลายห้องสนทนา, UX ครบ | ⏳ รอเริ่ม |

> เฟส 1 ทำงานได้จริงทั้งก้อน: ใส่ API Key → โหลดรายการโมเดล → ทดสอบการเชื่อมต่อ → แชทแบบสตรีมมิ่ง + นับโทเคน
> แท็บ “ไฟล์” และ “บันทึก” เป็นหน้าจอ placeholder ที่บอกชัดว่าเป็นงานของเฟส 3–4 (ไม่ใช่ TODO ในโค้ดที่ทำงานอยู่)

---

## โครงสร้างไฟล์

```
iOSAgentSandbox/
├── App/
│   └── iOSAgentSandboxApp.swift          # จุดเริ่มต้นแอป + ตรวจสิทธิ์ตอนเปิด
├── Models/
│   ├── JSONValue.swift                   # JSON แบบ type-safe (arguments ของ tool, JSON Schema)
│   ├── ChatModels.swift                  # ChatMessage, ToolCall, ToolDefinition, TokenUsage
│   └── OpenRouterModels.swift            # SSE chunk, error body, รายการโมเดล, ChatStreamEvent
├── Services/
│   ├── KeychainHelper.swift              # เก็บ API Key (พร้อม fallback กรณีไม่มี entitlement)
│   ├── AppSettings.swift                 # Model ID + สถานะการเก็บคีย์ + คีย์ค่าเริ่มต้นของเฟสถัดไป
│   ├── OpenRouterService.swift           # ★ streaming SSE + tool_calls delta + retry + usage
│   ├── TokenUsageTracker.swift           # รวมโทเคนต่อเซสชัน
│   ├── BackgroundTaskKeeper.swift        # UIApplication.beginBackgroundTask
│   ├── SystemAccessChecker.swift         # ตรวจสิทธิ์ /var/mobile ฯลฯ (root/non-root)
│   └── SystemPrompt.swift                # System Prompt (ภาษา, สิทธิ์เข้าถึง, กัน prompt injection)
├── Views/
│   ├── ChatView.swift + ChatViewModel.swift
│   ├── SettingsView.swift, ModelPickerView.swift
│   ├── MessageBubbleView.swift, MessageContentView.swift, MarkdownRenderer.swift
│   ├── MultilineInputField.swift         # ช่องพิมพ์หลายบรรทัดแบบ iOS 15 (ห่อ UITextView)
│   ├── ShareSheet.swift                  # UIActivityViewController
│   ├── RootTabView.swift, PlaceholderViews.swift
├── Resources/
│   ├── Info.plist
│   └── Assets.xcassets/AppIcon.appiconset
├── Entitlements/
│   └── iOSAgentSandbox.entitlements       # platform-application, no-container, no-sandbox, persona-mgmt, container-required
├── verification/                           # ชุดทดสอบที่รันได้โดยไม่ต้องมี Xcode
│   ├── Package.swift, run-verification.sh  # unit test ของแกนกลาง (33 เคส)
│   └── e2e/                                # เซิร์ฟเวอร์ OpenRouter จำลอง + harness (26 ข้อ)
├── Scripts/
│   ├── check-ios15-compat.sh              # สแกนห้ามใช้ API ของ iOS 16+
│   ├── audit-swift-symbols.py             # ตรวจโครงสร้าง/สัญลักษณ์ที่อ้างอิงผิด
│   ├── build-local.sh                     # build บน Mac (xcodegen + xcodebuild + ldid)
│   ├── push-to-github.sh                  # อัปโปรเจกต์ขึ้น GitHub ในคำสั่งเดียว
│   └── sign-and-package.sh                # ldid -S + แพ็ค .ipa
├── project.yml                            # สเปก XcodeGen → สร้าง iOSAgentSandbox.xcodeproj
└── .github/workflows/build.yml            # CI: build ไม่ลงนาม → ldid → .ipa → artifact
```

---

## วิธี Build

### บน GitHub Actions (แนะนำ)

push ขึ้น branch `main` หรือกด **Run workflow** — ขั้นตอนใน workflow:

1. `Scripts/check-ios15-compat.sh` — ถ้าเจอ API ของ iOS 16+ จะหยุดทันที
2. `xcodegen generate` — สร้าง `.xcodeproj` จาก `project.yml`
3. `xcodebuild -sdk iphoneos CODE_SIGNING_ALLOWED=NO` (Release, `IPHONEOS_DEPLOYMENT_TARGET=15.0`)
4. ตรวจ `MinimumOSVersion` ของผลลัพธ์ว่าต้องเป็น `15.0`
5. `ldid -S Entitlements/... iOSAgentSandbox.app/iOSAgentSandbox` แล้ว zip เป็น `Payload/...` → `iOSAgentSandbox.ipa`
6. อัปโหลดเป็น artifact ชื่อ **iOSAgentSandbox-ipa**

> หมายเหตุ: โปรเจกต์ไม่ commit ไฟล์ `.xcodeproj` (ไฟล์ pbxproj แตกง่ายเวลา merge) แต่สร้างจาก `project.yml` เสมอ
> ด้วย XcodeGen ทำให้โครงสร้างโปรเจกต์ตรงกับโฟลเดอร์จริงตลอด — ถ้าต้องการ commit ไฟล์ `.xcodeproj` ด้วย
> บอกได้เลย ผมจะ generate แล้วเก็บลง repo ให้ในเฟสถัดไป

### บน Mac ของคุณ

```bash
brew install xcodegen ldid-procursus   # ถ้าไม่มี ldid-procursus ใช้ ldid ปกติได้
cd iOSAgentSandbox
bash Scripts/build-local.sh            # ตรวจ API + build + ldid + ได้ไฟล์ .ipa
```

### การติดตั้งบนเครื่อง

* **TrollStore** — เปิดไฟล์ `iOSAgentSandbox.ipa` ด้วย TrollStore (TrollStore จะเซ็นซ้ำด้วย fakesign ให้)
* **palera1n (rootful)** — ขยาย `.app` ไปไว้ `/Applications/` แล้ว `ldid -S` (ตามสคริปต์) จากนั้น `uicache -a`
* **Sideloadly** — ติดตั้งได้ แต่จะ **ไม่ได้ entitlements สิทธิ์สูง** (ไม่มี no-sandbox) แอปจะเปิดได้แต่ Agent อ่านไฟล์ทั้งเครื่องไม่ได้ และหน้าตั้งค่าจะขึ้นเตือน

---

## การทดสอบอัตโนมัติ (รันได้โดยไม่ต้องมี Xcode)

โค้ดส่วนแกนกลาง (การรวม tool_calls delta, การถอดรหัส SSE, การซ่อม JSON, นโยบาย retry, payload encoding)
ถูกทดสอบด้วยการ **รันจริง** ทั้งแบบ unit test และแบบยิงเครือข่ายจริงกับเซิร์ฟเวอร์ OpenRouter จำลอง

```bash
bash verification/run-verification.sh        # unit 33 เคส (ตรวจ sha256 ของไฟล์ต้นฉบับก่อนรัน)
bash verification/e2e/run-e2e.sh             # E2E 26 ข้อ (SSE หั่นกลาง JSON / 429 retry / 404-401 ไม่ retry / GET /models)
python3 Scripts/audit-swift-symbols.py .     # ตรวจโครงสร้างและสัญลักษณ์ที่อ้างอิงผิด
bash Scripts/check-ios15-compat.sh .         # ห้ามใช้ API ของ iOS 16+
```

* `verification/Sources/OpenRouterCore/` เป็นไฟล์ที่สคริปต์คัดลอกจากต้นฉบับให้อัตโนมัติ — **ห้ามแก้ที่นั่น** ให้แก้ที่ `Models/`, `Services/` แล้วรันสคริปต์ใหม่
* ทั้งสองชุดรันใน CI ก่อนขั้น `xcodebuild` (ถ้าไม่ผ่านจะไม่เสียเวลา build)
* ผลการรันล่าสุดสรุปไว้ใน `VERIFICATION_REPORT_TH.md`

## วิธีทดสอบเฟส 1 (สั้น ๆ)

1. เปิดแอป → แท็บ **ตั้งค่า** → ใส่ API Key ของ OpenRouter (เก็บลง Keychain ทันที)
   * ถ้าแถวสถานะขึ้นว่า “เก็บแบบสำรองใน UserDefaults” แปลว่าแอปยังไม่มี entitlement ของ Keychain → ใช้ได้แต่ควรทราบว่าคีย์ไม่ได้เข้ารหัส
2. ช่อง **Model ID** กรอก `deepseek/deepseek-chat-v3-0324:free` หรือกด **โหลดรายการโมเดล** → ค้นหา → เลือก (ตัวกรอง “ฟรี / ใช้ tools ได้” เปิดไว้ให้แล้ว) → เลือกแล้วระบบทดสอบการเชื่อมต่อให้อัตโนมัติ
3. กด **ทดสอบการเชื่อมต่อ** แล้วตรวจว่าได้ข้อความ “เชื่อมต่อสำเร็จ” + “รองรับ tool calling: ใช่”
   * คีย์ผิด → ขึ้น 401 พร้อมบอกให้ไปแก้คีย์ (ไม่ลองซ้ำ)
   * โมเดลไม่มี/ไม่รองรับ tools → ขึ้น 404 พร้อมบอกให้เปลี่ยนโมเดล (ไม่ลองซ้ำ)
   * 429/502/503/เน็ตหลุด → เห็นข้อความ “กำลังลองใหม่ครั้งที่ 2/3 …” แล้วลองให้สูงสุด 3 ครั้งแบบ exponential backoff
4. ไปแท็บ **แชท** พิมพ์อะไรก็ได้ → ข้อความไหลมาแบบ streaming, แถบล่างขึ้น Token Usage (↑prompt ↓completion รวม) และชื่อโมเดล
5. ลองกด **หยุด** กลางการตอบ → คำขอถูกยกเลิกทันที (`Task.cancel`)
6. พิมพ์ข้อความยาว ๆ ในช่องพิมพ์ → ช่องขยายได้สูงสุด ~6 บรรทัด; กดค้างที่ bubble → คัดลอก/แชร์/ลบ
7. ปิด/เปิดแอป → จะเห็นแบนเนอร์เหลืองถ้าอ่าน `/var/mobile` ไม่ได้ (ต้อง TrollStore/palera1n) และปุ่มตรวจสิทธิ์ในหน้าตั้งค่าทำงานถูกต้อง

---

## หมายเหตุทางเทคนิคที่ตัดสินใจในเฟสนี้

* **งานที่ต้องแทน API ของ iOS 16** — `TextField(axis:.vertical)` → `MultilineInputField` (ห่อ `UITextView` คำนวณความสูงเอง), `View.fontWeight/.bold/.italic` → `Font.weight/.bold/.italic`, คงใช้ `NavigationView` + `.navigationViewStyle(.stack)` ทุกแท็บ
* **การส่งคำขอ** — ไม่ส่งฟิลด์ที่เป็น `null` (`tools`, `name`, `parallel_tool_calls` ฯลฯ) เพราะผู้ให้บริการโมเดลฟรีบางรายปฏิเสธคำขอ
* **tool_calls delta** — รวมชื่อ/arguments ตาม `index` ให้ครบก่อน parse; ถ้า stream ถูกตัดกลางทางจะซ่อม JSON ให้อัตโนมัติ (ปิดวงเล็บที่ขาด/ตัด comma เกิน) และขึ้นข้อความแจ้งในแชท
* **Token Usage** — OpenRouter ส่ง `usage` มาใน chunk สุดท้ายของสตรีมให้อยู่แล้ว จึงไม่ต้องส่งพารามิเตอร์ที่เลิกใช้แล้ว; ตัวนับรวมทุกคำขอในเซสชัน
* **หน่วยความจำ** (เครื่อง RAM 2GB) — `URLSessionConfiguration.ephemeral` ต่อคำขอ, จำกัดขนาดบรรทัด SSE ที่ 512KB, ตัดข้อความที่แสดงใน bubble, ใช้ `LazyVStack`
* **ATS/HTTP** — เฟสนี้ยังบังคับ HTTPS ตามค่าเริ่มต้นของ iOS; ในเฟส 2 (tool `http_request`) ต้องเลือกว่าจะเปิด `NSAllowsArbitraryLoads` เพื่อยิง HTTP ได้พร้อมคำเตือน หรือบังคับ HTTPS ล้วน — รอสรุปจากคุณ
* **Entitlements** — อธิบายความหมายของทั้ง 5 คีย์ไว้ในคอมเมนต์ของ `Entitlements/iOSAgentSandbox.entitlements` แล้ว (พร้อมระบุว่าคีย์ไหนจำเป็นเฉพาะ TrollStore และวิธีเพิ่มคีย์ของ Keychain ถ้าต้องการ)

## ข้อจำกัดที่ยังเหลือ (จะปิดในเฟสถัดไป)

* ยังไม่มีการบันทึกประวัติแชทลงเครื่อง (ปุ่มล้างแชทเพียงล้างในหน่วยความจำ) — เฟส 2
* ยังไม่มี tools/การอนุมัติคำสั่ง — เฟส 2
* แท็บ ไฟล์ / บันทึก ยังเป็นหน้าจออธิบาย — เฟส 3–4
* ยังไม่มี Onboarding, แนบไฟล์/รูป, หลายห้องสนทนา, ธีม/ขนาดตัวอักษร — เฟส 5
