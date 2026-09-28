# เฟส 4 — Component Library + สเปกสำหรับนักพัฒนา (v2 · ทับของเดิม)

ไฟล์คู่กัน: **`phase4-prototype.html`** — คลังคอมโพเนนต์ที่กดได้จริง **7 หมวด · 26 สเปก** (ตรวจอัตโนมัติผ่าน 43/43)
ใช้คู่กับ: `design-phase1-style.md` (โทเคน) · `design-phase1-activity.md` (ระบบกิจกรรม) · `design-phase2-cards-controls.md` (การ์ด/การอนุมัติ) · `phase3-background-tasks.md` (งานเบื้องหลัง/หน้ารอง)

---

## 1. Design Tokens ฉบับเต็ม

### 1.1 สี — Light

| Token | ค่า | บทบาท | คอนทราสต์บน `bg` |
|---|---|---|---|
| `bg` | `#F7F7F4` | พื้นหน้าแอป | — |
| `surface` | `#FFFFFF` | การ์ด แถบหัวเรื่อง แผ่นล่าง | — |
| `surface-2` | `#EFEFEA` | ช่องพิมพ์ ปุ่มรอง โครงร่าง | — |
| `surface-3` | `#E5E5DF` | ปุ่มที่ปิดใช้งาน | — |
| `border` | `#E0E0DA` | เส้นคั่น (ไม่ใช้เป็นตัวบ่งชี้สถานะ) | 1.23:1 |
| `border-strong` | `#C9C9C2` | ขอบช่องติ๊ก/ตัวจับลาก | 1.66:1 |
| `t1` | `#15181D` | ข้อความหลัก | 16.58:1 |
| `t2` | `#545B66` | ข้อความรอง meta | 6.38:1 |
| `t3` | `#646C77` | ข้อความจาง เวลา ป้ายเล็ก | 4.95:1 |
| `accent` | `#2E4A8A` | ปุ่มหลัก ตัวอักษรเน้น | 7.94:1 |
| `accent-soft` | `#E8ECF7` | พื้นเน้น (ฟองผู้ใช้ ชิป) | ตัวอักษร accent บนพื้นนี้ 7.22:1 |
| `on-accent` | `#FFFFFF` | ตัวอักษรบนปุ่มทึบ | 8.53:1 |
| `success` / `-soft` | `#17683F` / `#E3F0E9` | สำเร็จ | 6.34:1 / คู่ 5.80:1 |
| `warning` / `-soft` | `#8A5A00` / `#FAF0DA` | รอ/ควรระวัง | 5.52:1 / คู่ 5.23:1 |
| `error` / `-soft` | `#A3241F` / `#FBE9E7` | ล้มเหลว | 6.91:1 / คู่ 6.33:1 |

### 1.2 สี — Dark

| Token | ค่า | บทบาท | คอนทราสต์บน `bg #0F1013` |
|---|---|---|---|
| `surface` | `#17191E` | การ์ด | — |
| `surface-2` | `#1F2228` | ช่องพิมพ์ | — |
| `border` | `#2A2E37` | เส้นคั่น | 1.40:1 |
| `t1` | `#E9EBEF` | ข้อความหลัก | 15.94:1 |
| `t2` | `#9CA3AF` | ข้อความรอง | 7.49:1 |
| `t3` | `#8A93A1` | ข้อความจาง | 6.13:1 |
| `accent` (ตัวเติม) | `#8CA4E8` | ปุ่มทึบ + ตัวอักษร `#0F1013` | 7.78:1 |
| `accent-ink` | `#A7B8EE` | ตัวอักษร/ไอคอนเน้น | 9.72:1 |
| `success` / `warning` / `error` | `#6BC08C` / `#DDAE5E` / `#EE8B84` | สถานะ | 8.65 / 9.32 / 7.85 |

**กฎการใช้สี**
1. สถานะต้องมี **ไอคอน + ข้อความ** เสมอ สีเป็นเพียงตัวช่วย
2. ปุ่มทึบในโหมดมืด = ตัวเติมสว่าง + ตัวอักษรเข้ม (Material 3) ห้ามใช้สีเข้ม+ตัวอักษรขาว
3. พื้น `*-soft` ใช้กับตัวอักษรสีเดียวกันเท่านั้น (คู่ที่คำนวณแล้วผ่าน AA)
4. เงาโหมดมืดเข้มกว่า 50–60% เพราะเงาจางมองไม่เห็นบนพื้นดำ

### 1.3 ตัวอักษร

| ฟอนต์ | บทบาท | เหตุผล |
|---|---|---|
| **Anuphan** (หลัก) | ทั้งแอป | ไทย+ละตินชุดเดียว ทรงเรขาคณิตอ่านง่าย มี 400/500/600 พอสำหรับ UI |
| IBM Plex Sans Thai (สำรอง) | ถ้าโหลด Anuphan ไม่ได้ | นิ่ง อ่านสบายบนจอเล็ก |
| ฟอนต์ระบบ | ทางเลือกที่ไม่ต้องเพิ่มไฟล์ | เลย์เอาต์ทดสอบแล้วไม่พัง |
| SF Mono | โค้ด พาธ แฮช | ใช้กับข้อความเทคนิคที่ซ่อนอยู่เท่านั้น |

**สเกล + Dynamic Type**

| Token | 100% | 115% | 130% | line-height | ใช้กับ |
|---|---|---|---|---|---|
| `fs-display` | 25 | 28.5 | 32.5 | 1.40 | คำทักทายสถานะว่าง |
| `fs-title` | 20 | 23 | 26 | 1.45 | หัวเรื่องหน้า |
| `fs-head` | 17 | 19.5 | 22 | 1.45 | ชื่อบทสนทนา หัวข้อผลลัพธ์ |
| `fs-body` | 16 | 18.5 | 21 | **1.62** | ข้อความ Agent/ผู้ใช้ |
| `fs-callout` | 15 | 17 | 19.5 | 1.60 | ชื่อขั้นตอนในไทม์ไลน์ |
| `fs-sub` | 14 | 16 | 18 | 1.60 | แถบสถานะสด การ์ด |
| `fs-foot` | 13 | 15 | 17 | 1.58 | ปุ่ม หมายเหตุ |
| `fs-cap` | 12 | 14 | 15.5 | 1.55 | เวลา ป้ายสถานะ |
| `fs-micro` | 11.5 | 13 | 14.5 | 1.55 | รายละเอียดย่อย |

