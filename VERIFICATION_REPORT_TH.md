# รายงานผล: จำลองและรันทดสอบโค้ดในแซนด์บล็อก (เฟส 1 + 2 + 3)

> อัปเดตล่าสุด: **ได้ไฟล์ `.ipa` จริงแล้ว** ผ่าน GitHub Actions (macos-15) — build ไม่ลงนาม → ldid เซ็น
> entitlements → แพ็กเป็น .ipa (ดูหัวข้อ 10) ส่วนด้านล่างคือผลการรันโค้ดจริงของโปรเจกต์ในแซนด์บล็อก
> ทั้ง unit test และการยิงเครือข่ายจริงกับเซิร์ฟเวอร์ OpenRouter จำลอง
>
> **เฟส 3 เพิ่มการทดสอบที่รัน “โค้ด Darwin จริง”**: unit/E2E ที่รันบน macOS runner จะคอมไพล์สาขา
> `#if canImport(Darwin)` ของ `ShellService` จริง ทำให้ posix_spawn, persona fallback, timeout และการฆ่าโปรเซส
> ถูกทดสอบด้วยโค้ดเส้นทางเดียวกับที่รันบน iPhone

---

## 1) สรุปผลการรันจริงในแซนด์บล็อก

| ชุดทดสอบ | วิธีรัน | ผล |
|---|---|---|
| **Unit test แกนกลางเฟส 1+2+3** (141 เคส) | `bash verification/run-verification.sh` | ✅ **141 / 141 ผ่าน** |
| **E2E ยิงเครือข่ายจริง + รัน shell จริง** (92 ข้อ) | `bash verification/e2e/run-e2e.sh` | ✅ **92 / 92 ผ่าน** |
| ตรวจโครงสร้างโค้ด | `python3 Scripts/audit-swift-symbols.py .` | ✅ ผ่าน (50 ไฟล์ Swift, 128 ชนิด) |
| ตรวจห้ามใช้ API ของ iOS 16+ | `bash Scripts/check-ios15-compat.sh .` | ✅ ผ่าน (53 ไฟล์) |
| ตรวจก่อน push | `python3 Scripts/preflight.py .` | ✅ ผ่านทุกข้อ (10 การตรวจ) |

ทั้งหมดรันบน **ไฟล์ต้นฉบับของแอปจริง** โดยสคริปต์จะคัดลอกไฟล์มาแล้ว **ยืนยัน sha256 ว่าตรงกับต้นฉบับ 100%**
ก่อนทดสอบ (กันปัญหาทดสอบโค้ดคนละชุด)

**เฟส 1** ครอบคลุม `Models/*.swift`, `Services/OpenRouterCore.swift`, `Services/OpenRouterService.swift`
**เฟส 2** ครอบคลุม `Services/AgentEngine.swift`, `Services/ShellService.swift`, `Services/Tools/*.swift` ทั้ง 15 ไฟล์
(อ่าน arguments, ตรวจ path, ประเมินความเสี่ยงคำสั่ง, จำกัดผลลัพธ์ 10,000 ตัวอักษร, glob, HTML→ข้อความ,
DuckDuckGo, นโยบายเครือข่าย และการตัด context ที่ 80%)

**เฟส 3** ครอบคลุม `Services/Tools/PrivilegePolicy.swift`, `Services/FileSystemService.swift`,
`Services/EntitlementProbe.swift`, `Services/ShellService.swift` (persona + การยกเลิก), `Services/PrivilegeService.swift`
(นโยบายสิทธิ์, ลำดับการหา shell, การสร้าง/ตรวจไฟล์ entitlements, ชั้นไฟล์, ตัวสแกน entitlements, รายงานสิทธิ์ที่ผู้ใช้เห็น)

## 2) สภาพแวดล้อมที่ใช้จำลอง

| รายการ | ค่า |
|---|---|
| ระบบ | Debian GNU/Linux 13 (trixie), x86_64 |
| Swift | **Swift 6.1 (swift-6.1-RELEASE)** ติดตั้งที่ `~/.local/swift` |
| RAM / ดิสก์ | 2 GB / 20 GB ว่าง |
| เซิร์ฟเวอร์จำลอง | `verification/e2e/mock_openrouter_server.py` (Python, chunked SSE ผ่าน TCP จริง) |

