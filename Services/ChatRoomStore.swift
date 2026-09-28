//
//  ChatRoomStore.swift
//  iOS Agent Sandbox
//
//  หลายห้องสนทนา (เฟส 5)
//  - index.json เก็บรายการห้อง (ชื่อ, เวลาสร้าง/แก้ไข, จำนวนข้อความ, ตัวอย่างข้อความล่าสุด)
//  - messages-<uuid>.json เก็บข้อความของแต่ละห้อง
//  - ย้ายประวัติเดิม (chat-history.json ของเฟส 2-4) เข้าห้อง "แชทเดิม" ให้อัตโนมัติ
//  - ส่งออกเป็น Markdown / JSON เพื่อแชร์ผ่าน Share Sheet
//
//  เป็น Foundation ล้วน (ไม่พึ่ง UIKit) จึงทดสอบได้ทุกแพลตฟอร์ม
//

import Foundation

/// ข้อมูลสรุปของห้องสนทนาหนึ่งห้อง
struct ChatRoom: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date
    var messageCount: Int
    /// ข้อความล่าสุดแบบตัดสั้น (ใช้แสดงในลิสต์ห้อง)
    var preview: String

    init(id: UUID = UUID(),
         name: String,
         createdAt: Date = Date(),
         updatedAt: Date = Date(),
         messageCount: Int = 0,
         preview: String = "") {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.messageCount = messageCount
        self.preview = preview
    }

    /// เวลาที่แสดงในลิสต์
    var updatedText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "th_TH")
        formatter.dateFormat = "d MMM HH:mm"
        return formatter.string(from: updatedAt)
    }
}

/// โครงสร้างไฟล์ที่ส่งออก (JSON)
struct ChatExport: Codable {
    var roomName: String
    var exportedAt: Date
    var messageCount: Int
    var messages: [ChatMessage]
}

final class ChatRoomStore {

    private let fileManager: FileManager
    /// โฟลเดอร์เก็บข้อมูลห้อง
    let directoryPath: String

    init(directoryPath: String? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        if let custom = directoryPath {
            self.directoryPath = custom
        } else {
            let base = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first?.path
                ?? NSTemporaryDirectory()
            self.directoryPath = (base as NSString).appendingPathComponent("iosagentsandbox/rooms")
        }
    }

    private var indexPath: String { (directoryPath as NSString).appendingPathComponent("index.json") }

    func messagesPath(roomID: UUID) -> String {
        (directoryPath as NSString).appendingPathComponent("messages-\(roomID.uuidString).json")
    }

