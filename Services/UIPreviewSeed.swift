//
//  UIPreviewSeed.swift
//  iOS Agent Sandbox — เครื่องมือตรวจงานออกแบบ (มีเฉพาะบิลด์ Debug)
//
//  ทำไมต้องมีไฟล์นี้: ผมไม่มีเครื่อง iPhone จริงในแซนด์บ็อกซ์ จึงสร้างหน้า "จำลองสถานะ"
//  เพื่อให้ GitHub Actions เปิดแอปใน iOS Simulator แล้วถ่ายภาพหน้าจอจริงออกมาได้
//  (ภาพที่ได้คือหน้าจอที่แอปวาดจริง ไม่ใช่ภาพ mock) — ใช้ตรวจว่าดีไซน์ตรงกับแบบหรือไม่
//
//  เปิดใช้เฉพาะเมื่อสั่งด้วย launch argument เท่านั้น:
//      xcrun simctl launch booted com.example.iosagentsandbox -uiPreview chat
//  หน้าจอที่รองรับ: chat · running · approval · detail · tasks
//
//  หมายเหตุความปลอดภัย: ทั้งไฟล์ถูกตัดออกจากบิลด์ Release ด้วย #if DEBUG
//  จึงไม่มีทางที่ผู้ใช้ปลายทางจะเปิดโหมดนี้ได้ (และไม่มีผลกับข้อมูลจริงเลย)
//

#if DEBUG
import Foundation

enum UIPreview {