**กฎไทย (บังคับ)**
- line-height เนื้อหา ≥ 1.45 เสมอ (ใช้ 1.62) เพราะวรรณยุกต์/สระบน-ล่างกินพื้นที่เกินกล่องตัวอักษร
- ห้ามความสูงตายตัวกับกล่องข้อความไทย → ใช้ padding + min-height
- ห้าม `minimumScaleFactor` (สระซ้อนทับ) → ตัดบรรทัดเพิ่มแทน
- ห้าม uppercase กับข้อความผสมไทย
- ตัดบรรทัดไทยตามพจนานุกรมของระบบ · `break-all` ใช้เฉพาะพาธ/URL/แฮช และต้องเป็นฟอนต์ mono
- ตัวเลขที่ต้องเทียบกันใช้ tabular numerals
- วันที่: ไทย → พ.ศ. + 24 ชม. (`28 ก.ย. 2568 · 14:12`) · อังกฤษ → ค.ศ. + 12 ชม. · สลับได้

### 1.4 ระยะห่าง · มุมโค้ง · เงา

| หมวด | ค่า |
|---|---|
| กริด | 4 pt → `4 · 8 · 12 · 16 · 20 · 24 · 32` (ใช้ 8/12/16 เป็นหลัก) |
| ระยะขอบข้าง | 16 pt (แชท) · 12 pt (ในกล่อง) · ระยะระหว่างกลุ่ม 16 pt |
| มุมโค้ง | ชิป 12–16 · การ์ด 16 · แผ่นล่าง 20 (มุมบน) · ช่องพิมพ์ 28 · ฟองผู้ใช้ 18 (มุมขวาล่าง 6) |
| เงา | ระดับ 1 การ์ด `0 1 2 rgba(18,20,26,.06)` · ระดับ 2 แถบสถานะสด `0 4 14 .08` · ระดับ 3 แผ่นล่าง `0 12 32 .14` |

### 1.5 ไอคอน (SF Symbols — ตรวจว่ามีใน iOS 15 ทุกตัว)

| ใช้กับ | ชื่อ |
|---|---|
| คิด / แผน | `sparkles` · `list.bullet.rectangle` |
| ค้นเว็บ / เปิดหน้าเว็บ / เรียกเว็บ | `magnifyingglass` · `globe` · `arrow.up.arrow.down.circle` |
| ไฟล์ | `doc.text` · `square.and.pencil` · `folder` · `arrow.down.circle` |
| รันคำสั่ง | `terminal` |
| สถานะ | `checkmark.circle.fill` · `clock` · `ellipsis.circle` · `exclamationmark.triangle.fill` · `minus.circle` · `slash.circle` |
| ความปลอดภัย/สิทธิ์ | `lock.fill` · `shield.lefthalf.filled` · `hand.raised.fill` |
| ทั่วไป | `plus` · `paperplane.fill` · `stop.fill` · `mic.fill` · `chevron.down` · `ellipsis` · `arrow.uturn.backward` |

กติกา: ห้ามฝัง icon font · ไอคอนที่สื่อสถานะต้องมีข้อความกำกับ · น้ำหนักเส้น `.medium`/`.semibold` สม่ำเสมอ · ขนาด 17–21 pt ในปุ่ม 44 pt

---

## 2. Component Library (สเปกรายตัว)

