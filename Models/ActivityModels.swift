//
//  ActivityModels.swift
//  iOS Agent Sandbox — ดีไซน์ v2 (เฟส 5 ส่วนที่ 3)
//
//  โมเดล "กิจกรรมของ Agent" ที่ UI ใหม่ใช้แสดงไทม์ไลน์/การ์ด/แผ่นรายละเอียด
//  โครงสร้างตรงกับ phase4-component-library.md หมวด 5 (ActivityEvent schema)
//
//  ไฟล์นี้ไม่แตะ AgentEngine — UI ใหม่แปลงจาก AgentEvent เดิมผ่าน ActivityCenter
//  ทำให้ engine/เทสต์เดิมไม่ได้รับผลกระทบ (แผนใน design-project-context.md)
//

import Foundation

// MARK: - ชนิดของกิจกรรม

enum ActivityKind: String, Codable, Equatable {

    case thinking
    case plan
    case webSearch
    case browse
    case fileRead
    case fileWrite
    case fileEdit
    case fileDelete
    case shell
    case connector
    case subagent
    case askUser
    case permission
    case other

    /// แปลงชื่อ tool จริง (15 ตัวใน ToolRegistry) เป็นชนิดของกิจกรรม
    static func from(toolName: String) -> ActivityKind {
        switch toolName {
        case "web_search":
            return .webSearch
        case "fetch_webpage":
            return .browse
        case "read_file", "list_directory", "search_files", "search_content":
            return .fileRead
        case "write_file":
            return .fileWrite
        case "edit_file":
            return .fileEdit
        case "delete_file":
            return .fileDelete
        case "create_directory", "move_file", "copy_file":
            return .fileWrite
        case "execute_shell":
            return .shell
        case "http_request", "download_file":
            return .connector
        default:
            return .other
        }
    }

    var symbolName: String {
        switch self {
        case .thinking: return "sparkles"
        case .plan: return "list.bullet.rectangle"
        case .webSearch: return "magnifyingglass"
        case .browse: return "globe"
        case .fileRead: return "doc.text"
        case .fileWrite: return "square.and.pencil"
        case .fileEdit: return "square.and.pencil"
        case .fileDelete: return "trash"
        case .shell: return "terminal"
        case .connector: return "arrow.up.arrow.down.circle"
        case .subagent: return "square.stack.3d.up"
        case .askUser: return "questionmark.circle"
        case .permission: return "hand.raised.fill"
        case .other: return "circle.dashed"
        }
    }

    /// ข้อความระหว่างทำ (ภาษาคน ไม่มีศัพท์เทคนิค) — ตามชุดข้อความใน phase4-component-library.md หมวด 4
    var runningPhraseTH: String {
        switch self {
        case .thinking: return "กำลังทำความเข้าใจคำขอ"
        case .plan: return "กำลังวางแผนขั้นตอน"
        case .webSearch: return "กำลังค้นหาเว็บ"
        case .browse: return "กำลังเปิดอ่านหน้าเว็บ"
        case .fileRead: return "กำลังอ่านไฟล์"
        case .fileWrite: return "กำลังบันทึกไฟล์"
        case .fileEdit: return "กำลังแก้บางจุดในไฟล์"
        case .fileDelete: return "กำลังลบไฟล์"
        case .shell: return "กำลังรันคำสั่งบนเครื่อง"
        case .connector: return "กำลังทำงานกับบริการภายนอก"
        case .subagent: return "กำลังทำงานย่อย"
        case .askUser: return "ขอถามก่อนทำต่อ"
        case .permission: return "ต้องการอนุญาตก่อนทำต่อ"
        case .other: return "กำลังทำงานขั้นหนึ่ง"
        }
    }

    var runningPhraseEN: String {
        switch self {
        case .thinking: return "Understanding your request"
        case .plan: return "Planning the steps"
        case .webSearch: return "Searching the web"
        case .browse: return "Reading a web page"
        case .fileRead: return "Reading a file"
        case .fileWrite: return "Saving a file"
        case .fileEdit: return "Editing a file"
        case .fileDelete: return "Deleting a file"
        case .shell: return "Running a command on your device"
        case .connector: return "Working with an external service"
        case .subagent: return "Running a subtask"
        case .askUser: return "A quick question before continuing"
        case .permission: return "Needs your permission to continue"
        case .other: return "Working on a step"
        }
    }

