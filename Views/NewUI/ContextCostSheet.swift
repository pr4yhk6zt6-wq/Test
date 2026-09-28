//
//  ContextCostSheet.swift
//  iOS Agent Sandbox — ดีไซน์ v2 (เฟส 5 ส่วนที่ 5)
//
//  แผ่น "ต้นทุนและบริบท" — ยึดกติกาความซื่อสัตย์เรื่องตัวเลข:
//  โทเคนแสดงเฉพาะที่มีข้อมูลจริง • ค่าใช้จ่ายแสดงเมื่อผู้ให้บริการส่งมา ไม่มีการประมาณ
//  "เวลาที่เหลือ" ไม่แสดง (แอปไม่มีข้อมูลจริงให้คำนวณ) — ตรงกับที่ระบุไว้ในสเปกเฟส 3
//

import SwiftUI

struct ContextCostSheet: View {

    @ObservedObject var viewModel: ChatViewModel
    @ObservedObject private var usage: TokenUsageTracker = .shared

    @AppStorage(SettingsKeys.chatFontScale) private var fontScale: Double = 1.0
    @AppStorage(SettingsKeys.contextLengthTokens) private var contextLimitTokens: Int = 32_768

    var body: some View {
        VStack(alignment: .leading, spacing: DSMetrics.s5) {

            DSCardContainer(tone: .surface) {
                row(title: "โทเคนที่ส่งไป (คำถาม + บริบท)", value: number(usage.promptTokens))
                row(title: "โทเคนที่ได้กลับมา (คำตอบ)", value: number(usage.completionTokens))
                row(title: "รวมทั้งห้องนี้", value: number(usage.totalTokens), emphasized: true)
                row(title: "จำนวนคำขอที่ส่ง", value: number(usage.requestCount))
            }

            DSCardContainer(tone: .surface) {
                HStack {
                    Text("ค่าใช้จ่าย")
                        .font(DSFont.font(DSFont.sSub, weight: .medium, scale: fontScale))
                        .foregroundColor(DSColor.t1)
                    Spacer(minLength: DSMetrics.s2)
                    Text(costText)
                        .font(DSFont.font(DSFont.sSub, weight: .semibold, scale: fontScale))
                        .foregroundColor(DSColor.t1)
                }
                Text(usage.costCredits == nil
                     ? "ผู้ให้บริการไม่ได้ส่งข้อมูลค่าใช้จ่ายมาให้ แอปจึงไม่คำนวณเอง เพื่อไม่ให้คุณเห็นตัวเลขที่อาจไม่จริง"
                     : "ตัวเลขนี้มาจากผู้ให้บริการโดยตรง (เครดิตของ OpenRouter)")
                    .font(DSFont.font(DSFont.sCap, scale: fontScale))
                    .foregroundColor(DSColor.t2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            DSCardContainer(tone: contextTone) {
                Text("บริบทที่ใช้ไป")
                    .font(DSFont.font(DSFont.sSub, weight: .medium, scale: fontScale))
                    .foregroundColor(DSColor.t1)
                DSProgressBar(progress: contextProgress,
                              tone: contextProgressColor,
                              caption: contextCaption,
                              scale: fontScale)
                if contextNeedsTrim {
                    Text("เมื่อบริบทใกล้เต็ม คำตอบจะเริ่มตกหล่น — แนะนำให้ส่งออกบทสนทนาเก็บไว้ แล้วเริ่มห้องใหม่ หรือลบข้อความเก่าที่ไม่ใช้แล้ว")
                        .font(DSFont.font(DSFont.sCap, scale: fontScale))
                        .foregroundColor(DSColor.t2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            DSCardContainer(tone: .surface) {
                HStack {
                    Text("เวลาที่เหลือของงาน")
                        .font(DSFont.font(DSFont.sSub, weight: .medium, scale: fontScale))
                        .foregroundColor(DSColor.t1)
                    Spacer(minLength: DSMetrics.s2)
                    Text("ไม่แสดง")
                        .font(DSFont.font(DSFont.sSub, weight: .semibold, scale: fontScale))
                        .foregroundColor(DSColor.t2)
                }
                Text("แอปนี้ไม่ประมาณเวลาที่เหลือ เพราะไม่มีข้อมูลจริงจากผู้ให้บริการ — จะแสดงเมื่อมีข้อมูลจริงเท่านั้น")
                    .font(DSFont.font(DSFont.sCap, scale: fontScale))
                    .foregroundColor(DSColor.t2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - ชิ้นส่วน

    private func row(title: String, value: String, emphasized: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(DSFont.font(DSFont.sSub, weight: emphasized ? .semibold : .regular, scale: fontScale))
                .foregroundColor(emphasized ? DSColor.t1 : DSColor.t2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: DSMetrics.s2)
            Text(value)
                .font(DSFont.font(DSFont.sSub, weight: .semibold, scale: fontScale))
                .foregroundColor(DSColor.t1)
                .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(title): \(value)"))
    }

    private func number(_ value: Int) -> String {
        TokenUsageTracker.compact(value)
    }

    private var costText: String {
        guard let cost = usage.costCredits else { return "ไม่ระบุ" }
        return String(format: "%.4f เครดิต", cost)
    }

    private var contextProgress: Double? {
        let used = viewModel.estimatedContextTokens
        guard contextLimitTokens > 0, used > 0 else { return nil }
        return min(1.0, Double(used) / Double(contextLimitTokens))
    }

    private var contextPercent: Int {
        guard let progress = contextProgress else { return 0 }
        return Int((progress * 100).rounded())
    }

    private var contextCaption: String {
        let used = viewModel.estimatedContextTokens
        if contextLimitTokens <= 0 { return "ยังไม่ทราบเพดานบริบทของโมเดลนี้" }
        return "ใช้ไปประมาณ \(number(used)) จากเพดาน \(number(contextLimitTokens)) โทเคน (\(contextPercent)%)"
    }

    private var contextNeedsTrim: Bool {
        contextPercent >= 80
    }

    private var contextTone: DSCardTone {
        contextNeedsTrim ? .warning : .surface
    }

    private var contextProgressColor: Color {
        contextNeedsTrim ? DSColor.warning : DSColor.accent
    }
}
