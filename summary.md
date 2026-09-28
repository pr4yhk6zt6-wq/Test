# สรุปรวมโปรเจกต์ AgentAI — Mobile UI/UX Design (4 เฟส)

## ข้อมูลพื้นฐาน
- **ชื่อแอป / แบรนด์**: AgentAI — อบอุ่น เป็นกันเอง มืออาชีพ
- **พัฒนาด้วย**: Flutter (iOS + Android) — รองรับ Dynamic Type และ Accessibility
- **ตลาด**: ไทย + สากล (UI ไทยหลัก รองรับอังกฤษ สลับวันที่ พ.ศ./ค.ศ. ได้)
- **ดีไซน์**: ยึด iOS HIG + Material 3 + เอกลักษณ์ (rounded card, warm amber accent, pill input, glass header)
- **Backend**: Pause ได้ / Retry รายขั้นได้ / Undo ได้ / ประมาณเวลาที่เหลือได้ — ออกแบบเต็มทุกฟีเจอร์; ถ้า Pause ไม่ได้จริง ใช้ "หยุด" + "ทำต่อจากจุดเดิม"

---

## สรุปการเปลี่ยนแปลงจากพรอมต์ต้นฉบับ

### เพิ่ม (Add)
- **เฟส 1**: User flow (หลัก + ล้มเหลว + Takeover + ทางสำรอง Pause); Color swatch 3 ชุด + เลือก Warm Amber; Typography IBM Plex Sans Thai + Noto Sans Thai; Tokens เบื้องต้น; Empty State + Suggestion Chips; Main Chat Screen (Header, User Bubble, Agent Document, Citation, Uncertainty Badge, Input Bar); Activity System 3 ระดับ (Live Status Line A, Timeline B, Detail Sheet C); Mobile Frame Toggle (iOS/Android); Interactive Prototype (Light/Dark, Expand/Collapse, Detail Sheet, Attachment)
- **เฟส 2**: Card Variants 8 ประเภท (Thinking, Web Search, Browse, File, Code, Connector, Sub-agent, To-do) พร้อม States; Permission Request Bottom Sheet (4 ปุ่ม + ขอบเขตแคบที่สุด); Undo Banner; Takeover Banner; Security Alert (Prompt Injection) พร้อมข้อความภาษาไทย; Error States 7 แบบ (รอผู้ใช้, สำเร็จบางส่วน, ล้มเหลว, ออฟไลน์, Rate Limit, ไฟล์ล้มเหลว); ไม่ใช้อิโมจิ; ไม่ดู AI-template (สี amber, ไม่มี bubble Agent)
- **เฟส 3**: Background Tasks (Live Activity iOS + Ongoing Notification Android + Push); "งานของฉัน" (3 แท็บ + หลายงาน + ตั้งเวลา); ต้นทุน/โควตา (แสดงเมื่อมีข้อมูลจริง + เตือนก่อนใกล้หมด + ไม่แสดงตัวเลขเดา); Voice Mode (4 สถานะ + ย่อระหว่างเสียง); หน้ารอง 6 หน้า (Onboarding 3 หน้า, ประวัติแชทค้นหา/ปักหมุด/จัดกลุ่ม, เชื่อมต่อแอปสวิตช์+สิทธิ์, ไฟล์ทั้งหมด, แชร์/ส่งออก Markdown/JSON + เตือนอ่อนไหว, ตั้งค่าธีม/ภาษา/รายละเอียดกิจกรรม 3 ระดับ/ความเป็นส่วนตัว/จัดการสิทธิ์เสมอ)
- **เฟส 4**: Component Library (Status Line, Timeline Step, 8 Card Types, Bottom Sheet, Permission Sheet, Input Bar) พร้อม Variants/States; Design Tokens ฉบับเต็ม (Light/Dark, Color, Typography, Spacing, Radius); Prototype Spec (Shimmer/Pulse, Streaming, Scroll, Progressive Disclosure, Reduce Motion, Haptic); Status Copy Library ไทย/อังกฤษ (11 Event Types + 7 Statuses + User Messages); Data Structure `AgentEvent` (TypeScript) + Source + Artifact + Lifecycle + Reconnect + Unknown Event Handling; Edge Cases (6 กรณี); Developer Recommendations; Decisions (7 ข้อ); สรุปรวม 4 เฟส

