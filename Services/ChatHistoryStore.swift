//
//  ChatHistoryStore.swift
//  iOS Agent Sandbox
//
//  บันทึกประวัติการสนทนาลงเครื่องเป็นไฟล์ JSON (เฟส 2)
//  - เก็บที่ Documents/chat-history.json
//  - ถ้าไฟล์เสียหาย ระบบจะสำรองไว้ชื่อ .corrupt-<เวลา> แล้วเริ่มใหม่ (ไม่ทำให้แอปเปิดไม่ขึ้น)
//  - จำกัดจำนวนข้อความที่เก็บและขนาดไฟล์ เพื่อไม่ให้กินพื้นที่บนเครื่องรุ่นเก่า
//
//  หมายเหตุ: ไฟล์นี้ไม่เก็บ API Key และไม่เก็บข้อมูลลับใด ๆ — เก็บเฉพาะบทสนทนา
//

import Foundation

final class ChatHistoryStore {

    struct Snapshot: Codable {
        var version: Int
        var savedAt: Date
        var messages: [ChatMessage]
    }

    /// จำนวนข้อความสูงสุดที่เก็บลงไฟล์
    static let maximumStoredMessages = 300

    let fileURL: URL

    /// ข้อความ error ล่าสุด (ให้ UI แสดงได้โดยไม่ทำให้แอปล้ม)
    private(set) var lastErrorText: String?

    init(directory: URL? = nil, fileName: String = "chat-history.json") {
        let baseDirectory: URL
        if let directory = directory {
            baseDirectory = directory
        } else {
            let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            baseDirectory = documents ?? URL(fileURLWithPath: NSTemporaryDirectory())
        }
        self.fileURL = baseDirectory.appendingPathComponent(fileName)
    }

    // MARK: - อ่าน

    /// โหลดประวัติที่บันทึกไว้ (คืน [] เมื่อยังไม่มีไฟล์หรือไฟล์เสียหาย)
    func load() -> [ChatMessage] {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return []
        }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let snapshot = try decoder.decode(Snapshot.self, from: data)
            lastErrorText = nil
            return snapshot.messages
        } catch {
            lastErrorText = "อ่านประวัติที่บันทึกไว้ไม่สำเร็จ: \(error.localizedDescription)"
            backupCorruptFile()
            return []
        }
    }

    // MARK: - เขียน

    /// บันทึกประวัติ (ตัดข้อความเก่าออกถ้ามีมากเกินจำนวนที่กำหนด)
    func save(_ messages: [ChatMessage]) throws {
        guard !messages.isEmpty else {
            try clear()
            return
        }

        let trimmed = messages.count > ChatHistoryStore.maximumStoredMessages
            ? Array(messages.suffix(ChatHistoryStore.maximumStoredMessages))
            : messages
        let snapshot = Snapshot(version: 1, savedAt: Date(), messages: trimmed)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)

        // เขียนแบบ atomic เพื่อไม่ให้ไฟล์พังถ้าแอปถูกปิดกลางคัน
        try data.write(to: fileURL, options: .atomic)
        lastErrorText = nil
    }

    /// ลบไฟล์ประวัติทั้งหมด
    func clear() throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: fileURL.path) else { return }
        try fileManager.removeItem(at: fileURL)
        lastErrorText = nil
    }

    var exists: Bool {
        FileManager.default.fileExists(atPath: fileURL.path)
    }

    /// ขนาดไฟล์ที่บันทึกอยู่ (ไบต์)
    var fileSizeBytes: Int64 {
        let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        return (attributes?[.size] as? NSNumber)?.int64Value ?? 0
    }

    // MARK: - ตัวช่วย

    /// สำรองไฟล์ที่อ่านไม่ได้ เพื่อให้ผู้ใช้กู้คืนเองได้ถ้าต้องการ
    private func backupCorruptFile() {
        let fileManager = FileManager.default
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let suffix = formatter.string(from: Date())
        let backupURL = fileURL.deletingLastPathComponent()
            .appendingPathComponent("chat-history.corrupt-\(suffix).json")
        do {
            try fileManager.moveItem(at: fileURL, to: backupURL)
        } catch {
            // ย้ายไม่ได้ก็ปล่อยไว้ — ครั้งถัดไปจะลองอ่านแล้วสำรองใหม่
        }
    }
}
