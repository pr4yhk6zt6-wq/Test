//
//  DSApprovalSheet.swift
//  iOS Agent Sandbox — ดีไซน์ v2 (เฟส 5 ส่วนที่ 4)
//
//  หน้าต่างขออนุญาตของ UI ใหม่ (แทน ApprovalSheetView เดิมในหน้าจอใหม่)
//  ยึดกติกาความปลอดภัยใน design-phase2-cards-controls.md:
//  - บอกให้ชัดว่า "จะทำอะไร ที่ไหน ผลคืออะไร" ก่อนให้ตัดสินใจ
//  - การลบไฟล์ (destructive) ต้องติ๊กยืนยันก่อน และไม่มีตัวเลือกจำสิทธิ์
//  - ระบุขอบเขตสิทธิ์ตามจริงของ engine ปัจจุบัน (ครั้งนี้เท่านั้น — ถามใหม่ทุกครั้ง)
//  - ไม่มีตัวเลขประมาณการ/คำสัญญาที่ระบบทำไม่ได้
//

import SwiftUI

struct DSApprovalSheet: View {

    let request: ApprovalRequest
    var scale: Double = 1.0
    let onDecision: (ApprovalDecision) -> Void

    @Environment(\.presentationMode) private var presentationMode
    @State private var confirmedDestructive: Bool = false

    private var isDestructive: Bool { request.isDestructive }

