//
//  WorkspaceBackup.swift
//  iOS Agent Sandbox — ดีไซน์ v2 (เฟส 5 ส่วนที่ 7)
//
//  สำเนาสำรองก่อนที่ Agent จะเขียนทับ/แก้ไข/ลบ/ย้ายไฟล์ → ทำให้ปุ่ม "ย้อนกลับ" ในแอปทำงานได้จริง
//  (ดีไซน์เฟส 2/4 สัญญาเรื่อง "ย้อนกลับได้ในช่วงเวลาจำกัด" ไว้ แต่ engine เดิมไม่มีสำเนา
//   ไฟล์นี้จึงเป็นชิ้นที่ทำให้คำสัญญานั้นเป็นจริง แทนที่จะโชว์ปุ่มที่กดแล้วไม่ได้ผล)
//
//  หลักการ
//  - เก็บสำเนาไว้ในโฟลเดอร์ข้อมูลของแอป (ไม่แตะโฟลเดอร์ที่ผู้ใช้ทำงานด้วย)
//  - เก็บได้จำกัด: ไฟล์ใหญ่เกิน 20 MB หรือเป็นโฟลเดอร์ → บันทึกว่า "ไม่ได้สำรอง" (บอกตรง ๆ ในหน้าจอ)
//  - หน้าต่างย้อนกลับ = 10 นาที (นับจากเวลาจริง) หมดอายุแล้วลบสำเนาทิ้งอัตโนมัติ
//  - ห้ามสำรองไฟล์ที่อยู่ในโฟลเดอร์สำเนาเอง (กันการคัดลอกซ้ำไม่จบ)
//

import Foundation

struct BackupRecord: Identifiable, Equatable {

    enum Kind: String, Equatable {
        /// เขียนทับไฟล์ที่มีอยู่แล้ว
        case overwrite
        /// ลบไฟล์/โฟลเดอร์
        case deletion
        /// ย้ายไฟล์
        case move
        /// สร้างไฟล์ใหม่ (ไม่มีเวอร์ชันก่อนหน้าให้คืน)
        case created

        var thaiTitle: String {
            switch self {
            case .overwrite: return "คืนไฟล์เวอร์ชันก่อนหน้า"
            case .deletion: return "กู้ไฟล์ที่ถูกลบกลับคืน"
            case .move: return "คืนไฟล์กลับที่เดิม"
            case .created: return "ลบไฟล์ที่ Agent สร้างขึ้น"
            }
        }

        var thaiExplanation: String {
            switch self {
            case .overwrite:
                return "ไฟล์นี้มีอยู่ก่อนที่ Agent จะเขียนทับ ระบบเก็บสำเนาไว้ให้ — กดย้อนกลับเพื่อเอาเวอร์ชันก่อนหน้ากลับมา (เนื้อหาปัจจุบันจะถูกแทนที่)"
            case .deletion:
                return "ระบบเก็บสำเนาไฟล์นี้ไว้ก่อนลบ — กดย้อนกลับเพื่อนำไฟล์กลับมาที่ตำแหน่งเดิม"
            case .move:
                return "ระบบเก็บสำเนาไฟล์ต้นทางไว้ก่อนย้าย — กดย้อนกลับเพื่อคืนไฟล์กลับที่เดิม (ไฟล์ที่ย้ายไปปลายทางแล้วจะยังอยู่ที่นั่น)"
            case .created:
                return "ไฟล์นี้เพิ่งถูกสร้างขึ้นใหม่ ไม่มีเวอร์ชันก่อนหน้าให้คืน — ถ้าไม่ต้องการ ให้ลบไฟล์ที่ Agent สร้างออกได้เลย"
            }
        }
    }

    let id: String
    let kind: Kind
    let originalPath: String
    /// nil = ไม่มีสำเนาเก็บไว้ (เช่น ไฟล์ใหญ่เกินเพดาน)
    let backupPath: String?
    let createdAt: Date
    let byteSize: Int
    let skippedReason: String?