    func ensureDirectory() throws {
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: directoryPath, isDirectory: &isDirectory), isDirectory.boolValue { return }
        try fileManager.createDirectory(atPath: directoryPath, withIntermediateDirectories: true, attributes: nil)
    }

    // MARK: - รายการห้อง

    func loadRooms() -> [ChatRoom] {
        guard let data = fileManager.contents(atPath: indexPath) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let rooms = try? decoder.decode([ChatRoom].self, from: data) else { return [] }
        return rooms.sorted { $0.updatedAt > $1.updatedAt }
    }

    func saveRooms(_ rooms: [ChatRoom]) throws {
        try ensureDirectory()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(rooms)
        try data.write(to: URL(fileURLWithPath: indexPath), options: .atomic)
    }

    /// สร้างห้องใหม่พร้อมชื่อเริ่มต้น
    func createRoom(name: String? = nil, existingCount: Int = 0) throws -> ChatRoom {
        let trimmed = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let roomName = trimmed.isEmpty ? "แชทใหม่ \(existingCount + 1)" : trimmed
        let room = ChatRoom(name: roomName)
        try ensureDirectory()
        try saveMessages([], roomID: room.id)
        return room
    }

    /// ชื่อห้องที่ปลอดภัยสำหรับใช้เป็นชื่อไฟล์ส่งออก
    static func safeExportName(_ name: String) -> String {
        let cleaned = name.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "chat" : cleaned
    }

    // MARK: - ข้อความในห้อง

    func loadMessages(roomID: UUID) -> [ChatMessage] {
        guard let data = fileManager.contents(atPath: messagesPath(roomID: roomID)) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([ChatMessage].self, from: data)) ?? []
    }

    func saveMessages(_ messages: [ChatMessage], roomID: UUID) throws {
        try ensureDirectory()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(messages)
        try data.write(to: URL(fileURLWithPath: messagesPath(roomID: roomID)), options: .atomic)
    }

    func deleteRoomFiles(roomID: UUID) {
        let path = messagesPath(roomID: roomID)
        if fileManager.fileExists(atPath: path) {
            try? fileManager.removeItem(atPath: path)
        }
    }

    // MARK: - ย้ายประวัติเดิม (เฟส 2-4) เข้าห้องแรก

    /// ถ้ายังไม่มีห้องเลย แต่มีไฟล์ประวัติเดิมอยู่ → สร้างห้อง "แชทเดิม" และย้ายข้อความมา
    /// - Parameter legacyMessages: ข้อความที่โหลดมาจาก ChatHistoryStore แล้ว
    /// - Returns: (ห้องทั้งหมด, ข้อความของห้องแรก) — ข้อความว่างถ้าไม่มีการย้าย
    func migrateLegacyHistoryIfNeeded(legacyMessages: [ChatMessage]) throws -> (rooms: [ChatRoom], migrated: [ChatMessage]) {
        let existing = loadRooms()
        if !existing.isEmpty { return (existing, []) }
        guard !legacyMessages.isEmpty else { return ([], []) }

        let room = ChatRoom(name: "แชทเดิม",
                            messageCount: legacyMessages.count,
                            preview: ChatRoomStore.previewText(of: legacyMessages))
        try ensureDirectory()
        try saveMessages(legacyMessages, roomID: room.id)
        try saveRooms([room])
        return ([room], legacyMessages)
    }

    /// ตัวอย่างข้อความล่าสุดสำหรับแสดงในลิสต์
    static func previewText(of messages: [ChatMessage]) -> String {
        guard let last = messages.last else { return "" }
        let raw: String
        if last.isToolResult {
            raw = "🔧 " + (last.toolThaiLabel ?? last.name ?? "tool")
        } else {
            raw = last.text
        }
        let single = raw.replacingOccurrences(of: "\n", with: " ")
        return single.count > 60 ? String(single.prefix(60)) + "…" : single
    }

    // MARK: - ส่งออก

    /// ส่งออกเป็น Markdown (ทดสอบได้โดยไม่ต้องแตะดิสก์)
    static func markdownExport(roomName: String, messages: [ChatMessage]) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "th_TH")
        formatter.dateFormat = "d MMMM yyyy HH:mm"

        var lines: [String] = []
        lines.append("# \(roomName)")
        lines.append("")
        lines.append("- ส่งออกเมื่อ: \(formatter.string(from: Date()))")
        lines.append("- จำนวนข้อความ: \(messages.count)")
        lines.append("")

        for message in messages {
            switch message.role {
            case .user:
                lines.append("## ผู้ใช้")
                lines.append(message.text)
                if let attachments = message.attachments, !attachments.isEmpty {
                    for attachment in attachments {
                        lines.append("- 📎 \(attachment.originalName) (\(attachment.sizeText)) — `\(attachment.path)`")
                    }
                }
            case .assistant:
                lines.append("## ผู้ช่วย")
                lines.append(message.text.isEmpty ? "_(ไม่มีข้อความ)_" : message.text)
            case .tool:
                let label = message.toolThaiLabel ?? message.name ?? "tool"
                let status = (message.toolIsError ?? false) ? "❌" : "✅"
                lines.append("## \(status) tool: \(label)")
                if let arguments = message.toolArguments, !arguments.isEmpty {
                    lines.append("```json")
                    lines.append(arguments)
                    lines.append("```")
                }
                lines.append("```")
                lines.append(message.text)
                lines.append("```")
            case .system:
                continue
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    /// ส่งออกเป็น JSON
    static func jsonExport(roomName: String, messages: [ChatMessage]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let payload = ChatExport(roomName: roomName, exportedAt: Date(), messageCount: messages.count, messages: messages)
        return try encoder.encode(payload)
    }
}
