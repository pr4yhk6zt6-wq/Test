# รายงานผล: จำลองและรันทดสอบโค้ดเฟส 1 ในแซนด์บล็อก

> คำตอบตรง ๆ ข้อแรก: **ไฟล์ `.ipa` ที่ติดตั้งบน iPhone ยังต้อง build บน macOS** — เครื่องที่ผมรันอยู่เป็น Linux
> ไม่มี Xcode/iOS SDK จึงคอมไพล์แอป iOS ให้ไม่ได้จริง (ไฟล์ .ipa ที่ทำจาก Linux จะติดตั้งไม่ผ่าน)
> แต่ผมทำสิ่งที่ทำได้ในแซนด์บล็อกจนสุดทางแล้ว: **ติดตั้ง Swift toolchain และรันโค้ดจริงของโปรเจกต์**
> ทั้ง unit test และการยิงเครือข่ายจริงกับเซิร์ฟเวอร์ OpenRouter จำลอง — ผลอยู่ด้านล่างนี้ครับ

---

## 1) สรุปผลการรันจริงในแซนด์บล็อก

| ชุดทดสอบ | วิธีรัน | ผล |
|---|---|---|
| **Unit test แกนกลาง** (33 เคส) | `bash verification/run-verification.sh` | ✅ **33 / 33 ผ่าน** |
| **E2E ยิงเครือข่ายจริง** (26 ข้อ) | `bash verification/e2e/run-e2e.sh` | ✅ **26 / 26 ผ่าน** |
| ตรวจโครงสร้างโค้ด | `python3 Scripts/audit-swift-symbols.py .` | ✅ ผ่าน (26 ไฟล์ Swift) |
| ตรวจห้ามใช้ API ของ iOS 16+ | `bash Scripts/check-ios15-compat.sh .` | ✅ ผ่าน |

ทั้งหมดรันบน **ไฟล์ต้นฉบับของแอปจริง** โดยสคริปต์จะคัดลอกไฟล์มาแล้ว **ยืนยัน sha256 ว่าตรงกับต้นฉบับ 100%**
ก่อนทดสอบ (กันปัญหาทดสอบโค้ดคนละชุด) — ครอบคลุม `Models/*.swift`, `Services/OpenRouterCore.swift`, `Services/OpenRouterService.swift`

## 2) สภาพแวดล้อมที่ใช้จำลอง

| รายการ | ค่า |
|---|---|
| ระบบ | Debian GNU/Linux 13 (trixie), x86_64 |
| Swift | **Swift 6.1 (swift-6.1-RELEASE)** ติดตั้งที่ `~/.local/swift` |
| RAM / ดิสก์ | 2 GB / 20 GB ว่าง |
| เซิร์ฟเวอร์จำลอง | `verification/e2e/mock_openrouter_server.py` (Python, chunked SSE ผ่าน TCP จริง) |

> หมายเหตุ: Apple ไม่ได้แจก iOS SDK บน Linux และผมไม่ใช้มิเรอร์ SDK เถื่อน — จึงจำลองเท่าที่ทำได้อย่างถูกต้อง

## 3) สิ่งที่พิสูจน์ด้วยการรันจริง (Unit — 33 เคส)

