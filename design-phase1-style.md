# เฟส 1 — รากฐานสไตล์

## ตัวอักษร

- **หลัก:** IBM Plex Sans Thai (รองรับไทย/อังกฤษสมบูรณ์, รูปทรงเรขาคณิตอ่านง่าย, มีน้ำหนักหลายระดับ)
- **สำรอง:** Noto Sans Thai (fallback ถ้า IBM Plex ไม่โหลด, มีตัวหนาครบทุกน้ำหนัก)
- **เหตุผล:** IBM Plex Sans Thai มี kerning ไทยที่ดี, วรรณยุกต์ไม่ชนขอบ, รองรับ Dynamic Type ได้ดีใน Flutter

## Typography Scale (pt)

| ระดับ | ขนาด (iOS) | น้ำหนัก | การใช้ |
|---|---|---|---|
| H1 | 28 | Bold (700) | หัวเรื่องหลักในหน้าแชทว่าง |
| H2 | 22 | Semibold (600) | ชื่อบทสนทนา |
| Body | 16 | Regular (400) | ข้อความ Agent |
| Body Small | 14 | Regular (400) | รายละเอียดขั้นตอน |
| Caption | 12 | Medium (500) | Timestamp, label สถานะ |

- line-height: 1.6 สำหรับ Body, 1.4 สำหรับ Caption
- letter-spacing: 0.01em (Body), 0.02em (Caption)

## สี — เปรียบเทียบ 3 Swatch

### A. Warm Amber (แนะนำ)
- Background: #F9F6F2 (cream warm)
- Surface: #FFFFFF
- Accent: #C47F2A (amber deep, ไม่ฉูดฉาด)
- Success: #2D6A4F
- Warning: #9C6B1E
- Error: #8B2E2E
- Text Primary: #1A1A1A
- Text Secondary: #6B5E56

### B. Calm Teal
- Background: #F0F4F5
- Surface: #FFFFFF
- Accent: #2A7F8C
- Success: #2D6A4F
- Warning: #B07A1E
- Error: #8B2E2E

### C. Deep Indigo + Gold
- Background: #F4F4F6
- Surface: #FFFFFF
- Accent: #5A4A8A
- Success: #2D6A4F
- Warning: #C4A03D
- Error: #8B2E2E

**เลือก A (Warm Amber):** เข้ากับ "อบอุ่น เป็นกันเอง" มากที่สุด สี amber ไม่รบกวนการอ่านนาน และตัดกับพื้น cream ได้ดีโดยไม่เหนื่อยตา

## Spacing & Grid

- Base unit: 4pt → 8pt, 16pt, 24pt, 32pt
- Padding ขอบหน้าจอ: 16pt (iOS), 16pt (Android)
- Card radius: 20pt (iOS style), 16pt (Android) — ใช้ 18pt เป็นค่าเดียวทั้งแอปเพื่อความสม่ำเสมอ
- Elevation (shadow): 0 2px 8px rgba(0,0,0,0.06) สำหรับ card, 0 4px 16px rgba(0,0,0,0.08) สำหรับ sheet

## Radius & Shape

- Input bar: 28pt (pill-shaped)
- Chip: 20pt
- Button: 14pt
- Card (Agent message): 0 radius ด้านซ้าย, 20pt ด้านขวา (อ่านแบบเอกสาร)
- Card (User message): 20pt ทุกมุม (bubble)

## Icons

- Stroke 2px สม่ำเสมอ
- ขนาดมาตรฐาน: 24pt (ปุ่ม), 20pt (ในข้อความ), 16pt (เล็ก)
- Set: Phosphor-style (rounded stroke, friendly) — ใช้ SVG inline ใน prototype