| คอมโพเนนต์ | Variants | States | ขนาด | Accessibility | พฤติกรรม |
|---|---|---|---|---|---|
| **Live Status Line** | running · waiting_user · done (ก่อนพับ) | — | 52 + 3 pt | ทั้งแถบเป็นปุ่ม · `role=status` `aria-live=polite` | แตะ = กาง/พับไทม์ไลน์ · เวลา = เวลาจริง |
| **Ribbon** | 3–8 ช่วง | done/active/pending | 3 pt | `aria-hidden` (มีข้อความกำกับข้าง ๆ) | ช่วง active = shimmer 1.4 วิ |
| **Step Icon** | 7 สถานะ | pending/running/waiting/succeeded/failed/skipped/cancelled | 22 pt | อ่านชื่อขั้น + สถานะ + เวลา | running = นาฬิกาเต้น 1.6 วิ |
| **Timeline Header** | กาง/พับ · ระดับกิจกรรม 3 แบบ | — | 52 pt | `aria-expanded` + `aria-controls` | จบงานพับอัตโนมัติ |
| **Card: thinking** | running · collapsed | — | 52 pt | ชื่อการ์ดอ่านออกเสียง | ตัวเอียง พื้นจาง พับหลังจบ |
| **Card: web_search** | running · done · failed | ตาม model | 52 + body | ปุ่มในแถวแหล่งข้อมูล ≥ 44 pt | running = skeleton ไม่ใช่สปินเนอร์ |
| **Card: browse** | done · masked-sensitive · screenshot(เตรียมไว้) | — | 52 + body | ชิป “แตะเพื่อแสดง” เป็นปุ่ม | ปิดบังข้อมูลอ่อนไหวค่าเริ่มต้น |
| **Card: file** | read · write · edit · delete(+undo) | pending/running/done/failed | 52 + body | ปุ่มเปิด/แชร์/ย้อนกลับ ≥ 38 pt | ไฟล์เปลี่ยนเครื่องมีป้าย “ต้องขออนุญาต” |
| **Card: code run** | collapsed · expanded · failed | — | 52 + body | `<details>` มีชื่อไทย | โค้ดซ่อนเป็นค่าเริ่มต้น |
| **Card: connector** | single · multi | — | 52 + body | ชิปสิทธิ์อ่านออกเสียง | ห้ามแสดงโทเคน |
| **Card: subagent** | expanded · collapsed · done | — | 52 + body | แต่ละเลนเป็นรายการที่อ่านได้ | ค่าเริ่มต้นพับเป็นแถบเดียว |
| **Card: plan** | list · plan-changed | — | 52 + body | เช็กลิสต์อ่านทีละข้อ | ทุกครั้งที่เปลี่ยนแผนมีแถบ “ปรับแผนแล้ว” |
| **Detail Sheet** | 
เนื้อหา 8 ชนิด | — | สูง 62–90% | `role=dialog` `aria-modal` | ปิดด้วยปุ่ม · ฉากมืด · ปัดลง |
| **Permission Sheet** | ปกติ · เสี่ยงสูง | รอการตัดสินใจ | ขึ้นกับเนื้อหา | โฟกัสไปที่ปุ่มแรก · ติ๊กยืนยันก่อนลบ | ไม่มี “อนุญาตเสมอ” ในกรณีลบ |
| **Scope Chooser** | 4 ระดับ | — | 56 pt ต่อแถว | `aria-pressed` ต่อตัวเลือก | ค่าเริ่มต้น = แคบที่สุด |
| **Ask User** | เลือกเดียว · หลายข้อ · ตอบแล้ว | waiting_user | 44 pt ต่อปุ่ม | ช่องพิมพ์มี label | มี “ให้ Agent ตัดสินใจเอง” เสมอ |
| **Input Bar** | ว่าง · กำลังพิมพ์ · ทำงาน(ปุ่มหยุด) · ปิด(รอผู้ใช้) · แนบไฟล์ล้มเหลว | — | 44–112 pt | placeholder ต้องบอกเหตุผลเมื่อปิด | ข้อความยาวขยายได้สูงสุด 112 pt |
| **Banner** | info · warn · err · ok | — | ขึ้นกับเนื้อหา | ไอคอน + หัวข้อ + ปุ่ม | ห้ามใช้ toast แทน error |
| **List Row** | static · ปุ่ม | — | 52 pt | ทั้งแถวเป็นปุ่มเมื่อกดได้ | สวิตช์ความปลอดภัยมีคำอธิบาย |
| **Toggle** | accent · success | on/off/disabled | 48×29 (แตะ 44) | `aria-pressed` + label | — |
| **Button** | primary · secondary · ghost · danger-line · danger-solid · small | default/pressed/disabled/focus | 44 (เล็ก 38) | ต้องมีชื่อ · ปุ่มที่ปิดต้องอธิบาย | กดแล้ว scale 0.98 + opacity |
| **Chip** | default · run · ok · warn · err · query | — | 36 pt (แตะรวม 44) | อ่านข้อความในชิป | — |
| **Progress** | รู้จำนวน · ไม่รู้จำนวน | — | 4–6 pt | ถ้ามี % ต้องมีข้อความ | ไม่รู้จำนวน = แถบไม่มีตัวเลข |
| **Skeleton** | 1–3 บรรทัด | — | 10 pt | `aria-hidden` + ข้อความคู่กัน | shimmer 1.5 วิ |
| **Toast** | — | เข้า/ออก | 38 pt | `role=status` | ใช้เฉพาะการยืนยันที่ไม่มีผลถาวร |
| **Tab Bar / App Header** | 4 แท็บ · 3 สถานะ Agent | — | 50 pt / 56 pt | แท็บละ label · จุดสถานะมีข้อความ | สลับแท็บด้วยนิ้วโป้ง |

---

## 3. สเปก Interaction & Animation

| จังหวะ | ระยะเวลา | easing | สิ่งที่เปลี่ยน | เมื่อเปิด “ลดการเคลื่อนไหว” |
|---|---|---|---|---|
| กดปุ่ม | 120 ms | ease-out | opacity .9 + scale .98 | เหมือนเดิม (สั้นมาก) |
| ขั้นตอนใหม่เลื่อนเข้า | 240 ms | `cubic-bezier(.2,.8,.2,1)` | opacity 0→1, translateY 8→0 | fade 120 ms |
| ขั้นที่ทำอยู่ (shimmer) | 1.5 วิ วน | linear | background-position 150%→−50% | หยุด shimmer → ใช้สีทึบ + ข้อความ |
| เช็กมาร์กตอนสำเร็จ | 260 ms | ease-out | stroke-dashoffset 22→0 | เข้มขึ้นทันที (ไม่วาด) |
| ข้อความสถานะเปลี่ยน | 240 ms | ease-in-out | crossfade (เก่าจาง 120 ms ก่อน) | fade 120 ms |
| การ์ดกาง/พับ | 200 ms | ease-out | opacity + ความสูงสูงสุด (ไม่ animate layout ของข้อความ) | ทันที |
| แผ่นล่างเลื่อนขึ้น | 240 ms / ฉากมืด 180 ms | ease-out | translateY 102%→0 | fade 120 ms |
| Toast | เข้า/ออก 180 ms | ease-out | opacity + translateY 8→0 | fade 120 ms |
| ริบบิ้นช่วงที่ทำอยู่ | 1.4 วิ วน | linear | สี shimmer | เปลี่ยนเป็นสีทึบ |

**กฎการสตรีมข้อความ**
1. รวมชิ้นข้อความก่อนวาด (แอปทำอยู่แล้ว: ทุก 80 ms) → ไม่กระตุกบน iPhone 7
2. **ห้ามดึงหน้าเลื่อนเองถ้าผู้ใช้กำลังอ่านข้างบน** — แสดงปุ่ม “ข้อความใหม่” แทน (มีในเฟส 1)
3. ข้อความที่ยังสตรีมอยู่ไม่ต้องมีแอนิเมชันเพิ่ม
4. เมื่อสตรีมจบ → แสดงปุ่มการกระทำ (คัดลอก/สร้างใหม่/แชร์) แบบ fade

