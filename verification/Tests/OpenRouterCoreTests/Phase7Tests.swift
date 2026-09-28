//
//  Phase7Tests.swift
//  iOS Agent Sandbox — ชุดทดสอบแกนกลางของดีไซน์ v2 (เฟส 5 ส่วนที่ 8)
//
//  ทดสอบของจริงบนดิสก์ (ไม่ mock): ทะเบียนงานถาวร และคิวข้อความระหว่าง Agent ทำงาน
//  จุดที่ต้องพิสูจน์ให้ได้:
//   1. งานที่ค้างอยู่ตอนแอปถูกปิด ต้องกลายเป็น "ถูกปิดกลางทาง" — ห้ามขึ้นว่า "กำลังทำอยู่"
//   2. งานที่ยังไม่จบ ต้องไม่มีตัวเลขเวลา (ห้ามประมาณการล่วงหน้า)
//   3. คิวข้อความต้องไม่หายเมื่อปิดแอป และต้องไม่โตเกินเพดาน
//

import XCTest
@testable import OpenRouterCore

final class Phase7TaskRegistryTests: XCTestCase {

    private func temporaryFile(_ name: String) -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("phase7-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory,
                                                 withIntermediateDirectories: true,
                                                 attributes: nil)
        return directory.appendingPathComponent(name, isDirectory: false)
    }

    // MARK: - ทะเบียนงานถาวร

    func testShortTitleUsesFirstLineAndCapsLength() {
        XCTAssertEqual(TaskRegistry.shortTitle("  สร้างโฟลเดอร์\nแล้วเขียนไฟล์  "), "สร้างโฟลเดอร์")
        XCTAssertEqual(TaskRegistry.shortTitle("   "), "งานจากแชท")

        let long = String(repeating: "ก", count: 200)
        let shortened = TaskRegistry.shortTitle(long)
        XCTAssertEqual(shortened.count, TaskRegistry.maxTitleLength + 1)
        XCTAssertTrue(shortened.hasSuffix("…"))
    }

    func testStartCreatesRunningRecordWithoutDuration() {
        let registry = TaskRegistry(sessionID: "session-a", fileURL: temporaryFile("tasks.json"))
        let record = registry.start(title: "จัดระเบียบไฟล์ในโฟลเดอร์ทำงาน", roomID: UUID())

        XCTAssertEqual(record.outcome, .running)
        XCTAssertEqual(registry.count, 1)
        XCTAssertEqual(registry.all.first?.id, record.id)
        XCTAssertNil(record.endedAt)
        XCTAssertNil(record.duration)          // ยังไม่จบ = ไม่มีตัวเลขเวลาเลย
        XCTAssertFalse(record.outcome.canContinue)
    }

    func testFinishRecordsOutcomeStepsAndDuration() throws {
        let registry = TaskRegistry(sessionID: "session-a", fileURL: temporaryFile("tasks.json"))
        let record = registry.start(title: "ลบไฟล์ขยะ", roomID: nil)
        registry.finish(id: record.id,
                        outcome: .done,
                        summary: "ทำเสร็จแล้ว",
                        stepCount: 4,
                        lastStepTitle: "ลบไฟล์",
                        fileChangeCount: 2)

        let stored = try XCTUnwrap(registry.record(id: record.id))
        XCTAssertEqual(stored.outcome, .done)
        XCTAssertEqual(stored.stepCount, 4)
        XCTAssertEqual(stored.lastStepTitle, "ลบไฟล์")
        XCTAssertEqual(stored.fileChangeCount, 2)
        XCTAssertTrue(stored.touchedFiles)
        XCTAssertNotNil(stored.duration)
    }

    func testRunningTaskFromPreviousSessionBecomesInterrupted() throws {
        let file = temporaryFile("tasks.json")
        let first = TaskRegistry(sessionID: "session-a", fileURL: file)
        let record = first.start(title: "ค้นข้อมูลในเว็บ", roomID: nil)
        XCTAssertEqual(first.all.first?.outcome, .running)

        // เปิดแอปใหม่ = คนละรอบ แต่ไฟล์เดิม
        let second = TaskRegistry(sessionID: "session-b", fileURL: file)
        XCTAssertEqual(second.markInterruptedFromPreviousSessions(), 1)

        let stored = try XCTUnwrap(second.record(id: record.id))
        XCTAssertEqual(stored.outcome, .interrupted)
        XCTAssertTrue(stored.outcome.canContinue)
        XCTAssertNotNil(stored.endedAt)
        XCTAssertNotNil(stored.summary)
        // เรียกซ้ำต้องไม่นับซ้ำ
        XCTAssertEqual(second.markInterruptedFromPreviousSessions(), 0)
    }

    func testRegistryKeepsNewestFirstAndCapsCount() {
        let registry = TaskRegistry(sessionID: "session-a", fileURL: temporaryFile("tasks.json"))
        for index in 0..<(TaskRegistry.maxRecords + 5) {
            registry.start(title: "งานที่ \(index)", roomID: nil)
        }
        XCTAssertEqual(registry.count, TaskRegistry.maxRecords)
        XCTAssertEqual(registry.all.first?.title, "งานที่ \(TaskRegistry.maxRecords + 4)")
    }

    func testClearFinishedKeepsRunningTask() {
        let registry = TaskRegistry(sessionID: "session-a", fileURL: temporaryFile("tasks.json"))
        let finished = registry.start(title: "งานที่จบแล้ว", roomID: nil)
        registry.finish(id: finished.id,
                        outcome: .done,
                        summary: nil,
                        stepCount: 1,
                        lastStepTitle: nil,
                        fileChangeCount: 0)
        let running = registry.start(title: "งานที่ยังทำอยู่", roomID: nil)

        registry.clearFinished()
        XCTAssertEqual(registry.count, 1)
        XCTAssertEqual(registry.all.first?.id, running.id)
    }

    func testDeleteRemovesOnlyThatRecord() {
        let registry = TaskRegistry(sessionID: "session-a", fileURL: temporaryFile("tasks.json"))
        let first = registry.start(title: "งานแรก", roomID: nil)
        let second = registry.start(title: "งานที่สอง", roomID: nil)

        registry.delete(id: first.id)
        XCTAssertEqual(registry.count, 1)
        XCTAssertNil(registry.record(id: first.id))
        XCTAssertNotNil(registry.record(id: second.id))
    }

    func testOutcomeLabelsAndContinueRules() {
        XCTAssertEqual(TaskOutcome.running.thaiLabel, "กำลังทำอยู่")
        XCTAssertEqual(TaskOutcome.interrupted.thaiLabel, "ถูกปิดกลางทาง")
        XCTAssertTrue(TaskOutcome.interrupted.canContinue)
        XCTAssertTrue(TaskOutcome.failed.canContinue)
        XCTAssertTrue(TaskOutcome.needsAnswer.canContinue)
        XCTAssertTrue(TaskOutcome.systemPaused.canContinue)
        XCTAssertFalse(TaskOutcome.running.canContinue)
        XCTAssertFalse(TaskOutcome.cancelled.canContinue)
        XCTAssertFalse(TaskOutcome.running.isFinished)
        XCTAssertTrue(TaskOutcome.done.isFinished)
    }

    // MARK: - คิวข้อความระหว่าง Agent ทำงาน

    func testQueueKeepsOrderAndRejectsEmptyText() throws {
        let queue = PendingMessageQueue(fileURL: temporaryFile("queue.json"))
        XCTAssertNil(queue.enqueue(text: "   \n  ", roomID: nil))

        let room = UUID()
        _ = try XCTUnwrap(queue.enqueue(text: "ข้อความแรก", roomID: room))
        _ = try XCTUnwrap(queue.enqueue(text: "ข้อความที่สอง", roomID: room))

        XCTAssertEqual(queue.count(for: room), 2)
        XCTAssertEqual(queue.first(for: room)?.text, "ข้อความแรก")
    }

    func testQueueCapsItemCount() {
        let queue = PendingMessageQueue(fileURL: temporaryFile("queue.json"))
        for index in 0..<(PendingMessageQueue.maxItems + 3) {
            _ = queue.enqueue(text: "ข้อความ \(index)", roomID: nil)
        }
        XCTAssertEqual(queue.items.count, PendingMessageQueue.maxItems)
        XCTAssertNil(queue.enqueue(text: "เกินเพดานแล้ว", roomID: nil))
    }

    func testQueueClipsVeryLongText() throws {
        let queue = PendingMessageQueue(fileURL: temporaryFile("queue.json"))
        let long = String(repeating: "ก", count: PendingMessageQueue.maxTextCharacters + 500)
        let item = try XCTUnwrap(queue.enqueue(text: long, roomID: nil))
        XCTAssertEqual(item.text.count, PendingMessageQueue.maxTextCharacters)
    }

    func testQueueFiltersByRoomAndRemovesOnlyThatRoom() {
        let queue = PendingMessageQueue(fileURL: temporaryFile("queue.json"))
        let roomA = UUID()
        let roomB = UUID()
        _ = queue.enqueue(text: "ของห้อง A", roomID: roomA)
        _ = queue.enqueue(text: "ของห้อง B", roomID: roomB)

        XCTAssertEqual(queue.count(for: roomA), 1)
        XCTAssertEqual(queue.count(for: roomB), 1)

        queue.removeAll(for: roomA)
        XCTAssertEqual(queue.count(for: roomA), 0)
        XCTAssertEqual(queue.count(for: roomB), 1)
    }

    func testQueuePersistsAcrossLaunches() throws {
        let file = temporaryFile("queue.json")
        let room = UUID()

        let first = PendingMessageQueue(fileURL: file)
        _ = first.enqueue(text: "พิมพ์ไว้ตอน Agent กำลังทำงาน", roomID: room)

        let second = PendingMessageQueue(fileURL: file)
        XCTAssertEqual(second.count(for: room), 1)
        let item = try XCTUnwrap(second.first(for: room))
        XCTAssertEqual(item.text, "พิมพ์ไว้ตอน Agent กำลังทำงาน")
        XCTAssertEqual(item.roomID, room)
    }

    func testQueuePreviewIsSingleLineAndCapped() throws {
        let queue = PendingMessageQueue(fileURL: temporaryFile("queue.json"))
        let item = try XCTUnwrap(queue.enqueue(text: "บรรทัดแรก\nบรรทัดที่สอง", roomID: nil))
        XCTAssertEqual(item.preview, "บรรทัดแรก")

        let long = String(repeating: "ข", count: 200)
        let longItem = try XCTUnwrap(queue.enqueue(text: long, roomID: nil))
        XCTAssertEqual(longItem.preview.count, 81)
    }
}
