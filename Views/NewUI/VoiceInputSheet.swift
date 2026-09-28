//
//  VoiceInputSheet.swift
//  iOS Agent Sandbox — ดีไซน์ v2 (เฟส 5 ส่วนที่ 8)
//
//  ชีต "พูดแทนการพิมพ์"
//  หลักการออกแบบ: ขออนุญาตอย่างมีบริบท (อธิบายก่อน ระบบเด้งกล่องขออนุญาตทีหลัง) ·
//  บอกตรง ๆ ว่าเสียงถูกประมวลผลที่ไหน · ข้อความที่ถอดได้ต้องผ่านตาผู้ใช้ก่อนเสมอ ·
//  ทุกสถานะมีทางไปต่อ (พิมพ์แทนได้ตลอด ไม่มีสปินเนอร์เปล่า ไม่มีทางตัน)
//

import SwiftUI
import UIKit

struct VoiceInputSheet: View {

    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    @AppStorage(SettingsKeys.chatFontScale) private var fontScale: Double = 1.0
    @StateObject private var voice = VoiceInputService()

    /// ส่งข้อความที่ผู้ใช้ยืนยันแล้วกลับไปที่ช่องพิมพ์ (ไม่ส่งเองอัตโนมัติ)
    let onUseText: (String) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DSMetrics.groupSpacing) {
                header
                privacyCard
                if !settings.voiceInputEnabled {
                    enableCard
                } else {
                    stateArea
                }
                footer
            }
            .padding(.horizontal, DSMetrics.screenPadding)
            .padding(.top, DSMetrics.s5)
            .padding(.bottom, DSMetrics.s8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(DSColor.bg)
        .onAppear {
            if settings.voiceInputEnabled { voice.prepare() }
        }
        .onDisappear { voice.stop() }
    }

    // MARK: - ส่วนหัว

    private var header: some View {
        HStack(alignment: .top, spacing: DSMetrics.s3) {
            Image(systemName: "mic.fill")
                .font(DSFont.font(DSFont.sTitle, weight: .semibold, scale: fontScale))
                .foregroundColor(DSColor.accentInk)
                .frame(width: DSMetrics.touch, height: DSMetrics.touch)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(DSColor.accentSoft))

            VStack(alignment: .leading, spacing: 4) {
                Text("พูดแทนการพิมพ์")
                    .font(DSFont.font(DSFont.sTitle, weight: .semibold, scale: fontScale))
                    .foregroundColor(DSColor.t1)
                    .fixedSize(horizontal: false, vertical: true)
                Text("ใช้ตอนถือมือเดียวหรือพิมพ์ยาวไม่สะดวก — ข้อความที่ได้จะรอให้คุณตรวจก่อนส่ง")
                    .font(DSFont.font(DSFont.sSub, scale: fontScale))
                    .foregroundColor(DSColor.t2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - บอกตรง ๆ ว่าเสียงไปไหน

    private var privacyCard: some View {
        DSCardContainer(tone: .surface) {
            HStack(alignment: .top, spacing: DSMetrics.s3) {
                Image(systemName: "lock.shield.fill")
                    .font(DSFont.font(DSFont.sCallout, weight: .semibold, scale: fontScale))
                    .foregroundColor(DSColor.success)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("เสียงของคุณถูกใช้อย่างไร")
                        .font(DSFont.font(DSFont.sSub, weight: .semibold, scale: fontScale))
                        .foregroundColor(DSColor.t1)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(processingExplanation)
                        .font(DSFont.font(DSFont.sCap, scale: fontScale))
                        .foregroundColor(DSColor.t2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("แอปไม่เก็บไฟล์เสียงไว้ในเครื่องหลังจบการพูด และข้อความที่ถอดได้จะไม่ถูกส่งเองจนคุณกดยืนยัน")
                        .font(DSFont.font(DSFont.sCap, scale: fontScale))
                        .foregroundColor(DSColor.t2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var processingExplanation: String {
        if voice.onDeviceOnly {
            return "เครื่องนี้ถอดเสียงให้ในตัว — เสียงไม่ถูกส่งออกไปที่อื่นเลย"
        }
        return "เครื่องนี้ยังถอดเสียงในตัวไม่ได้ จึงต้องใช้อินเทอร์เน็ตในการถอดเสียง (เสียงจะถูกส่งไปประมวลผลแล้วไม่ถูกเก็บไว้)"
    }

    // MARK: - ยังไม่เปิดใช้

    private var enableCard: some View {
        DSCardContainer(tone: .accent) {
            Text("โหมดเสียงยังปิดอยู่")
                .font(DSFont.font(DSFont.sSub, weight: .semibold, scale: fontScale))
                .foregroundColor(DSColor.t1)
            Text("โหมดเสียงปิดไว้เป็นค่าเริ่มต้น เพราะต้องใช้ไมโครโฟน เปิดเมื่อคุณต้องการใช้เท่านั้น ปิดคืนได้ทุกเมื่อในหน้าตั้งค่า")
                .font(DSFont.font(DSFont.sCap, scale: fontScale))
                .foregroundColor(DSColor.t2)
                .fixedSize(horizontal: false, vertical: true)
            DSButton(title: "เปิดใช้โหมดเสียง",
                     icon: "mic",
                     kind: .primary,
                     scale: fontScale,
                     accessibilityHint: "iOS จะถามอนุญาตใช้ไมโครโฟนและถอดเสียงเป็นข้อความ") {
                settings.voiceInputEnabled = true
                voice.prepare()
            }
            Text("ขั้นถัดไป: iOS จะถามอนุญาตใช้ไมโครโฟนและถอดเสียงเป็นภาษาไทย")
                .font(DSFont.font(DSFont.sMicro, scale: fontScale))
                .foregroundColor(DSColor.t3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - สถานะการใช้งาน

    @ViewBuilder
    private var stateArea: some View {
        switch voice.phase {
        case .idle:
            idleCard
        case .preparing:
            preparingCard
        case .listening:
            listeningCard
        case .denied:
            deniedCard
        case .unavailable(let message):
            problemCard(tone: .warning, title: "ยังใช้โหมดเสียงไม่ได้", message: message)
        case .failed(let message):
            problemCard(tone: .error, title: "ถอดเสียงไม่สำเร็จ", message: message)
        }
    }

    private var idleCard: some View {
        DSCardContainer(tone: .surface) {
            if voice.transcript.isEmpty {
                Text("พร้อมฟังแล้ว")
                    .font(DSFont.font(DSFont.sSub, weight: .semibold, scale: fontScale))
                    .foregroundColor(DSColor.t1)
                Text("กดปุ่มด้านล่างแล้วพูดเป็นภาษาไทย ระบบจะแสดงข้อความให้ตรวจทีละส่วน")
                    .font(DSFont.font(DSFont.sCap, scale: fontScale))
                    .foregroundColor(DSColor.t2)
                    .fixedSize(horizontal: false, vertical: true)
                startButton
            } else {
                Text("ตรวจข้อความก่อนใช้")
                    .font(DSFont.font(DSFont.sSub, weight: .semibold, scale: fontScale))
                    .foregroundColor(DSColor.t1)
                reviewBox
                DSButton(title: "ใช้ข้อความนี้",
                         icon: "checkmark.circle.fill",
                         kind: .primary,
                         scale: fontScale,
                         accessibilityHint: "ข้อความจะถูกใส่ในช่องพิมพ์ ให้คุณตรวจอีกครั้งก่อนส่ง") {
                    useTranscript()
                }
                DSButton(title: "พูดใหม่",
                         icon: "arrow.clockwise",
                         kind: .secondary,
                         scale: fontScale) {
                    voice.reset()
                    voice.start()
                }
            }
        }
    }

    private var preparingCard: some View {
        DSCardContainer(tone: .surface) {
            Text("กำลังขออนุญาตจากระบบ")
                .font(DSFont.font(DSFont.sSub, weight: .semibold, scale: fontScale))
                .foregroundColor(DSColor.t1)
            Text("ถ้ามีกล่องขออนุญาตของ iOS ขึ้นมา กด \"อนุญาต\" เพื่อให้ถอดเสียงได้")
                .font(DSFont.font(DSFont.sCap, scale: fontScale))
                .foregroundColor(DSColor.t2)
                .fixedSize(horizontal: false, vertical: true)
            DSSkeleton(lines: 2, scale: fontScale)
        }
    }

    private var listeningCard: some View {
        DSCardContainer(tone: .accent) {
            HStack(alignment: .center, spacing: DSMetrics.s3) {
                DSStatusGlyph(status: .running, scale: fontScale)
                Text("กำลังฟัง… พูดได้เลย")
                    .font(DSFont.font(DSFont.sSub, weight: .semibold, scale: fontScale))
                    .foregroundColor(DSColor.t1)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            levelMeter
            if !voice.transcript.isEmpty {
                reviewBox
            }
            DSButton(title: "หยุดและใช้ข้อความ",
                     icon: "stop.fill",
                     kind: .primary,
                     scale: fontScale,
                     accessibilityHint: "หยุดฟัง แล้วนำข้อความที่ได้ไปตรวจในช่องพิมพ์") {
                voice.stop()
            }
            DSButton(title: "ยกเลิกการพูด",
                     icon: "xmark",
                     kind: .ghost,
                     scale: fontScale) {
                voice.reset()
                voice.stop()
                dismiss()
            }
        }
    }

    private var deniedCard: some View {
        DSCardContainer(tone: .warning) {
            HStack(alignment: .top, spacing: DSMetrics.s3) {
                DSStatusGlyph(status: .waitingUser, scale: fontScale)
                VStack(alignment: .leading, spacing: 4) {
                    Text("ยังไม่ได้รับอนุญาตใช้ไมโครโฟน")
                        .font(DSFont.font(DSFont.sSub, weight: .semibold, scale: fontScale))
                        .foregroundColor(DSColor.t1)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("เปิดได้ที่ ตั้งค่า → ความเป็นส่วนตัวและความปลอดภัย → ไมโครโฟน → iOS Agent Sandbox แล้วกลับมาเปิดชีตนี้ใหม่")
                        .font(DSFont.font(DSFont.sCap, scale: fontScale))
                        .foregroundColor(DSColor.t2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            DSButton(title: "เปิดการตั้งค่าแอป",
                     icon: "gearshape.fill",
                     kind: .secondary,
                     scale: fontScale) {
                openAppSettings()
            }
            DSButton(title: "พิมพ์แทน",
                     icon: "keyboard",
                     kind: .ghost,
                     scale: fontScale) {
                dismiss()
            }
        }
    }

    private func problemCard(tone: DSBanner<EmptyView>.Tone, title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: DSMetrics.s3) {
            DSBanner(tone: tone, title: title, message: message, scale: fontScale)
            DSButton(title: "ลองอีกครั้ง",
                     icon: "arrow.clockwise",
                     kind: .secondary,
                     scale: fontScale) {
                voice.reset()
                voice.start()
            }
            DSButton(title: "พิมพ์แทน",
                     icon: "keyboard",
                     kind: .ghost,
                     scale: fontScale) {
                dismiss()
            }
        }
    }

    private var footer: some View {
        Text("โหมดเสียงเป็นตัวเลือกเสริม — ปิดไว้ได้ตลอดจากหน้าตั้งค่า และทุกอย่างยังใช้การพิมพ์ได้ตามปกติ")
            .font(DSFont.font(DSFont.sMicro, scale: fontScale))
            .foregroundColor(DSColor.t3)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - ชิ้นส่วน

    private var startButton: some View {
        Button(action: {
            DSHaptic.medium()
            voice.start()
        }) {
            HStack(spacing: DSMetrics.s3) {
                Image(systemName: "mic.fill")
                    .font(DSFont.font(DSFont.sHead, weight: .semibold, scale: fontScale))
                Text("เริ่มพูด")
                    .font(DSFont.font(DSFont.sCallout, weight: .semibold, scale: fontScale))
            }
            .foregroundColor(DSColor.onAccent)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 52)
            .background(RoundedRectangle(cornerRadius: DSMetrics.rField, style: .continuous).fill(DSColor.accent))
        }
        .buttonStyle(DSPressableStyle())
        .accessibilityLabel(Text("เริ่มพูด"))
        .accessibilityHint(Text("เริ่มฟังเสียงของคุณเป็นภาษาไทย"))
    }

    private var reviewBox: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(voice.transcript)
                .font(DSFont.font(DSFont.sBody, scale: fontScale))
                .foregroundColor(DSColor.t1)
                .fixedSize(horizontal: false, vertical: true)
            Text("ยังไม่ถูกส่ง — ตรวจแก้ได้ในช่องพิมพ์ก่อนกดส่ง")
                .font(DSFont.font(DSFont.sMicro, scale: fontScale))
                .foregroundColor(DSColor.t3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DSMetrics.s3)
        .background(RoundedRectangle(cornerRadius: DSMetrics.rField, style: .continuous).fill(DSColor.surface2))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("ข้อความที่ถอดได้: \(voice.transcript)"))
    }

    private var levelMeter: some View {
        HStack(spacing: 3) {
            ForEach(0..<12, id: \.self) { index in
                let threshold = Float(index + 1) / 12
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(voice.level >= threshold ? DSColor.accent : DSColor.surface3)
                    .frame(width: 5, height: 10 + CGFloat(index) * 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("ระดับเสียงที่ได้ยิน"))
        .accessibilityValue(Text(levelDescription))
    }

    private var levelDescription: String {
        if voice.level >= 0.6 { return "ดัง" }
        if voice.level >= 0.25 { return "ได้ยินชัด" }
        if voice.level > 0.05 { return "เบา" }
        return "ยังไม่ได้ยินเสียง"
    }

    // MARK: - การทำงาน

    private func useTranscript() {
        let text = voice.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        DSHaptic.success()
        voice.stop()
        onUseText(text)
        dismiss()
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }
}