**Haptics**: `light` เมื่อเริ่มงานและเมื่องานเสร็จ · `medium` เมื่อต้องขออนุญาตหรือมีขั้นล้มเหลว · **ห้ามสั่นระหว่างสตรีม**

**ห้ามทำ** (มีผลกับเครื่อง 2GB): แอนิเมชันที่เปลี่ยน width/height/position ของหลาย view พร้อมกัน · blur ซ้อนชั้น · เงาหลายชั้น · auto-scroll ที่แย่งกับผู้ใช้

---

## 4. Status Copy Library (ไทย / อังกฤษ)

### 4.1 ระหว่างทำ (ตามประเภทกิจกรรม)

| ประเภท (tool จริง) | ไทย | อังกฤษ |
|---|---|---|
| `thinking` | กำลังทำความเข้าใจคำขอ… | Understanding your request… |
| `plan` | กำลังวางแผน 4 ขั้นตอน… | Planning 4 steps… |
| `read_file` | กำลังอ่านไฟล์… | Reading a file… |
| `list_directory` | กำลังดูรายการโฟลเดอร์… | Listing a folder… |
| `search_files` | กำลังหาไฟล์ที่ตรงเงื่อนไข… | Finding matching files… |
| `search_content` | กำลังค้นข้อความในไฟล์… | Searching inside files… |
| `write_file` | กำลังบันทึกไฟล์… (ต้องขออนุญาต) | Saving a file… (permission needed) |
| `edit_file` | กำลังแก้บางจุดในไฟล์… | Editing a file… |
| `create_directory` | กำลังสร้างโฟลเดอร์… | Creating a folder… |
| `move_file` | กำลังย้ายไฟล์… | Moving a file… |
| `copy_file` | กำลังคัดลอกไฟล์… | Copying a file… |
| `delete_file` | กำลังลบไฟล์… (เสี่ยงสูง) | Deleting a file… (high risk) |
| `execute_shell` | กำลังรันคำสั่งบนเครื่อง… | Running a command on your device… |
| `http_request` | กำลังเรียกข้อมูลจากเว็บ… | Requesting data from a website… |
| `download_file` | กำลังดาวน์โหลดไฟล์… | Downloading a file… |
| `web_search` | กำลังค้นหาเว็บ… | Searching the web… |
| `fetch_webpage` | กำลังเปิดอ่านหน้าเว็บ… | Opening a web page… |
| `connector` | กำลังทำงานกับ {ชื่อบริการ}… | Working with {service}… |
| `subagent` | กำลังทำงานย่อย {n} งาน… | Running {n} subtasks… |
| `ask_user` | ขอถามก่อนทำต่อ | A quick question before I continue |
| `permission` | ต้องการอนุญาตก่อนทำต่อ | Needs your permission to continue |

### 4.2 เมื่อจบ / สถานะ

| สถานการณ์ | ไทย | อังกฤษ |
|---|---|---|
| ขั้นสำเร็จ | เสร็จแล้ว · ใช้เวลา {n} วินาที | Done · took {n}s |
| รอคิว | รอคิว — จะเริ่มหลังขั้นนี้เสร็จ | Queued — starts after the current step |
| รอผู้ใช้ | รอคุณตอบ | Waiting for you |
| ล้มเหลว (เน็ต) | อินเทอร์เน็ตขาดตอนระหว่างทำขั้นนี้ | The connection dropped during this step |
| ล้มเหลว (คำสั่งไม่มี) | เครื่องนี้ไม่มีคำสั่ง “{name}” — ลองวิธีอื่นได้ | This device has no “{name}” command — I can try another way |
| ข้ามไป | ข้ามขั้นนี้แล้ว เพราะไม่จำเป็นต่อผลลัพธ์ | Skipped — not needed for the result |
| ยกเลิก | ยกเลิกตามที่คุณสั่ง | Cancelled as you asked |
| งานจบทั้งงาน | ทำเสร็จแล้ว ใช้เวลา 1 นาที 12 วินาที | Done — took 1 minute 12 seconds |
| สำเร็จบางส่วน | ได้ผลลัพธ์แล้ว แต่ยังขาดส่วนอ้างอิงจากเว็บ | Results ready, but web citations are missing |
| ไม่สำเร็จทั้งหมด | ยังทำไม่ได้ในตอนนี้ — สาเหตุคือ {…} ลองใหม่ได้เลย | Couldn't finish — {reason}. You can retry. |
| ต้องขออนุญาต | ต้องการอนุญาตก่อน {การกระทำ} | Needs your permission to {action} |
| อนุญาตแล้ว | อนุญาตแล้ว — ทำงานต่อจากขั้นที่ {n} | Approved — continuing from step {n} |
| ปฏิเสธ | ไม่เป็นไร ผมจะไม่แตะ {สิ่งนั้น} และปรับแผนให้ | No problem — I won't touch it and will adjust the plan |
| บันทึกขอบเขต | บันทึกแล้ว: “ครั้งนี้เท่านั้น” — จะถามใหม่เมื่องานนี้จบ | Saved: “this time only” — I'll ask again when this task ends |
| เพิกถอนสิทธิ์ | เพิกถอนแล้ว — ครั้งหน้าจะถามใหม่ | Revoked — I'll ask again next time |
| คำสั่งแอบแฝง | หน้าเว็บนี้มีข้อความที่พยายามสั่งให้ทำสิ่งอื่น ผมไม่ทำตามและทำงานของคุณต่อ | That page contained instructions aimed at me — I ignored them and continued your task |
| ปิดบังข้อมูล | ข้อมูลส่วนตัวถูกปิดบังไว้ — กด “แตะเพื่อแสดง” ถ้าจำเป็น | Personal data is masked — tap to reveal if needed |
| ย้อนกลับได้ | ย้อนกลับได้อีก {m:ss} | You can undo for another {m:ss} |
| หมดเวลาย้อนกลับ | เลยเวลาย้อนกลับแล้ว — สำเนาเดิมยังอยู่ที่ {path} | The undo window has closed — a backup copy is still at {path} |
| เน็ตหลุด | อินเทอร์เน็ตขาดตอน งานหยุดชั่วคราวที่ขั้น {n} ผลที่ทำแล้วถูกเก็บไว้ครบ | Connection lost — paused at step {n}, results saved |
| กลับมาต่อ | สัญญาณกลับมาแล้ว ทำงานต่อจากจุดเดิม | Back online — continuing where I left off |
| ถูกจำกัดการใช้งาน | ผู้ให้บริการจำกัดการใช้งานชั่วคราว จะลองใหม่ในอีก {n} วินาที | The provider is rate-limiting; retrying in {n} seconds |
| โควตาหมด | โควตาของโมเดลนี้หมดแล้ว — ใช้โมเดลอื่นต่อได้เลย | This model's quota is used up — you can continue with another model |
| คีย์ผิด | คีย์ใช้งานไม่ถูกต้อง ต้องตรวจในหน้าตั้งค่า | The API key isn't valid — please check it in Settings |
| ไฟล์ใหญ่เกิน | ไฟล์ใหญ่เกินเพดานที่ตั้งไว้ ({limit}) | The file is larger than your limit ({limit}) |
| บริบทใกล้เต็ม | บริบทของห้องนี้ใช้ไป {n}% — ตัดประวัติเก่าหรือส่งออกก่อนได้ | This chat's context is {n}% full — trim or export first |
| รับช่วงต่อ | เว็บนี้ต้องให้คุณล็อกอินเอง ผมทำแทนไม่ได้ | You'll need to sign in yourself — I can't do this step |
| ส่งคืน Agent | เสร็จแล้ว ให้ Agent ทำต่อ | Done — hand back to the agent |
| งานถูกระบบระงับ | ระบบหยุดงานชั่วคราวตอนแอปอยู่เบื้องหลัง — กดทำต่อจากจุดเดิมได้เลย | iOS paused the task in the background — tap to resume from where it stopped |

