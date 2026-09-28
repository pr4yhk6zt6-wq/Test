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
| **1** | Settings + OpenRouterService (Keychain, Model ID, streaming SSE, รวม tool_calls delta, retry/error handling, Token Usage) | ✅ เสร็จ + ทดสอบบนเครื่องผู้ใช้แล้ว |
| **2** | AgentEngine (ReAct loop) + Tools 9 ตัว + โหมดขออนุมัติ + ประวัติแชท JSON | ✅ เสร็จ + ผ่าน unit 141/141, E2E 99/99 |
| **3** | ShellService (`posix_spawn`) + FileSystemService + entitlements/ldid | ✅ เสร็จ (ยืนยันบนเครื่องผู้ใช้ + entitlements ครบ 5 คีย์ในไบนารี) |
| **4** | ChatView/FileBrowserView/AgentLogView ฉบับเต็ม + background task + แก้บั๊กที่ผู้ใช้รายงาน 2 จุด | ✅ เสร็จในบิลด์นี้ |
| 5 | แนบไฟล์/รูป, Markdown + code block, หลายห้องสนทนา, UX ครบ | ⏳ รอเริ่ม |

> ทุกแท็บทำงานจริงแล้ว: แชท (Agent + อนุมัติทีละครั้ง) • ไฟล์ (เริ่มที่ `/var/mobile`) • บันทึกการเรียก tool • ตั้งค่า
> บิลด์นี้แก้ 2 บั๊กที่เจอบนเครื่องจริง: (1) ต้องถามอนุมัติ **ทุกครั้ง** แม้เพิ่งกดไม่อนุมัติไป (2) บับเบิลหมุนค้างหลังคำตอบจบถูกเก็บกวาด

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
bash verification/run-verification.sh        # unit 167 เคส (ตรวจ sha256 ของไฟล์ต้นฉบับก่อนรัน)
bash verification/e2e/run-e2e.sh             # E2E 101 ข้อ (SSE หั่นกลาง JSON / ReAct + tools จริง / posix_spawn / entitlements / อนุมัติทุกครั้ง / ทำความสะอาดคีย์)
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

## วิธีทดสอบเฟส 3 + 4 (สั้น ๆ)

1. **ตั้งค่า → Agent** — เปิด “ขออนุมัติก่อนทำสิ่งที่เปลี่ยนเครื่อง” (ค่าเริ่มต้นเปิด) และ “อนุญาตให้ใช้ internet”
2. **ตั้งค่า → สิทธิ์ของแอป (เฟส 3)** — ดูรายการตรวจ 8 ข้อ: uid, shell ที่ใช้จริง, อ่าน/เขียน `/var/mobile`, ฟังก์ชัน persona, entitlements ที่ฝังในไบนารี
   * กด “คำอธิบาย entitlements ทั้ง 5 คีย์” → กดแต่ละคีย์เพื่ออ่านว่าเปิดอะไรให้แอป และถ้าไม่มีจะเป็นอย่างไร
   * ปุ่ม “บันทึกไฟล์ .entitlements ลงโฟลเดอร์ทำงาน” เขียนไฟล์ที่ใช้กับ `ldid` ได้ทันที
3. **แชท** — พิมพ์ “อ่านไฟล์ใน /var/mobile แล้วสรุปให้ฟัง” → จะเห็นสถานะ “กำลังใช้ tool: read_file” แล้วได้คำตอบ
   * ถ้าเปิดโหมดอนุมัติ จะมีหน้าต่างถามก่อนรัน `execute_shell` — กด “อนุญาตครั้งนี้” เพื่อทำงานต่อ
4. **ลองสั่ง shell** — “รันคำสั่ง `id` แล้วบอกว่าเป็น user ไหน” → ผลลัพธ์ของการ์ด tool จะบอกท้ายว่า “รันในนาม: …” เสมอ (ผู้ใช้ปัจจุบัน หรือ root ผ่าน persona)
5. **หยุดงาน** — สั่งงานยาว ๆ เช่น “ค้นหาไฟล์ชื่อ .plist ทั้งเครื่อง” แล้วกด **หยุด** → คำสั่ง shell ที่ค้างอยู่ถูกฆ่าทันที (SIGKILL) และรายงานว่าถูกยกเลิก
6. **ประวัติแชท** — ปิด/เปิดแอป → ประวัติยังอยู่ (บันทึกเป็น JSON ใน Documents) และกดปุ่มล้างแชทเพื่อลบได้

### สิ่งที่เพิ่มในเฟส 4

