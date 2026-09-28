//
//  AttachmentStore.swift
//  iOS Agent Sandbox
//
//  จัดการไฟล์แนบของผู้ใช้ (เฟส 5)
//  - คัดลอกไฟล์ที่ผู้ใช้เลือกเข้าสู่ /var/mobile/AgentWorkspace/uploads (ไม่ย้ายต้นฉบับ)
//  - ตั้งชื่อไฟล์ใหม่แบบกันชนกัน: yyyyMMdd-HHmmss-<ชื่อเดิมที่ทำความสะอาดแล้ว>
//  - ไฟล์ข้อความเล็กกว่า 20KB จะถูกอ่านแบบมีเพดาน (FileHandle) เพื่อฝังไปกับข้อความ
//  - ไม่โหลดไฟล์ใหญ่เข้าหน่วยความจำ: ใช้ FileHandle อ่านไม่เกินเพดาน + 1 ไบต์ เพื่อ "ตรวจ" ขนาดเท่านั้น
//

import Foundation

/// ข้อผิดพลาดของไฟล์แนบ (ข้อความภาษาไทยสำหรับแสดงให้ผู้ใช้)
enum AttachmentStoreError: LocalizedError, Equatable {
    case emptyFile
    case tooLarge(bytes: Int, limit: Int)
    case copyFailed(String)
    case nameUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .emptyFile:
            return "ไฟล์นี้ว่างเปล่า (0 ไบต์) — เลือกไฟล์อื่น"
        case .tooLarge(let bytes, let limit):
            return "ไฟล์ใหญ่เกินเพดาน: \(Attachment.sizeText(for: bytes)) (สูงสุด \(Attachment.sizeText(for: limit)))"
        case .copyFailed(let detail):
            return "คัดลอกไฟล์เข้าโฟลเดอร์ทำงานไม่สำเร็จ: \(detail)"
        case .nameUnavailable(let name):
            return "ตั้งชื่อไฟล์ในโฟลเดอร์ uploads ไม่สำเร็จ: \(name)"
        }
    }
}

final class AttachmentStore {

    /// เพดานขนาดไฟล์แนบต่อไฟล์ (ไบต์) — เท่ากับเพดานดาวน์โหลดเริ่มต้นของแอป
    static let defaultMaxBytes = 200 * 1024 * 1024
    /// ไฟล์ข้อความที่เล็กกว่านี้จะถูกฝังเนื้อหาไปกับข้อความเลย
    static let inlineTextLimitBytes = 20 * 1024
    /// เพดานเนื้อหาที่ฝังจริง (กัน context บวม)
    static let inlineTextHardLimitBytes = 24 * 1024

    /// โฟลเดอร์ปลายทางของไฟล์แนบ
    let rootPath: String

    private let fileManager: FileManager

    init(rootPath: String = "/var/mobile/AgentWorkspace/uploads",
         fileManager: FileManager = .default) {
        self.rootPath = rootPath
        self.fileManager = fileManager
    }

    // MARK: - ตัวช่วยแบบบริสุทธิ์

    /// ทำความสะอาดชื่อไฟล์: ตัดพาธ, อักขระต้องห้าม, ช่องว่างซ้ำ, จำกัดความยาว
    static func sanitizeFileName(_ raw: String) -> String {
        var name = raw
        if let slash = name.lastIndex(of: "/") {
            name = String(name[name.index(after: slash)...])
        }
        let forbidden: Set<Character> = ["\\", ":", "*", "?", "\"", "<", ">", "|", "\n", "\r", "\t", "\0"]
        name = String(name.filter { !forbidden.contains($0) })
        // ยุบช่องว่างซ้ำทั้งหมดให้เหลือช่องเดียว (ทำซ้ำจนนิ่ง เพราะการแทนที่ครั้งเดียว
        // จะเหลือช่องว่างค้างได้เมื่อมีช่องว่างสามตัวขึ้นไป)
        while name.contains("  ") {
            name = name.replacingOccurrences(of: "  ", with: " ")
        }
        name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { name = "ไฟล์แนบ" }
        if name == "." || name == ".." { name = "ไฟล์แนบ" }
        if name.count > 80 {
            let ext = (name.split(separator: ".").last.map(String.init) ?? "")
            let base = name.prefix(60)
            name = ext.isEmpty ? String(base) : "\(base).\(ext)"
        }
        // ชื่อที่ขึ้นต้นด้วยจุดซ่อนไฟล์ในบางเครื่อง — กันไว้เพื่อให้ผู้ใช้หาเจอง่าย
        if name.hasPrefix(".") { name = "ไฟล์" + name }
        return name
    }

    /// สร้างชื่อไฟล์ไม่ให้ชนกัน (ทดสอบได้โดยไม่ต้องแตะดิสก์)
    static func uniqueFileName(original: String, date: Date, existing: Set<String>) -> String {
        let clean = sanitizeFileName(original)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = formatter.string(from: date)

        let base: String
        let ext: String
        if let dotIndex = clean.lastIndex(of: "."), dotIndex != clean.startIndex {
            base = String(clean[clean.startIndex..<dotIndex])
            ext = String(clean[clean.index(after: dotIndex)...])
        } else {
            base = clean
            ext = ""
        }

        func compose(_ suffix: String) -> String {
            let tail = ext.isEmpty ? suffix : "\(suffix).\(ext)"
            return "\(stamp)-\(base)\(tail)"
        }

        var candidate = compose("")
        var counter = 1
        while existing.contains(candidate) {
            candidate = compose("-\(counter)")
            counter += 1
            if counter > 999 { break }
        }
        return candidate
    }

