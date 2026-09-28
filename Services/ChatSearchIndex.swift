//
//  ChatSearchIndex.swift
//  iOS Agent Sandbox
//
//  ค้นข้อความย้อนหลังในทุกห้องสนทนา (เฟส 6)
//  ทำงานกับข้อมูลในหน่วยความจำเท่านั้น — ไม่สร้างดัชนีถาวรเพื่อประหยัดพื้นที่บนเครื่อง RAM 2GB
//
//  Foundation-only → รัน unit test ได้ทุกแพลตฟอร์ม
//

import Foundation

/// ผลการค้นหาหนึ่งรายการ (แตะแล้วข้ามไปห้องนั้น)
struct ChatSearchHit: Identifiable, Equatable {
    let id: String
    let roomID: UUID
    let roomName: String
    let messageID: UUID
    let roleLabel: String
    let date: Date
    let snippet: String
}

enum ChatSearchIndex {

    /// คำค้นสั้นกว่านี้จะไม่ค้น (ได้ผลลัพธ์เยอะเกินประโยชน์)
    static let minimumQueryLength = 2

    /// ตัดข้อความรอบคำค้นให้สั้นพอแสดงในลิสต์ (ไม่ส่งทั้งข้อความยาว)
    static func snippet(in text: String, around query: String, context: Int = 40) -> String? {
        guard !query.isEmpty else { return nil }

        // แทนขึ้นบรรทัดใหม่ด้วยช่องว่าง เพื่อให้ตัวอย่างอยู่ในบรรทัดเดียว
        let flattened = text
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")

        let loweredText = flattened.lowercased()
        let loweredQuery = query.lowercased()
        guard let found = loweredText.range(of: loweredQuery) else { return nil }

        let matchStart = loweredText.distance(from: loweredText.startIndex, to: found.lowerBound)
        let matchLength = loweredText.distance(from: found.lowerBound, to: found.upperBound)

        // lowercased() อาจเปลี่ยนความยาวของสตริงในบางภาษา → ถ้าไม่เท่ากันให้ใช้ช่วงต้นของข้อความแทน
        guard loweredText.count == flattened.count else {
            return String(flattened.prefix(140))
        }

        let start = max(0, matchStart - context)
        let end = min(flattened.count, matchStart + matchLength + context)

        guard let startIndex = flattened.index(flattened.startIndex, offsetBy: start, limitedBy: flattened.endIndex),
              let endIndex = flattened.index(flattened.startIndex, offsetBy: end, limitedBy: flattened.endIndex) else {
            return String(flattened.prefix(140))
        }

        var piece = String(flattened[startIndex..<endIndex])
        if start > 0 { piece = "…" + piece }
        if end < flattened.count { piece += "…" }
        return piece
    }

    /// ป้ายบอกว่าข้อความนี้เป็นของใคร
    static func roleLabel(for message: ChatMessage) -> String {
        switch message.role {
        case .user: return "ผู้ใช้"
        case .assistant: return "ผู้ช่วย"
        case .tool: return "ผลลัพธ์ tool"
        case .system: return "ระบบ"
        }
    }

    /// ค้นทุกห้องจากข้อความที่โหลดไว้ในหน่วยความจำ (ใหม่สุดก่อน)
    static func search(query: String,
                       rooms: [ChatRoom],
                       messagesForRoom: (UUID) -> [ChatMessage],
                       limit: Int = 60) -> [ChatSearchHit] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= minimumQueryLength else { return [] }

        var hits: [ChatSearchHit] = []
        let orderedRooms = rooms.sorted { $0.updatedAt > $1.updatedAt }

        for room in orderedRooms {
            let messages = messagesForRoom(room.id)
            for message in messages.reversed() {
                guard !message.text.isEmpty else { continue }
                guard let snippet = snippet(in: message.text, around: trimmed) else { continue }

                hits.append(ChatSearchHit(id: room.id.uuidString + "-" + message.id.uuidString,
                                          roomID: room.id,
                                          roomName: room.name,
                                          messageID: message.id,
                                          roleLabel: roleLabel(for: message),
                                          date: message.createdAt,
                                          snippet: snippet))
                if hits.count >= limit { return hits }
            }
        }
        return hits
    }
}
