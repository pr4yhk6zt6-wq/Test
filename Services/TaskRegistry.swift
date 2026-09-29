//
//  TaskRegistry.swift
//  iOS Agent Sandbox — ดีไซน์ v2 (เฟส 5 ส่วนที่ 8)
//
//  ทะเบียนงานถาวร: จำไว้ว่าเคยสั่งงานอะไร ผลเป็นอย่างไร แม้ปิดแอปไปแล้ว
//  ทำไมต้องมี: เดิมงานที่ทำอยู่จะหายไปทันทีที่ปิดแอป ทำให้ผู้ใช้ไม่รู้ว่า "งานเมื่อกี้จบหรือยัง"
//
//  กติกาความซื่อสัตย์ (ห้ามละเมิด):
//   1. งานที่ยังค้างอยู่ตอนแอปถูกปิด จะถูกเปลี่ยนเป็น "ถูกปิดกลางทาง" ทันทีที่เปิดแอปครั้งถัดไป
//      — ไม่มีทางที่รายการจะขึ้นว่า "กำลังทำอยู่" ทั้งที่ไม่มีอะไรทำงานอยู่จริง
//   2. ไม่มีตัวเลขประมาณการเวลาเหลือ และไม่มีการเดาความสำเร็จ — เก็บเฉพาะสิ่งที่เกิดขึ้นจริง
//   3. งานที่ถูกยกเลิก/ถูกปิดกลางทาง ต้องยังกด "ทำต่อจากจุดเดิม" ได้ และไม่ลบผลที่ทำไว้แล้ว
//
//  ไฟล์นี้ใช้ Foundation ล้วน (ไม่มี UIKit/AVFoundation) จึงถูกดึงไปทดสอบในชุดทดสอบแกนกลางได้
//

import Foundation

/// ผลลัพธ์ของงานหนึ่งงาน — ใช้คำที่ผู้ใช้เข้าใจ ไม่ใช่ศัพท์เทคนิค
enum TaskOutcome: String, Codable, Equatable {

    case running
    case done
    case needsAnswer
    case failed
    case cancelled
    case interrupted
    case systemPaused

    var thaiLabel: String {
        switch self {
        case .running: return "กำลังทำอยู่"
        case .done: return "ทำเสร็จแล้ว"
        case .needsAnswer: return "รอคำสั่งต่อจากคุณ"
        case .failed: return "ยังไม่สำเร็จ"
        case .cancelled: return "ยกเลิกตามที่คุณสั่ง"
        case .interrupted: return "ถูกปิดกลางทาง"
        case .systemPaused: return "ระบบหยุดชั่วคราว"
        }
    }

    /// ไอคอนคู่กับข้อความเสมอ (ห้ามใช้สีบอกความหมายลำพัง)
    var symbolName: String {
        switch self {
        case .running: return "arrow.triangle.2.circlepath"
        case .done: return "checkmark.circle.fill"
        case .needsAnswer: return "questionmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        case .cancelled: return "stop.circle.fill"
        case .interrupted: return "pause.circle.fill"
        case .systemPaused: return "clock.badge.exclamationmark"
        }
    }

    /// งานที่ยัง "ทำต่อได้" — ใช้ตัดสินว่าจะแสดงปุ่มทำต่อหรือไม่
    var canContinue: Bool {
        switch self {
        case .needsAnswer, .failed, .interrupted, .systemPaused: return true
        case .running, .done, .cancelled: return false
        }
    }

    /// งานที่จบแล้ว (ใช้กรอง "ล้างรายการที่จบแล้ว")
    var isFinished: Bool { self != .running }
}

/// หนึ่งงานที่เคยสั่ง — ข้อมูลจริงจากเหตุการณ์จริงเท่านั้น
struct TaskRecord: Codable, Identifiable, Equatable {

    var id: String
    var title: String
    var roomID: UUID?
    var startedAt: Date
    var endedAt: Date?
    var outcome: TaskOutcome
    var summary: String?
    var stepCount: Int
    var lastStepTitle: String?
    var fileChangeCount: Int
    var sessionID: String

    /// ใช้เวลาไปเท่าไร — nil ถ้ายังไม่จบ (ไม่ประมาณการล่วงหน้า)
    var duration: TimeInterval? {
        guard let endedAt = endedAt else { return nil }
        return max(0, endedAt.timeIntervalSince(startedAt))
    }

    /// งานนี้แตะไฟล์ของผู้ใช้หรือไม่ (ใช้เตือนว่ามีอะไรให้ตรวจ/ย้อนกลับ)
    var touchedFiles: Bool { fileChangeCount > 0 }
}

final class TaskRegistry {

    static let shared = TaskRegistry()

    /// เก็บไม่เกินเท่านี้ (เก่าสุดถูกตัดออก — รายการต้องอ่านได้ ไม่กลายเป็นกองขยะ)
    static let maxRecords = 40
    static let maxTitleLength = 60

    /// รหัสรอบการเปิดแอปนี้ — ใช้แยกแยะงานที่ค้างจากรอบก่อน
    let sessionID: String

    private let fileURL: URL?
    private let clock: () -> Date
    private let lock = NSLock()
    private var records: [TaskRecord] = []

    init(sessionID: String = UUID().uuidString,
         fileURL: URL? = TaskRegistry.defaultFileURL(),
         clock: @escaping () -> Date = Date.init) {
        self.sessionID = sessionID
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
            .appendingPathComponent("tasks.json", isDirectory: false)
    }