**โทนภาษา:** กระชับ เป็นมิตร ไม่ตำหนิ ไม่ใช้คำเทคนิค ไม่ใช้เครื่องหมายอัศเจรีย์ และไม่ใช้คำว่า “พัก/Pause” (แอปทำไม่ได้จริง)

---

## 5. โครงสร้างข้อมูล Event สำหรับนักพัฒนา

### 5.1 Schema

```ts
type ActivityType =
  | 'thinking' | 'plan' | 'web_search' | 'browse' | 'read_file' | 'write_file'
  | 'run_code' | 'connector' | 'subagent' | 'ask_user' | 'permission';

type ActivityStatus =
  | 'pending' | 'running' | 'waiting_user' | 'succeeded' | 'failed' | 'skipped' | 'cancelled';

type Sensitivity = 'none' | 'personal' | 'financial' | 'credentials';

type ActivityEvent = {
  id: string;              // ไม่ซ้ำ ใช้ dedupe
  seq: number;             // ลำดับสำหรับเรียง (ห้ามใช้เวลาเรียง)
  parent_id?: string;      // ถ้าเป็นงานย่อย (subagent)
  type: ActivityType;
  status: ActivityStatus;
  title: { th: string; en: string };
  detail?: string;         // สรุปภาษาคน
  started_at?: number;     // epoch ms
  ended_at?: number;
  progress?: { done: number; total: number };   // ใส่เฉพาะเมื่อรู้จำนวนจริง
  requires_approval?: boolean;
  reversible?: boolean;    // ปัจจุบัน write/delete = false
  sensitivity: Sensitivity;
  sources?: { name: string; domain: string; url?: string; snippet?: string }[];
  artifacts?: { name: string; size: number; path?: string }[];
  error?: { code: string; user_message: string; retryable: boolean };
};
```

### 5.2 Lifecycle

```
started            updated (0..n)                 completed
  ├─ status=running ──► progress / การค้นพบกลางทาง ──► status=succeeded (+ ended_at)
  │                                                └► status=failed    (+ error)
  │                                                └► status=cancelled (ผู้ใช้หยุด)
  └─ status=pending ──► running ──► …                status=waiting_user (กลางทาง)
```

กติกา: `pending → running → (succeeded | failed | cancelled | skipped)` และ `waiting_user` เปลี่ยนกลับเป็น `running` ได้เมื่อผู้ใช้ตอบ · **ห้ามข้ามจาก pending ไป succeeded** (ผู้ใช้จะไม่เห็นว่างานเริ่ม)

### 5.3 การเชื่อมกับของจริง (`AgentEvent` ใน `AgentEngine.swift`)

| AgentEvent เดิม | แปลงเป็น |
|---|---|
| `assistantStarted(UUID)` | สร้าง event `type=thinking, status=running` |
| `assistantDelta(UUID, String)` | อัปเดตข้อความคำตอบ (ไม่สร้าง event ใหม่) |
| `assistantFinished(UUID, ChatMessage?)` | ปิด `thinking` → `succeeded` + `ended_at` |
| `toolStarted(ToolInvocation)` | สร้าง event ตาม `toolName` → `type` ที่ map ไว้ · `status=running` |
| `toolFinished(invocation:result:duration:)` | ปิด event → `succeeded`/`failed` + `ended_at` + `error{ retryable }` |
| `approvalRequested(ApprovalRequest)` | สร้าง event `type=permission, status=waiting_user, requires_approval=true` |
| `approvalResolved(id:decision:autoApproved:)` | ปิด event → `succeeded` (อนุญาต) / `cancelled` (ปฏิเสธ) |
| `status(String)` | ข้อความของแถบสถานะสด (ไม่สร้าง event) |
| `notice(String)` | แบนเนอร์ในแชท (ไม่สร้าง event) |
| `usage(TokenUsage)` | สะสมที่ตัวนับของงาน (ไม่แสดงเป็นขั้น) |
| `completed(reason)` | ปิด event ที่ค้างทั้งหมด + ปิดไทม์ไลน์ |

