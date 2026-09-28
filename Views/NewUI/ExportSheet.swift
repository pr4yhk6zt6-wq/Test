//
//  ExportSheet.swift
//  iOS Agent Sandbox — ดีไซน์ v2 (เฟส 5 ส่วนที่ 5)
//
//  แผ่น "ส่งออกการสนทนา" — ทุกเส้นทางมีคำเตือนเรื่องข้อมูลอ่อนไหว และค่าเริ่มต้นคือ "ปิดบังข้อมูล"
//  ตามกติกาใน design-phase2-cards-controls.md: การส่งออกเป็นจุดที่ข้อมูลส่วนตัวหลุดบ่อยที่สุด
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct ExportSheet: View {

    @ObservedObject var viewModel: ChatViewModel

    @Environment(\.presentationMode) private var presentationMode
    @AppStorage(SettingsKeys.chatFontScale) private var fontScale: Double = 1.0

    enum Format: String, CaseIterable, Identifiable {
        case markdown
        case json

        var id: String { rawValue }

        var title: String {
            switch self {
            case .markdown: return "Markdown (อ่านง่าย)"
            case .json: return "JSON (เก็บข้อมูลครบ)"
            }
        }
    }

    enum Scope: String, CaseIterable, Identifiable {
        case conversation
        case everything

        var id: String { rawValue }

        var title: String {
            switch self {
            case .conversation: return "เฉพาะบทสนทนา"
            case .everything: return "รวมรายละเอียดเครื่องมือ"
            }
        }
    }

    @State private var format: Format = .markdown
    @State private var scope: Scope = .conversation
    @State private var maskSensitive: Bool = true
    @State private var shareURL: ShareableURL?
    @State private var notice: String?

    var body: some View {
        VStack(alignment: .leading, spacing: DSMetrics.s5) {

            DSBanner(tone: .warning,
                     title: "ก่อนส่งออก — โปรดอ่าน",
                     message: "ไฟล์ที่ส่งออกจะเก็บข้อความทั้งหมดของห้องนี้ รวมทั้งคำสั่งที่ Agent ทำและผลลัพธ์ที่ได้ "
                        + "ถ้ามีข้อมูลส่วนตัวอยู่ในนั้นและคุณส่งต่อให้คนอื่น ข้อมูลจะออกไปด้วย",
                     scale: fontScale)

            VStack(alignment: .leading, spacing: DSMetrics.s2) {
                sectionTitle("รูปแบบไฟล์")
                Picker("รูปแบบไฟล์", selection: $format) {
                    ForEach(Format.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .frame(minHeight: DSMetrics.touch)
            }

            VStack(alignment: .leading, spacing: DSMetrics.s2) {
                sectionTitle("เนื้อหา")
                Picker("เนื้อหา", selection: $scope) {
                    ForEach(Scope.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .frame(minHeight: DSMetrics.touch)
                Text(scope == .conversation
                     ? "เอาเฉพาะข้อความที่คุณและ Agent พูดกัน ไม่รวมรายละเอียดการเรียกเครื่องมือ"
                     : "รวมคำสั่งและผลลัพธ์ของทุกขั้นตอน — เหมาะกับการตรวจย้อนหลัง แต่มีข้อมูลมากกว่า")
                    .font(DSFont.font(DSFont.sCap, scale: fontScale))
                    .foregroundColor(DSColor.t2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: DSMetrics.s2) {
                Button(action: {
                    DSHaptic.light()
                    maskSensitive.toggle()
                }) {
                    HStack(alignment: .top, spacing: DSMetrics.s3) {
                        Image(systemName: maskSensitive ? "checkmark.square.fill" : "square")
                            .font(DSFont.font(DSFont.sHead, scale: fontScale))
                            .foregroundColor(maskSensitive ? DSColor.success : DSColor.t3)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("ปิดบังข้อมูลอ่อนไหวก่อนบันทึก")
                                .font(DSFont.font(DSFont.sSub, weight: .medium, scale: fontScale))
                                .foregroundColor(DSColor.t1)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("ปิดรหัสผ่าน คีย์ อีเมล เบอร์โทร และเลขบัตรในไฟล์ที่ได้ (ใช้ได้กับ Markdown)")
                                .font(DSFont.font(DSFont.sCap, scale: fontScale))
                                .foregroundColor(DSColor.t2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: DSMetrics.touch)
                    .contentShape(Rectangle())
                }
                .buttonStyle(DSPressableStyle())
                .accessibilityAddTraits(maskSensitive ? [.isButton, .isSelected] : .isButton)
                .accessibilityLabel(Text("ปิดบังข้อมูลอ่อนไหวก่อนบันทึก"))
            }

            if let notice = notice {
                DSBanner(tone: .info, title: notice, scale: fontScale)
            }

            VStack(spacing: DSMetrics.s3) {
                DSButton(title: "สร้างไฟล์และแชร์",
                         icon: "square.and.arrow.up",
                         kind: .primary,
                         accessibilityHint: "เปิดหน้าต่างแชร์ของ iOS เพื่อส่งไฟล์ออกจากเครื่อง",
                         scale: fontScale,
                         action: { createFile() })

                DSButton(title: "คัดลอกเป็นข้อความ",
                         icon: "doc.on.doc",
                         kind: .secondary,
                         scale: fontScale,
                         action: { copyToClipboard() })
            }

            Text("ไฟล์ที่สร้างจะถูกเก็บไว้ในโฟลเดอร์ชั่วคราวของแอป และถูกลบเมื่อปิดแอปหรือล้างข้อมูล")
                .font(DSFont.font(DSFont.sMicro, scale: fontScale))
                .foregroundColor(DSColor.t3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .sheet(item: $shareURL) { item in
            ShareSheet(items: [item.url])
        }
    }

    // MARK: - การทำงาน

    private func createFile() {
        guard let content = buildContent() else {
            notice = "ยังไม่มีข้อความให้ส่งออก"
            return
        }
        let extensionName = (format == .markdown) ? "md" : "json"
        let name = "\(ChatRoomStore.safeExportName(viewModel.currentRoomName))-\(stamp()).\(extensionName)"
        guard let url = writeTemporaryFile(named: name, content: content) else {
            notice = "เขียนไฟล์ไม่สำเร็จ — ลองใหม่หรือใช้ปุ่มคัดลอกแทน"
            return
        }
        DSHaptic.success()
        shareURL = ShareableURL(url: url)
    }

    private func copyToClipboard() {
        guard let content = buildContent() else {
            notice = "ยังไม่มีข้อความให้คัดลอก"
            return
        }
        UIPasteboard.general.string = content
        DSHaptic.success()
        notice = maskSensitive
            ? "คัดลอกแล้ว (ปิดบังข้อมูลอ่อนไหวให้เรียบร้อย)"
            : "คัดลอกแล้ว — โปรดระวังข้อมูลส่วนตัวก่อนวางที่อื่น"
    }

    /// สร้างเนื้อหาตามตัวเลือก:
    /// - JSON หรือ "รวมรายละเอียดเครื่องมือ" = ใช้ไฟล์ที่แอปสร้างเอง (ข้อมูลครบตามที่แอปมี)
    /// - Markdown + เฉพาะบทสนทนา = สร้างใหม่ในหน้านี้ ทำให้ปิดบังข้อมูลได้จริง
    private func buildContent() -> String? {
        if format == .json {
            guard let url = viewModel.exportJSONURL() else { return nil }
            return (try? String(contentsOf: url, encoding: .utf8))
        }

        if scope == .everything {
            return viewModel.exportMarkdownText()
        }

        let lines = viewModel.messages.compactMap { message -> String? in
            switch message.role {
            case .user:
                guard !message.text.isEmpty else { return nil }
                var text = "### ผู้ใช้\n\n\(message.text)"
                if let attachments = message.attachments, !attachments.isEmpty {
                    let names = attachments.map { $0.originalName }.joined(separator: ", ")
                    text += "\n\n_ไฟล์แนบ: \(names)_"
                }
                return text
            case .assistant:
                guard !message.isTextEmpty else { return nil }
                return "### Agent\n\n\(message.text)"
            case .tool, .system:
                return nil
            }
        }

        guard !lines.isEmpty else { return nil }
        var header = "# \(viewModel.currentRoomName)\n\n"
        header += "_ส่งออกจาก iOS Agent Sandbox เมื่อ \(fullStamp())_\n"
        if maskSensitive {
            header += "_ข้อมูลอ่อนไหวถูกปิดบังไว้_\n"
        }
        let body = lines.joined(separator: "\n\n---\n\n")
        let raw = header + "\n" + body + "\n"
        return maskSensitive ? SensitiveMask.mask(raw).text : raw
    }

    private func writeTemporaryFile(named name: String, content: String) -> URL? {
        let directory = FileManager.default.temporaryDirectory
        let url = directory.appendingPathComponent(name)
        do {
            try content.data(using: .utf8)?.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    private func stamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmm"
        return formatter.string(from: Date())
    }

    private func fullStamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "th_TH")
        formatter.dateFormat = "d MMMM yyyy HH:mm"
        return formatter.string(from: Date())
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(DSFont.font(DSFont.sCap, weight: .semibold, scale: fontScale))
            .foregroundColor(DSColor.t3)
            .fixedSize(horizontal: false, vertical: true)
    }
}