    /// ชื่อสั้นบรรทัดเดียวสำหรับทะเบียน (ตัดขึ้นบรรทัดใหม่ + จำกัดความยาว)
    static func shortTitle(_ text: String) -> String {
        let firstLine = text.split(whereSeparator: { $0.isNewline }).first.map(String.init) ?? text
        let trimmed = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "งานจากแชท" }
        if trimmed.count <= maxTitleLength { return trimmed }
        return String(trimmed.prefix(maxTitleLength)) + "…"
    }

    // MARK: - อ่าน

    /// งานทั้งหมด เรียงใหม่สุดอยู่บนสุด
    var all: [TaskRecord] {
        lock.lock()
        defer { lock.unlock() }
        return records
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return records.count
    }

    func record(id: String) -> TaskRecord? {
        lock.lock()
        defer { lock.unlock() }
        return records.first { $0.id == id }
    }

    // MARK: - เขียน

    /// เริ่มงานใหม่ (เรียกตอนผู้ใช้ส่งคำสั่ง)
    @discardableResult
    func start(title: String, roomID: UUID?) -> TaskRecord {
        let item = TaskRecord(id: UUID().uuidString,
                              title: TaskRegistry.shortTitle(title),
                              roomID: roomID,
                              startedAt: clock(),
                              endedAt: nil,
                              outcome: .running,
                              summary: nil,
                              stepCount: 0,
                              lastStepTitle: nil,
                              fileChangeCount: 0,
                              sessionID: sessionID)
        lock.lock()
        records.insert(item, at: 0)
        trimLocked()
        lock.unlock()
        save()
        return item
    }

    /// อัปเดตความคืบหน้า (จำนวนขั้นล่าสุด) — กันข้อมูลหายถ้าแอปถูกฆ่ากลางทาง
    func updateProgress(id: String, stepCount: Int, lastStepTitle: String?, fileChangeCount: Int) {
        lock.lock()
        guard let index = records.firstIndex(where: { $0.id == id }) else {
            lock.unlock()
            return
        }
        records[index].stepCount = stepCount
        if let title = lastStepTitle { records[index].lastStepTitle = title }
        records[index].fileChangeCount = fileChangeCount
        lock.unlock()
        save()
    }

    /// ปิดงานด้วยผลลัพธ์จริง
    func finish(id: String,
                outcome: TaskOutcome,
                summary: String?,
                stepCount: Int,
                lastStepTitle: String?,
                fileChangeCount: Int) {
        lock.lock()
        guard let index = records.firstIndex(where: { $0.id == id }) else {
            lock.unlock()
            return
        }
        records[index].outcome = outcome
        records[index].endedAt = clock()
        records[index].summary = summary
        records[index].stepCount = max(stepCount, records[index].stepCount)
        if let title = lastStepTitle { records[index].lastStepTitle = title }
        records[index].fileChangeCount = max(fileChangeCount, records[index].fileChangeCount)
        lock.unlock()
        save()
    }

    /// งานที่ยังค้างอยู่จากรอบก่อน = แอปถูกปิดกลางทาง
    /// คืนจำนวนรายการที่ถูกปรับ (ใช้รายงานผลได้)
    @discardableResult
    func markInterruptedFromPreviousSessions() -> Int {
        let now = clock()
        var changed = 0
        lock.lock()
        for index in records.indices where records[index].outcome == .running {
            records[index].outcome = .interrupted
            records[index].endedAt = now
            records[index].summary = "แอปถูกปิดก่อนงานนี้จะจบ — ผลที่ทำไว้แล้วยังอยู่ครบ กด \"ทำต่อจากจุดเดิม\" ได้"
            changed += 1
        }
        lock.unlock()
        if changed > 0 { save() }
        return changed
    }

#if DEBUG
    /// ใช้เฉพาะข้อมูลตัวอย่างสำหรับภาพตรวจแบบ: กำหนดเวลาเริ่ม/จบให้สมจริง
    /// (ของจริงไม่มีการแก้ย้อนหลัง — เมธอดนี้อยู่ในบล็อก Debug เท่านั้น)
    func previewBackdate(id: String, startedAt: Date, endedAt: Date?) {
        lock.lock()
        guard let index = records.firstIndex(where: { $0.id == id }) else {
            lock.unlock()
            return
        }
        records[index].startedAt = startedAt
        records[index].endedAt = endedAt
        lock.unlock()
        save()
    }
#endif

    func delete(id: String) {
        lock.lock()
        records.removeAll { $0.id == id }
        lock.unlock()
        save()
    }

    /// ล้างเฉพาะงานที่จบแล้ว (งานที่กำลังทำอยู่ไม่ถูกลบ)
    func clearFinished() {
        lock.lock()
        records.removeAll { $0.outcome.isFinished }
        lock.unlock()
        save()
    }

    // MARK: - ภายใน

    private func trimLocked() {
        guard records.count > TaskRegistry.maxRecords else { return }
        records = Array(records.prefix(TaskRegistry.maxRecords))
    }

    private func load() {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let decoded = try? decoder.decode([TaskRecord].self, from: data) else { return }
        lock.lock()
        records = decoded
        lock.unlock()
    }

    func save() {
        guard let url = fileURL else { return }
        lock.lock()
        let snapshot = records
        lock.unlock()

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