    private var maskedArguments: SensitiveMask.Result {
        SensitiveMask.maskAndLimit(request.argumentsText, maxCharacters: 2_000)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DSMetrics.s5) {

                header

                if isDestructive {
                    DSBanner(tone: .error,
                             title: "การกระทำนี้ย้อนกลับไม่ได้",
                             message: "การลบไฟล์บน iPhone ที่ยังไม่เจลเบรคเต็มรูปแบบกู้คืนไม่ได้ "
                                + "ถ้าไม่แน่ใจ ให้กด \"ไม่อนุญาต\" แล้วบอก Agent ว่าต้องการเก็บไฟล์ไว้",
                             scale: scale)
                }

                sectionTitle("จะทำอะไร")
                DSCardContainer(tone: .surface) {
                    Text(request.summary)
                        .font(DSFont.font(DSFont.sSub, scale: scale))
                        .foregroundColor(DSColor.t1)
                        .fixedSize(horizontal: false, vertical: true)
                    if let detail = request.detail, !detail.isEmpty {
                        Text(detail)
                            .font(DSFont.font(DSFont.sCap, scale: scale))
                            .foregroundColor(DSColor.t2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    HStack(spacing: DSMetrics.s2) {
                        DSChip(text: request.risk.level.thaiName,
                               tone: riskTone,
                               icon: "exclamationmark.triangle.fill",
                               scale: scale)
                        DSChip(text: request.thaiLabel, tone: .neutral, scale: scale)
                    }
                }

                if !request.risk.reasons.isEmpty {
                    sectionTitle("เหตุที่ระบบจัดว่าเสี่ยง")
                    VStack(alignment: .leading, spacing: DSMetrics.s2) {
                        ForEach(Array(request.risk.reasons.enumerated()), id: \.offset) { pair in
                            HStack(alignment: .top, spacing: DSMetrics.s2) {
                                Image(systemName: "circle.fill")
                                    .font(DSFont.font(6, scale: scale))
                                    .foregroundColor(DSColor.warning)
                                    .padding(.top, 6)
                                    .accessibilityHidden(true)
                                Text(pair.element)
                                    .font(DSFont.font(DSFont.sCap, scale: scale))
                                    .foregroundColor(DSColor.t2)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }

                sectionTitle("สิ่งที่ Agent จะส่งไป")
                DSCardContainer(tone: .surface) {
                    Text(maskedArguments.text.isEmpty ? "—" : maskedArguments.text)
                        .font(DSFont.mono(DSFont.sMicro, scale: scale))
                        .foregroundColor(DSColor.t1)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                    if maskedArguments.maskedCount > 0 {
                        Text("ข้อมูลส่วนตัว \(maskedArguments.maskedCount) จุดถูกปิดบังไว้ในหน้านี้")
                            .font(DSFont.font(DSFont.sMicro, scale: scale))
                            .foregroundColor(DSColor.t3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                sectionTitle("ขอบเขตของสิทธิ์")
                DSCardContainer(tone: .surface) {
                    Text("ครั้งนี้เท่านั้น — ระบบจะถามคุณใหม่ทุกครั้งที่ Agent จะทำแบบเดิมอีก")
                        .font(DSFont.font(DSFont.sCap, scale: scale))
                        .foregroundColor(DSColor.t2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("ถ้าคุณไม่อนุญาต Agent จะไม่แตะสิ่งนี้ และจะหาทางเลือกอื่นให้แทน")
                        .font(DSFont.font(DSFont.sMicro, scale: scale))
                        .foregroundColor(DSColor.t3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if isDestructive {
                    Button(action: {
                        DSHaptic.light()
                        confirmedDestructive.toggle()
                    }) {
                        HStack(alignment: .top, spacing: DSMetrics.s3) {
                            Image(systemName: confirmedDestructive ? "checkmark.square.fill" : "square")
                                .font(DSFont.font(DSFont.sHead, scale: scale))
                                .foregroundColor(confirmedDestructive ? DSColor.error : DSColor.t3)
                                .accessibilityHidden(true)
                            Text("ฉันเข้าใจว่าการลบนี้ย้อนกลับไม่ได้ และต้องการให้ Agent ลบต่อ")
                                .font(DSFont.font(DSFont.sCap, scale: scale))
                                .foregroundColor(DSColor.t1)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                        .frame(minHeight: DSMetrics.touch)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(DSPressableStyle())
                    .accessibilityAddTraits(confirmedDestructive ? [.isButton, .isSelected] : .isButton)
                    .accessibilityLabel(Text("ยืนยันว่าการลบนี้ย้อนกลับไม่ได้"))
                }

                actionButtons

                Text("ทำไมต้องถาม: แอปนี้ให้ Agent ทำงานกับไฟล์ในเครื่องของคุณ "
                     + "การอนุมัติทุกครั้งจึงเป็นการกันความเสียหายที่คุณไม่ได้ตั้งใจ")
                    .font(DSFont.font(DSFont.sMicro, scale: scale))
                    .foregroundColor(DSColor.t3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(DSMetrics.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(DSColor.bg)
        .accessibilityAddTraits(.isModal)
    }

    // MARK: - ชิ้นส่วน

    private var header: some View {
        HStack(alignment: .top, spacing: DSMetrics.s3) {
            DSIconBadge(icon: isDestructive ? "exclamationmark.triangle.fill" : "hand.raised.fill",
                        tint: isDestructive ? DSColor.error : DSColor.warning,
                        background: isDestructive ? DSColor.errorSoft : DSColor.warningSoft,
                        size: 36,
                        scale: scale)
            VStack(alignment: .leading, spacing: 4) {
                Text("ต้องการอนุญาตก่อนทำต่อ")
                    .font(DSFont.font(DSFont.sTitle, weight: .semibold, scale: scale))
                    .foregroundColor(DSColor.t1)
                    .fixedSize(horizontal: false, vertical: true)
                Text(isDestructive
                     ? "Agent กำลังจะทำสิ่งที่ย้อนกลับไม่ได้"
                     : "Agent หยุดรอคำตอบของคุณอยู่ — ไม่มีการทำงานใด ๆ เกิดขึ้นจนกว่าคุณจะเลือก")
                    .font(DSFont.font(DSFont.sCap, scale: scale))
                    .foregroundColor(DSColor.t2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private var actionButtons: some View {
        VStack(spacing: DSMetrics.s3) {
            DSButton(title: "อนุญาตครั้งนี้",
                     icon: "checkmark",
                     kind: isDestructive ? .dangerSolid : .primary,
                     isEnabled: !isDestructive || confirmedDestructive,
                     disabledReason: isDestructive && !confirmedDestructive
                        ? "ติ๊กยืนยันด้านบนก่อนจึงจะอนุญาตการลบได้"
                        : nil,
                     accessibilityHint: "Agent จะทำงานต่อทันที และจะถามใหม่เมื่อจะทำแบบเดิมอีก",
                     scale: scale) {
                finish(.allowOnce)
            }

            DSButton(title: "ไม่อนุญาต",
                     icon: "xmark",
                     kind: .secondary,
                     accessibilityHint: "Agent จะไม่แตะสิ่งนี้และจะหาทางเลือกอื่นให้",
                     scale: scale) {
                finish(.deny)
            }
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(DSFont.font(DSFont.sCap, weight: .semibold, scale: scale))
            .foregroundColor(DSColor.t3)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var riskTone: DSChip.Tone {
        switch request.risk.level {
        case .normal: return .success
        case .elevated: return .warning
        case .destructive: return .error
        }
    }

    private func finish(_ decision: ApprovalDecision) {
        if decision.isAllowed {
            DSHaptic.success()
        } else {
            DSHaptic.warning()
        }
        onDecision(decision)
        presentationMode.wrappedValue.dismiss()
    }
}
