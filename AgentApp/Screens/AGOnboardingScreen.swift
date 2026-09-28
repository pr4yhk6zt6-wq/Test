//
//  AGOnboardingScreen.swift
//  AgentApp — แนะนำการใช้งาน 3 หน้า (ตามแบบ P3): เห็นทุกขั้น · ปลอดภัย · เริ่มใช้
//
//  ตั้งใจให้สั้น อ่านจบได้ในหน้าเดียวต่อหนึ่งแนวคิด และไม่ขอสิทธิ์ใด ๆ ก่อนผู้ใช้เห็นคุณค่า
//

import SwiftUI

struct AGOnboardingScreen: View {

    let onFinish: () -> Void

    @EnvironmentObject private var settings: AppSettings
    @State private var page: Int = 0
    @State private var apiKeyDraft: String = ""
    @State private var keyError: String?

    private var fontScale: Double { 1 }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: AGMetric.s2) {
                ForEach(0..<3, id: \.self) { index in
                    Capsule()
                        .fill(index <= page ? AGColor.accent : AGColor.surface3)
                        .frame(height: 3)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, AGMetric.screenPadding)
            .padding(.top, AGMetric.s4)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("หน้าที่ \(page + 1) จาก 3"))

            ScrollView {
                VStack(alignment: .leading, spacing: AGMetric.s4) {
                    switch page {
                    case 0: seeingPage
                    case 1: safetyPage
                    default: startPage
                    }
                }
                .padding(.horizontal, AGMetric.screenPadding)
                .padding(.vertical, AGMetric.s5)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            actions
        }
        .background(AGColor.bg)
    }

    // MARK: - หน้า 1: เห็นทุกขั้น

    private var seeingPage: some View {
        VStack(alignment: .leading, spacing: AGMetric.s4) {
            Image(systemName: "eye")
                .font(.system(size: 26, weight: .medium))
                .foregroundColor(AGColor.accentInk)
                .frame(width: AGMetric.touch, height: AGMetric.touch)
                .background(RoundedRectangle(cornerRadius: AGMetric.rSM, style: .continuous).fill(AGColor.accentSoft))
                .accessibilityHidden(true)

            Text("เห็นทุกขั้นตอนที่ Agent ทำ")
                .font(AGFont.font(AGFont.display, weight: .semibold, scale: fontScale))
                .foregroundColor(AGColor.t1)
                .fixedSize(horizontal: false, vertical: true)

            Text("แอปนี้ไม่ให้ Agent ทำงานแบบลับ ๆ ทุกครั้งที่ลงมือ คุณจะเห็นชื่อขั้นตอนที่กำลังทำ เวลาที่ใช้ และผลลัพธ์ที่ได้ — กดดูรายละเอียดได้ทุกขั้น")
                .font(AGFont.font(AGFont.body, scale: fontScale))
                .foregroundColor(AGColor.t2)
                .lineSpacing(AGFont.lineSpacing(AGFont.body, multiplier: AGFont.lhBody))
                .fixedSize(horizontal: false, vertical: true)

            demoCard
        }
    }

    private var demoCard: some View {
        AGCard(padding: AGMetric.s4) {
            VStack(alignment: .leading, spacing: 0) {
                AGStepRow(status: .succeeded, title: "อ่านไฟล์ในโฟลเดอร์ทำงาน", meta: "พบ 12 ไฟล์", isLast: false, scale: fontScale, action: { })
                AGStepRow(status: .succeeded, title: "สรุปเนื้อหาแต่ละไฟล์", meta: "สรุปแล้ว 12 ไฟล์", isLast: false, scale: fontScale, action: { })
                AGStepRow(status: .waitingUser, title: "ขออนุญาตเขียนไฟล์สรุป.md", meta: "รอคำตอบจากคุณ", isLast: true, scale: fontScale, action: { })
            }
        }
    }

    // MARK: - หน้า 2: ปลอดภัย

    private var safetyPage: some View {
        VStack(alignment: .leading, spacing: AGMetric.s4) {
            Image(systemName: "hand.raised")
                .font(.system(size: 26, weight: .medium))
                .foregroundColor(AGColor.warning)
                .frame(width: AGMetric.touch, height: AGMetric.touch)
                .background(RoundedRectangle(cornerRadius: AGMetric.rSM, style: .continuous).fill(AGColor.warningSoft))
                .accessibilityHidden(true)

            Text("คุณคุมทุกอย่างที่สำคัญ")
                .font(AGFont.font(AGFont.display, weight: .semibold, scale: fontScale))
                .foregroundColor(AGColor.t1)
                .fixedSize(horizontal: false, vertical: true)

            bullet("questionmark.circle", "ก่อน Agent จะเขียนทับหรือลบอะไร ระบบจะถามคุณก่อนเสมอ และจะบอกว่ากำลังจะทำอะไร ที่ไหน")
            bullet("arrow.uturn.backward", "ไฟล์ที่ Agent แก้จะถูกสำรองไว้ 10 นาที — กดย้อนกลับได้ทันทีถ้าไม่พอใจ")
            bullet("stop.circle", "กดหยุดได้ทุกเมื่อที่ต้องการ งานจะหยุดที่ขั้นปัจจุบัน ไม่มีการทำต่อเงียบ ๆ")
            bullet("eye.slash", "ข้อมูลอ่อนไหวอย่างรหัสผ่านหรือคีย์ จะถูกปิดบังก่อนแสดงผลและก่อนส่งออกไฟล์")

            AGBanner(tone: .info,
                     title: "สิ่งที่แอปนี้ไม่ทำ",
                     message: "ไม่มีการอนุมัติจากการแจ้งเตือนบนหน้าจอล็อก (ต้องเข้ามากดในแอป) · ไม่มีการประมาณเวลาที่เหลือ · ไม่มีงานตามเวลาที่ตั้งล่วงหน้า",
                     scale: fontScale)
        }
    }

    private func bullet(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: AGMetric.s3) {
            Image(systemName: icon)
                .font(AGFont.font(AGFont.callout, scale: fontScale))
                .foregroundColor(AGColor.t2)
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)
            Text(text)
                .font(AGFont.font(AGFont.sub, scale: fontScale))
                .foregroundColor(AGColor.t1)
                .lineSpacing(AGFont.lineSpacing(AGFont.sub, multiplier: AGFont.lhMeta))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - หน้า 3: เริ่มใช้

    private var startPage: some View {
        VStack(alignment: .leading, spacing: AGMetric.s4) {
            Image(systemName: "key")
                .font(.system(size: 26, weight: .medium))
                .foregroundColor(AGColor.accentInk)
                .frame(width: AGMetric.touch, height: AGMetric.touch)
                .background(RoundedRectangle(cornerRadius: AGMetric.rSM, style: .continuous).fill(AGColor.accentSoft))
                .accessibilityHidden(true)

            Text("เตรียมพร้อมก่อนเริ่ม")
                .font(AGFont.font(AGFont.display, weight: .semibold, scale: fontScale))
                .foregroundColor(AGColor.t1)
                .fixedSize(horizontal: false, vertical: true)

            Text("Agent ต้องใช้คีย์ของ OpenRouter (ผู้ให้บริการโมเดล) คีย์จะถูกเก็บไว้ใน Keychain ของเครื่องนี้เท่านั้น และไม่ถูกส่งไปที่อื่นนอกจากผู้ให้บริการ")
                .font(AGFont.font(AGFont.body, scale: fontScale))
                .foregroundColor(AGColor.t2)
                .lineSpacing(AGFont.lineSpacing(AGFont.body, multiplier: AGFont.lhBody))
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: AGMetric.s2) {
                SecureField("วางคีย์ที่ขึ้นต้นด้วย sk-or-…", text: $apiKeyDraft)
                    .font(AGFont.mono(AGFont.body, scale: fontScale))
                    .padding(.horizontal, AGMetric.s3)
                    .frame(minHeight: AGMetric.touch)
                    .background(RoundedRectangle(cornerRadius: AGMetric.rSM, style: .continuous).fill(AGColor.surface2))
                if let keyError = keyError {
                    Text(keyError)
                        .font(AGFont.font(AGFont.cap, scale: fontScale))
                        .foregroundColor(AGColor.error)
                        .fixedSize(horizontal: false, vertical: true)
                }
                AGButton(title: "บันทึกคีย์และเริ่มใช้งาน",
                         icon: "checkmark.circle.fill",
                         kind: .primary,
                         scale: fontScale,
                         hint: apiKeyDraft.isEmpty ? "ยังไม่ได้วางคีย์ — ข้ามไปก่อนได้ แล้วมาตั้งในหน้าตั้งค่า" : nil) {
                    saveKeyAndFinish()
                }
                AGButton(title: "ข้ามไปก่อน (ตั้งค่าทีหลังได้)", kind: .ghost, scale: fontScale) {
                    onFinish()
                }
            }

            AGBanner(tone: .info,
                     title: "โฟลเดอร์ทำงานเริ่มต้น",
                     message: "Agent จะทำงานใน \(settings.workspacePath) เป็นหลัก และจะขออนุญาตเป็นรายครั้งถ้าต้องแตะที่อื่น",
                     scale: fontScale)
        }
    }

    private func saveKeyAndFinish() {
        let trimmed = apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            onFinish()
            return
        }
        do {
            try settings.saveAPIKey(trimmed)
            AGHaptic.success()
            onFinish()
        } catch {
            keyError = "บันทึกคีย์ไม่สำเร็จ: \(error.localizedDescription) — ลองอีกครั้ง หรือข้ามไปตั้งค่าทีหลัง"
        }
    }

    // MARK: - ปุ่มเดินหน้า

    private var actions: some View {
        VStack(spacing: AGMetric.s2) {
            AGButton(title: page < 2 ? "ถัดไป" : "เริ่มใช้งานเลย",
                     icon: page < 2 ? "arrow.right" : nil,
                     kind: .primary,
                     scale: fontScale) {
                if page < 2 {
                    withAnimation(AGMotion.animation(AGMotion.ease)) { page += 1 }
                } else {
                    onFinish()
                }
            }
            if page > 0 {
                AGButton(title: "ย้อนกลับ", kind: .ghost, scale: fontScale) {
                    withAnimation(AGMotion.animation(AGMotion.ease)) { page -= 1 }
                }
            }
        }
        .padding(.horizontal, AGMetric.screenPadding)
        .padding(.top, AGMetric.s2)
        .padding(.bottom, AGMetric.s4)
        .background(AGColor.surface)
        .overlay(Rectangle().fill(AGColor.border).frame(height: 1), alignment: .top)
    }
}