    var expiresAt: Date {
        createdAt.addingTimeInterval(WorkspaceBackup.window)
    }

    var isExpired: Bool {
        Date() >= expiresAt
    }

    var remainingSeconds: Int {
        max(0, Int(expiresAt.timeIntervalSinceNow.rounded()))
    }

    var remainingText: String {
        let total = remainingSeconds
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// กดย้อนกลับได้หรือไม่ (ไฟล์ใหม่กดได้แม้ไม่มีสำเนา เพราะการลบไฟล์ที่เพิ่งสร้างก็คือการย้อนกลับ)
    var canUndo: Bool {
        if isExpired { return false }
        return kind == .created ? true : (backupPath != nil)
    }
}

final class WorkspaceBackup {

    static let shared = WorkspaceBackup()

    /// หน้าต่างเวลาที่ย้อนกลับได้ (นับจากเวลาจริงเท่านั้น)
    static let window: TimeInterval = 10 * 60
    /// เพดานขนาดไฟล์ที่จะสำรอง (ใหญ่กว่านี้ = ไม่สำรอง แต่บอกผู้ใช้ตรง ๆ)
    static let maxFileBytes: Int = 20 * 1024 * 1024
    /// จำนวนรายการสำรองสูงสุดที่เก็บไว้
    static let maxRecords: Int = 30

    private let lock = NSLock()
    private var records: [BackupRecord] = []
    private let rootDirectory: String

    init(rootDirectory: String? = nil) {
        if let custom = rootDirectory {
            self.rootDirectory = custom
        } else {
            let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.path
                ?? NSTemporaryDirectory()
            self.rootDirectory = (base as NSString).appendingPathComponent("iosagentsandbox/backups")
        }
    }

    // MARK: - บันทึกสำเนา

    /// เรียก "ก่อน" ลงมือแก้ไฟล์เสมอ
    @discardableResult
    func keep(path: String, kind: BackupRecord.Kind) -> BackupRecord? {
        guard !path.isEmpty else { return nil }
        // กันการสำรองไฟล์ที่อยู่ในโฟลเดอร์สำรองเอง
        guard !path.hasPrefix(rootDirectory) else { return nil }

        let fileManager = FileManager.default
        let exists = fileManager.fileExists(atPath: path)
        let identifier = UUID().uuidString

        var backupPath: String?
        var size = 0
        var skipped: String?

        if kind != .created {
            guard exists else { return nil }
            let attributes = try? fileManager.attributesOfItem(atPath: path)
            let isDirectory = (attributes?[.type] as? FileAttributeType) == .typeDirectory
            size = (attributes?[.size] as? NSNumber)?.intValue ?? 0

            if isDirectory {
                skipped = "เป็นโฟลเดอร์ — ระบบสำรองได้เฉพาะไฟล์ จึงย้อนกลับอัตโนมัติไม่ได้"
            } else if size > WorkspaceBackup.maxFileBytes {
                skipped = "ไฟล์ใหญ่เกิน \(NetworkPolicy.formatBytes(Int64(WorkspaceBackup.maxFileBytes))) — ไม่ได้เก็บสำเนา"
            } else {
                backupPath = copyIntoStore(path: path, identifier: identifier)
                if backupPath == nil {
                    skipped = "คัดลอกสำเนาไม่สำเร็จ (อาจมีพื้นที่ไม่พอ)"
                }
            }
        }

        let record = BackupRecord(id: identifier,
                                  kind: kind,
                                  originalPath: path,
                                  backupPath: backupPath,
                                  createdAt: Date(),
                                  byteSize: size,
                                  skippedReason: skipped)

        lock.lock()
        records.removeAll { $0.isExpired }
        records.append(record)
        if records.count > WorkspaceBackup.maxRecords {
            let dropped = records.prefix(records.count - WorkspaceBackup.maxRecords)
            for item in dropped {
                removeStoredFile(of: item)
            }
            records.removeFirst(records.count - WorkspaceBackup.maxRecords)
        }
        lock.unlock()

        return record
    }