    /// ข้อความเมื่อจบขั้น
    var donePhraseTH: String {
        switch self {
        case .thinking: return "เข้าใจคำขอแล้ว"
        case .plan: return "วางแผนเสร็จแล้ว"
        case .webSearch: return "ค้นหาเว็บเสร็จแล้ว"
        case .browse: return "อ่านหน้าเว็บเสร็จแล้ว"
        case .fileRead: return "อ่านไฟล์เสร็จแล้ว"
        case .fileWrite: return "บันทึกไฟล์เสร็จแล้ว"
        case .fileEdit: return "แก้ไขไฟล์เสร็จแล้ว"
        case .fileDelete: return "ลบไฟล์แล้ว"
        case .shell: return "รันคำสั่งเสร็จแล้ว"
        case .connector: return "ทำงานกับบริการภายนอกเสร็จแล้ว"
        case .subagent: return "งานย่อยเสร็จแล้ว"
        case .askUser: return "ได้คำตอบแล้ว"
        case .permission: return "ได้คำตอบเรื่องการอนุญาตแล้ว"
        case .other: return "ขั้นนี้เสร็จแล้ว"
        }
    }

    /// คำอธิบายสั้นว่าขั้นนี้ทำอะไร (ใช้ในแผ่นรายละเอียด — ภาษาคน ไม่มีศัพท์เทคนิค)
    var explanationTH: String {
        switch self {
        case .thinking:
            return "Agent กำลังอ่านคำขอและข้อมูลที่มีอยู่ เพื่อตัดสินใจว่าจะทำอะไรต่อ"
        case .plan:
            return "Agent แบ่งงานใหญ่ออกเป็นขั้นตอนย่อย เพื่อให้คุณเห็นภาพรวมและหยุดได้ทุกจุด"
        case .webSearch:
            return "Agent ค้นข้อมูลบนเว็บด้วยคำค้น แล้วอ่านเฉพาะผลลัพธ์ที่เกี่ยวข้อง"
        case .browse:
            return "Agent เปิดหน้าเว็บมาอ่านเนื้อหา ข้อมูลที่พบจะถูกใช้ตอบคำถามของคุณ"
        case .fileRead:
            return "Agent เปิดอ่านไฟล์ในเครื่องของคุณเพื่อใช้เป็นข้อมูล ไม่มีการแก้ไขไฟล์"
        case .fileWrite:
            return "Agent เขียนไฟล์ใหม่หรือทับไฟล์เดิมในเครื่องของคุณ — ต้องได้รับอนุญาตก่อนทุกครั้ง"
        case .fileEdit:
            return "Agent แก้ไขเฉพาะบางจุดในไฟล์ที่มีอยู่ โดยเก็บส่วนอื่นไว้เหมือนเดิม"
        case .fileDelete:
            return "Agent ลบไฟล์ออกจากเครื่อง — ย้อนกลับไม่ได้ จึงต้องได้รับการยืนยันจากคุณก่อนเสมอ"
        case .shell:
            return "Agent รันคำสั่งบนเครื่องของคุณ คำสั่งที่เสี่ยงจะถูกถามก่อนทุกครั้ง"
        case .connector:
            return "Agent รับส่งข้อมูลกับบริการภายนอกผ่านอินเทอร์เน็ต ข้อมูลที่ส่งออกจะถูกจำกัดตามที่คุณตั้งไว้"
        case .subagent:
            return "Agent แยกงานย่อยให้ทำพร้อมกัน เพื่อให้งานใหญ่เสร็จเร็วขึ้น"
        case .askUser:
            return "Agent ต้องการข้อมูลจากคุณก่อน จึงหยุดรอและไม่ทำอะไรต่อจนกว่าจะได้คำตอบ"
        case .permission:
            return "Agent ต้องการความยินยอมจากคุณก่อนทำสิ่งที่มีผลกับเครื่องหรือข้อมูลของคุณ"
        case .other:
            return "ขั้นตอนหนึ่งของ Agent ที่ยังไม่มีคำอธิบายเฉพาะ — ดูรายละเอียดดิบได้ในแผ่นนี้"
        }
    }
}

// MARK: - สถานะของกิจกรรม

enum ActivityStatus: String, Codable, Equatable {

    case pending
    case running
    case waitingUser = "waiting_user"
    case succeeded
    case failed
    case skipped
    case cancelled

    /// รองรับค่าที่ไม่รู้จักจากอนาคต: ถือเป็น "กำลังทำ" แล้วปิดเมื่อมีเหตุการณ์ปิดตามมา
    static func from(raw: String) -> ActivityStatus {
        ActivityStatus(rawValue: raw) ?? .running
    }

    var thaiLabel: String {
        switch self {
        case .pending: return "รอคิว"
        case .running: return "กำลังทำ"
        case .waitingUser: return "รอคุณตอบ"
        case .succeeded: return "เสร็จแล้ว"
        case .failed: return "ไม่สำเร็จ"
        case .skipped: return "ข้ามไป"
        case .cancelled: return "ยกเลิก"
        }
    }