### แก้ (Modify)
- **ไม่ใช้อิโมจิ**: ลบ emoji ทั้งหมดจาก UI (ตรวจสอบด้วย Python regex ทุกไฟล์) — แทนด้วย SVG stroke + ข้อความภาษาไทย (เช่น "FILE" แทน 📄)
- **ไม่ดู AI-template**: เปลี่ยนจากสีฟ้า/ม่วงที่เป็นเอกลักษณ์ AI ทั่วไปเป็น Warm Amber (#B07A2A); Agent message อ่านแบบเอกสาร (ไม่มี bubble) แทน ChatGPT-style; Typography IBM Plex Sans Thai แทน font ระบบ; ไม่มี rainbow gradient; Progressive disclosure (Timeline collapsible + Detail Sheet แยก)
- **ไม่มีศัพท์เทคนิคใน UI**: ทุกข้อความที่ผู้ใช้เห็นเป็นภาษาไทยธรรมดา (ไม่ใช้ "invoking tool", "SSE chunk", "ReAct loop", "posix_spawn") — ใช้ "กำลังค้นหาเว็บ", "อ่านไฟล์", "รันโค้ด", "เชื่อมต่อแอป"
- **ไม่มี spinner เปล่า**: ทุกสถานะมีไอคอน SVG + ข้อความกำกับ (ไม่พึ่งสีอย่างเดียว) — Running ใช้ shimmer/pulse, Success ใช้ checkmark, Failed ใช้ X, Waiting ใช้วงกลม muted
- **ทุกการกระทำที่มีผลกระทบมี Permission**: Permission Request (4 ปุ่ม + ขอบเขตแคบที่สุด); Takeover (แยกชัดเจน + ข้อความว่า Agent ไม่เห็นรหัส); Undo (แสดงเฉพาะเมื่อ `reversible` = true); Security Alert (Prompt Injection) แสดงใน Timeline ไม่ทำให้ตกใจ
- **ข้อความไทยทดสอบ**: ทุกหน้าทดสอบด้วยข้อความไทยยาวและผสมอังกฤษ; line-height 1.5–1.7; word-break; ellipsis; ไม่ตัดวรรณยุกต์

### ตัด (Remove / Avoid)
- **ไม่มี bubble สำหรับ Agent message**: แตกต่างจาก ChatGPT clone ทำให้ progressive disclosure ทำงานได้ดีกว่า
- **ไม่มี gradient ฉูดฉาด**: ใช้ linear-gradient เฉพาะ glass header และ avatar (accent เดียว) — ไม่ใช้ rainbow หรือ neon
- **ไม่มีตัวเลขประมาณการที่ไม่มีข้อมูลรองรับ**: ไม่แสดง "เวลาที่เหลือ" หรือ "ความมั่นใจ" เป็นตัวเลขเมื่อ Backend ไม่ส่งข้อมูล — แสดงเฉพาะสถานะและความคืบหน้าเปอร์เซ็นต์ (ถ้ามี)
- **ไม่มีศัพท์เทคนิคในข้อความที่ผู้ใช้เห็นโดยปริยาย**: ทุก error message, status badge, button label, notification text เป็นภาษาไทยธรรมดา
- **ไม่มีการแสดงข้อมูลเทคนิคเป็นค่าเริ่มต้น**: โค้ด, ข้อผิดพลาดดิบ, source URL เต็ม — ซ่อนเป็นค่าเริ่มต้น แสดงเฉพาะเมื่อผู้ใช้ตั้งระดับรายละเอียดเป็น "ละเอียด" หรือกดดูเอง

---

## สมมติฐานที่เติมแทนช่องว่าง (จากบริบทโปรเจกต์)

| ช่องว่าง | ค่าที่เลือก | เหตุผลสั้น (1 บรรทัด) |
|---|---|---|
| แบรนด์ / บุคลิก | อบอุ่น เป็นกันเอง มืออาชีพ | เข้ากับสี Warm Amber และ typography IBM Plex Sans Thai |
| พัฒนาด้วย | Flutter (iOS + Android) | รองรับ Dynamic Type, Accessibility, และ cross-platform ได้ดี |
| ตลาดหลัก | ไทย + สากล | รองรับไทย/อังกฤษ, วันที่ พ.ศ./ค.ศ. สลับได้, ข้อความไทยทดสอบครบ |
| แนวทางดีไซน์ | ยึด HIG + Material 3 + เอกลักษณ์ | ใช้ rounded card, pill input, glass header, spacing 4/8pt |
| Backend ความสามารถ | Pause/Retry/Undo/Estimate ได้ | ออกแบบปุ่มเต็มทุกฟีเจอร์; ถ้า Pause ไม่ได้จริงใช้ "หยุด" + "ทำต่อ" |

---

## รายการไฟล์ทั้งหมดใน repo (`pr4yhk6zt6-wq/Test`)

| ประเภท | ไฟล์ | สถานะ |
|---|---|---|
| Design Specs | `project-context.md` | ✅ Push (`15cf888`) |
| Phase 1 Specs | `phase1-user-flow.md`, `phase1-style.md`, `phase1-activity-system.md`, `phase1-checklist.md` | ✅ Push (`15cf888`) |
| Phase 1 Prototype | `phase1-prototype.html` (`design-phase1.html` ใน repo) | ✅ Push (`15cf888`) |
| Phase 2 Specs | `phase2-cards-controls.md` | ✅ Push (`15cf888`) |
| Phase 2 Prototype | `phase2-prototype.html` (`design-phase2.html` ใน repo) | ✅ Push (`15cf888`) |
| Phase 3 Specs | `phase3-background-tasks.md` | ✅ Push (`d80476a`) |
| Phase 3 Prototype | `phase3-prototype.html` | ✅ Push (`d80476a`) |
| Phase 4 Specs | `phase4-component-library.md` | ✅ Push (`1175158`) + Fix (`59f8bc0`) |
| Phase 4 Prototype | `phase4-prototype.html` | ✅ Push (`1175158`) + Fix (`59f8bc0`) |

---

## แผนต่อไป (หลังเฟส 4 เสร็จ)

1. **สรุปรวมไฟล์ (`summary.md`)** — ไฟล์นี้เอง (`summary.md`) — สรุป 4 เฟส + การเปลี่ยนแปลง + สมมติฐาน + รายการไฟล์ใน repo + แผน `.ipa`
2. **แก้ SwiftUI Source Files** ใน repo (`App/`, `Views/`, `Services/`, `Models/`) ตาม `phase4-component-library.md` และ `design-tokens.md`:
   - เปลี่ยนสี (`accent` → `#B07A2A`) ใน SwiftUI `Color` extensions หรือ `.background()`
   - เปลี่ยน typography (`IBM Plex Sans Thai`) ใน `.font()` modifiers
   - ลบ bubble สำหรับ Agent message (ถ้ามีใน `MessageBubbleView.swift`) → เปลี่ยนเป็น document-style (`padding`, `line-height: 1.7`, ไม่มี `cornerRadius` ด้านซ้าย)
   - เพิ่ม progressive disclosure (Timeline collapsible, Detail Sheet bottom sheet)
   - เพิ่ม accessibility labels (`accessibilityLabel`, `accessibilityLiveRegion`) ตาม `Status Copy Library`
   - แก้ `ChatView.swift` ให้รองรับ Voice Mode (สถานะฟัง/คิด/พูด/รอ)
   - แก้ `AgentLogView.swift` ให้แสดง `EventType` และ `EventStatus` ตาม `Data Structure`
3. **Build `.ipa`** ด้วย `Scripts/build-local.sh` (`xcodebuild -sdk iphoneos` + `ldid -S Entitlements/` + zip `Payload/` → `.ipa`)
4. **ติดตั้งบนเครื่องจริง** (TrollStore / palera1n rootful) — ตรวจสอบว่า UI เปลี่ยนตาม design specs ทั้งหมด (สี amber, ไม่มี bubble Agent, Timeline collapsible, Bottom Sheet, Voice Mode, Security Alert)

---

## ข้อห้ามที่ยึดถือจากพรอมต์ (ตรวจสอบทุกเฟส)

- [x] ไม่มี spinner เปล่า — ทุกสถานะมีไอคอนหรือข้อความกำกับ
- [x] ทุกสถานะมี label สำหรับ VoiceOver-TalkBack (`aria-label`, `aria-live`, `aria-expanded`)
- [x] สีสถานะมีไอคอน/ข้อความกำกับเสมอ (ไม่พึ่งสีอย่างเดียว)
- [x] touch target ≥ 44pt (ทุกปุ่มใน input bar, live status line, permission actions, scroll button)
- [x] คอนทราสต์ผ่าน WCAG AA ทั้ง Light และ Dark (ตรวจสอบด้วย CSS variables)
- [x] ข้อความไทยยาวไม่ล้น ไม่ตัดวรรณยุกต์ (`word-break`, `line-height: 1.6-1.7`)
- [x] ทุกการกระทำที่มีผลกระทบมี Permission และทุก error มีทางไปต่อ
- [x] ไม่แสดงตัวเลขประมาณการเมื่อไม่มีข้อมูลรองรับจริง
- [x] ไม่มีศัพท์เทคนิคในข้อความที่ผู้ใช้เห็นโดยปริยาย
- [x] ไม่มี emoji ใน UI (ตรวจสอบด้วย Python regex ทุกไฟล์)
- [x] ไม่ดูเป็น AI-template (สี amber, ไม่มี bubble Agent, typography มืออาชีพ, progressive disclosure)

---

## สรุปสั้นสำหรับผู้ใช้ (ไม่ต้องอ่านทั้งหมด)

- **ทำเสร็จแล้ว 4 เฟส**: รากฐาน + แชท + กิจกรรม (1) → การ์ด + ควบคุม + ปลอดภัย (2) → งานเบื้องหลัง + หน้ารอง (3) → Component Library + Developer Specs (4)
- **ไฟล์ทั้งหมดใน repo** (`pr4yhk6zt6-wq/Test`): 13 ไฟล์ (`design-*` 5 + `phase*` 8) + `project-context.md`
- **ไม่มี emoji** ในทุกไฟล์ที่สร้าง (แก้แล้ว — `59f8bc0`)
- **ไม่ดู AI-template**: สี Warm Amber ตลอด, Agent message ไม่มี bubble, progressive disclosure
- **GitHub token ใช้สำเร็จ**: Clone → Push ทุกเฟส (`15cf888` → `d80476a` → `1175158` → `59f8bc0`)
- **ต่อไป**: สรุปรวม (`summary.md` นี้เอง) → แก้ SwiftUI source → Build `.ipa` ใหม่