| กลุ่ม | จำนวน | ตัวอย่างสิ่งที่ยืนยัน |
|---|---|---|
| `ToolCallAccumulatorTests` | 6 | merge arguments ที่หั่นเป็น 4 chunk ตาม `index` ได้ครบ, parallel tool calls 2 ตัวสลับ chunk, delta ที่ไม่มี `index`, ชื่อฟังก์ชันที่ถูกหั่น 2 chunk, สร้าง id ชั่วคราวเมื่อไม่มี id, ข้าม call ที่ไม่มีชื่อ |
| `ToolArgumentsSanitizerTests` | 8 | ซ่อม JSON ที่ถูกตัดกลางสตริง/กลางออบเจกต์ซ้อน/กลางคีย์ (เคสใหม่), ท้ายด้วย `,` หรือ `:`, escaped quote ไม่ทำให้ซ่อมเพี้ยน, arguments ว่าง/ไม่ใช่ออบเจกต์/แยกไม่ออก → คืน `{}` พร้อมเหตุผล ไม่ throw |
| `SSEDecoderTests` | 8 | ลำดับ text delta, ข้าม `: OPENROUTER PROCESSING` และบรรทัด JSON เสีย, อ่าน `usage` ครบทั้ง cost + cached_tokens, **tool_calls ถูกปล่อยก่อน `finished` เสมอ**, stream ที่ถูกตัดกลางทางยังปล่อย tool call ครบ, ไม่ปล่อยซ้ำสองครั้ง, แยก `reasoning` ออกจาก `content`, error chunk → notice |
| `ErrorAndRetryTests` | 5 | 401 → ไม่ retry + ชี้ให้แก้ API Key, 404 → ไม่ retry + ชี้ให้เปลี่ยนโมเดล, 429/502/503/เน็ตหลุด → retry ได้, 400/402/cancel → ไม่ retry, backoff 1s→2s→4s→8s (cap) + jitter ≤ 0.25s, `maxAttempts = 3` |
| `JSONAndPayloadTests` | 6 | round-trip ของทุกชนิด JSON, assistant ที่มีแต่ tool_calls ส่ง `content: null` ตามสเปก, tool result มี `tool_call_id`, ฟิลด์ที่เป็น nil ไม่ถูกส่ง, คำนวณ total tokens เมื่อ API ไม่ส่งมา, JSON Schema ของ tool ถูกต้อง |

## 4) สิ่งที่พิสูจน์ด้วยการยิงเครือข่ายจริง (E2E — 26 ข้อ)

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

## 5) บั๊กที่เจอเพราะการรันในแซนด์บล็อก (แก้แล้วทั้งหมด)

| # | บั๊ก | ผลถ้าไม่เจอ | สถานะ |
|---|---|---|---|
| 1 | `case array(...)` กับ `static func array(...)` **ซ้ำ signature** ใน `JSONValue.swift` → `error: invalid redeclaration of 'array'` | **Xcode build ไม่ผ่านทั้งโปรเจกต์** (คือสาเหตุที่จะทำให้ CI แดงตั้งแต่รอบแรก) | ✅ ลบ helper ที่ซ้ำออก ใช้ `.array([...])` ตรง ๆ |
| 2 | `JSONValue` ไม่มี `subscript(index:)` | เทสต์/โค้ดเฟส 2 ที่อ่าน element ในอาร์เรย์ (arguments ของ tool) คอมไพล์ไม่ผ่าน | ✅ เพิ่ม subscript แบบปลอดภัย (คืน `nil` เมื่อเกินขอบ) |
| 3 | `ToolArgumentsSanitizer.repair()` ซ่อม JSON ที่ถูกตัด **กลางคีย์** (`{"a":1,"b":`) ไม่ได้ → คืน `{}` **ทิ้งค่าที่อ่านมาแล้วทั้งหมด** | เวลาสตรีมถูกตัดกลางทาง (เกิดจริงบ่อยกับโมเดลฟรี) tool call จะได้ arguments ว่าง → Agent ทำงานผิดโดยไม่รู้สาเหตุ | ✅ เขียน `repair()` ใหม่ 3 ขั้น (ตัดอักขระเกินท้าย → ปิดโครงสร้างที่ขาด → ตัดสมาชิกท้ายที่ค้าง) + เพิ่มเทสต์กันถอยหลัง 3 เคส |
| 4 | (ไม่ใช่บั๊กแอป) fixture ในไฟล์เทสต์ escaping กำกวม ทำให้ผลทดสอบหลอก | — | ✅ เปลี่ยนเป็น raw string `#"..."#` เห็นไบต์จริงบนสายตรง ๆ |

## 6) สิ่งที่เพิ่มเข้าโค้ดแอปเพื่อให้ทดสอบได้ (ปลอดภัยบน iOS ทั้งหมด)

