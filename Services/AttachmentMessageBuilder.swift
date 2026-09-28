//
//  AttachmentMessageBuilder.swift
//  iOS Agent Sandbox
//
//  สร้างเนื้อหาข้อความผู้ใช้ที่มีไฟล์แนบ (เฟส 5)
//  - โมเดลที่รับรูปได้ → content เป็น array ของ parts: text + image_url (data URL)
//  - โมเดลที่รับรูปไม่ได้ → ส่งเป็นข้อความ + รายการพาธไฟล์ (Agent เปิดอ่านเองด้วย tool ได้)
//  - ไฟล์ข้อความเล็กกว่า 20KB ถูกฝังเนื้อหาไว้ในบล็อกข้อความ
//
//  ไฟล์นี้เป็น Foundation ล้วน จึงรันทดสอบได้ทุกแพลตฟอร์ม (unit + E2E)
//

import Foundation

enum AttachmentMessageBuilder {

    /// ป้ายกำกับบล็อกไฟล์แนบในข้อความ
    static let blockHeader = "[ไฟล์แนบจากผู้ใช้]"

    /// เนื้อหาแบบข้อความล้วน (ใช้เมื่อไม่มีรูปที่ต้องส่งเป็น image_url)
    static func textBlock(text: String, attachments: [Attachment]) -> String {
        guard !attachments.isEmpty else { return text }

        var lines: [String] = []
        lines.append(blockHeader)
        for (index, attachment) in attachments.enumerated() {
            lines.append(attachment.summaryLine(index: index + 1))
        }

        let inlineTexts = attachments.filter { $0.isInlineText && !($0.inlineText ?? "").isEmpty }
        if !inlineTexts.isEmpty {
            lines.append("")
            lines.append("[เนื้อหาไฟล์ข้อความที่ฝังมาให้]")
            for attachment in inlineTexts {
                let ext = attachment.fileExtension.isEmpty ? "text" : attachment.fileExtension
                lines.append("--- \(attachment.originalName) ---")
                lines.append("```\(ext)")
                lines.append(attachment.inlineText ?? "")
                lines.append("```")
            }
        }

        let header = text.isEmpty ? "ช่วยดูไฟล์แนบเหล่านี้ให้หน่อย" : text
        return header + "\n\n" + lines.joined(separator: "\n")
    }

    /// เนื้อหาที่จะส่งไป OpenRouter
    /// - Parameters:
    ///   - imageDataURLs: รูปที่ย่อและแปลง base64 แล้ว (เรียงตามลำดับรูปใน attachments)
    ///   - includeImages: true เมื่อจะส่งรูปเป็น image_url ให้โมเดล
    static func content(text: String,
                        attachments: [Attachment],
                        imageDataURLs: [String],
                        includeImages: Bool) -> JSONValue {
        let block = textBlock(text: text, attachments: attachments)
        guard includeImages, !imageDataURLs.isEmpty else {
            return .string(block)
        }

        var parts: [JSONValue] = [.object(["type": .string("text"), "text": .string(block)])]
        for url in imageDataURLs {
            parts.append(.object([
                "type": .string("image_url"),
                "image_url": .object(["url": .string(url)])
            ]))
        }
        return .array(parts)
    }

    /// รายการไฟล์แนบที่ควรส่งเป็นรูปภาพ (เฉพาะรูป)
    static func imageAttachments(in attachments: [Attachment]) -> [Attachment] {
        attachments.filter { $0.isImage }
    }

    /// ข้อความเตือนเมื่อมีรูปแต่โมเดลที่เลือกอาจไม่รับรูป
    static func noVisionWarning(modelID: String, imageCount: Int) -> String {
        let subject = imageCount == 1 ? "มีรูปแนบ 1 รูป" : "มีรูปแนบ \(imageCount) รูป"
        return "\(subject) แต่โมเดล \(modelID) อาจไม่รับรูปภาพ — แอปจะส่งเฉพาะพาธไฟล์ให้ Agent เปิดอ่านเอง " +
               "ถ้าต้องการให้โมเดล \"เห็น\" รูป ให้เปลี่ยนเป็นโมเดลที่รับรูป (เช่น gpt-4o / gemini / claude / qwen-vl)"
    }

    /// ตัวช่วย: สร้าง data URL จาก base64 (ใช้ทั้งในแอปและเทสต์)
    static func dataURL(mimeType: String, base64: String) -> String {
        "data:\(mimeType);base64,\(base64)"
    }
}
