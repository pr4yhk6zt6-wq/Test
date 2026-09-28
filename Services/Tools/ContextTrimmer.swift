//
//  ContextTrimmer.swift
//  iOS Agent Sandbox
//
//  ตัดบทสนทนาก่อนส่งให้โมเดลเมื่อใกล้เต็มขอบเขต context
//
//  กติกาของเฟส 2:
//  1. เริ่มตัดเมื่อใช้ไปประมาณ 80% ของขอบเขต
//  2. ตัด "ผลลัพธ์ของ tool ที่เก่าที่สุดก่อน" (กิน token มากที่สุดและมีค่าที่สุดน้อยที่สุด)
//  3. ห้ามตัด system prompt และห้ามตัดข้อความล่าสุด
//  4. ข้อความ assistant ที่มี tool_calls ต้องอยู่หรือไปพร้อมกับผลลัพธ์ของ tool นั้นเสมอ
//     (ไม่งั้น API จะปฏิเสธเพราะมี tool message ที่ไม่มีคู่)
//
//  Foundation-only → รัน unit test ได้ทุกแพลตฟอร์ม
//

import Foundation

// MARK: - ผลลัพธ์การตัด

struct ContextTrimResult: Equatable {
    /// บทสนทนาที่จะส่งจริง
    let messages: [ChatMessage]
    /// จำนวนผลลัพธ์ของ tool ที่ถูกตัดออก
    let droppedToolResults: Int
    /// จำนวนข้อความอื่นที่ถูกตัดออก
    let droppedMessages: Int
    /// token โดยประมาณก่อนตัด
    let estimatedTokensBefore: Int
    /// token โดยประมาณหลังตัด
    let estimatedTokensAfter: Int

    var didTrim: Bool {
        droppedToolResults > 0 || droppedMessages > 0
    }

    /// ข้อความแจ้งผู้ใช้เมื่อมีการตัด
    var noticeText: String? {
        guard didTrim else { return nil }
        var parts: [String] = []
        if droppedToolResults > 0 {
            parts.append("ผลลัพธ์ tool เก่า \(droppedToolResults) รายการ")
        }
        if droppedMessages > 0 {
            parts.append("ข้อความเก่า \(droppedMessages) ข้อความ")
        }
        return "บทสนทนายาวเกินขอบเขต — ตัด \(parts.joined(separator: " และ ")) ออกเพื่อให้ตอบต่อได้ " +
            "(ประมาณ \(estimatedTokensBefore) → \(estimatedTokensAfter) token)"
    }
}

// MARK: - ตัวตัดบทสนทนา

enum ContextTrimmer {

    /// สัดส่วนของขอบเขตที่ถือว่า "เริ่มแน่น" (80%)
    static let triggerFraction = 0.8

    /// จำนวนข้อความล่าสุดที่ห้ามตัด (ไม่นับ system)
    static let defaultKeepRecentCount = 6

    /// ข้อความแทนผลลัพธ์ tool ที่ถูกตัด
    static func placeholderText(for toolName: String?) -> String {
        let label = toolName ?? "tool"
        return "[ผลลัพธ์ของ \(label) ถูกตัดออกเพราะบทสนทนายาวเกินขอบเขต — เรียก tool นี้อีกครั้งถ้าต้องการข้อมูล]"
    }

    // MARK: ประมาณจำนวน token

    /// ประมาณ token จากข้อความ: ภาษาไทย/อังกฤษปนกันเฉลี่ยประมาณ 3 ตัวอักษรต่อ 1 token
    /// (เป็นค่าประมาณสำหรับตัดสินใจ ไม่ใช่การนับที่แม่นยำ — OpenRouter ส่งค่าจริงมาใน usage)
    static func estimateTokens(_ text: String) -> Int {
        guard !text.isEmpty else { return 0 }
        let byCharacters = (text.count + 2) / 3
        return max(1, byCharacters)
    }

    static func estimateTokens(_ message: ChatMessage) -> Int {
        var total = estimateTokens(message.text) + 4 // ค่าเผื่อโครงสร้างข้อความ
        for call in message.toolCalls ?? [] {
            total += estimateTokens(call.function.name) + estimateTokens(call.function.arguments)
        }
        if message.toolCallID != nil {
            total += 4
        }
        return total
    }

    static func estimate(_ messages: [ChatMessage]) -> Int {
        messages.reduce(0) { $0 + estimateTokens($1) }
    }

    /// ควรเริ่มตัดหรือยัง
    static func shouldTrim(estimatedTokens: Int, contextLengthTokens: Int) -> Bool {
        guard contextLengthTokens > 0 else { return false }
        let triggerPoint = Double(contextLengthTokens) * triggerFraction
        return Double(estimatedTokens) > triggerPoint
    }

    // MARK: ตัดจริง

