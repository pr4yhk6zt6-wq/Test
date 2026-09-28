//
//  PendingMessageQueue.swift
//  iOS Agent Sandbox — ดีไซน์ v2 (เฟส 5 ส่วนที่ 8)
//
//  คิวข้อความที่พิมพ์ระหว่าง Agent กำลังทำงาน
//  ทำไมต้องมี: เดิมช่องพิมพ์ถูกปิดระหว่างงานเดินอยู่ ทำให้ผู้ใช้ต้องรอแล้วพิมพ์ใหม่ (และบางทีพิมพ์ตอน Agent เพิ่งจบพอดี)
//  ดีไซน์ v2 จึงให้ "พิมพ์ได้เสมอ" — ข้อความจะเข้าคิวและส่งให้อัตโนมัติเมื่องานปัจจุบันจบ
//
//  กติกาความซื่อสัตย์:
//   1. ข้อความในคิวต้องมองเห็นได้ตลอด (จำนวน + เนื้อหา) และยกเลิกได้ทีละข้อความ
//   2. ถ้าผู้ใช้เป็นคนกดหยุดงานเอง ระบบจะ *ไม่* ยิงข้อความในคิวอัตโนมัติ — ให้ผู้ใช้กด "ส่งเลย" เอง (คุมได้จริง)
//   3. ถ้าตั้งค่าโมเดล/คีย์ไม่ครบ ข้อความต้องไม่หาย — ค้างในคิวพร้อมบอกสาเหตุ
//   4. ข้อความค้างข้ามการปิดแอปได้ (เขียนลงดิสก์) แต่ไม่เกินเพดานที่กำหนด
//
//  ไฟล์นี้ใช้ Foundation + Combine ล้วน (ไม่มี UIKit) จึงทดสอบในชุดทดสอบแกนกลางได้
//

import Foundation
import Combine

struct QueuedMessage: Codable, Identifiable, Equatable {
    var id: String
    var text: String
    var roomID: UUID?
    var createdAt: Date

    /// ข้อความสั้นสำหรับแสดงบนชิป
    var preview: String {
        let oneLine = text.split(whereSeparator: { $0.isNewline }).first.map(String.init) ?? text
        let trimmed = oneLine.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 80 { return trimmed }
        return String(trimmed.prefix(80)) + "…"
    }
}

final class PendingMessageQueue: ObservableObject {

    static let shared = PendingMessageQueue()

    /// เพดานคิว — มากกว่านี้คือ "กองขยะ" ที่ผู้ใช้ตามไม่ทัน
    static let maxItems = 10
    static let maxTextCharacters = 4_000

    @Published private(set) var items: [QueuedMessage] = []

    private let fileURL: URL?
    private let clock: () -> Date
    private let lock = NSLock()

    init(fileURL: URL? = PendingMessageQueue.defaultFileURL(),
         clock: @escaping () -> Date = Date.init) {
        self.fileURL = fileURL
        self.clock = clock
        load()
    }

    static func defaultFileURL() -> URL? {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        return docs
            .appendingPathComponent("iosagentsandbox", isDirectory: true)
            .appendingPathComponent("message-queue.json", isDirectory: false)
    }

    // MARK: - เพิ่ม / อ่าน

    /// เพิ่มข้อความเข้าคิว — คืน nil เมื่อข้อความว่างหรือคิวเต็ม (ผู้เรียกต้องบอกผู้ใช้ตามจริง)
    @discardableResult
    func enqueue(text: String, roomID: UUID?) -> QueuedMessage? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        lock.lock()
        defer { lock.unlock() }
        guard items.count < PendingMessageQueue.maxItems else { return nil }

        let clipped = trimmed.count > PendingMessageQueue.maxTextCharacters
            ? String(trimmed.prefix(PendingMessageQueue.maxTextCharacters))
            : trimmed

        let item = QueuedMessage(id: UUID().uuidString,
                                 text: clipped,
                                 roomID: roomID,
                                 createdAt: clock())
        items.append(item)
        persist(items)
        return item
    }

    func items(for roomID: UUID?) -> [QueuedMessage] {
        guard let roomID = roomID else { return items }
        return items.filter { $0.roomID == roomID }
    }

    func first(for roomID: UUID?) -> QueuedMessage? {
        return items(for: roomID).first
    }

    func count(for roomID: UUID?) -> Int {
        return items(for: roomID).count
    }

    // MARK: - ลบ

    func remove(id: String) {
        lock.lock()
        items.removeAll { $0.id == id }
        persist(items)
        lock.unlock()
    }

    func removeAll(for roomID: UUID?) {
        lock.lock()
        if let roomID = roomID {
            items.removeAll { $0.roomID == roomID }
        } else {
            items.removeAll()
        }
        persist(items)
        lock.unlock()
    }

    func removeAll() {
        removeAll(for: nil)
    }

    // MARK: - ภายใน

    private func load() {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let decoded = try? decoder.decode([QueuedMessage].self, from: data) else { return }
        lock.lock()
        items = Array(decoded.prefix(PendingMessageQueue.maxItems))
        lock.unlock()
    }

    /// เรียกขณะถือ lock อยู่แล้ว
    private func persist(_ snapshot: [QueuedMessage]) {
        guard let url = fileURL else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(snapshot) else { return }
        let directory = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory,
                                                 withIntermediateDirectories: true,
                                                 attributes: nil)
        try? data.write(to: url, options: .atomic)
    }
}