* `import FoundationNetworking` แบบมีเงื่อนไข — มีผลเฉพาะ Linux ไม่กระทบ iOS
* `#if canImport(Darwin)` ครอบ `waitsForConnectivity` (corelibs-foundation เป็น get-only)
* พารามิเตอร์ `baseURLString:` (ค่าเริ่มต้น = `https://openrouter.ai/api/v1`) ให้ทุกเมธอด — ใช้ยิงเซิร์ฟเวอร์จำลองในการทดสอบ และยังเป็นประโยชน์จริงถ้าผู้ใช้ต่อผ่าน gateway/proxy ของตัวเอง

## 7) สิ่งที่ **ยังพิสูจน์ในแซนด์บล็อกนี้ไม่ได้** (ตรงไปตรงมา)

| ยังไม่ยืนยัน | เหตุผล | วิธีที่จะยืนยัน |
|---|---|---|
| คอมไพล์ทั้งแอป (SwiftUI/UIKit, 22 ไฟล์) | ต้องมี Xcode + iOS SDK | GitHub Actions (ผมใส่ unit+E2E เป็นขั้นบังคับก่อน `xcodebuild` แล้ว) |
| พฤติกรรม `URLSession.bytes(for:)` ของ Apple | Linux ใช้ shim (delegate) แทน — โค้ด *เหนือ* shim (ประกอบบรรทัด/ถอดรหัส SSE) เป็นไฟล์เดียวกันที่ทดสอบแล้ว | รันบนเครื่องจริง/CI iOS |
| entitlements `no-sandbox`, รันเป็น root ผ่าน persona API, Keychain บนอุปกรณ์ | ต้องรันบน iOS 15.8 ที่ปลดล็อก | ขั้นทดสอบ 8 ข้อท้าย `BUILD_IPA_TH.md` |
| การติดตั้งผ่าน TrollStore/palera1n | ต้องมีเครื่องจริง | — |
| **ไฟล์ `.ipa`** | ต้อง build บน macOS | `BUILD_IPA_TH.md` (push ครั้งเดียวได้ลิงก์โหลดถาวร) |

## 8) รันซ้ำเองได้ทุกเมื่อ (ไม่ต้องมี Xcode)

```bash
# ในโฟลเดอร์โปรเจกต์ (ต้องมี swift; ถ้ามี ~/.local/swift สคริปต์จะใช้ให้เอง)
bash verification/run-verification.sh        # unit 33 เคส — ตรวจ sha256 ไฟล์ต้นฉบับก่อนรัน
bash verification/e2e/run-e2e.sh             # E2E 26 ข้อ กับเซิร์ฟเวอร์จำลอง
python3 Scripts/audit-swift-symbols.py .     # ตรวจโครงสร้าง/สัญลักษณ์ที่อ้างอิงผิด
bash Scripts/check-ios15-compat.sh .         # ห้ามใช้ API ของ iOS 16+
```

ทั้งสองชุดถูกรวมเข้า GitHub Actions แล้ว (ขั้นที่ 4–5 ของ workflow) → ถ้าโค้ดพัง regression จะรู้ทันที **ก่อน** เสียเวลา build Xcode

## 9) สรุปสถานะส่งมอบ

* ✅ เฟส 1 ครบทุกไฟล์ + ผ่านการ **รันจริง** ในส่วนที่รันได้ (แกนหลักของ OpenRouter ทั้งก้อน)
* ✅ เจอและแก้บั๊กที่จะทำให้บิลด์แรกไม่ผ่าน 1 จุด (สำคัญมาก — ถ้าไม่รันในนี้ คุณจะเจอตอน CI แดง)
* ✅ เจอและแก้บั๊กพฤติกรรมจริง 1 จุด (repair JSON ที่ถูกตัดกลางคีย์)
* ⏳ `.ipa`: ต้อง build บน macOS → ทำตาม `BUILD_IPA_TH.md` (หรือมี Mac ใช้ `Scripts/build-local.sh`)
* ⏳ รอคำยืนยัน 3 เรื่องเดิม: (1) commit `.xcodeproj` ด้วยไหม (2) นโยบาย HTTP/ATS สำหรับเฟส 2 (3) เริ่มเฟส 2 ได้หรือยัง