> เฟส 5 ให้ทำ **adapter** ชั้นนี้ก่อน เพื่อไม่ต้องแก้ backend/engine เดิม · เมื่อพร้อมจึงค่อยย้าย engine ให้ส่ง event ตาม schema ตรง ๆ

### 5.4 การ reconnect เมื่อเน็ตหลุด

| สถานการณ์ | กติกา |
|---|---|
| หลุดแล้วกลับมา | ส่ง event ซ้ำได้ทันที — **dedupe ด้วย `id`** (ถ้า id ซ้ำและ `seq` ใหม่กว่า = อัปเดตของเดิม ไม่สร้างใหม่) |
| เรียงลำดับ | ใช้ `seq` เท่านั้น (นาฬิกาเครื่องอาจเพี้ยน) |
| event มาถึงช้ากว่าที่ควร | ถ้า event นั้นถูกปิดไปแล้ว (`ended_at` มีค่า) ให้ **ทับเฉพาะข้อมูลที่ใหม่กว่า** (เทียบ `seq`) |
| งานถูกยกเลิกไปแล้ว | ทิ้ง event ที่ `seq` มาหลังเหตุการณ์ยกเลิก |
| ขาดช่วงกลาง (หายไปบาง seq) | แสดงขั้นที่หายเป็นขั้นทั่วไป “กำลังทำขั้นตอนหนึ่ง…” ไม่ล้มทั้งไทม์ไลน์ แล้วเติมเมื่อข้อมูลมาถึง |
| ข้อความสตรีมขาดกลาง | คงข้อความบางส่วนไว้ + หมายเหตุ “ข้อความอาจไม่ครบ” + ปุ่ม “สร้างใหม่” |

### 5.5 event ที่ไม่รู้จัก (Forward compatibility)

- **ห้าม crash และห้ามทิ้งไทม์ไลน์** — แสดงเป็นการ์ดทั่วไป “กำลังทำขั้นตอนหนึ่ง…” พร้อม `detail` ถ้ามี
- เก็บ `type` ดิบไว้ในไทม์ไลน์ เพื่อให้ตรวจย้อนหลังได้ และวันหลังค่อยเพิ่มการรองรับ
- ถ้า `status` ไม่รู้จัก → ถือเป็น `running` และปิดเมื่อมี event ปิด
- ถ้า `sensitivity` ไม่รู้จัก → ถือเป็น `personal` (ปลอดภัยไว้ก่อน) แล้วปิดบังค่าเริ่มต้น

### 5.6 ร่างโครง Swift (ใช้ในเฟส 5)

```swift
struct ActivityEvent: Codable, Identifiable, Equatable {
    let id: String
    let seq: Int
    let parentID: String?
    let type: String            // เก็บเป็น String เพื่อรองรับชนิดใหม่ในอนาคต
    var status: Status
    let title: LocalizedText
    var detail: String?
    var startedAt: Date?
    var endedAt: Date?
    var progress: Progress?
    var requiresApproval: Bool?
    var reversible: Bool?
    var sensitivity: Sensitivity
    var sources: [Source]?
    var artifacts: [Artifact]?
    var error: EventError?

    enum Status: String, Codable {
        case pending, running, waitingUser = "waiting_user"
        case succeeded, failed, skipped, cancelled
        // กันข้อมูลพัง: รองรับค่าที่ไม่รู้จัก
        init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Status(rawValue: raw) ?? .running
        }
    }
}
```

**การเก็บบนเครื่อง:** เขียนแบบ append-only เป็นไฟล์ต่อห้อง (`activity-<roomID>.jsonl`) จำกัดจำนวนล่าสุด (เช่น 2,000 บรรทัด) แล้วตัดของเก่า — เข้ากับแนวทางประหยัด RAM ของแอปเดิม

---

## 6. Edge Cases และคำแนะนำนักพัฒนา