7. **อนุมัติทุกครั้ง (บั๊กที่แก้)** — สั่งงานที่ต้องอนุมัติ เช่น “รันคำสั่ง `echo 1`” แล้วกด **ไม่อนุมัติ** → สั่งงานเดิมอีกครั้ง
   * ต้องมีหน้าต่างขออนุมัติเด้งขึ้นใหม่ **ทุกครั้ง** (ไม่มีปุ่ม “อนุญาตตลอดเซสชัน” อีกแล้ว — การอนุญาตมีผลครั้งเดียว)
   * ถ้าอนุมัติครั้งที่สอง ต้องรันจริงและได้ผลลัพธ์ (การไม่อนุมัติครั้งก่อนไม่ปิดกั้นงานถัดไป)
8. **สปินเนอร์ค้าง (บั๊กที่แก้)** — เมื่อคำตอบจบหรือกด **หยุด** ระหว่างที่ Agent กำลังเรียก tool
   * กล่อง “…” ที่หมุนอยู่ต้องหายไป (ไม่มีบับเบิลว่างค้าง) และแถบสถานะ “กำลังคิด…” ต้องหายด้วย
9. **แท็บไฟล์** — เปิดมาจะอยู่ที่ `/var/mobile` → แตะโฟลเดอร์เพื่อเข้าไปต่อ, แตะไฟล์เพื่อดูเนื้อหา (ข้อความ/รูป/hex) + ข้อมูลไฟล์ (ขนาด/วันที่/สิทธิ์/symlink)
   * ปุ่มทางขวาบน: อ่านใหม่ • แสดงไฟล์ที่ซ่อน • คัดลอก path • ไปยัง path ที่ใช้บ่อย
10. **แท็บบันทึก** — ทุกครั้งที่ Agent เรียก tool จะมีรายการ: ชื่อไทย + ชื่อ tool + arguments + เวลา + ระยะเวลา + สถานะ
   * แตะรายการ → ดู arguments/ผลลัพธ์เต็ม + คัดลอก/แชร์ ; เมนูมุมขวาบน: คัดลอกทั้งหมด / ล้างบันทึก ; มีช่องค้นหา
11. **ทำงานเบื้องหลัง** — ระหว่างที่ Agent ทำงาน จะมีป้าย “ทำงานเบื้องหลัง” ในแถบสถานะ (ขอเวลาเพิ่มจากระบบด้วย `beginBackgroundTask`)

---

## หมายเหตุทางเทคนิคที่ตัดสินใจในเฟสนี้

* **งานที่ต้องแทน API ของ iOS 16** — `TextField(axis:.vertical)` → `MultilineInputField` (ห่อ `UITextView` คำนวณความสูงเอง), `View.fontWeight/.bold/.italic` → `Font.weight/.bold/.italic`, คงใช้ `NavigationView` + `.navigationViewStyle(.stack)` ทุกแท็บ
* **การส่งคำขอ** — ไม่ส่งฟิลด์ที่เป็น `null` (`tools`, `name`, `parallel_tool_calls` ฯลฯ) เพราะผู้ให้บริการโมเดลฟรีบางรายปฏิเสธคำขอ
* **tool_calls delta** — รวมชื่อ/arguments ตาม `index` ให้ครบก่อน parse; ถ้า stream ถูกตัดกลางทางจะซ่อม JSON ให้อัตโนมัติ (ปิดวงเล็บที่ขาด/ตัด comma เกิน) และขึ้นข้อความแจ้งในแชท
* **Token Usage** — OpenRouter ส่ง `usage` มาใน chunk สุดท้ายของสตรีมให้อยู่แล้ว จึงไม่ต้องส่งพารามิเตอร์ที่เลิกใช้แล้ว; ตัวนับรวมทุกคำขอในเซสชัน
* **หน่วยความจำ** (เครื่อง RAM 2GB) — `URLSessionConfiguration.ephemeral` ต่อคำขอ, จำกัดขนาดบรรทัด SSE ที่ 512KB, ตัดข้อความที่แสดงใน bubble, ใช้ `LazyVStack`
* **ATS/HTTP** — บังคับ HTTPS ล้วนในทุก tool เครือข่าย (ตามข้อกำหนดความปลอดภัย) ยกเว้น `http://127.0.0.1` และ `localhost` ที่อนุญาตไว้ให้ทดสอบกับเซิร์ฟเวอร์ในเครื่องเท่านั้น
* **การรันคำสั่งเป็น root (เฟส 3)** — ใช้ `posix_spawnattr_set_persona_np/_uid_np/_gid_np` ผ่าน `dlsym` (ไม่ผูกกับ header ของ SDK) ถ้าสลับ persona ไม่สำเร็จจะถอยไปรันในนามผู้ใช้ปัจจุบันพร้อมรายงานเหตุผลให้ผู้ใช้เห็น — ไม่ทำให้ทั้งคำสั่งล้มเหลว
* **การตรวจจับการยกเลิก shell** — ไม่ใช้ `Task.isCancelled` (ไม่ทำงานในคิว `DispatchQueue`) แต่ใช้ธง `cancellationRequested` ที่ป้องกันด้วย `NSLock` และตั้งค่าก่อนฆ่าโปรเซส จึงรายงาน `wasCancelled` ได้จริง
* **ชั้นไฟล์เดียวทั้งแอป (เฟส 3)** — tools ฝั่งไฟล์และหน้าจอเบราว์เซอร์ไฟล์ (เฟส 4) ใช้ `FileSystemService` ร่วมกัน ทำให้ข้อความ error เป็นภาษาไทยที่บอกสาเหตุจริง และเพดานขนาด/RAM ถูกบังคับที่จุดเดียว
* **การฆ่าคำสั่งที่ค้างเมื่อกดหยุด (เฟส 4)** — ตั้ง `POSIX_SPAWN_SETPGROUP` ให้โปรเซสลูกเป็นหัวหน้ากลุ่มของตัวเอง แล้วยิง `kill(-pid, SIGKILL)`
  ตอนกดหยุด/หมดเวลา จึงไม่เหลือคำสั่งลูก (เช่น `sleep`) ทำงานต่อเบื้องหลัง — E2E วัดเวลาว่าหยุดได้ภายใน 2 วินาที