    /// หน้าจอที่ขอให้แสดง (nil = โหมดใช้งานจริง)
    static var screen: String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-uiPreview"), index + 1 < arguments.count else {
            return nil
        }
        return arguments[index + 1]
    }

    static var isActive: Bool { screen != nil }

    // MARK: - ข้อความตัวอย่าง (เนื้อหาเดียวกับที่ใช้ในแบบ)

    static let userPrompt = "ช่วยสรุปค่าไฟบ้านเราเดือนนี้เทียบกับเดือนก่อน แล้วบอกว่าอะไรทำให้สูงขึ้น"

    static let assistantAnswer = """
    สรุปให้แล้วครับ — เดือนนี้ค่าไฟสูงกว่าเดือนก่อนประมาณ 18% โดยตัวการหลักคือ **เครื่องปรับอากาศ** \
    ที่ทำงานนานขึ้น เพราะค่าเฉลี่ยอุณหภูมิกลางคืนสูงกว่าเดิม 2.4 องศา

    รายละเอียดที่พบ:
    1. หน่วยไฟเพิ่มจาก 412 เป็น 486 หน่วย (+18%)
    2. เครื่องปรับอากาศใช้ไป 61% ของหน่วยทั้งหมด (เดือนก่อน 48%)
    3. ค่าไฟหน่วยละเท่าเดิม ไม่ใช่การขึ้นราคา

    ผมเขียนสรุปลงไฟล์ `สรุปค่าไฟ-เดือนนี้.md` ไว้ในโฟลเดอร์ทำงานแล้ว
    """

    // MARK: - ขั้นตอนตัวอย่าง

    static func events() -> [ActivityEvent] {
        let base = Date().addingTimeInterval(-96)
        var list: [ActivityEvent] = []

        list.append(ActivityEvent(id: "p1", seq: 1, kind: .thinking, status: .succeeded,
                                  title: "คิดวางแผนงาน", detail: "แยกงานเป็น 4 ขั้น: หาไฟล์บิล → เทียบตัวเลข → หาสาเหตุ → สรุป",
                                  startedAt: base, endedAt: base.addingTimeInterval(1.2), duration: 1.2))
        list.append(ActivityEvent(id: "p2", seq: 2, kind: .fileRead, status: .succeeded,
                                  title: "อ่านไฟล์บิลค่าไฟ", detail: "อ่าน 2 ไฟล์ในโฟลเดอร์ทำงาน",
                                  startedAt: base.addingTimeInterval(2), endedAt: base.addingTimeInterval(5.4),
                                  duration: 3.4, artifactNames: ["บิลค่าไฟ-เดือนนี้.pdf", "บิลค่าไฟ-เดือนก่อน.pdf"],
                                  artifactPath: "/var/mobile/Documents/iosagentsandbox/บิลค่าไฟ-เดือนนี้.pdf"))
        list.append(ActivityEvent(id: "p3", seq: 3, kind: .webSearch, status: .succeeded,
                                  title: "ค้นข้อมูลอุณหภูมิย้อนหลัง", detail: "ค้นในเว็บ: \"อุณหภูมิเฉลี่ยกลางคืน เชียงใหม่ เดือนนี้\"",
                                  startedAt: base.addingTimeInterval(6), endedAt: base.addingTimeInterval(12.1), duration: 6.1))
        list.append(ActivityEvent(id: "p4", seq: 4, kind: .fileWrite, status: .succeeded,
                                  title: "เขียนไฟล์สรุป", detail: "สร้างไฟล์สรุปค่าไฟ-เดือนนี้.md",
                                  startedAt: base.addingTimeInterval(13), endedAt: base.addingTimeInterval(15.2),
                                  duration: 2.2, artifactNames: ["สรุปค่าไฟ-เดือนนี้.md"],
                                  artifactPath: "/var/mobile/Documents/iosagentsandbox/สรุปค่าไฟ-เดือนนี้.md"))
        return list
    }

    static func runningEvents() -> [ActivityEvent] {
        let base = Date().addingTimeInterval(-24)
        var list = events().prefix(3).map { event -> ActivityEvent in
            var copy = event
            copy.startedAt = base
            copy.endedAt = base.addingTimeInterval(event.duration ?? 1)
            return copy
        }
        list.append(ActivityEvent(id: "r4", seq: 4, kind: .browse, status: .running,
                                  title: "อ่านหน้าเว็บที่เกี่ยวข้อง",
                                  detail: "เปิด 2 แหล่งที่เชื่อถือได้ แล้วเทียบตัวเลขกับไฟล์บิล",
                                  startedAt: Date().addingTimeInterval(-6)))
        return list
    }

    static func messages(finished: Bool) -> [ChatMessage] {
        var list: [ChatMessage] = [
            .user(userPrompt),
            .assistant("", toolCalls: nil)
        ]
        list.append(.toolResult("พบ 2 ไฟล์บิลค่าไฟ", toolCallID: "c1", name: "read_file",
                                argumentsText: "{\"path\":\"บิลค่าไฟ-เดือนนี้.pdf\"}",
                                thaiLabel: "อ่านไฟล์บิลค่าไฟ", duration: 3.4))
        list.append(.toolResult("อุณหภูมิเฉลี่ยกลางคืนสูงกว่าเดือนก่อน 2.4 องศา", toolCallID: "c2",
                                name: "web_search", argumentsText: "{\"query\":\"อุณหภูมิเฉลี่ย\"}",
                                thaiLabel: "ค้นข้อมูลอุณหภูมิย้อนหลัง", duration: 6.1))
        list.append(.toolResult("เขียนไฟล์แล้ว: สรุปค่าไฟ-เดือนนี้.md", toolCallID: "c3", name: "write_file",
                                argumentsText: "{\"path\":\"สรุปค่าไฟ-เดือนนี้.md\"}",
                                thaiLabel: "เขียนไฟล์สรุป", duration: 2.2))
        if finished {
            list.append(.assistant(assistantAnswer))
        }
        return list
    }

    // MARK: - ทะเบียนงานตัวอย่าง (หน้า "งานของฉัน")

    static func seedTasks() {
        let registry = TaskRegistry.shared
        registry.clearFinished()

        let done = registry.start(title: "สรุปค่าไฟเดือนนี้เทียบกับเดือนก่อน", roomID: nil)
        registry.finish(id: done.id,
                        outcome: .done,
                        summary: "ทำเสร็จแล้ว ใช้เวลา 15 วินาที · เขียนไฟล์สรุปไว้ในโฟลเดอร์ทำงาน",
                        stepCount: 4,
                        lastStepTitle: "เขียนไฟล์สรุป",
                        fileChangeCount: 2)

        let stopped = registry.start(title: "จัดระเบียบโฟลเดอร์ดาวน์โหลด", roomID: nil)
        registry.finish(id: stopped.id,
                        outcome: .interrupted,
                        summary: "แอปถูกปิดก่อนงานนี้จะจบ — ผลที่ทำไว้แล้วยังอยู่ครบ กด \"ทำต่อจากจุดเดิม\" ได้",
                        stepCount: 2,
                        lastStepTitle: "ย้ายไฟล์เข้าโฟลเดอร์",
                        fileChangeCount: 1)

        let failed = registry.start(title: "ดึงราคาสินค้ามาทำตารางเทียบ", roomID: nil)
        registry.finish(id: failed.id,
                        outcome: .failed,
                        summary: "ดึงข้อมูลไม่สำเร็จ เพราะเว็บปลายทางไม่ตอบสนอง — ลองใหม่ได้",
                        stepCount: 3,
                        lastStepTitle: "เรียกเว็บปลายทาง",
                        fileChangeCount: 0)
    }

    // MARK: - คำขออนุมัติตัวอย่าง (กรณีลบไฟล์ — ต้องมีการยืนยันก่อนลบ)

    static func approvalRequest() -> ApprovalRequest {
        ApprovalRequest(toolCallID: "preview-approval",
                        toolName: "delete_file",
                        thaiLabel: "ลบไฟล์",
                        summary: "ลบไฟล์ บิลค่าไฟ-เดือนก่อน.pdf ออกจากโฟลเดอร์ทำงาน",
                        detail: "/var/mobile/Documents/iosagentsandbox/บิลค่าไฟ-เดือนก่อน.pdf · 184 KB",
                        argumentsText: "{\n  \"path\": \"/var/mobile/Documents/iosagentsandbox/บิลค่าไฟ-เดือนก่อน.pdf\"\n}",
                        risk: RiskAssessment(level: .destructive,
                                             reasons: ["ลบไฟล์ถาวร", "ไฟล์นี้อยู่นอกโฟลเดอร์ทำงานย่อย"]))
    }
}
#endif
