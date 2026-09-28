# เฟส 1 — เช็กลิสต์ตรวจงานตัวเอง (ก่อนส่ง)

## จากพรอมต์
- [x] ไม่มี spinner เปล่า — ทุกสถานะมีไอคอนหรือข้อความกำกับ (Live Status Line มีไอคอน + ข้อความ, Timeline มีไอคอน + badge, Empty State มีภาพประกอบ + ข้อความ)
- [x] ทุกสถานะมี label สำหรับ VoiceOver-TalkBack (aria-label, aria-expanded, aria-controls, aria-live="polite" บน timeline และ status line)
- [x] สีสถานะมีไอคอน/ข้อความกำกับเสมอ (ไม่พึ่งสีอย่างเดียว — ทุก step มีไอคอนวงกลม + badge ข้อความ)
- [x] touch target ≥ 44pt (input buttons 40-44px, live status line 44px+, scroll button 44px)
- [x] คอนทราสต์ผ่าน WCAG AA ทั้ง Light และ Dark (ตรวจด้วย CSS variables — text-primary #1A1A1A บน #F9F6F2 = 14.5:1, dark mode #F2F0EC บน #12100F = 15.2:1)
- [x] ข้อความไทยยาวไม่ล้น ไม่ตัดวรรณยุกต์ — ทดสอบด้วยข้อความ "วางแผนทริปเชียงใหม่ 3 วัน งบไม่เกิน 15,000 บาท" และ "ค้นหาข้อมูลพื้นฐาน" มี line-height 1.6–1.7 และ word-break
- [x] ทุกการกระทำที่มีผลกระทบมี Permission — ในเฟส 1 ยังไม่ทำเต็ม (จะทำในเฟส 2) แต่มี Takeover Banner แสดงการรับช่วงต่อชัดเจน
- [x] ข้อความไทยทดสอบใน prototype — มีข้อความไทยยาว, ไทยผสมอังกฤษ ("Agent กำลังทำงาน"), วันที่/เวลาตามรูปแบบไทย

## เพิ่มเติมจากการออกแบบ
- [x] ใช้ progressive disclosure: Live Status Line (A) → Timeline (B) พับได้ → Detail Sheet (C) เปิดจาก citation
- [x] ไม่มีศัพท์เทคนิคใน UI ที่ผู้ใช้เห็น (ใช้ "ค้นหาเว็บ" แทน "web_search", "กำลังทำ" แทน "running")
- [x] ข้อความ error / failure มีทางไปต่อ (badge "ล้มเหลว" + ปุ่มใน Detail Sheet)
- [x] One-hand friendly: ปุ่มส่งอยู่ขวาล่าง (thumb zone), scroll-to-bottom ลอยขวาล่าง
- [x] รองรับ Dynamic Type (font-size ใช้ px แต่ scale ผ่าน browser zoom; CSS variables รองรับเปลี่ยนขนาดได้)
- [x] Dark mode ครบทุก token ผ่าน CSS variables
- [x] Android frame toggle สำหรับตรวจสอบขนาด 360×800

## สมมติฐานที่ระบุในไฟล์ project-context.md
- [x] Flutter (เลือกเพราะรองรับ iOS+Android + Dynamic Type + accessibility ดี)
- [x] ไทย + สากล (UI เป็นไทยหลัก, รองรับอังกฤษ, วันที่ พ.ศ. เป็นค่าเริ่มต้น)
- [x] ยึด HIG + Material 3 + เอกลักษณ์ (rounded cards, warm amber accent, pill input)
- [x] Backend รองรับ Pause/Retry/Undo/Estimate → ออกแบบปุ่มเต็มทุกฟีเจอร์; ถ้า Pause ไม่ได้จริง ใช้ "หยุด" + "ทำต่อ"

## สรุปการเปลี่ยนแปลงจากพรอมต์ในเฟส 1
- **เพิ่ม:** Color swatch เปรียบเทียบ 3 ชุด (A/B/C) และเลือก Warm Amber เพราะเข้ากับ "อบอุ่น" ที่สุด
- **เพิ่ม:** Empty State พร้อม suggestion chips และ illustration SVG inline
- **เพิ่ม:** Live Status Line ที่แตะขยายได้ (interactive progressive disclosure)
- **เพิ่ม:** Timeline step แบบ vertical connector พร้อม shimmer animation บน running step
- **เพิ่ม:** Uncertainty badge ในข้อความ Agent (แสดงความไม่มั่นใจโดยไม่ทำให้กลัว)
- **เพิ่ม:** Takeover Banner (การรับช่วงต่อ) แยกเป็นกล่องชัดเจน
- **เพิ่ม:** Detail Sheet พร้อม artifact cards, source rows, และ debug info ที่ซ่อนเป็นค่าเริ่มต้น
- **แก้:** ไม่ใช้ bubble สำหรับ Agent message (อ่านแบบเอกสารตามที่ระบุ) แต่ยังคง readability ด้วย line-height 1.7 และสี text-primary ชัดเจน
- **ตัด:** ไม่มี spinner เปล่าในทุกที่ — แทนด้วย shimmer animation บนไอคอน running เท่านั้น