* **การขออนุมัติ (เฟส 4)** — engine ไม่จำคำตอบข้ามครั้งอีกแล้ว: เรียกใหม่ = ถามใหม่เสมอ และมีเทสต์ E2E เฉพาะเรื่องนี้ (deny แล้วครั้งต่อไปยังถามและยังทำงานได้)
* **Entitlements** — อธิบายความหมายของทั้ง 5 คีย์ไว้ในคอมเมนต์ของ `Entitlements/iOSAgentSandbox.entitlements` แล้ว (พร้อมระบุว่าคีย์ไหนจำเป็นเฉพาะ TrollStore และวิธีเพิ่มคีย์ของ Keychain ถ้าต้องการ)

## ถ้าเชื่อมต่อไม่ได้ (401) — เช็กลิสต์

1. **กด “ลบ API Key” ก่อน แล้วค่อยวางคีย์ใหม่** — บิลด์ก่อนหน้านี้ถ้าที่เก็บสำรองมีคีย์เก่าค้างอยู่ คีย์เก่าจะถูกอ่านทับคีย์ใหม่ ทำให้สร้างคีย์ใหม่แล้วยังได้ 401 ตลอด (บิลด์นี้แก้แล้ว: คีย์ใน Keychain ชนะเสมอ + ล้างคีย์เก่าทิ้งให้)
2. ดูบรรทัด **“คีย์ที่ใช้อยู่”** ในแท็บตั้งค่า — ต้องตรงกับคีย์ในหน้า openrouter.ai/keys (ขึ้นต้น `sk-or-`, ความยาวตามที่เว็บแสดง)
3. กด **ทดสอบการเชื่อมต่อ** — บิลด์นี้จะบันทึกคีย์ที่พิมพ์ค้างไว้ก่อนทดสอบ และบอก “คีย์ที่ส่งไป” กับ “ที่เก็บ” ให้ด้วย
4. เจอ `401 – User not found.` = คีย์ที่ส่งไปไม่มีผู้ใช้จริง (คีย์ผิด/ถูกยกเลิก/คัดลอกไม่ครบ) — ไม่ใช่ปัญหาสิทธิ์ของแอป
5. เจอ `404` = โมเดลไม่มีหรือไม่รองรับ tool calling → เปลี่ยนเป็นโมเดลที่ขึ้นป้าย “ใช้ tools ได้”

## ข้อจำกัดที่ยังเหลือ (จะปิดในเฟสถัดไป)

* ยังไม่มี Onboarding, แนบไฟล์/รูป, หลายห้องสนทนา, ธีม/ขนาดตัวอักษร, การแก้ไฟล์ในแอป — เฟส 5
* การรันเป็น root ต้องติดตั้งผ่าน TrollStore (หรือรันแบบ rootful ด้วย palera1n) เท่านั้น — ถ้าติดตั้งด้วย Sideloadly จะได้แค่สิทธิ์ผู้ใช้ปัจจุบัน