> หมายเหตุ: Apple ไม่ได้แจก iOS SDK บน Linux และผมไม่ใช้มิเรอร์ SDK เถื่อน — จึงจำลองเท่าที่ทำได้อย่างถูกต้อง

## 3) สิ่งที่พิสูจน์ด้วยการรันจริง (Unit — 141 เคส)

| กลุ่ม | จำนวน | ตัวอย่างสิ่งที่ยืนยัน |
|---|---|---|
| `ToolCallAccumulatorTests` | 6 | merge arguments ที่หั่นเป็น 4 chunk ตาม `index` ได้ครบ, parallel tool calls 2 ตัวสลับ chunk, delta ที่ไม่มี `index`, ชื่อฟังก์ชันที่ถูกหั่น 2 chunk, สร้าง id ชั่วคราวเมื่อไม่มี id, ข้าม call ที่ไม่มีชื่อ |
| `ToolArgumentsSanitizerTests` | 8 | ซ่อม JSON ที่ถูกตัดกลางสตริง/กลางออบเจกต์ซ้อน/กลางคีย์ (เคสใหม่), ท้ายด้วย `,` หรือ `:`, escaped quote ไม่ทำให้ซ่อมเพี้ยน, arguments ว่าง/ไม่ใช่ออบเจกต์/แยกไม่ออก → คืน `{}` พร้อมเหตุผล ไม่ throw |
| `SSEDecoderTests` | 8 | ลำดับ text delta, ข้าม `: OPENROUTER PROCESSING` และบรรทัด JSON เสีย, อ่าน `usage` ครบทั้ง cost + cached_tokens, **tool_calls ถูกปล่อยก่อน `finished` เสมอ**, stream ที่ถูกตัดกลางทางยังปล่อย tool call ครบ, ไม่ปล่อยซ้ำสองครั้ง, แยก `reasoning` ออกจาก `content`, error chunk → notice |
| `ErrorAndRetryTests` | 5 | 401 → ไม่ retry + ชี้ให้แก้ API Key, 404 → ไม่ retry + ชี้ให้เปลี่ยนโมเดล, 429/502/503/เน็ตหลุด → retry ได้, 400/402/cancel → ไม่ retry, backoff 1s→2s→4s→8s (cap) + jitter ≤ 0.25s, `maxAttempts = 3` |
| `JSONAndPayloadTests` | 6 | round-trip ของทุกชนิด JSON, assistant ที่มีแต่ tool_calls ส่ง `content: null` ตามสเปก, tool result มี `tool_call_id`, ฟิลด์ที่เป็น nil ไม่ถูกส่ง, คำนวณ total tokens เมื่อ API ไม่ส่งมา, JSON Schema ของ tool ถูกต้อง |
| ชุดเฟส 2 (8 คลาส: `Phase2ToolArgumentsTests` 10, `Phase2HTMLTests` 9, `Phase2NetworkPolicyTests` 9, `Phase2RiskyCommandTests` 9, `Phase2PathGuardTests` 8, `Phase2ContextTrimmerTests` 7, `Phase2GlobMatcherTests` 4, `Phase2ToolOutputLimiterTests` 4) | 60 | arguments ที่ผิดชนิด/ว่าง/ถูกตัดกลางทาง, การยุบ `..`/`~` ของ path, path ของระบบที่ต้องขออนุมัติ, การประเมินความเสี่ยงของคำสั่ง shell และการเขียนไฟล์, การตัดผลลัพธ์ที่ 10,000 ตัวอักษร, การจับคู่ glob, HTML→ข้อความ, ผลค้นหา DuckDuckGo (รวมลิงก์ `uddg`), นโยบาย HTTPS/internet/ Wi-Fi เท่านั้น/เพดานดาวน์โหลด, การตัด context ที่ 80% |
| `Phase3Tests` (เฟส 3) | 48 | **entitlements 5 คีย์** (ครบ/ค่า true-false/คำอธิบายไทยทุกรายการ) + ไฟล์ `.entitlements` ที่สร้างขึ้นต้อง parse กลับเป็น plist ได้ครบ, การเลือกโหมดรัน 4 กรณี, ลำดับ shell `/var/jb/bin/sh`→`/bin/sh`, `PATH`/`HOME` ของ root กับ mobile, การจำแนกชนิดการติดตั้ง, **FileSystemService** (เขียน/ต่อท้าย/สร้างโฟลเดอร์ย่อย/ลิสต์/สิทธิ์/ลบ/ย้าย/คัดลอก/พื้นที่ว่าง/ข้อความ error ไทย), กฎ RAM (อ่านไฟล์ 3MB โดยได้ไม่เกิน 4KB), **ShellService จริง** (stdout, stderr, exit code, working directory, timeout 1s แล้วฆ่าโปรเซส, คำสั่งว่าง), `ShellTool` ต้องรายงาน “รันในนาม:”, **EntitlementProbe** (ไฟล์ฝัง entitlements / คีย์ขาด / คีย์ตกขอบก้อน 256KB / ไฟล์หาย), **PrivilegeService** (ทดสอบเขียนจริง, รายงาน 8 ข้อ, ไฟล์ entitlements, แคช) |

