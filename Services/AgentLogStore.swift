//
//  AgentLogStore.swift
//  iOS Agent Sandbox
//
//  บันทึกการเรียก tool ทุกครั้งของ Agent (เฟส 4)
//  เก็บไว้ในหน่วยความจำ (สูงสุด 300 รายการ) เพื่อให้ผู้ใช้ย้อนดูว่า "Agent ทำอะไรไปแล้วบ้าง"
//  พร้อมคัดลอก/ล้างได้จากแท็บบันทึก
//
//  ทำไมไม่เก็บลงดิสก์: ผลลัพธ์ของ tool อาจมีข้อมูลส่วนตัวจำนวนมาก
//  และเครื่องนี้ RAM 2GB — เก็บในหน่วยความจำแล้วหายเมื่อปิดแอปจึงปลอดภัยกว่า
//  (ประวัติการสนทนายังถูกบันทึกแยกที่ ChatHistoryStore อยู่แล้ว)
//

import Foundation

struct AgentLogEntry: Identifiable, Equatable {

    let id: UUID
    let date: Date
    /// ชื่อ tool ตามสัญญาของ API (เช่น execute_shell)
    let toolName: String
    /// ชื่อไทยที่ผู้ใช้เห็น
    let thaiLabel: String
    /// หมวดของ tool (ไฟล์ / shell / เครือข่าย)
    let category: ToolCategory
    /// arguments ที่โมเดลส่งมา (อ่านง่าย)
    let argumentsText: String
    /// ผลลัพธ์ที่ได้ (ตัดตามเพดานของ tool แล้ว)
    let resultText: String
    /// true = ผลลัพธ์เป็น error หรือผู้ใช้ไม่อนุมัติ
    let isError: Bool
    /// ใช้เวลาทำงาน (วินาที)
    let duration: TimeInterval
    /// true = ผลลัพธ์ถูกตัดเพราะยาวเกินเพดาน
    let wasTruncated: Bool

    var timeText: String {
        AgentLogEntry.timeFormatter.string(from: date)
    }

    var durationText: String {
        if duration < 1 {
            return "\(Int((duration * 1000).rounded())) มิลลิวินาที"
        }
        return String(format: "%.2f วินาที", duration)
    }

    var statusText: String {
        isError ? "ผิดพลาด/ถูกปฏิเสธ" : "สำเร็จ"
    }

    var symbolName: String {
        switch category {
        case .fileSystem: return "doc.text.magnifyingglass"
        case .shell: return "terminal"
        case .network: return "globe"
        }
    }

    /// ข้อความเต็มของรายการนี้ (ใช้คัดลอก)
    var copyText: String {
        var lines: [String] = []
        lines.append("[\(timeText)] \(thaiLabel) (\(toolName)) — \(statusText) • \(durationText)")
        if !argumentsText.isEmpty {
            lines.append("arguments:")
            lines.append(argumentsText)
        }
        lines.append("ผลลัพธ์:")
        lines.append(resultText.isEmpty ? "(ว่าง)" : resultText)
        if wasTruncated {
            lines.append("(ผลลัพธ์ถูกตัดให้สั้นลงตามเพดานของ tool)")
        }
        return lines.joined(separator: "\n")
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "th_TH")
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}

final class AgentLogStore: ObservableObject {

    static let shared = AgentLogStore()

    /// จำนวนรายการสูงสุดที่เก็บ (กัน RAM บวมบนเครื่อง 2GB)
    static let maximumEntries = 300
    /// ความยาวสูงสุดของผลลัพธ์ที่เก็บต่อรายการ
    static let maximumResultCharacters = 4_000

    @Published private(set) var entries: [AgentLogEntry] = []

    private init() { }

    var isEmpty: Bool {
        entries.isEmpty
    }

    var count: Int {
        entries.count
    }

    /// เพิ่มรายการใหม่ (รายการล่าสุดอยู่บนสุด)
    func record(toolName: String,
                thaiLabel: String,
                category: ToolCategory,
                argumentsText: String,
                resultText: String,
                isError: Bool,
                duration: TimeInterval,
                wasTruncated: Bool = false,
                date: Date = Date()) {
        let trimmedResult: String
        let truncatedHere = resultText.count > AgentLogStore.maximumResultCharacters
        if truncatedHere {
            trimmedResult = String(resultText.prefix(AgentLogStore.maximumResultCharacters)) +
                "\n…(ตัดข้อความส่วนที่เกิน \(AgentLogStore.maximumResultCharacters) ตัวอักษร เพื่อประหยัดหน่วยความจำ)"
        } else {
            trimmedResult = resultText
        }

        let entry = AgentLogEntry(id: UUID(),
                                  date: date,
                                  toolName: toolName,
                                  thaiLabel: thaiLabel,
                                  category: category,
                                  argumentsText: argumentsText,
                                  resultText: trimmedResult,
                                  isError: isError,
                                  duration: duration,
                                  wasTruncated: wasTruncated || truncatedHere)

        entries.insert(entry, at: 0)
        if entries.count > AgentLogStore.maximumEntries {
            entries.removeLast(entries.count - AgentLogStore.maximumEntries)
        }
    }

    /// คัดลอกทั้งหมดเป็นข้อความเดียว
    var allCopyText: String {
        guard !entries.isEmpty else { return "" }
        let header = "บันทึกการทำงานของ Agent — \(entries.count) รายการ"
        return ([header] + entries.map { $0.copyText }).joined(separator: "\n\n──────────\n\n")
    }

    func clear() {
        entries.removeAll()
    }

    func remove(id: UUID) {
        entries.removeAll { $0.id == id }
    }
}
