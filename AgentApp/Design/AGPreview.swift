//
//  AGPreview.swift
//  AgentApp — ข้อมูลตัวอย่างสำหรับโหมดตรวจงานออกแบบ (บิลด์ Debug เท่านั้น)
//
//  ใช้คู่กับ workflow .github/workflows/ui-preview.yml: เปิดแอปด้วย `-uiPreview <หน้าจอ>`
//  เพื่อถ่ายภาพหน้าจอจริงมาเทียบกับแบบ — ข้อมูลทั้งหมดเป็นข้อมูลสมมติที่สมจริง (ไม่มีการต่อเน็ต)
//

#if DEBUG
import Foundation

enum AGPreview {

    /// หน้าจอที่ขอให้แสดง (nil = โหมดใช้งานจริง)
    static var screen: String? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-uiPreview"), args.count > index + 1 else { return nil }
        return args[index + 1]
    }

    static var isActive: Bool { screen != nil }

    // MARK: - บทสนทนา

    static func messages(finished: Bool) -> [ChatMessage] {
        let start = Date().addingTimeInterval(-120)
        var items: [ChatMessage] = []

        items.append(ChatMessage(role: .user,
                                 text: "ช่วยสรุปไฟล์ในโฟลเดอร์ทำงานให้หน่อย แล้วเขียนสรุปลงไฟล์ใหม่",
                                 createdAt: start))

        items.append(ChatMessage(role: .assistant,
                                 text: "ได้ครับ ผมจะเริ่มจากดูรายการไฟล์ก่อน แล้วอ่านเฉพาะไฟล์ข้อความ",
                                 createdAt: start.addingTimeInterval(6)))

        items.append(ChatMessage(role: .tool,
                                 text: "พบ 12 ไฟล์ในโฟลเดอร์ทำงาน",
                                 name: "list_directory",
                                 createdAt: start.addingTimeInterval(9),
                                 toolThaiLabel: "ดูรายการไฟล์",
                                 toolDuration: 0.4))

        items.append(ChatMessage(role: .tool,
                                 text: "อ่าน 5 ไฟล์ข้อความ รวม 42 KB",
                                 name: "read_file",
                                 createdAt: start.addingTimeInterval(14),
                                 toolThaiLabel: "อ่านไฟล์",
                                 toolDuration: 1.2))

        if !finished {
            items.append(ChatMessage(role: .assistant,
                                     text: "",
                                     createdAt: start.addingTimeInterval(20)))
            return items
        }

        items.append(ChatMessage(role: .assistant,
                                 text: """
                                 สรุปให้แล้วครับ — เรียงตามความสำคัญ

                                 **สิ่งที่พบ**
                                 1. `notes/ประชุม.md` — บันทึกการประชุมล่าสุด ยังไม่มีสรุปท้ายไฟล์
                                 2. `data/ยอดขาย.csv` — ข้อมูลยอดขาย 3 เดือน (มีเลขบัญชี 2 จุด ถูกปิดบังไว้)
                                 3. ไฟล์อื่น ๆ เป็นรูปและสำเนาสำรอง ไม่ต้องแตะ

                                 **สิ่งที่ทำไป**
                                 - เขียนไฟล์ใหม่ `สรุปโฟลเดอร์.md` พร้อมหัวข้อและตารางสรุป
                                 - ไม่ได้ลบหรือย้ายไฟล์ใด ๆ

                                 ถ้าต้องการให้สรุปเป็นรายสัปดาห์ บอกได้เลยครับ
                                 """,
                                 createdAt: start.addingTimeInterval(26)))

        return items
    }

    // MARK: - ไทม์ไลน์กิจกรรม

    static func events() -> [ActivityEvent] {
        let start = Date().addingTimeInterval(-96)
        return [
            ActivityEvent(id: "p1", seq: 1, kind: .thinking, status: .succeeded,
                          title: "วางแผนงาน",
                          detail: "แยกงานเป็น 3 ขั้น: ดูรายการไฟล์ → อ่านไฟล์ข้อความ → เขียนไฟล์สรุป",
                          startedAt: start, endedAt: start.addingTimeInterval(3), duration: 3),
            ActivityEvent(id: "p2", seq: 2, kind: .fileRead, status: .succeeded,
                          title: "ดูรายการไฟล์ในโฟลเดอร์ทำงาน",
                          detail: "พบ 12 ไฟล์ (โฟลเดอร์ 3, ไฟล์ข้อความ 5, รูป 4)",
                          startedAt: start.addingTimeInterval(3), endedAt: start.addingTimeInterval(4), duration: 1),
            ActivityEvent(id: "p3", seq: 3, kind: .fileRead, status: .succeeded,
                          title: "อ่านไฟล์ข้อความ 5 ไฟล์",
                          detail: "อ่านครบ 5 ไฟล์ รวม 42 KB · พบข้อมูลอ่อนไหว 2 จุด (ปิดบังไว้แล้ว)",
                          rawDetail: "อ่านครบ 5 ไฟล์ รวม 42 KB · บัญชี 411-2-34567-8 และอีเมล somchai@example.com ถูกปิดบัง",
                          maskedCount: 2,
                          startedAt: start.addingTimeInterval(4), endedAt: start.addingTimeInterval(12), duration: 8),
            ActivityEvent(id: "p4", seq: 4, kind: .fileWrite, status: .succeeded,
                          title: "เขียนไฟล์สรุปโฟลเดอร์.md",
                          detail: "สร้างไฟล์ใหม่ 3.1 KB · สำรองไฟล์เดิมไว้ให้ย้อนกลับได้ 10 นาที",
                          startedAt: start.addingTimeInterval(12), endedAt: start.addingTimeInterval(15), duration: 3,
                          artifactNames: ["สรุปโฟลเดอร์.md"],
                          artifactPath: "/var/mobile/AgentWorkspace/สรุปโฟลเดอร์.md")
        ]
    }

    static func runningEvents() -> [ActivityEvent] {
        let start = Date().addingTimeInterval(-24)
        return [
            ActivityEvent(id: "r1", seq: 1, kind: .thinking, status: .succeeded,
                          title: "วางแผนงาน",
                          detail: "จะค้นเว็บ 3 แหล่ง แล้วสรุปเป็นตารางเปรียบเทียบ",
                          startedAt: start, endedAt: start.addingTimeInterval(2), duration: 2),
            ActivityEvent(id: "r2", seq: 2, kind: .webSearch, status: .succeeded,
                          title: "ค้นเว็บเรื่องราคา iPhone มือสอง",
                          detail: "พบ 8 ผลลัพธ์ เลือกอ่าน 3 แหล่งที่น่าเชื่อถือ",
                          startedAt: start.addingTimeInterval(2), endedAt: start.addingTimeInterval(9), duration: 7),
            ActivityEvent(id: "r3", seq: 3, kind: .browse, status: .running,
                          title: "กำลังอ่านหน้าเว็บที่เกี่ยวข้อง",
                          detail: "หน้า 2 จาก 3 · อ่านไปแล้ว 1.4 KB",
                          startedAt: start.addingTimeInterval(9))
        ]
    }

    // MARK: - คำขออนุมัติ

    static func approvalRequest() -> ApprovalRequest {
        ApprovalRequest(toolCallID: "call-preview-1",
                        toolName: "delete_file",
                        thaiLabel: "ลบไฟล์",
                        summary: "ลบไฟล์สำเนาสำรอง.zip ที่มีขนาด 84 MB",
                        detail: "/var/mobile/AgentWorkspace/สำเนาสำรอง.zip",
                        argumentsText: "{\n  \"path\": \"/var/mobile/AgentWorkspace/สำรอง.zip\"\n}",
                        risk: RiskAssessment(level: .destructive,
                                             reasons: ["เป็นการลบไฟล์ถาวร",
                                                       "ไฟล์นี้ไม่ได้ถูกสร้างโดย Agent",
                                                       "ลบแล้วกู้คืนไม่ได้บนเครื่องนี้"]))
    }


    // MARK: - โฟลเดอร์ทำงานตัวอย่าง (ใช้กับภาพตรวจหน้าจอ "ไฟล์")

    /// สร้างโฟลเดอร์ทำงานชั่วคราวที่มีไฟล์ตัวอย่างสมจริง แล้วตั้งเป็นโฟลเดอร์ทำงาน
    /// (เฉพาะบิลด์ Debug + โหมดตรวจภาพ: เครื่องซิมูเลเตอร์อ่าน /var/mobile ไม่ได้ตามจริง)
    static func prepareWorkspace() {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent("AgentWorkspacePreview", isDirectory: true)
        let folders = ["notes", "data", "สำรอง"]
        let files: [(String, String)] = [
            ("notes/ประชุม.md", "# บันทึกการประชุม 12 ก.ย.\n\n- เรื่องที่คุย: แผนงานไตรมาส 4\n- ผู้รับผิดชอบ: ทีมผลิตภัณฑ์\n- ต้องสรุปภายใน 20 ก.ย.\n"),
            ("notes/ไอเดีย.md", "# ไอเดียที่ยังไม่ได้ทำ\n\n1. ทำรายงานอัตโนมัติทุกสัปดาห์\n2. รวบรวมใบเสร็จเป็นไฟล์เดียว\n"),
            ("data/ยอดขาย.csv", "เดือน,ยอดขาย,หน่วย\nก.ค.,182000,1204\nส.ค.,201500,1338\nก.ย.,164000,1090\n"),
            ("data/ค่าไฟ.csv", "เดือน,หน่วย,บาท\nก.ค.,402,1780\nส.ค.,438,1912\nก.ย.,512,2210\n"),
            ("สรุปโฟลเดอร์.md", "# สรุปโฟลเดอร์ทำงาน\n\n- ไฟล์ข้อความ 5 ไฟล์\n- ข้อมูลยอดขาย 3 เดือน\n")
        ]
        try? manager.createDirectory(at: root, withIntermediateDirectories: true)
        for folder in folders {
            try? manager.createDirectory(at: root.appendingPathComponent(folder, isDirectory: true),
                                         withIntermediateDirectories: true)
        }
        for (relative, body) in files {
            let url = root.appendingPathComponent(relative)
            try? manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? body.write(to: url, atomically: true, encoding: .utf8)
        }
        AppSettings.shared.workspacePath = root.path
    }

    // MARK: - ทะเบียนงาน

    static func seedTasks() {
        let registry = TaskRegistry.shared
        // ล้างของเดิมก่อน เพื่อให้ภาพที่ได้เหมือนกันทุกครั้งที่ถ่าย (ทะเบียนจริงสะสมข้ามการเปิดแอป)
        for record in registry.all { registry.delete(id: record.id) }

        let now = Date()

        let first = registry.start(title: "สรุปไฟล์ในโฟลเดอร์ทำงาน", roomID: nil)
        registry.finish(id: first.id,
                        outcome: .done,
                        summary: "เขียนไฟล์ สรุปโฟลเดอร์.md ให้แล้ว ไม่ได้ลบหรือย้ายไฟล์ใด",
                        stepCount: 4,
                        lastStepTitle: "เขียนไฟล์ สรุปโฟลเดอร์.md",
                        fileChangeCount: 1)
        registry.previewBackdate(id: first.id,
                                 startedAt: now.addingTimeInterval(-3600),
                                 endedAt: now.addingTimeInterval(-3600 + 42))

        let second = registry.start(title: "ค้นราคา iPhone มือสองในเชียงใหม่", roomID: nil)
        registry.finish(id: second.id,
                        outcome: .interrupted,
                        summary: "แอปถูกปิดระหว่างอ่านหน้าเว็บที่ 2 จาก 3",
                        stepCount: 3,
                        lastStepTitle: "อ่านหน้าเว็บที่ 2",
                        fileChangeCount: 0)
        registry.previewBackdate(id: second.id,
                                 startedAt: now.addingTimeInterval(-2400),
                                 endedAt: now.addingTimeInterval(-2400 + 96))

        let third = registry.start(title: "แก้ไขไฟล์ data/ยอดขาย.csv", roomID: nil)
        registry.finish(id: third.id,
                        outcome: .failed,
                        summary: "ไฟล์ถูกล็อกอยู่ จึงเขียนทับไม่ได้",
                        stepCount: 2,
                        lastStepTitle: "เขียนทับไฟล์",
                        fileChangeCount: 0)
        registry.previewBackdate(id: third.id,
                                 startedAt: now.addingTimeInterval(-1200),
                                 endedAt: now.addingTimeInterval(-1200 + 18))

        let fourth = registry.start(title: "จัดระเบียบไฟล์รูป 40 ไฟล์", roomID: nil)
        registry.finish(id: fourth.id,
                        outcome: .needsAnswer,
                        summary: "Agent ขอให้ยืนยันว่าจะย้ายรูปไปโฟลเดอร์ไหน",
                        stepCount: 5,
                        lastStepTitle: "ถามผู้ใช้ว่าจะย้ายไปโฟลเดอร์ใด",
                        fileChangeCount: 0)
        registry.previewBackdate(id: fourth.id,
                                 startedAt: now.addingTimeInterval(-300),
                                 endedAt: now.addingTimeInterval(-300 + 64))
    }
}
#endif