    // MARK: - นำเข้าไฟล์

    /// สร้างโฟลเดอร์ uploads ถ้ายังไม่มี
    func ensureDirectory() throws {
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: rootPath, isDirectory: &isDirectory), isDirectory.boolValue {
            return
        }
        do {
            try fileManager.createDirectory(atPath: rootPath, withIntermediateDirectories: true, attributes: nil)
        } catch {
            throw AttachmentStoreError.copyFailed(error.localizedDescription)
        }
    }

    /// คัดลอกไฟล์จาก URL ต้นทาง (เช่นไฟล์ที่ผู้ใช้เลือกหรือไฟล์ชั่วคราวของกล้อง) เข้าโฟลเดอร์ uploads
    func importFile(at sourceURL: URL,
                    originalName: String? = nil,
                    maxBytes: Int = AttachmentStore.defaultMaxBytes) throws -> Attachment {
        try ensureDirectory()

        let name = originalName ?? sourceURL.lastPathComponent
        let size = try fileSize(atPath: sourceURL.path)
        guard size > 0 else { throw AttachmentStoreError.emptyFile }
        guard size <= maxBytes else { throw AttachmentStoreError.tooLarge(bytes: size, limit: maxBytes) }

        let fileName = AttachmentStore.uniqueFileName(original: name,
                                                      date: Date(),
                                                      existing: existingFileNames())
        let destinationPath = (rootPath as NSString).appendingPathComponent(fileName)

        do {
            if fileManager.fileExists(atPath: destinationPath) {
                try fileManager.removeItem(atPath: destinationPath)
            }
            try fileManager.copyItem(atPath: sourceURL.path, toPath: destinationPath)
        } catch {
            throw AttachmentStoreError.copyFailed(error.localizedDescription)
        }

        return try makeAttachment(fileName: fileName, originalName: name, path: destinationPath, byteSize: size)
    }

    /// นำเข้าข้อมูลที่อยู่ในหน่วยความจำแล้ว (เช่นรูปจากคลิปบอร์ด) — จำกัดเพดานเพื่อความปลอดภัยของ RAM
    func importData(_ data: Data, originalName: String, maxBytes: Int = 32 * 1024 * 1024) throws -> Attachment {
        try ensureDirectory()
        guard !data.isEmpty else { throw AttachmentStoreError.emptyFile }
        guard data.count <= maxBytes else { throw AttachmentStoreError.tooLarge(bytes: data.count, limit: maxBytes) }

        let fileName = AttachmentStore.uniqueFileName(original: originalName, date: Date(), existing: existingFileNames())
        let destinationPath = (rootPath as NSString).appendingPathComponent(fileName)
        do {
            try data.write(to: URL(fileURLWithPath: destinationPath), options: .atomic)
        } catch {
            throw AttachmentStoreError.copyFailed(error.localizedDescription)
        }
        return try makeAttachment(fileName: fileName, originalName: originalName, path: destinationPath, byteSize: data.count)
    }

    /// ลบไฟล์แนบออกจากเครื่อง (ใช้เมื่อผู้ใช้กด x บนชิป หรือลบข้อความ)
    func delete(_ attachment: Attachment) throws {
        guard fileManager.fileExists(atPath: attachment.path) else { return }
        do {
            try fileManager.removeItem(atPath: attachment.path)
        } catch {
            throw AttachmentStoreError.copyFailed(error.localizedDescription)
        }
    }

    /// รายชื่อไฟล์ในโฟลเดอร์ uploads (ใช้กันชื่อซ้ำ)
    func existingFileNames() -> Set<String> {
        let names = (try? fileManager.contentsOfDirectory(atPath: rootPath)) ?? []
        return Set(names)
    }

    /// อ่านเนื้อหาไฟล์ข้อความแบบมีเพดาน (ไม่โหลดไฟล์ใหญ่เข้าหน่วยความจำ)
    /// - Returns: เนื้อหาถ้าไฟล์เล็กกว่าเพดานและเป็นข้อความ UTF-8 ที่อ่านได้
    func readInlineText(path: String, limitBytes: Int = AttachmentStore.inlineTextLimitBytes) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        let data = handle.readData(ofLength: limitBytes + 1)
        guard !data.isEmpty, data.count <= limitBytes else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - ภายใน

    private func fileSize(atPath path: String) throws -> Int {
        let attributes = try fileManager.attributesOfItem(atPath: path)
        if let number = attributes[.size] as? NSNumber { return number.intValue }
        if let value = attributes[.size] as? Int { return value }
        return 0
    }

    private func makeAttachment(fileName: String,
                                originalName: String,
                                path: String,
                                byteSize: Int) throws -> Attachment {
        let ext = AttachmentStore.extensionOf(fileName)
        let kind = Attachment.kind(forExtension: ext)

        var inlineText: String?
        if kind == .text, byteSize <= AttachmentStore.inlineTextLimitBytes {
            inlineText = readInlineText(path: path, limitBytes: AttachmentStore.inlineTextHardLimitBytes)
        }

        return Attachment(fileName: fileName,
                          originalName: originalName,
                          path: path,
                          byteSize: byteSize,
                          kind: kind,
                          isInlineText: inlineText != nil,
                          inlineText: inlineText)
    }

    /// นามสกุลไฟล์แบบบริสุทธิ์ (ไม่พึ่ง NSString)
    static func extensionOf(_ name: String) -> String {
        guard let dotIndex = name.lastIndex(of: "."), dotIndex != name.startIndex else { return "" }
        return String(name[name.index(after: dotIndex)...]).lowercased()
    }
}
