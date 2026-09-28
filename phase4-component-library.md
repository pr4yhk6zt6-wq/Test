# เฟส 4 — Component Library + สเปกสำหรับนักพัฒนา

## ข้อกำหนดต่อเนื่อง
- ไม่มี emoji ในทุกไฟล์ (ตรวจสอบด้วย grep ก่อน commit)
- ไม่ดูเป็น AI-template: สี Warm Amber (#B07A2A) ตลอดทุก component, typography IBM Plex Sans Thai + Noto Sans Thai, ไม่มี bubble Agent, ไม่มี gradient ฉูดฉาด (ยกเว้น glass header และ avatar เท่านั้น)
- ทุกไฟล์ commit และ push เข้า repo `pr4yhk6zt6-wq/Test` ด้วย GitHub token (`ghp_...`)

---

## 1. Component Library

### 1.1 Status Line Component
| Variant | State | Visual | Interaction |
|---|---|---|---|
| `LiveStatusLine` | `idle` | ไอคอนวงกลม muted + ข้อความ "ว่าง" | แตะเพื่อขยาย Timeline |
| `LiveStatusLine` | `working` | ไอคอน pulse (accent) + ข้อความ "กำลังทำ..." | แตะเพื่อขยาย/พับ |
| `LiveStatusLine` | `waiting` | ไอคอน warning + ข้อความ "รอคุณ" | แตะเพื่อดูรายละเอียด |
| `LiveStatusLine` | `completed` | ไอคอน check (success) + ข้อความสรุป "เสร็จแล้ว — X วินาที" | แตะเพื่อดูผลลัพธ์ |

- **Touch target**: ความสูง ≥ 52px (≥ 44pt ตามมาตรฐาน)
- **Animation**: Crossfade ข้อความ 200ms ease-in-out (ไม่กระตุก)
- **Accessibility**: `aria-expanded`, `aria-controls`, `aria-live="polite"`

### 1.2 Timeline Step Component
| Variant | State | Visual | Behavior |
|---|---|---|---|
| `TimelineStep` | `pending` | ไอคอนวงกลมเล็ก muted + ข้อความรอ | ไม่มี animation |
| `TimelineStep` | `running` | ไอคอน pulse (accent) + shimmer stroke + ring pulse | Shimmer 1.5s loop |
| `TimelineStep` | `success` | ไอคอน check (success) + สีเขียวอ่อน | Checkmark draw-in 150ms |
| `TimelineStep` | `failed` | ไอคอน X (error) + สีแดงอ่อน | ไม่มี animation |
| `TimelineStep` | `skipped` | ไอคอนขีดเส้น (muted) + จาง (`opacity: 0.7`) | ไม่มี animation |
| `TimelineStep` | `waiting_user` | ไอคอนรอ (warning) + badge "รอคุณ" | Pulse 2s loop |

- **Connector line**: เส้นแนวตั้ง (`width: 2px`, `background: var(--border)`) เชื่อมระหว่างขั้นตอน — ไม่ใช้สีฉูดฉาด
- **Vertical spacing**: แต่ละขั้นห่างกัน 0 (แชร์เส้นเชื่อม) แต่มี `padding-top/bottom: 10px` เพื่อให้อ่านสบาย

### 1.3 Card Components (8 ประเภท)

#### Thinking Card (`ThinkingCard`)
- **States**: `expanded`, `collapsed`
- **Visual**: พื้น `surface-2`, ขอบ `border`, ไม่มี shadow (ไม่รบกวนการอ่าน)
- **Typography**: `font-style: italic` บน title, `font-size: 13px`, `color: var(--text-secondary)`
- **Animation**: Collapse/expand `max-height` transition 400ms ease

#### Web Search Card (`WebSearchCard`)
- **Visual**: พื้น `surface`, ขอบ `border`, shadow `shadow-card`
- **Content**: หัวข้อ + chip แหล่งข้อมูล (เลื่อนแนวนอนได้)
- **Chip**: `border-radius: 16px`, `padding: 6px 12px`, `font-size: 12px`, `background: surface-2`, `border: 1px solid border`
- **Icon**: ลูกโลก SVG (`stroke-width: 2`, `fill: none`)

#### Browse / Computer Use Card (`BrowseCard`)
- **Visual**: `overflow: hidden`, `border-radius: 18px`, `box-shadow: shadow-card`
- **Thumbnail**: `height: 160px`, `background: linear-gradient(135deg, #3D342E, #5A4F45)` — ไม่ใช้สีฉูดฉาด
- **Overlay point**: วงกลม `border: 3px solid accent`, `background: rgba(176,122,42,0.15)`, `animation: pulse-ring 2s infinite`
- **Blur sensitive**: `filter: blur(8px)` + ข้อความ "ข้อมูลอ่อนไหวถูกปิดบัง"
- **Full-screen**: คลิก thumbnail ขยายเต็มจอ (`position: fixed`, `inset: 0`, `z-index: 200`)

#### File Card (`FileCard`)
- **Visual**: `display: flex`, `gap: 12px`, `align-items: flex-start`
- **Icon box**: `width: 40px`, `height: 40px`, `border-radius: 12px`, `background: surface-2`, `border: 1px solid border`
- **Actions**: ปุ่ม "เปิด", "บันทึก", "แชร์" — ขนาด `padding: 4px 10px`, `font-size: 11px`, `border-radius: 10px`

#### Code Run Card (`CodeRunCard`)
- **Visual**: พื้น `surface-2` (อ่อนกว่าปกติ), ขอบ `border`
- **Default state**: แสดงสรุปภาษาไทยเท่านั้น (`font-size: 13px`, `line-height: 1.5`)
- **Expanded state**: `pre` block (`background: surface`, `border-radius: 12px`, `font-family: ui-monospace`)
- **Toggle**: ปุ่ม "ดูโค้ดและผลลัพธ์" → สลับ `display: none/block` พร้อมเปลี่ยนข้อความ

#### Connector / App Card (`ConnectorCard`)
- **Visual**: `display: flex`, `align-items: center`, `gap: 12px`
- **Logo**: วงกลมหรือสี่เหลี่ยมตามแอป (`border-radius: 10px`, `background: accent-soft`, `border: 1px solid border`)
- **Action text**: `font-size: 12px`, `color: text-secondary`

#### Sub-agent / Parallel Card (`SubAgentCard`)
- **Visual**: `display: flex`, `flex-direction: column`
- **Progress bar**: `height: 6px`, `background: surface-2`, `border-radius: 3px`
- **Progress fill**: `linear-gradient(90deg, accent, accent-deep)` — ไม่ใช้ rainbow
- **Collapse**: ปุ่ม "ย่อ/ขยาย" เปิด-ปิดหลายเลน

#### To-do / Plan Card (`TodoCard`)
- **Visual**: แต่ละข้อ `display: flex`, `gap: 10px`, `padding: 8px 0`, `border-bottom: 1px solid border`
- **Checkbox**: วงกลม `width: 20px`, `height: 20px`, `border: 2px solid border`
- **Done state**: `border-color: success`, `background: success-soft`, checkmark SVG (`display: block`)
- **Text done**: `text-decoration: line-through`, `color: text-muted`, `opacity: 0.7`

### 1.4 Bottom Sheet Component (`BottomSheet`)
- **Overlay**: `background: var(--overlay)`, `z-index: 200`, `opacity` transition 250ms
- **Sheet**: `border-top-left-radius: 28px`, `border-top-right-radius: 28px`, `transform: translateY(0)` เมื่อเปิด
- **Handle**: `width: 36px`, `height: 5px`, `border-radius: 3px`, `background: border`, `margin: 0 auto 16px`
- **Close**: คลิก overlay (`if (event.target === this) closeDetail()`)

### 1.5 Permission Request Component (`PermissionSheet`)
- **Header**: `font-size: 16px`, `font-weight: 700`, `color: text-primary`
- **Sub**: `font-size: 13px`, `line-height: 1.5`, `color: text-secondary`
- **Risk row**: `dot` วงกลม (`low: success`, `med: warning`, `high: error`) + `label` (`min-width: 80px`) + `desc`
- **Actions**: 4 ปุ่ม (`flex: 1`, `min-width: 100px`, `border-radius: 14px`)
  - `btn-allow`: `background: accent`, `color: #fff`
  - `btn-deny`: `background: error-soft`, `color: error`
  - `btn-edit`: `background: surface`, `border: 1px solid border`

### 1.6 Input Bar Component (`InputBar`)
- **Container**: `padding: 10px 14px`, `background: surface`, `border: 1.5px solid border`, `border-radius: 28px`
- **Focus**: `border-color: accent`, `box-shadow: 0 4px 16px rgba(176,122,42,0.10)`
- **Textarea**: `flex: 1`, `border: none`, `background: transparent`, `resize: none`, `max-height: 120px`
- **Buttons**: `icon-btn` (`width: 40px`, `height: 40px`, `border-radius: 50%`) และ `send-btn` (`width: 44px`, `height: 44px`, `background: accent`, `box-shadow: 0 4px 12px rgba(176,122,42,0.25)`)
- **Stop state**: `send-btn` เปลี่ยนเป็น `stop-btn` (`background: error`, `box-shadow: 0 4px 12px rgba(139,46,46,0.25)`)

---

## 2. Design Tokens ฉบับเต็ม + คู่มือสไตล์

### 2.1 Color Tokens (Light / Dark)
| Token | Light | Dark | Usage |
|---|---|---|---|
| `--bg` | `#F5F3F0` | `#161310` | พื้นหลังหลัก |
| `--surface` | `#FFFFFF` | `#1E1C18` | พื้นผิว card / sheet |
| `--surface-2` | `#EDEAE6` | `#2A2721` | พื้นรอง / icon box |
| `--text-primary` | `#1C1916` | `#F0EDE8` | ข้อความหลัก |
| `--text-secondary` | `#6B6058` | `#A89F94` | ข้อความรอง |
| `--text-muted` | `#9A9088` | `#6B5E56` | ข้อความจาง |
| `--accent` | `#B07A2A` | `#D49A4A` | สีเน้น (warm amber) |
| `--accent-soft` | `#F2E6CE` | `rgba(212,154,74,0.12)` | พื้นสีเน้นอ่อน |
| `--accent-deep` | `#8A5E1E` | `#A87D2E` | สีเน้นเข้ม |
| `--success` | `#2D5A3F` | `#4A8F6A` | สำเร็จ |
| `--success-soft` | `#E2EBE5` | `rgba(74,143,106,0.12)` | พื้นสำเร็จ |
| `--warning` | `#9A6B1E` | `#C48A3A` | เตือน |
| `--warning-soft` | `#F5EDD8` | `rgba(196,138,58,0.12)` | พื้นเตือน |
| `--error` | `#8B2E2E` | `#C06A6A` | ล้มเหลว |
| `--error-soft` | `#F4E4E4` | `rgba(192,106,106,0.12)` | พื้นล้มเหลว |
| `--border` | `#E2DDD8` | `#2A2721` | ขอบ |
| `--overlay` | `rgba(28,25,22,0.30)` | `rgba(240,237,232,0.30)` | พื้น overlay |
| `--glass` | `rgba(255,255,255,0.90)` | `rgba(30,28,24,0.92)` | Glass effect |

### 2.2 Typography Scale
| ระดับ | ขนาด (pt) | น้ำหนัก | line-height | letter-spacing | Usage |
|---|---|---|---|---|---|
| H1 | 28 | 700 | 1.25 | 0 | หัวเรื่องหลัก (Empty State) |
| H2 | 22 | 600 | 1.3 | 0 | ชื่อบทสนทนา |
| H3 | 17 | 600 | 1.3 | 0 | หัวข้อใน Agent document |
| Body | 16 | 400 | 1.7 | 0.01em | ข้อความ Agent |
| Body Small | 14 | 400 | 1.6 | 0.01em | ข้อความใน card / step |
| Caption | 12 | 500 | 1.4 | 0.02em | Timestamp, label |
| Micro | 11 | 600 | 1.3 | 0.06em | Badge, status pill |

- **Font family**: `font-family: 'IBM Plex Sans Thai', 'Noto Sans Thai', -apple-system, sans-serif;`
- **Dynamic Type**: รองรับการขยายตัวอักษรของระบบ (iOS Dynamic Type, Android Font Size) โดยใช้ `rem` หรือ `em` แทน `px` ใน production code
- **Thai line-height**: `1.5`–`1.7` สำหรับเนื้อหา, `1.3` สำหรับหัวเรื่อง
- **Text truncation**: `white-space: nowrap; overflow: hidden; text-overflow: ellipsis;` สำหรับชื่อไฟล์และข้อความยาวใน chip

### 2.3 Spacing Grid
- **Base unit**: 4pt → 8pt, 12pt, 16pt, 24pt, 32pt
- **Padding ขอบหน้าจอ**: 16pt (iOS), 16pt (Android)
- **Card radius**: 18pt (ค่าเดียวทั้งแอป)
- **Pill radius**: 28pt (input bar)
- **Button radius**: 14pt

### 2.4 Radius & Shape Tokens
| Component | Radius | Note |
|---|---|---|
| `Card` | 18px | ทุก card ใช้ค่าเดียว |
| `InputBar` | 28px | Pill-shaped |
| `Chip` | 20px | Suggestion / source chip |
| `Button` | 14px | ปุ่มทั่วไป |
| `Badge` | 20px | Status badge |
| `BottomSheet` | 28px (top) | เฉพาะด้านบน |

---

## 3. Prototype Specification (Interaction & Animation)

### 3.1 Shimmer / Pulse
- **Running step icon**: `animation: shimmer 1.5s infinite;` (opacity 1 → 0.4 → 1)
- **Live Status Line pulse**: `animation: pulse 1.5s infinite;` (dot 6px)
- **Takeover banner**: ไม่มี shimmer — ใช้สี `warning-soft` อ่อนเพื่อไม่รบกวน
- **Voice Mode think**: `animation: pulse-ring 2s infinite;` (ring ขยายออก)

### 3.2 Streaming & Scroll
- **Streaming text**: ข้อความ Agent ปรากฏทีละบรรทัด (ไม่กระตุก) — ใช้ `word-break: break-word;` และ `line-height: 1.7`
- **Scroll behavior**: `scroll-behavior: smooth;` — แต่ไม่ดึงหน้าเลื่อนเองเมื่อผู้ใช้อ่านข้างบน (`scrollToBottom` เรียกเฉพาะเมื่อผู้ใช้ส่งข้อความใหม่)
- **Scroll-to-bottom**: ปุ่มลอย (`fixed`, `bottom: 88px`, `right: 16px`) ปรากฏเมื่อ `scrollTop + clientHeight < scrollHeight - 120`

### 3.3 Progressive Disclosure
- **Live Status Line (A)**: แตะขยาย → แสดง Timeline (B)
- **Timeline (B)**: แตะ header อีกครั้ง → พับกลับ (max-height transition 400ms)
- **Detail Sheet (C)**: เปิดจาก citation number (`.cite-num`) → bottom sheet เต็มจอ
- **Code card**: ปุ่ม "ดูโค้ด" → ขยายบล็อก (`display: block`) + เปลี่ยนข้อความปุ่ม
- **Thinking card**: คลิกที่ card → พับ/กาง (`max-height` transition)

### 3.4 Reduce Motion & Accessibility
- **Reduce Motion**: เมื่อระบบตั้งค่า `prefers-reduced-motion: reduce` → เปลี่ยน animation ทั้งหมดเป็น `fade` หรือ `opacity` transition สั้น (≤ 150ms)
- **No shimmer**: เมื่อ `prefers-reduced-motion` เปิด — shimmer เปลี่ยนเป็น `opacity: 0.7` คงที่ (ไม่กระพริบ)
- **Haptic**: `haptic-feedback` เบาๆ (`UIImpactFeedbackGenerator(.light)`) เมื่อ:
  - งานสำคัญเสร็จ
  - ต้องการอนุมัติจากผู้ใช้
  - พบคำสั่งแปลก (security alert)
- **VoiceOver / TalkBack**: ทุก component มี `aria-label`, `aria-live`, `aria-expanded`, `aria-controls`, `role` ที่เหมาะสม

---

## 4. Status Copy Library (ไทย / อังกฤษ)

### 4.1 Activity Types (message title — ภาษาไทย)
| Type | Thai Label | English Label |
|---|---|---|
| `thinking` | กำลังคิด... | Thinking... |
| `web_search` | ค้นหาเว็บ | Web search |
| `browse` | ดูหน้าจอ | Browsing |
| `read_file` | อ่านไฟล์ | Reading file |
| `write_file` | เขียนไฟล์ | Writing file |
| `run_code` | รันโค้ด | Running code |
| `connector` | เชื่อมต่อแอป | App connector |
| `subagent` | งานคู่ขนาน | Sub-agent |
| `plan` | วางแผนงาน | Planning |
| `ask_user` | ขอคำตอบจากคุณ | Waiting for you |
| `permission` | ต้องการอนุญาต | Needs approval |

### 4.2 Status Labels (badge + VoiceOver text)
| Status | Thai Badge | English Badge | Thai Description | English Description |
|---|---|---|---|---|
| `pending` | รอ | Waiting | รอเริ่มทำงาน | Waiting to start |
| `running` | กำลังทำ | Running | กำลังดำเนินการ | In progress |
| `waiting_user` | รอคุณ | Waiting for you | รอคำตอบหรือการอนุมัติ | Waiting for input |
| `succeeded` | สำเร็จ | Done | ทำเสร็จแล้ว | Completed |
| `failed` | ล้มเหลว | Failed | ไม่สำเร็จ — มีสาเหตุและทางแก้ | Failed — with cause and next step |
| `skipped` | ข้าม | Skipped | ข้ามขั้นตอนนี้ | Skipped |
| `cancelled` | ยกเลิก | Cancelled | ถูกยกเลิกโดยผู้ใช้ | Cancelled by user |

### 4.3 User-Facing Messages (ไม่ใช้ศัพท์เทคนิค)
| Context | Thai Message | English Message |
|---|---|---|
| Reading file | "กำลังอ่านไฟล์ที่คุณส่ง..." | "Reading the file you sent..." |
| Web search (found) | "พบ 8 แหล่งข้อมูล กำลังเลือกที่น่าเชื่อถือ" | "Found 8 sources, selecting the most reliable" |
| Web search (none) | "ไม่พบข้อมูลที่ตรงกับคำค้น — ลองปรับคำค้น" | "No matching results — try adjusting your query" |
| Permission request | "ต้องการอนุญาตก่อนส่งอีเมลนี้" | "Needs approval before sending this email" |
| Takeover | "Agent ต้องการความช่วยเหลือจากคุณ — คุณทำเองได้ และ Agent จะไม่เห็นรหัสที่พิมพ์" | "Agent needs your help — you can do it yourself, and Agent won't see your input" |
| Security alert | "เว็บนี้พยายามสั่งให้ทำสิ่งอื่น — เราไม่ทำตามและกำลังดำเนินงานต่อ" | "This site tried to instruct something else — we ignored it and are continuing" |
| Completed | "ทำเสร็จแล้ว ใช้เวลา 1 นาที 12 วินาที" | "Done. Took 1 minute 12 seconds." |
| Partial success | "ทำเสร็จบางขั้นตอน — บางขั้นไม่สำเร็จ" | "Partially completed — some steps failed" |
| Undo available | "ทำเสร็จแล้ว — ย้อนกลับได้ภายใน 30 วินาที" | "Done — undo available for 30 seconds" |
| Rate limit warning | "โควตาใกล้หมด — ใช้ไป 65%" | "Quota running low — 65% used" |

---

## 5. Event Data Structure (สำหรับนักพัฒนา)

```typescript
interface AgentEvent {
  id: string;                    // UUID หรือ unique identifier
  seq: number;                   // ลำดับขั้นตอนในบทสนทนา (เริ่มจาก 1)
  parent_id?: string;            // id ของ sub-agent หรืองานคู่ขนาน (ถ้ามี)
  type: EventType;              // ดูรายการด้านล่าง
  status: EventStatus;          // pending | running | waiting_user | succeeded | failed | skipped | cancelled
  title: { th: string; en: string };  // ชื่อขั้นตอน (ภาษาไทย + อังกฤษ)
  detail?: { th: string; en: string }; // คำอธิบายละเอียด (ไม่บังคับ)
  started_at: string;           // ISO 8601 timestamp
  ended_at?: string;            // ISO 8601 timestamp (ถ้าเสร็จ/ล้มเหลว/ข้าม)
  progress?: number;            // 0 - 100 (เปอร์เซ็นต์ความคืบหน้า — ถ้าประมาณได้)
  requires_approval: boolean;   // ต้องขออนุญาตก่อนทำงานต่อหรือไม่
  reversible: boolean;          // สามารถ Undo ได้หรือไม่
  sensitivity: 'none' | 'personal' | 'financial' | 'credentials'; // ระดับความอ่อนไหวของข้อมูล
  sources?: Source[];           // แหล่งข้อมูลที่ใช้ (สำหรับ web_search, browse)
  artifacts?: Artifact[];       // ไฟล์หรือผลงานที่สร้าง (สำหรับ write_file, run_code)
  error?: {
    code: string;               // รหัสข้อผิดพลาด (ภาษาอังกฤษสั้น)
    user_message: { th: string; en: string }; // ข้อความที่แสดงให้ผู้ใช้ (ไม่ใช้ศัพท์เทคนิค)
    retryable: boolean;         // สามารถลองใหม่ได้หรือไม่
  };
}

interface Source {
  id: string;                   // ลำดับหรือ UUID
  favicon_url?: string;         // URL favicon (ถ้ามี)
  domain: string;               // โดเมน (เช่น booking.com)
  url: string;                  // URL เต็ม
  title?: string;               // ชื่อหน้า (ถ้ามี)
}

interface Artifact {
  id: string;
  file_type: 'document' | 'image' | 'code' | 'audio' | 'video' | 'other';
  file_name: string;
  file_size?: number;           // ขนาดไฟล์ (bytes)
  url?: string;                 // URL เปิดไฟล์
  created_at: string;
}

enum EventType {
  Thinking = 'thinking',
  WebSearch = 'web_search',
  Browse = 'browse',
  ReadFile = 'read_file',
  WriteFile = 'write_file',
  RunCode = 'run_code',
  Connector = 'connector',
  SubAgent = 'subagent',
  Plan = 'plan',
  AskUser = 'ask_user',
  Permission = 'permission'
}

enum EventStatus {
  Pending = 'pending',
  Running = 'running',
  WaitingUser = 'waiting_user',
  Succeeded = 'succeeded',
  Failed = 'failed',
  Skipped = 'skipped',
  Cancelled = 'cancelled'
}
```

### Lifecycle
- `started` → `updated` (ความคืบหน้าหรือข้อมูลเพิ่มเติม) → `completed` (status: succeeded / failed / skipped / cancelled)
- `updated` สามารถเรียกได้หลายครั้งระหว่าง `started` และ `completed`

### Reconnect เมื่อเน็ตหลุด
- ส่ง event ซ้ำ (resend) ด้วย `seq` เดิม — ระบบเรียงลำดับด้วย `seq` และไม่สร้าง event ซ้ำ
- ถ้า event ที่ไม่รู้จัก (`type` ไม่อยู่ใน `EventType`) — แสดงเป็นขั้นตอนทั่วไป (`type: 'unknown'`, `title: { th: 'ขั้นตอนที่ไม่รู้จัก', en: 'Unknown step' }`) โดยไม่ crash

---

## 6. Edge Cases และคำแนะนำนักพัฒนา

### 6.1 เมื่อ Backend ไม่ส่งข้อมูลบางอย่าง
- ถ้า `progress` ไม่ส่งมา → ไม่แสดงเปอร์เซ็นต์ใน Timeline (แสดงเฉพาะสถานะ "กำลังทำ")
- ถ้า `sources` ว่าง → Web Search Card ไม่แสดง chip แหล่งข้อมูล (แสดงเฉพาะหัวข้อ)
- ถ้า `artifacts` ว่าง → File Card ไม่ปรากฏใน Detail Sheet
- ถ้า `error` ไม่มี `user_message` → ใช้ข้อความเริ่มต้น: "เกิดข้อผิดพลาดที่ไม่ทราบสาเหตุ — ลองใหม่อีกครั้ง" (ไม่แสดง error code ดิบให้ผู้ใช้เห็น)

### 6.2 เมื่อ Event มี `parent_id`
- แสดงเป็นเลนย่อย (sub-agent) ใน SubAgentCard
- ความคืบหน้าของงานหลัก (`parent`) = ค่าเฉลี่ยของความคืบหน้างานย่อยทั้งหมด
- ถ้างานย่อยล้มเหลว → งานหลักแสดงสถานะ "สำเร็จบางส่วน" (partial success)

### 6.3 เมื่อ `requires_approval` = true แต่ผู้ใช้ไม่ตอบ
- หลังจากเวลาผ่านไป 10 นาที (หรือตามที่ตั้งค่าใน Settings) → งานเปลี่ยนสถานะเป็น `cancelled` พร้อมข้อความ "หมดเวลาในการรอตอบ — งานถูกยกเลิกโดยอัตโนมัติ"
- ระบบส่ง Push Notification ก่อนหมดเวลา 2 นาที: "Agent รอคำตอบจากคุณ — เหลือเวลาอีก 2 นาที"

### 6.4 เมื่อ `reversible` = false
- ไม่แสดงปุ่ม Undo ใน Timeline หรือใน Banner หลังงานเสร็จ
- ถ้าผู้ใช้พยายามกด Undo → แสดงข้อความ "งานนี้ไม่สามารถย้อนกลับได้" (ไม่ทำให้แอป crash)

### 6.5 เมื่อ `sensitivity` = 'credentials'
- ข้อมูลใน Detail Sheet (แหล่งข้อมูล, ไฟล์, โค้ด) จะไม่แสดงรายละเอียดที่เกี่ยวข้องกับรหัสผ่านหรือข้อมูลส่วนตัว — แทนด้วยข้อความ "ข้อมูลอ่อนไหวถูกปิดบัง"
- การส่งออก (Export) จะไม่รวมข้อมูลที่มี `sensitivity` = 'credentials' หรือ 'financial' ยกเว้นผู้ใช้เลือก "รวมข้อมูลทั้งหมด" และยืนยันเพิ่มเติม

### 6.6 การแสดงผลในหน้าจอเล็ก (iPhone 7 — 4.7")
- ทุก card ใช้ `padding: 14px` (ไม่มากเกินไป) และ `font-size: 13px` (ไม่เล็กเกินไปสำหรับจอเล็ก)
- Timeline step ลด `gap` เป็น `8px` (จาก `12px`) เมื่อความกว้างจอ < 360px
- Bottom Sheet ใช้ `max-height: 85vh` (ไม่เต็มจอ) เพื่อให้เห็น header ด้านบนเสมอ

---

## 7. เหตุผลเบื้องหลังการตัดสินใจสำคัญ (5–7 ข้อ)

### 7.1 ทำไมไม่ใช้อิโมจิใน UI ทั้งหมด
- **เหตุผล**: อิโมจิทำให้ UI ดูไม่เป็นมืออาชีพและไม่เหมาะกับแอปที่ต้องการความน่าเชื่อถือ (trust) โดยเฉพาะเมื่อต้องจัดการข้อมูลส่วนตัวและการเงิน — การใช้ SVG stroke + ข้อความภาษาไทยให้ความรู้สึกที่เป็นระบบและชัดเจนมากกว่า
- **ผลกระทบ**: UI อ่านง่ายขึ้นสำหรับผู้ใช้ทุกวัย และไม่ขึ้นอยู่กับการรองรับอิโมจิของระบบ (บางอุปกรณ์ jailbroken อาจไม่มี font อิโมจิครบ)

### 7.2 ทำไม Agent message ไม่มี bubble (อ่านแบบเอกสาร)
- **เหตุผล**: การใช้ bubble ทั้งสองฝั่ง (ผู้ใช้และ Agent) เป็นรูปแบบที่ ChatGPT, Claude, Gemini ใช้ — การไม่ใช้ bubble สำหรับ Agent สร้างความแตกต่างและทำให้ผู้ใช้รู้สึกว่า Agent เป็น "เอกสารที่กำลังสร้าง" ไม่ใช่ "คู่สนทนา" ทำให้ progressive disclosure (ซ่อนรายละเอียดใน Timeline) ทำงานได้ดีกว่า
- **ผลกระทบ**: ข้อความ Agent อ่านสบายขึ้น (line-height 1.7, ไม่ถูกจำกัดด้วย bubble width) และไม่ต้องปรับ layout เมื่อข้อความยาว

### 7.3 ทำไมใช้สี Warm Amber (#B07A2A) แทนสีฟ้า/ม่วงที่เป็นเอกลักษณ์ AI
- **เหตุผล**: สีฟ้า (#3B82F6) และสีม่วง (#7C3AED) เป็นสีที่ ChatGPT, Claude, Perplexity, Gemini ใช้เป็นเอกลักษณ์ — การใช้สีอบอุ่น (amber) สร้างความแตกต่างและสื่อถึงความเป็น "อบอุ่น เป็นกันเอง" ตามบุคลิกแบรนด์ที่ระบุใน project context
- **ผลกระทบ**: แอปไม่ถูกเข้าใจผิดว่าเป็น "ChatGPT clone" และผู้ใช้รู้สึกผ่อนคลายมากขึ้นเมื่อใช้งาน (สีอบอุ่นลดความเครียดเมื่ออ่านข้อมูลที่ซับซ้อน)

### 7.4 ทำไมไม่แสดงตัวเลขประมาณการเวลาหรือความมั่นใจเมื่อไม่มีข้อมูลจริง
- **เหตุผล**: พรอมต์ระบุชัดเจนว่า "ห้ามแสดงตัวเลขประมาณการ (เวลาที่เหลือ ความมั่นใจ) ถ้าไม่มีข้อมูลรองรับจริง" — การแสดงตัวเลขที่ไม่มีข้อมูลจริงทำให้ผู้ใช้เข้าใจผิดและลดความน่าเชื่อถือ
- **ผลกระทบ**: ผู้ใช้ไม่ถูกหลอกด้วยตัวเลขที่ไม่ถูกต้อง และระบบไม่ต้องสร้างข้อมูลเท็จเพื่อเติมช่องว่าง

### 7.5 ทำไม Timeline ใช้ vertical connector line แทน card แยกกัน
- **เหตุผล**: การใช้เส้นเชื่อม (connector) สร้างความรู้สึกว่า "ขั้นตอนเหล่านี้เป็นส่วนหนึ่งของงานเดียวกัน" มากกว่าการใช้ card แยกกันที่ดูเหมือนรายการที่ไม่เกี่ยวข้อง — ยังช่วยลดพื้นที่ในแนวตั้ง (ไม่ต้องมี margin ใหญ่ระหว่าง card)
- **ผลกระทบ**: Timeline อ่านง่ายขึ้นและไม่รก แม้จะมี 6-8 ขั้นตอน

### 7.6 ทำไม Detail Sheet แยกเป็น bottom sheet แทนแสดงใน Timeline
- **เหตุผล**: ข้อมูลใน Detail Sheet (แหล่งข้อมูล, โค้ด, ข้อผิดพลาดดิบ) มีความยาวและซับซ้อน — ถ้าแสดงใน Timeline จะทำให้ Timeline ยืดและอ่านยาก — การแยกเป็น bottom sheet (progressive disclosure) ทำให้ผู้ใช้เลือกดูได้เมื่อจำเป็น
- **ผลกระทบ**: Timeline ยังคงสั้นและอ่านง่าย ข้อมูลเทคนิคไม่รบกวนการอ่านผลลัพธ์หลัก

### 7.7 ทำไม Status Copy ใช้ภาษาธรรมดา (ไม่ใช้ศัพท์เทคนิค) ในทุกข้อความที่ผู้ใช้เห็น
- **เหตุผล**: พรอมต์ระบุว่า "ภาษาใน UI ต้องเข้าใจง่าย เช่น 'กำลังค้นหาเว็บ' แทน 'invoking web_search tool'" — ผู้ใช้เป้าหมายไม่ใช่โปรแกรมเมอร์ และการใช้ศัพท์เทคนิคทำให้ผู้ใช้รู้สึกว่าไม่ควบคุมงานได้
- **ผลกระทบ**: ผู้ใช้เข้าใจทุกขั้นตอนที่ Agent ทำ และรู้สึกว่าควบคุมได้จริง (ไม่ใช่แค่ดู Agent ทำงานโดยไม่รู้ความหมาย)

---

## 8. สรุปรวม: เพิ่ม/แก้/ตัดอะไรจากพรอมต์ในเฟส 4

- **เพิ่ม** Component Library ครบทุก component (Status Line, Timeline Step, 8 Card Types, Bottom Sheet, Permission Sheet, Input Bar) พร้อม variants และ states
- **เพิ่ม** Design Tokens ฉบับเต็ม (Light/Dark, Typography Scale, Spacing, Radius, Color) + คู่มือสไตล์
- **เพิ่ม** Prototype Specification (Animation, Interaction, Progressive Disclosure, Reduce Motion, Haptic, Accessibility)
- **เพิ่ม** Status Copy Library ไทย/อังกฤษ ครบทุก event type และ status
- **เพิ่ม** โครงสร้างข้อมูล Event (`AgentEvent`, `Source`, `Artifact`, `EventType`, `EventStatus`) พร้อม lifecycle, reconnect, และการจัดการ event ที่ไม่รู้จัก
- **เพิ่ม** Edge Cases (6 กรณี) และคำแนะนำสำหรับนักพัฒนา (7 ข้อ)
- **เพิ่ม** เหตุผลการตัดสินใจสำคัญ 7 ข้อ (ไม่ใช้อิโมจิ, ไม่มี bubble Agent, สี amber, ไม่แสดงตัวเลขเดา, connector line, bottom sheet, ภาษาธรรมดา)
- **แก้** ไม่มี emoji ในทุกไฟล์ (ตรวจสอบด้วย grep ก่อน commit)
- **แก้** ไม่ดู AI-template — สี amber ตลอด, typography มืออาชีพ, ไม่มี rainbow/neon, progressive disclosure
- **ตัด** ไม่มีการใช้ศัพท์เทคนิคในข้อความที่ผู้ใช้เห็น (ทุก status copy เป็นภาษาไทย/อังกฤษธรรมดา)
- **เพิ่ม** Push เข้า repo `pr4yhk6zt6-wq/Test` ด้วย GitHub token (`ghp_...`) — commit `d80476a` (เฟส 3) และจะ push เฟส 4 ต่อ

---

## สรุปรวมทั้ง 4 เฟส

| เฟส | หัวข้อ | สถานะ |
|---|---|---|
| 1 | รากฐาน + หน้าแชทหลัก + ระบบกิจกรรม (A/B/C) | เสร็จแล้ว เสร็จ + Push (`15cf888`) |
| 2 | การ์ด + การควบคุม + ความปลอดภัย + สถานะผิดปกติ | เสร็จแล้ว เสร็จ + Push (`15cf888`) |
| 3 | งานเบื้องหลัง + หน้ารอง (งานของฉัน, โควตา, Voice, Onboarding, ประวัติ, เชื่อมต่อ, ไฟล์, ส่งออก, ตั้งค่า) | เสร็จแล้ว เสร็จ + Push (`d80476a`) |
| 4 | Component Library + Design Tokens + Prototype Spec + Status Copy + Data Structure + Edge Cases + Decisions + สรุปรวม | เสร็จแล้ว เสร็จ (ไฟล์นี้) + รอ Push |

**แผนต่อไป (หลังเฟส 4):**
1. Push ไฟล์เฟส 4 เข้า repo (`git add -A`, `commit`, `push`)
2. สร้างสรุปรวมทั้งหมด (`summary.md`) ใน repo
3. เริ่มแก้ SwiftUI source files (`App/`, `Views/`, `Services/`) ใน repo เพื่อสร้าง `.ipa` ใหม่ที่มี UI ตาม design specs ทั้งหมด
4. รัน `Scripts/build-local.sh` เพื่อ build `.ipa` (ใช้ `xcodebuild` + `ldid`)

**พิมพ์ 'ต่อ'** เพื่อไปขั้นตอนสรุปรวมและเริ่มแก้ `.ipa` (หรือบอกว่าต้องการให้ทำอะไรเพิ่มเติมก่อน)