## 4) สิ่งที่พิสูจน์ด้วยการยิงเครือข่ายจริง (E2E — 92 ข้อ)

ไคลเอนต์คือ `OpenRouterService.swift` ของแอป ยิงไปยังเซิร์ฟเวอร์จำลองที่ "โหด" กว่าของจริง
(ส่ง SSE แบบ chunked, **หั่นกลาง JSON**, แทรก keep-alive, ส่งบรรทัดเสีย, ตอบ 429/404/401/503):

| กลุ่ม | ผล |
|---|---|
| 1) สตรีมข้อความปกติ | ข้อความ 2 ท่อนประกอบถูกต้องข้าม TCP packet, `finish_reason = stop`, ไม่ล้มเพราะบรรทัดเสีย, `usage` (77/12/89) + `cost` มาครบ, ยิงคำขอครั้งเดียว |
| 2) tool_calls delta | ได้ tool call 1 รายการชื่อ `read_file`, **arguments ที่ถูกหั่น 4 chunk รวมได้และ parse เป็น `/var/mobile/Documents/report.txt`**, ปล่อยก่อน `finished`, `usage` ท้ายสตรีม (cached 64) มาถึง |
| 3) 429 → retry | ยิง 2 ครั้ง (ครั้งแรก 429 ครั้งที่สองสำเร็จ), มีข้อความ "กำลังลองใหม่" ให้ผู้ใช้, รอตาม backoff จริง ≥ 1 วินาที |
| 4) 404 | ยิง **ครั้งเดียว** (ไม่ retry) + ข้อความชี้ให้เปลี่ยนโมเดล |
| 5) 401 | ยิง **ครั้งเดียว** (ไม่ retry) + ข้อความชี้ให้ตรวจ API Key |
| 6) 503 ติดกัน | พยายาม **ครบ 3 ครั้งแล้วหยุด** (ไม่วนไม่จำกัด) |
| 7) `GET /models` | ได้ 3 โมเดล (ข้ามรายการที่เสียได้ ไม่ทำให้ทั้งลิสต์พัง), แยก "ฟรี / รองรับ tools / รับรูป" จากข้อมูลจริงของ API |
| 9) ReAct loop จริง (เฟส 2) | โมเดลขอ `read_file` → tool อ่านไฟล์จริงบนดิสก์ → ส่งผลกลับเป็น role `tool` → ได้คำตอบสุดท้าย (มี `tool_call_id` ตรงกัน) |
| 10) โหมดอนุมัติ + `execute_shell` | มีการขออนุมัติ 1 ครั้งพร้อม arguments จริง • อนุมัติ → คำสั่งรันจริงและได้ผลลัพธ์ • ไม่อนุมัติ → คำสั่งไม่ถูกรันและแจ้งโมเดล |
| 11) เพดาน 20 รอบ | ลูป ReAct หยุดที่ 20 รอบจริง (กันการวนไม่จบ) พร้อมข้อความหยุดที่ชัดเจน |
| 12) ปุ่มหยุด | ยกเลิกกลางทางแล้วหยุดยิงคำขอ (ไม่ครบ 20 รอบ) และรายงานว่าถูกยกเลิก |
| 13) **posix_spawn จริง (เฟส 3)** | รัน `echo` ได้ผลจริง, รายงาน shell ที่ใช้, รหัสออก, แยก stdout/stderr, `workingDirectory`, **timeout 1s แล้วฆ่าโปรเซสทันที**, **กดหยุด → โปรเซสถูกฆ่าและรายงาน `wasCancelled`**, ขอ root แล้วถอยกลับอัตโนมัติพร้อมเหตุผล |
| 14) **FileSystemService (เฟส 3)** | เขียน/อ่านส่วนต้น/ต่อท้าย/ลิสต์/ย้าย/ลบ บนดิสก์จริง + error ภาษาไทยที่บอกสาเหตุ |
| 15) **นโยบายสิทธิ์ + entitlements (เฟส 3)** | 5 คีย์/ค่าถูกต้อง, ลำดับ shell, โหมดการรัน 3 กรณี, ไฟล์ `.entitlements` ที่สร้างต้อง parse ได้, สแกน entitlements จากไฟล์ที่ฝังไว้เจอครบ 5 คีย์ + สแกนไบนารีของตัวเองต้อง **ไม่** รายงานผลบวกลวง |
| 16) **PrivilegeService (เฟส 3)** | รายงาน 8 ข้อ, คำแนะนำ, ข้อความสำหรับ System Prompt, เขียนไฟล์ entitlements, แคชไม่สแกนไบนารีซ้ำ |