| # | กรณี | คำแนะนำ |
|---|---|---|
| 1 | ค้นเว็บได้ 0 ผลลัพธ์ | ไม่ใช่ `failed` — ใช้ `succeeded` พร้อมข้อความ “ไม่พบผลลัพธ์ที่ตรง” + เสนอ “ลองคำค้นอื่น” (ทางเลือกที่ทำได้) |
| 2 | เรียก tool เดิมซ้ำ 3 ครั้งด้วยค่าเดิม | หยุดและถามผู้ใช้ (“ผมลองแบบเดิมซ้ำ 3 ครั้งแล้ว ต้องการให้ลองวิธีอื่นไหม”) |
| 3 | อ่านไฟล์ใหญ่มาก (หลายสิบ MB) | มี `progress` ที่รู้จำนวนจริง + จำกัดตัวอย่างที่แสดง (ตัดกลางไฟล์) และห้ามโหลดทั้งไฟล์เข้า RAM |
| 4 | โมเดลส่ง arguments ผิดรูปแบบ | จัดเป็น `failed` + `retryable=true` + ข้อความภาษาคน (“ผมตีความคำสั่งพลาด”) และลองใหม่ได้ทันที |
| 5 | iOS ระงับแอประหว่างงาน | ตอนเปิดใหม่: ตรวจ event ที่ค้าง → เปลี่ยนเป็น `waiting_user` พร้อมปุ่ม “ทำต่อจากตรงนี้” และข้อความ “ระบบหยุดงานชั่วคราว” |
| 6 | ผู้ใช้กดหยุดในจังหวะเดียวกับขั้นที่เพิ่งสำเร็จ | ให้ขั้นนั้นเป็น `succeeded` และขั้นถัดไปเป็น `cancelled` — ห้ามรายงานขั้นที่สำเร็จแล้วเป็น “ล้มเหลว” |
| 7 | เวลาของเครื่องเพี้ยน/เปลี่ยน timezone | เรียงด้วย `seq` · คำนวณเวลาที่ใช้จาก `ended_at - started_at` ของระบบ ไม่ใช้เวลาผู้ใช้ |
| 8 | ข้อความสตรีมขาดกลางทาง | คงข้อความบางส่วน + หมายเหตุ “ข้อความอาจไม่ครบ” + ปุ่มสร้างใหม่ (ไม่ลบทิ้ง) |
| 9 | ผลลัพธ์จาก tool ยาวมาก | จำกัดที่ 20 บรรทัด + พับ + ปุ่ม “แสดงทั้งหมด” (แอปมี `ToolOutputLimiter` อยู่แล้ว) |
| 10 | ข้อมูลอ่อนไหวโผล่ในผลลัพธ์ tool | ปิดบังก่อนเขียนลงไทม์ไลน์/บันทึก และห้ามส่งค่าเดิมเข้าโมเดลในรอบถัดไป |
| 11 | ชื่อขั้นตอนยาวมาก (ไทยผสมอังกฤษ) | ตัดที่ 1 บรรทัดด้วย … และเก็บข้อความเต็มไว้ใน `aria-label` + แผ่นรายละเอียด |
| 12 | ไม่รู้จำนวนขั้นทั้งหมด | ห้ามแสดง % หรือ “อีก n ขั้น” — ใช้ริบบิ้น/แถบไม่มีตัวเลข + ข้อความ |
| 13 | เครื่องร้อน/หน่วยความจำต่ำ | ลดคุณภาพเอง: ปิด shimmer → พับไทม์ไลน์อัตโนมัติ → ลดจำนวนข้อความที่วาด (มีกลไกในแอปแล้ว) |
| 14 | ผู้ใช้เปิดสองห้องสนทนาพร้อมกัน | ทำทีละงาน (คิว) — UI ต้องบอก “รอคิว” ไม่แสร้งว่ารันพร้อมกัน |

---

## 7. เหตุผลเบื้องหลังการตัดสินใจสำคัญ (7 ข้อ)

1. **ย้ายแถบสถานะสดมาเหนือช่องพิมพ์** — ผู้ใช้มองจุดเดียวตลอดเวลา ไม่ต้องเลื่อนหาว่า “ตอนนี้ทำอะไรอยู่” และยังอยู่ในโซนนิ้วโป้ง
2. **แสดง “ขั้นที่ n จาก m” แทน % หรือเวลาที่เหลือ** — เป็นข้อมูลที่รู้จริงจากแผน ส่วนเวลาที่เหลือต้องเดา จึงไม่แสดงเลย
3. **แยก “ลองใหม่” ออกจาก “วิธีอื่น”** — ความล้มเหลวบางชนิดลองใหม่แล้วล้มเหมือนเดิม (คำสั่งไม่มีในเครื่อง) การยัดปุ่มเดิมทุกกรณีทำให้ผู้ใช้เสียเวลาและลดความเชื่อถือ
4. **ค่าเริ่มต้นแคบที่สุดทุกเรื่อง** — ขอบเขตสิทธิ์ (ครั้งนี้เท่านั้น) · การปิดบังข้อมูลอ่อนไหว · ระดับกิจกรรม (ปกติ) · การยืนยันก่อนลบ
5. **สีเดียว + ไอคอน/ข้อความกำกับสถานะเสมอ** — แยกสีได้ยากและในโหมดมืดความต่างลดลง จึงไม่พึ่งสีเป็นสัญญาณเดียว
6. **ตัด Live Activity / Dynamic Island / ปุ่มอนุมัติจากแจ้งเตือน** — เครื่องเป้าหมายทำไม่ได้จริง (iPhone 7 / iOS 15) และการอนุมัติจากหน้าล็อกเสี่ยงกดพลาดโดยไม่เห็นบริบท
7. **แทนแท็บ “บันทึก” ด้วย “งานของฉัน”** — สิ่งที่ผู้ใช้สนใจคือ “งานเดินไปถึงไหน” ไม่ใช่ “เรียก tool อะไร” และบันทึกการเรียกใช้ยังเข้าถึงได้จากในหน้านั้น

---

## 8. สรุปรวม — เพิ่ม/แก้/ตัด อะไรจากพรอมต์ และทำไม (ทั้ง 4 เฟส)

**สิ่งที่ทำตรงตามพรอมต์**
- ครบทุกหัวข้อ: หน้าแชทหลัก · ระบบกิจกรรม 3 ระดับ · การ์ดทุกชนิด · การอนุมัติและขอบเขตสิทธิ์ · Takeover · การแจ้งเตือน · งานของฉัน · ต้นทุน/โควตา · โหมดเสียง · หน้ารอง · Component library · โทเคน · สเปกแอนิเมชัน · ชุดข้อความ · โครง event · edge cases
- ทุกหน้าจอมี Light/Dark ผ่านโทเคน · ทดสอบ iPhone 7 375×667 · ข้อความไทยยาวและไทยผสมอังกฤษ

