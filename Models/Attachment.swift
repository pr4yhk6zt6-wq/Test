//
//  Attachment.swift
//  iOS Agent Sandbox
//
//  ไฟล์แนบของผู้ใช้ (เฟส 5)
//  - ไฟล์ที่ผู้ใช้เลือกจะถูก "คัดลอก" เข้าโฟลเดอร์ทำงาน /var/mobile/AgentWorkspace/uploads
//  - เก็บเฉพาะข้อมูลที่จำเป็นสำหรับแสดงผลและส่งให้โมเดล (ชื่อ, ขนาด, พาธ, ชนิด)
//  - ไฟล์ข้อความเล็กกว่า 20KB จะถูกฝังเนื้อหาไปกับข้อความ (ประหยัดรอบการเรียก tool)
//  - รูปภาพจะถูกย่อและแปลงเป็น base64 เฉพาะเมื่อโมเดลรับรูป (ดู AttachmentMessageBuilder)
//
//  หมายเหตุหน่วยความจำ: ไฟล์ใหญ่ไม่ถูกอ่านทั้งไฟล์ ยกเว้นไฟล์ข้อความที่เล็กกว่า 20KB เท่านั้น
//

import Foundation

/// ชนิดของไฟล์แนบที่แอปแยกแยะได้
enum AttachmentKind: String, Codable {
    case image
    case text
    case binary

    var thaiName: String {
        switch self {
        case .image: return "รูปภาพ"
        case .text: return "ข้อความ"
        case .binary: return "ไฟล์"
        }
    }

    /// ชื่อไอคอน SF Symbol ที่ใช้บนชิปไฟล์แนบ
    var iconName: String {
        switch self {
        case .image: return "photo"
        case .text: return "doc.text"
        case .binary: return "doc"
        }
    }
}

/// ไฟล์แนบหนึ่งไฟล์
struct Attachment: Identifiable, Codable, Equatable {
    var id: UUID
    /// ชื่อไฟล์จริงในโฟลเดอร์ uploads (ถูกทำความสะอาดแล้ว)
    var fileName: String
    /// ชื่อไฟล์เดิมที่ผู้ใช้เห็น
    var originalName: String
    /// พาธเต็มบนเครื่อง
    var path: String
    /// ขนาดเป็นไบต์
    var byteSize: Int
    var kind: AttachmentKind
    /// true = เนื้อหาถูกฝังไปกับข้อความแล้ว (ไฟล์ข้อความเล็กกว่า 20KB)
    var isInlineText: Bool
    /// เนื้อหาที่ฝัง (เฉพาะไฟล์ข้อความเล็ก)
    var inlineText: String?
    var pixelWidth: Int?
    var pixelHeight: Int?
    var createdAt: Date

    init(id: UUID = UUID(),
         fileName: String,
         originalName: String,
         path: String,
         byteSize: Int,
         kind: AttachmentKind,
         isInlineText: Bool = false,
         inlineText: String? = nil,
         pixelWidth: Int? = nil,
         pixelHeight: Int? = nil,
         createdAt: Date = Date()) {
        self.id = id
        self.fileName = fileName
        self.originalName = originalName
        self.path = path
        self.byteSize = byteSize
        self.kind = kind
        self.isInlineText = isInlineText
        self.inlineText = inlineText
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.createdAt = createdAt
    }

    var isImage: Bool { kind == .image }

    /// นามสกุลไฟล์ (ตัวพิมพ์เล็ก, ไม่มีจุด) — คำนวณแบบบริสุทธิ์เพื่อให้ทดสอบได้ทุกแพลตฟอร์ม
    var fileExtension: String {
        guard let dotIndex = fileName.lastIndex(of: "."), dotIndex != fileName.startIndex else { return "" }
        let ext = String(fileName[fileName.index(after: dotIndex)...]).lowercased()
        return ext == fileName.lowercased() ? "" : ext
    }

    /// ข้อความขนาดไฟล์แบบอ่านง่าย เช่น "1.2 MB"
    var sizeText: String { Attachment.sizeText(for: byteSize) }

    /// ข้อมูลสำหรับแสดงบนชิป (เช่น "IMG_0421.jpg • 1.2 MB")
    var chipSubtitle: String {
        var parts: [String] = [sizeText]
        if let width = pixelWidth, let height = pixelHeight {
            parts.append("\(width)×\(height)")
        }
        if isInlineText {
            parts.append("ฝังเนื้อหาแล้ว")
        }
        return parts.joined(separator: " • ")
    }

    /// บรรทัดสรุปสำหรับแนบไปกับข้อความ (ใช้เมื่อไม่ฝังเนื้อหา)
    func summaryLine(index: Int) -> String {
        "\(index). \(originalName) — \(sizeText) — ชนิด: \(kind.thaiName) — พาธ: \(path)"
    }

    // MARK: - ตัวช่วยแบบบริสุทธิ์ (ทดสอบได้ทุกแพลตฟอร์ม)

    /// แปลงขนาดไฟล์เป็นข้อความอ่านง่าย
    static func sizeText(for bytes: Int) -> String {
        if bytes < 1_024 { return "\(bytes) ไบต์" }
        let kilobytes = Double(bytes) / 1_024
        if kilobytes < 1_024 { return String(format: "%.0f KB", kilobytes) }
        let megabytes = kilobytes / 1_024
        if megabytes < 1_024 { return String(format: "%.1f MB", megabytes) }
        return String(format: "%.2f GB", megabytes / 1_024)
    }

    /// เดาชนิดไฟล์จากนามสกุล
    static func kind(forExtension ext: String) -> AttachmentKind {
        let lower = ext.lowercased()
        if imageExtensions.contains(lower) { return .image }
        if textExtensions.contains(lower) { return .text }
        return .binary
    }

    static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "gif", "heic", "heif", "webp", "bmp", "tiff", "tif"]

    static let textExtensions: Set<String> = [
        "txt", "md", "markdown", "json", "xml", "yml", "yaml", "csv", "tsv", "log", "ini", "conf", "plist",
        "swift", "m", "mm", "h", "c", "cpp", "hpp", "js", "jsx", "ts", "tsx", "py", "rb", "go", "rs", "java",
        "kt", "kts", "php", "sh", "bash", "zsh", "html", "htm", "css", "scss", "sql", "toml", "pl", "lua", "r"
    ]
}