## 5) บั๊กที่เจอเพราะการรันในแซนด์บล็อก (แก้แล้วทั้งหมด)

| # | บั๊ก | ผลถ้าไม่เจอ | สถานะ |
|---|---|---|---|
| 1 | `case array(...)` กับ `static func array(...)` **ซ้ำ signature** ใน `JSONValue.swift` → `error: invalid redeclaration of 'array'` | **Xcode build ไม่ผ่านทั้งโปรเจกต์** (คือสาเหตุที่จะทำให้ CI แดงตั้งแต่รอบแรก) | ✅ ลบ helper ที่ซ้ำออก ใช้ `.array([...])` ตรง ๆ |
| 2 | `JSONValue` ไม่มี `subscript(index:)` | เทสต์/โค้ดเฟส 2 ที่อ่าน element ในอาร์เรย์ (arguments ของ tool) คอมไพล์ไม่ผ่าน | ✅ เพิ่ม subscript แบบปลอดภัย (คืน `nil` เมื่อเกินขอบ) |
| 3 | `ToolArgumentsSanitizer.repair()` ซ่อม JSON ที่ถูกตัด **กลางคีย์** (`{"a":1,"b":`) ไม่ได้ → คืน `{}` **ทิ้งค่าที่อ่านมาแล้วทั้งหมด** | เวลาสตรีมถูกตัดกลางทาง (เกิดจริงบ่อยกับโมเดลฟรี) tool call จะได้ arguments ว่าง → Agent ทำงานผิดโดยไม่รู้สาเหตุ | ✅ เขียน `repair()` ใหม่ 3 ขั้น (ตัดอักขระเกินท้าย → ปิดโครงสร้างที่ขาด → ตัดสมาชิกท้ายที่ค้าง) + เพิ่มเทสต์กันถอยหลัง 3 เคส |
| 4 | (ไม่ใช่บั๊กแอป) fixture ในไฟล์เทสต์ escaping กำกวม ทำให้ผลทดสอบหลอก | — | ✅ เปลี่ยนเป็น raw string `#"..."#` เห็นไบต์จริงบนสายตรง ๆ |
| 5 | **เฟส 3:** `Task.isCancelled` ที่เรียกในบล็อกของ `DispatchQueue.global().async` **คืนค่า false เสมอ** → การกดหยุดระหว่างคำสั่ง shell ไม่ถูกรายงานว่าถูกยกเลิก | ปุ่ม “หยุด” ดูเหมือนทำงาน แต่ผลลัพธ์จะบอกว่าคำสั่งจบเอง — ผู้ใช้เข้าใจผิดว่าแอปค้าง | ✅ เปลี่ยนไปใช้ธง `cancellationRequested` ที่ป้องกันด้วย `NSLock` ตั้งค่าก่อน `kill` และเพิ่มเทสต์ E2E ที่ยืนยันว่ากดหยุดแล้วโปรเซสถูกฆ่าจริง |
| 6 | **เฟส 3:** คำไทย “รันในนาม” ถูกพิมพ์เป็นรูปที่มีอักษรละติน `r` ปน (mixed-script-allow) และใช้ `.fontWeight(...)` ซึ่งเป็น API ของ iOS 16 | ข้อความบนหน้าจอเพี้ยน และแอปจะไม่คอมไพล์บนเป้า iOS 15 | ✅ แก้ทั้งสองจุด + **เพิ่มตัวตรวจอัตโนมัติ 2 ตัว**: กฎห้าม `.fontWeight` (มีอยู่แล้ว) และตัวสแกน “อักษรละตินปนคำไทย” ใน `Scripts/preflight.py` |
| 7 | **เฟส 3 (CI จับ):** `posix_spawnattr_t` บน Darwin เป็น opaque pointer (`UnsafeMutableRawPointer`) ไม่ใช่ struct → โค้ดที่เขียนพอยน์เตอร์ซ้อนพอยน์เตอร์คอมไพล์ไม่ผ่านบน macOS/iOS | build บน CI แดงตั้งแต่รอบแรกที่เพิ่ม persona (เจอใน run 36419357769) | ✅ เขียนใหม่: ประกาศ `var attributes` แบบมีเงื่อนไขต่อแพลตฟอร์ม แล้วส่ง `&attributes` เข้า `posix_spawn` ตรง ๆ + ตั้ง persona ผ่าน `dlsym` แบบพอยน์เตอร์ชั้นเดียว |
| 8 | **เฟส 3 (CI จับ):** `ChatViewModel.makeConversationPayload()` เรียก `settings` ที่เป็นตัวแปร local ของเมธอด `send()` เท่านั้น → `cannot find 'settings' in scope` | build บน CI แดง (run 36419659402) | ✅ ใช้ `AppSettings.shared` ในเมธอดนั้นโดยตรง |

