//
//  AGFilePreviewSheet.swift
//  AgentApp — เปิดดูไฟล์ (อ่านอย่างเดียว) พร้อมปิดบังข้อมูลอ่อนไหวและปุ่มส่งต่อให้ Agent
//
//  เหตุผลที่แก้ไฟล์ตรงนี้ไม่ได้: การแก้ไฟล์ของผู้ใช้ต้องผ่าน Agent เพื่อให้ระบบสำรองไฟล์ไว้ก่อน
//  (ย้อนกลับได้ 10 นาที) — ตรงกับคำสัญญาเรื่อง "ย้อนกลับได้จริง" ของดีไซน์
//

import SwiftUI
import UIKit

struct AGFilePreviewSheet: View {

    let path: String
    var fontScale: Double = 1
    let onGiveToAgent: () -> Void

    @State private var text: String = ""
    @State private var maskedCount: Int = 0
    @State private var revealed: Bool = false
    @State private var isBinary: Bool = false
    @State private var isLoading: Bool = true
    @State private var errorText: String?
    @State private var shareBox: ShareBox?
    @State private var copied: Bool = false

    private var fileName: String { (path as NSString).lastPathComponent }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AGMetric.s4) {
                infoCard

                if maskedCount > 0 {
                    AGBanner(tone: .warning,
                             title: "พบข้อมูลอ่อนไหว \(maskedCount) จุด",
                             message: revealed ? "คุณกำลังเห็นข้อมูลจริง — ระวังเวลาแชร์หน้าจอหรือส่งไฟล์ต่อ"
                                               : "ระบบปิดบังให้ก่อนโดยอัตโนมัติ ถ้าจำเป็นต้องเห็นจึงกดปุ่มด้านล่าง",
                             scale: fontScale)
                    AGButton(title: revealed ? "ซ่อนข้อมูลอีกครั้ง" : "แตะเพื่อแสดงข้อมูลจริง",
                             icon: revealed ? "eye.slash" : "eye",
                             kind: .secondary,
                             scale: fontScale) {
                        revealed.toggle()
                    }
                }

                if isLoading {
                    VStack(alignment: .leading, spacing: AGMetric.s2) {
                        Text("กำลังอ่านไฟล์…")
                            .font(AGFont.font(AGFont.sub, scale: fontScale))
                            .foregroundColor(AGColor.t2)
                        AGSkeleton(lines: 6, scale: fontScale)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("กำลังอ่านไฟล์"))
                } else if let errorText = errorText {
                    AGBanner(tone: .error,
                             title: "เปิดไฟล์นี้ไม่ได้",
                             message: errorText,
                             scale: fontScale)
                } else if isBinary {
                    AGBanner(tone: .info,
                             title: "ไฟล์นี้ไม่ใช่ข้อความ",
                             message: "เปิดดูในแอปไม่ได้ (ไฟล์รูปหรือไฟล์ไบนารี) — ใช้ปุ่ม \"แชร์ไฟล์\" เพื่อเปิดด้วยแอปอื่น หรือให้ Agent อธิบายไฟล์นี้แทน",
                             scale: fontScale)
                } else {
                    AGCodeBlock(language: languageName, code: text, scale: fontScale)
                    if text.count >= 4_000 {
                        Text("แสดงเฉพาะตอนต้นของไฟล์ (จำกัดเพื่อความลื่นไหล) — ถ้าต้องการทั้งไฟล์ ให้บอก Agent ให้สรุปหรือให้แชร์ไฟล์ออกไป")
                            .font(AGFont.font(AGFont.micro, scale: fontScale))
                            .foregroundColor(AGColor.t3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                actions
            }
            .padding(.horizontal, AGMetric.screenPadding)
            .padding(.vertical, AGMetric.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 620)
        .onAppear(perform: load)
        .sheet(item: $shareBox) { box in
            AGShareSheet(items: [box.url])
        }
    }

    private var infoCard: some View {
        AGCard(padding: AGMetric.s4) {
            VStack(alignment: .leading, spacing: AGMetric.s2) {
                Text(fileName)
                    .font(AGFont.font(AGFont.sub, weight: .semibold, scale: fontScale))
                    .foregroundColor(AGColor.t1)
                    .fixedSize(horizontal: false, vertical: true)
                Text(path)
                    .font(AGFont.mono(AGFont.micro, scale: fontScale))
                    .foregroundColor(AGColor.t2)
                    .lineLimit(3)
                    .truncationMode(.middle)
                if let attributes = try? FileSystemService.attributes(of: path) {
                    HStack(spacing: AGMetric.s2) {
                        AGChip(text: AGFormat.bytes(Int(attributes.sizeBytes)), tone: .neutral, scale: fontScale)
                        if let date = attributes.modificationDate {
                            AGChip(text: AGFormat.time(date), tone: .neutral, scale: fontScale)
                        }
                    }
                }
            }
        }
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: AGMetric.s2) {
            AGButton(title: "แชร์ไฟล์นี้", icon: "square.and.arrow.up", kind: .secondary, scale: fontScale) {
                shareBox = ShareBox(URL(fileURLWithPath: path))
                AGHaptic.light()
            }
            AGButton(title: "ให้ Agent แก้ไฟล์นี้ (มีการสำรองก่อนแก้)", icon: "wand.and.stars", kind: .primary, scale: fontScale) {
                onGiveToAgent()
            }
            AGButton(title: copied ? "คัดลอกพาธแล้ว" : "คัดลอกพาธ", icon: "doc.on.doc", kind: .ghost, scale: fontScale) {
                UIPasteboard.general.string = path
                copied = true
                AGHaptic.light()
            }
            Text("การแก้ไฟล์ด้วยมือในแอป (นอก Agent) จะไม่มีการสำรองให้ย้อนกลับ จึงไม่เปิดให้ทำจากหน้านี้")
                .font(AGFont.font(AGFont.micro, scale: fontScale))
                .foregroundColor(AGColor.t3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var languageName: String? {
        let ext = (fileName as NSString).pathExtension
        return ext.isEmpty ? nil : ext.lowercased()
    }

    private func load() {
        isLoading = true
        errorText = nil
        do {
            let prefix = try FileSystemService.readPrefix(path, maxBytes: 48 * 1024)
            if prefix.isBinary {
                isBinary = true
                text = ""
            } else {
                let masked = SensitiveMask.mask(prefix.text)
                text = masked.text
                maskedCount = masked.maskedCount
            }
        } catch {
            errorText = error.localizedDescription
        }
        isLoading = false
    }
}

/// กล่องห่อ URL ให้ใช้กับ .sheet(item:) (URL ไม่ได้เป็น Identifiable)
struct ShareBox: Identifiable {

    let url: URL
    var id: String { url.absoluteString }

    init(_ url: URL) { self.url = url }
}

/// ตัวเปิดหน้าต่างแชร์ของระบบ (ใช้ได้ทั้งเครื่องจริงและซิมูเลเตอร์)
struct AGShareSheet: UIViewControllerRepresentable {

    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) { }
}