    var englishLabel: String {
        switch self {
        case .pending: return "Queued"
        case .running: return "Running"
        case .waitingUser: return "Waiting for you"
        case .succeeded: return "Done"
        case .failed: return "Failed"
        case .skipped: return "Skipped"
        case .cancelled: return "Cancelled"
        }
    }

    /// ชื่อไอคอน SF Symbols (มีใน iOS 15 ทุกตัว)
    var symbolName: String {
        switch self {
        case .pending: return "clock"
        case .running: return "ellipsis.circle"
        case .waitingUser: return "questionmark.circle.fill"
        case .succeeded: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        case .skipped: return "minus.circle"
        case .cancelled: return "slash.circle"
        }
    }

    var isActive: Bool {
        self == .running || self == .pending || self == .waitingUser
    }
}

// MARK: - กิจกรรมหนึ่งรายการ

struct ActivityEvent: Identifiable, Equatable {

    var id: String
    var seq: Int
    var kind: ActivityKind
    var status: ActivityStatus
    var title: String
    /// สรุป/รายละเอียดที่ผ่านการปิดบังข้อมูลอ่อนไหวแล้ว
    var detail: String?
    /// ข้อความเดิมก่อนปิดบัง (เก็บในหน่วยความจำเท่านั้น เพื่อให้กด "แตะเพื่อแสดง" ได้)
    /// เป็น nil เมื่อไม่พบข้อมูลอ่อนไหวในขั้นนั้น
    var rawDetail: String?
    /// จำนวนจุดที่ถูกปิดบังข้อมูลอ่อนไหว (0 = ไม่มี)
    var maskedCount: Int
    var startedAt: Date?
    var endedAt: Date?
    var duration: TimeInterval?
    var requiresApproval: Bool
    var isDestructive: Bool
    /// ข้อความแจ้งเมื่อล้มเหลว (ภาษาคน)
    var failureMessage: String?
    var artifactNames: [String]
    /// path เต็มของไฟล์ที่ขั้นนี้แตะ (ใช้ค้นสำเนาสำรองเพื่อย้อนกลับ) — nil = ไม่เกี่ยวกับไฟล์
    var artifactPath: String?
    var note: String?

    init(id: String,
         seq: Int,
         kind: ActivityKind,
         status: ActivityStatus,
         title: String,
         detail: String? = nil,
         rawDetail: String? = nil,
         maskedCount: Int = 0,
         startedAt: Date? = nil,
         endedAt: Date? = nil,
         duration: TimeInterval? = nil,
         requiresApproval: Bool = false,
         isDestructive: Bool = false,
         failureMessage: String? = nil,
         artifactNames: [String] = [],
         artifactPath: String? = nil,
         note: String? = nil) {
        self.id = id
        self.seq = seq
        self.kind = kind
        self.status = status
        self.title = title
        self.detail = detail
        self.rawDetail = rawDetail
        self.maskedCount = maskedCount
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.duration = duration
        self.requiresApproval = requiresApproval
        self.isDestructive = isDestructive
        self.failureMessage = failureMessage
        self.artifactNames = artifactNames
        self.artifactPath = artifactPath
        self.note = note
    }

    /// บรรทัดตัวอย่างที่ใช้แสดงในการ์ด (ตัดให้สั้นเสมอ ไม่กิน RAM ของ iPhone 7)
    func previewLines(limit: Int) -> [String] {
        guard let detail = detail, !detail.isEmpty else { return [] }
        let lines = detail
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return Array(lines.prefix(limit))
    }

    /// แปลงข้อความผลลัพธ์ของ tool ในประวัติ ให้กลายเป็นการ์ดแบบเดียวกับไทม์ไลน์สด
    static func fromToolMessage(_ message: ChatMessage) -> ActivityEvent {
        let toolName = message.name ?? ""
        let kind = ActivityKind.from(toolName: toolName)
        let masked = SensitiveMask.mask(message.text)
        let status: ActivityStatus = (message.toolIsError == true) ? .failed : .succeeded
        return ActivityEvent(id: message.id.uuidString,
                             seq: 0,
                             kind: kind,
                             status: status,
                             title: message.toolDisplayName,
                             detail: masked.text,
                             maskedCount: masked.maskedCount,
                             startedAt: message.createdAt,
                             endedAt: message.createdAt,
                             duration: message.toolDuration,
                             requiresApproval: false,
                             isDestructive: kind == .fileDelete,
                             failureMessage: status == .failed ? firstLine(masked.text) : nil,
                             artifactNames: [],
                             note: "จากประวัติการสนทนา")
    }

    private static func firstLine(_ text: String) -> String? {
        text.split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
    }
}