## 6) สิ่งที่เพิ่มเข้าโค้ดแอปเพื่อให้ทดสอบได้ (ปลอดภัยบน iOS ทั้งหมด)

* `import FoundationNetworking` แบบมีเงื่อนไข — มีผลเฉพาะ Linux ไม่กระทบ iOS
* `#if canImport(Darwin)` ครอบ `waitsForConnectivity` (corelibs-foundation เป็น get-only)
* พารามิเตอร์ `baseURLString:` (ค่าเริ่มต้น = `https://openrouter.ai/api/v1`) ให้ทุกเมธอด — ใช้ยิงเซิร์ฟเวอร์จำลองในการทดสอบ และยังเป็นประโยชน์จริงถ้าผู้ใช้ต่อผ่าน gateway/proxy ของตัวเอง

## 7) สิ่งที่ **ยังพิสูจน์ในแซนด์บล็อกนี้ไม่ได้** (ตรงไปตรงมา)

| ยังไม่ยืนยัน | เหตุผล | วิธีที่จะยืนยัน |
|---|---|---|
| คอมไพล์ทั้งแอป (SwiftUI/UIKit, 22 ไฟล์) | ต้องมี Xcode + iOS SDK | GitHub Actions (ผมใส่ unit+E2E เป็นขั้นบังคับก่อน `xcodebuild` แล้ว) |
| พฤติกรรม `URLSession.bytes(for:)` ของ Apple | Linux ใช้ shim (delegate) แทน — โค้ด *เหนือ* shim (ประกอบบรรทัด/ถอดรหัส SSE) เป็นไฟล์เดียวกันที่ทดสอบแล้ว | รันบนเครื่องจริง/CI iOS |
| การสลับ persona จริงบนอุปกรณ์ (รันเป็น root) | macOS/Linux ไม่มีฟังก์ชัน persona ของ XNU — ทดสอบได้แค่เส้นทางถอยกลับอัตโนมัติ | รัน `.ipa` บน iPhone ที่ติดตั้งผ่าน TrollStore แล้วดูหัวข้อ “สิทธิ์ของแอป” ในหน้าตั้งค่า |
| Keychain บนอุปกรณ์ (แอปที่ไม่ได้เซ็นด้วย Team ID) | ต้องรันบน iOS จริง — โค้ดมีที่เก็บสำรองใน UserDefaults พร้อมแจ้งเตือนผู้ใช้แล้ว | ทดสอบข้อ 1 ในขั้นตอนท้ายข้อ 10 |
| การอ่าน `/var/mobile` จริงบนเครื่องที่ปลดล็อก | Linux/CI ไม่มี path นี้ | ทดสอบบนเครื่องจริง (หน้าตั้งค่าจะขึ้นผล 8 ข้อ) |
| **ไฟล์ `.ipa`** | ✅ ได้แล้วจาก GitHub Actions | ดูหัวข้อ 10 |

## 8) รันซ้ำเองได้ทุกเมื่อ (ไม่ต้องมี Xcode)