    /// ตัดบทสนทนาให้พอดีขอบเขต
    /// - Parameters:
    ///   - messages: บทสนทนาทั้งหมด (รวม system prompt และข้อความผู้ใช้ล่าสุด)
    ///   - contextLengthTokens: ขอบเขตของโมเดล (ดึงจากรายการโมเดล หรือค่าที่ผู้ใช้ตั้ง)
    ///   - keepRecentCount: จำนวนข้อความท้ายสุดที่ห้ามตัด
    static func trim(_ messages: [ChatMessage],
                     contextLengthTokens: Int,
                     keepRecentCount: Int = ContextTrimmer.defaultKeepRecentCount) -> ContextTrimResult {
        let estimatedBefore = estimate(messages)

        guard !messages.isEmpty, contextLengthTokens > 0 else {
            return ContextTrimResult(messages: messages,
                                     droppedToolResults: 0,
                                     droppedMessages: 0,
                                     estimatedTokensBefore: estimatedBefore,
                                     estimatedTokensAfter: estimatedBefore)
        }

        // เป้าหมาย: ลดลงให้เหลือต่ำกว่า 80% ของขอบเขต
        let target = Int(Double(contextLengthTokens) * triggerFraction)
        guard estimatedBefore > target else {
            return ContextTrimResult(messages: messages,
                                     droppedToolResults: 0,
                                     droppedMessages: 0,
                                     estimatedTokensBefore: estimatedBefore,
                                     estimatedTokensAfter: estimatedBefore)
        }

        // 1) จัดกลุ่มเป็นหน่วยที่ตัดได้ทั้งหน่วย
        //    - system เดี่ยว ๆ (ตัดไม่ได้)
        //    - assistant ที่มี tool_calls + ผลลัพธ์ tool ที่ตามมา (ต้องอยู่ด้วยกัน)
        //    - ข้อความอื่นเดี่ยว ๆ
        struct Unit {
            var indices: [Int]
            var isSystem: Bool
            var hasToolResult: Bool
        }

        var units: [Unit] = []
        var index = 0
        while index < messages.count {
            let message = messages[index]
            if message.role == .system {
                units.append(Unit(indices: [index], isSystem: true, hasToolResult: false))
                index += 1
                continue
            }
            if message.role == .assistant && message.hasToolCalls {
                var group = [index]
                var cursor = index + 1
                while cursor < messages.count, messages[cursor].role == .tool {
                    group.append(cursor)
                    cursor += 1
                }
                units.append(Unit(indices: group, isSystem: false, hasToolResult: true))
                index = cursor
                continue
            }
            units.append(Unit(indices: [index],
                              isSystem: false,
                              hasToolResult: message.role == .tool))
            index += 1
        }

        // 2) กำหนดว่าหน่วยใด "แตะไม่ได้" = system + ข้อความท้ายสุด keepRecentCount ข้อความ
        var protectedUnitIndices = Set<Int>()
        for (unitIndex, unit) in units.enumerated() where unit.isSystem {
            protectedUnitIndices.insert(unitIndex)
        }
        let recentMessageIDs = Set(messages.suffix(max(1, keepRecentCount)).map { $0.id })
        for (unitIndex, unit) in units.enumerated() {
            if unit.indices.contains(where: { recentMessageIDs.contains(messages[$0].id) }) {
                protectedUnitIndices.insert(unitIndex)
            }
        }

        var working = messages
        var droppedToolResults = 0
        var droppedMessages = 0
        var estimated = estimatedBefore

        func dropUnit(_ unit: Unit, asToolResult: Bool) {
            for messageIndex in unit.indices {
                let message = working[messageIndex]
                let before = estimateTokens(message)
                if asToolResult {
                    // ตัดเฉพาะ "ผลลัพธ์ของ tool" — ส่วน assistant ที่มี tool_calls ต้องคงไว้
                    // เพื่อให้คู่ tool_call_id ยังครบและ API ไม่ปฏิเสธคำขอ
                    guard message.role == .tool else { continue }
                    working[messageIndex].text = placeholderText(for: message.name)
                    droppedToolResults += 1
                } else {
                    working[messageIndex].text = ""
                    working[messageIndex].toolCalls = nil
                    droppedMessages += 1
                }
                estimated -= max(0, before - estimateTokens(working[messageIndex]))
            }
        }

        // 3) รอบแรก: ตัดผลลัพธ์ของ tool ที่เก่าที่สุดก่อน
        for (unitIndex, unit) in units.enumerated() where !protectedUnitIndices.contains(unitIndex) {
            guard estimated > target else { break }
            guard unit.hasToolResult else { continue }
            dropUnit(unit, asToolResult: true)
        }

        // 4) รอบสอง: ถ้ายังแน่นอยู่ ตัดข้อความเก่าอื่น ๆ (ข้อความที่ตัดแล้วจะกลายเป็นค่าว่าง
        //    ซึ่ง payload() จะข้ามไปในฝั่งที่ส่งจริง — ที่นี่กันไว้ด้วยหมายเหตุ)
        for (unitIndex, unit) in units.enumerated() where !protectedUnitIndices.contains(unitIndex) {
            guard estimated > target else { break }
            guard !unit.hasToolResult else { continue }
            dropUnit(unit, asToolResult: false)
        }

        // 5) ลบข้อความที่ถูกตัดจนว่างออกจริง เพื่อไม่ให้ payload มีข้อความแปลก ๆ
        var result: [ChatMessage] = []
        for message in working {
            if message.role != .system, message.isTextEmpty, !message.hasToolCalls {
                continue
            }
            result.append(message)
        }

        return ContextTrimResult(messages: result,
                                 droppedToolResults: droppedToolResults,
                                 droppedMessages: droppedMessages,
                                 estimatedTokensBefore: estimatedBefore,
                                 estimatedTokensAfter: estimate(result))
    }
}