    // MARK: - ค้นหา / ย้อนกลับ

    /// รายการสำรองล่าสุดของไฟล์นี้ (ยังไม่หมดอายุ)
    func latest(forPath path: String) -> BackupRecord? {
        lock.lock()
        defer { lock.unlock() }
        return records
            .filter { $0.originalPath == path && !$0.isExpired }
            .sorted { $0.createdAt > $1.createdAt }
            .first
    }

    /// รายการที่ย้อนกลับได้ทั้งหมด (ใหม่สุดก่อน) — ใช้กับหน้างานของฉันในอนาคต
    var undoableRecords: [BackupRecord] {
        lock.lock()
        defer { lock.unlock() }
        return records.filter { $0.canUndo }.sorted { $0.createdAt > $1.createdAt }
    }

    enum UndoError: LocalizedError {
        case expired
        case missingBackup
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .expired: return "เลยเวลาย้อนกลับแล้ว (เกิน 10 นาที)"
            case .missingBackup: return "ไม่พบสำเนาที่เก็บไว้ — ย้อนกลับไม่ได้"
            case .failed(let message): return message
            }
        }
    }

    /// ย้อนกลับตามรายการสำรอง (คืนไฟล์ / ลบไฟล์ที่เพิ่งสร้าง)
    func restore(_ record: BackupRecord) throws {
        guard !record.isExpired else { throw UndoError.expired }

        let fileManager = FileManager.default

        if record.kind == .created {
            guard fileManager.fileExists(atPath: record.originalPath) else {
                throw UndoError.failed("ไฟล์นี้ถูกลบไปแล้ว — ไม่มีอะไรต้องทำ")
            }
            do {
                try fileManager.removeItem(atPath: record.originalPath)
            } catch {
                throw UndoError.failed("ลบไฟล์ไม่สำเร็จ: \(error.localizedDescription)")
            }
            markUsed(record)
            return
        }

        guard let backupPath = record.backupPath,
              fileManager.fileExists(atPath: backupPath) else {
            throw UndoError.missingBackup
        }

        do {
            if fileManager.fileExists(atPath: record.originalPath) {
                try fileManager.removeItem(atPath: record.originalPath)
            }
            try fileManager.copyItem(atPath: backupPath, toPath: record.originalPath)
        } catch {
            throw UndoError.failed("คืนไฟล์ไม่สำเร็จ: \(error.localizedDescription)")
        }

        markUsed(record)
    }

    /// ล้างสำเนาที่หมดอายุทั้งหมด (เรียกได้จากหน้าตั้งค่า)
    @discardableResult
    func pruneExpired() -> Int {
        lock.lock()
        let expired = records.filter { $0.isExpired }
        records.removeAll { $0.isExpired }
        lock.unlock()

        for item in expired {
            removeStoredFile(of: item)
        }
        return expired.count
    }

    // MARK: - ภายใน

    private func markUsed(_ record: BackupRecord) {
        lock.lock()
        if let index = records.firstIndex(where: { $0.id == record.id }) {
            records.remove(at: index)
        }
        lock.unlock()
        removeStoredFile(of: record)
    }

    private func copyIntoStore(path: String, identifier: String) -> String? {
        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(atPath: rootDirectory,
                                            withIntermediateDirectories: true,
                                            attributes: nil)
            let name = (path as NSString).lastPathComponent
            let destination = (rootDirectory as NSString)
                .appendingPathComponent("\(identifier)-\(name.isEmpty ? "file" : name)")
            try fileManager.copyItem(atPath: path, toPath: destination)
            return destination
        } catch {
            return nil
        }
    }

    private func removeStoredFile(of record: BackupRecord) {
        guard let backupPath = record.backupPath else { return }
        try? FileManager.default.removeItem(atPath: backupPath)
    }
}