```bash
# ในโฟลเดอร์โปรเจกต์ (ต้องมี swift; ถ้ามี ~/.local/swift สคริปต์จะใช้ให้เอง)
bash verification/run-verification.sh        # unit 141 เคส — ตรวจ sha256 ไฟล์ต้นฉบับก่อนรัน
bash verification/e2e/run-e2e.sh             # E2E 92 ข้อ กับเซิร์ฟเวอร์จำลอง (รวม posix_spawn จริง)
python3 Scripts/audit-swift-symbols.py .     # ตรวจโครงสร้าง/สัญลักษณ์ที่อ้างอิงผิด
bash Scripts/check-ios15-compat.sh .         # ห้ามใช้ API ของ iOS 16+
```

ทั้งสองชุดถูกรวมเข้า GitHub Actions แล้ว (ขั้นที่ 4–5 ของ workflow) → ถ้าโค้ดพัง regression จะรู้ทันที **ก่อน** เสียเวลา build Xcode

## 9) สรุปสถานะส่งมอบ

* ✅ **เฟส 1** — ตั้งค่า/โมเดล/สตรีม/retry/usage ครบ และถูกทดสอบด้วยการยิงเครือข่ายจริง
* ✅ **เฟส 2** — 9 tools + ReAct loop + โหมดอนุมัติ + ประวัติแชท (ทดสอบ E2E กับไฟล์และ shell จริงบนดิสก์)
* ✅ **เฟส 3** — รันเป็น root ผ่าน persona (พร้อมถอยกลับอัตโนมัติ), ชั้นไฟล์กลาง, ตัวสแกน entitlements, หน้าจอสิทธิ์ + คำอธิบาย 5 คีย์
* ✅ บั๊กที่เจอเพราะ “รันจริง” และแก้แล้ว 8 จุด: 4 จุดในเฟส 1, 2 จุดในเฟส 2 (Darwin `posix_spawn_file_actions_t`, `approvalBinding`),
  2 จุดในเฟส 3 ที่เจอในแซนด์บล็อก (การตรวจจับการยกเลิก shell ที่ใช้ `Task.isCancelled` ไม่ทำงานในคิว Dispatch → เปลี่ยนเป็นธงที่ป้องกันด้วย `NSLock`;
  อักษรละตินหลุดปนคำไทย + `.fontWeight` ของ iOS 16) และ 2 จุดที่ **CI จับได้** (ชนิดพอยน์เตอร์ของ `posix_spawnattr_t` บน Darwin, `settings` หลุด scope)
* ✅ ตรวจ entitlements ในไฟล์ `.ipa` ที่ส่งมอบจริงด้วยตัวสแกนของโปรเจกต์เอง — พบครบทั้ง 5 คีย์ในไบนารี (`<key>…</key>` ครบทุกตัว)
* ✅ เฟส 4 ส่งมอบในบิลด์นี้: FileBrowserView (เริ่มที่ `/var/mobile`), FilePreviewView, AgentLogView + บันทึกทุกการเรียก tool,
  EntitlementExplanationView ในหน้าตั้งค่า, การทำงานเบื้องหลัง, และ **แก้ 2 บั๊กที่คุณเจอบนเครื่อง** (ถามอนุมัติทุกครั้ง / สปินเนอร์ค้าง)
* ✅ เพิ่มเทสต์ E2E ชุดใหม่ (ข้อ 17) ที่พิสูจน์บั๊กการอนุมัติโดยตรง: กดไม่อนุมัติครั้งแรก → ครั้งที่สองต้องมีคำถามใหม่และคำสั่งต้องรันจริง
* ✅ **แก้บั๊กที่ 9 (401 “User not found.” ที่ผู้ใช้เจอ):** `KeychainHelper.string(for:)` เดิมอ่านที่เก็บสำรองก่อน
  ทำให้คีย์เก่าที่ค้างอยู่บดบังคีย์ใหม่ที่เพิ่งบันทึกได้ตลอดไป → เปลี่ยนเป็น "Keychain ชนะเสมอ" + ล้างคีย์เก่าที่ค้างทิ้งให้อัตโนมัติ,
  ตัดช่องว่าง/ขึ้นบรรทัดใหม่/อักขระล่องหน/เครื่องหมายคำพูดที่ติดมากับการคัดลอกก่อนเก็บและก่อนส่งทุกคำขอ,
  แสดง "คีย์ที่ใช้อยู่" (ไม่เปิดเผยคีย์เต็ม) ในหน้าตั้งค่า และแจ้ง "คีย์ที่ส่งไป/ที่เก็บ" ทุกครั้งที่ทดสอบการเชื่อมต่อไม่สำเร็จ
  (คุมด้วยเทสต์ unit 26 เคส + E2E 2 ข้อ)