**แก้จากพรอมต์ (และเหตุผล)**
| พรอมต์ระบุ | ทำเป็น | เพราะ |
|---|---|---|
| สีอบอุ่น/amber + Flutter | โทนกลาง + สีเน้นคราม `#2E4A8A` + SwiftUI | ตรวจเรโปแล้วแอปเป็น SwiftUI iOS 15 ไม่ใช่ Flutter · สีเดิมถูกทับตามที่สั่ง |
| Pause / Retry รายขั้น / Undo / ประมาณเวลา | “หยุด + ทำต่อจากผลเดิม” · “ลองใหม่ตั้งแต่ขั้นที่ล้มเหลว” · Undo เฉพาะเมื่อมีสำเนา · ไม่แสดงเวลา | engine จริงยังไม่มี ทำให้ผู้ใช้เข้าใจผิดไม่ได้ |
| Live Activity + Dynamic Island + ongoing notification (Android) | แจ้งเตือนปกติ + แบนเนอร์ในแอป | iPhone 7 / iOS 15 ทำไม่ได้ และโปรเจกต์ไม่มี Android |
| ปุ่ม Stop บนแจ้งเตือน | ตัดออก | กันกดพลาดจากหน้าล็อกที่มองไม่เห็นบริบท |
| ตัวบอกความมั่นใจเป็นตัวเลข | หมายเหตุ “ที่มาของตัวเลข” | ไม่มีข้อมูลความมั่นใจจริงจากโมเดล |
| Android 360×800 | iPhone 7 375×667 | เครื่องเป้าหมายจริงของแอป |
| Flutter/Dart components | SwiftUI + SF Symbols ล้วน | ไม่เพิ่ม dependency/ขนาดแอป |

**เพิ่มจากพรอมต์**
- แบนเนอร์เตือนก่อน iOS ระงับงานเบื้องหลัง + กติกาความปลอดภัยของแจ้งเตือน (ห้ามอนุมัติจากแจ้งเตือน)
- เกณฑ์การปิดบังข้อมูลอ่อนไหว 3 ระดับ + แถว “ดูทั้งหมด n แหล่ง”
- แถบ “ปรับแผนแล้ว” ทุกครั้งที่ Agent เปลี่ยนแผน รวมถึงหลังผู้ใช้พิมพ์แทรก
- หน้าจัดการสิทธิ์ที่เข้าถึงได้ 2 ทาง + สถานะว่างที่สร้างความมั่นใจ
- การเตือนช่องโหว่สวิตช์ “ถามอนุมัติทุกครั้ง” พร้อมกติกาบังคับ 4 ข้อ
- รายการ “สิ่งที่ต้องแก้ใน engine” 20 ข้อ เรียงลำดับที่ควรทำ

**ตัดจากพรอมต์**
- ไม่มี spinner เปล่า · ไม่มีตัวเลขประมาณการ · ไม่มีศัพท์เทคนิคในข้อความผู้ใช้ · ไม่มีภาพประกอบที่กิน RAM
- ไม่มีสถานะ “พักอัตโนมัติ” และไม่มีการรันหลายงานพร้อมกันจริง (บอกตามจริงเป็นคิว)
- ไม่มีไอคอนแบบอีโมจิหรือฟอนต์ไอคอน และไม่มีอีโมจิในเอกสารทั้งหมด

---

## 9. สิ่งที่เหลือสำหรับเฟส 5

**ต้องมีก่อนเริ่ม (ผู้ใช้เป็นคนทำ)**
1. **ยกเลิก token เก่าและออกใหม่แบบ Fine-grained** จำกัดเฉพาะ repo `Test` อายุ ≤ 7 วัน สิทธิ์: Contents · Pull requests · Actions · Workflows · Metadata (ตอนนี้ token ที่ให้มามีสิทธิ์ระดับ admin และ `delete_repo` — อันตรายกว่าสเปกมาก)
2. ยืนยันว่าจะทำ **TrollStore / palera1n / Sideloadly** ทางไหน (แอปไม่ได้ใช้ Apple Developer)
3. ยืนยันลำดับการทำ PR (7 ส่วนตามพรอมต์) และการเปิดใช้ feature flag “UI ใหม่ / UI เดิม”

**งานในเฟส 5 (ในโค้ดจริง)**
- PR 1: design tokens เป็น Swift (`Theme.swift`) + ฟอนต์ไทย + feature flag
- PR 2: หน้าแชท + input bar + แถบสถานะสด
- PR 3: ไทม์ไลน์ + การ์ด + แผ่นรายละเอียด + adapter จาก `AgentEvent`
- PR 4: การอนุมัติ + ขอบเขตสิทธิ์ + Takeover + ความปลอดภัย
- PR 5: งานของฉัน + การแจ้งเตือน + ต้นทุน/บริบท + หน้ารอง
- PR 6: งานเบื้องหลัง/แจ้งเตือนขั้นสูง (ตามข้อจำกัด iOS 15)
- PR 7: โหมดเสียง (ถ้าต้องการ) — ต้องขอสิทธิ์ไมโครโฟนเพิ่ม
- ทุก PR: build ผ่าน GitHub Actions + ลายเซ็นตามวิธีที่เลือก + คู่มือติดตั้งภาษาไทย

**เช็กลิสต์ก่อนส่งงานเฟส 5:** ไม่มี token/ความลับใน log-commit-PR · ไม่แตะ `main` · ฟีเจอร์เดิมครบ (regression list) · สลับกลับ UI เดิมได้ · ข้อความไทยไม่ล้น · VoiceOver/Reduce Motion/Dark mode ผ่าน · ทุกการกระทำที่มีผลต่อเครื่องยังต้องขออนุญาต

---

## 10. วิธีใช้ไฟล์ชุดนี้

| อยากทำอะไร | เปิดไฟล์ |
|---|---|
| ดูว่าหน้าจอจริงเป็นอย่างไร | `design-phase1.html` → `design-phase2.html` → `phase3-prototype.html` |
| ดูรายการคอมโพเนนต์ทั้งหมด + ทดลองแอนิเมชัน | `phase4-prototype.html` |
| เขียน SwiftUI ตามสเปก | ไฟล์นี้ (§1–§6) + `design-phase1-style.md` |
| ทำความเข้าใจกติกาความปลอดภัย | `design-phase2-cards-controls.md` §2–§3 + §9 ของไฟล์นี้ |
| เริ่มลงมือแก้โค้ด | `design-project-context.md` (ข้อเท็จจริงของแอป) + §9 ของไฟล์นี้ |
| อ่านสรุปทั้งหมดในหน้าเดียว | `summary.md` |