* ✅ ปรับการยกเลิกคำสั่ง shell ให้ฆ่าทั้งกลุ่มโปรเซส (`POSIX_SPAWN_SETPGROUP` + `kill(-pid)`) — กดหยุดแล้วไม่มีคำสั่งลูกค้างต่อ (E2E วัดได้ < 2 วินาที)

## 10) สถานะการส่งมอบไฟล์ .ipa (อัปเดตล่าสุด — เฟส 4)

| รายการ | ค่า |
|---|---|
| ไฟล์ | `iOSAgentSandbox.ipa` (**เฟส 4** — มีครบทั้งเฟส 1 + 2 + 3 + 4) |
| ขนาด | 2,435,009 ไบต์ (2.4 MB) — ไบนารี 3,816,960 ไบต์ |
| sha256 | `7c06600b636d0e9faf21e3d2a8ded1059ddf1dd5fa735ef5b33df7278f370e76` |
| ลิงก์โหลดตรง | https://github.com/pr4yhk6zt6-wq/Test/releases/download/latest-build/iOSAgentSandbox.ipa |
| CI run | 36423199379 (commit 17c38dd) — **13/13 ขั้นตอนผ่าน** |
| MinimumOSVersion | 15.0 • UIDeviceFamily: iPhone เท่านั้น • bundle `com.example.iosagentsandbox` |
| เซ็นด้วย | `ldid -S` พร้อม entitlements 5 คีย์ — **ตรวจซ้ำในไบนารีที่ส่งมอบจริงแล้วพบครบทั้ง 5** (`platform-application`, `no-container`, `no-sandbox`, `persona-mgmt`, `container-required=false`) |
| ตรวจว่าโค้ดเฟส 4 อยู่ในบิลด์นี้ | พบ `FileBrowserView`, `FilePreviewView`, `AgentLogView`, `AgentLogStore`, `AgentLogEntry`, `EntitlementExplanationView` ในไบนารี + ข้อความหน้าต่างอนุมัติแบบใหม่ ("การอนุญาตมีผลเฉพาะครั้งนี้เท่านั้น") |
| ผลทดสอบบน runner (macOS) | unit **167/167** • E2E **101/101** (posix_spawn จริงบน Darwin + อนุมัติทุกครั้ง + ทำความสะอาดคีย์) • build ไม่ลงนามสำเร็จ • deployment target ผ่าน |

**เฟส 2–4 ที่อยู่ในไฟล์นี้:**
* **เฟส 2** — ReAct loop ไม่เกิน 20 รอบ, tools 9 ตัว (read_file, write_file, list_directory, search_files, execute_shell,
  http_request, download_file, web_search, fetch_webpage), เพดานเวลา 30 วินาที, ผลลัพธ์จำกัด 10,000 ตัวอักษร,
  สวิตช์อินเทอร์เน็ต/เฉพาะ Wi-Fi/เพดานดาวน์โหลด 200MB, ตัด context เมื่อใช้เกิน 80%, ประวัติแชทเป็น JSON
* **เฟส 3** — `posix_spawn` + persona 99 (root ผ่าน TrollStore) พร้อมถอยกลับอัตโนมัติ, `FileSystemService` ใช้ร่วมกันทั้งแอป,
  หน้าจอตรวจสิทธิ์ 8 ข้อ + คำอธิบาย entitlements ทั้ง 5 คีย์, เซ็นไบนารีด้วย `ldid -S`
* **เฟส 4** — แท็บ **ไฟล์** (เริ่มที่ `/var/mobile`, เข้าโฟลเดอร์, ดูข้อความ/รูป/hex), แท็บ **บันทึก** (ทุกการเรียก tool พร้อม arguments/ผลลัพธ์/เวลา),
  ทำงานเบื้องหลังด้วย `beginBackgroundTask`, **ถามอนุมัติทุกครั้ง** (ตัดปุ่ม "อนุญาตตลอดเซสชัน" ออก), เก็บกวาดบับเบิลหมุนค้างทุกกรณี,
  ฆ่าทั้งกลุ่มโปรเซสเมื่อกดหยุด (ไม่มีคำสั่งลูกค้างต่อ)
