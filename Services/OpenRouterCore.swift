//
//  OpenRouterCore.swift
//  iOS Agent Sandbox
//
//  แกนกลางของชั้น OpenRouter ที่ "ไม่ผูกกับแพลตฟอร์ม" (Foundation อย่างเดียว)
//  แยกออกมาจาก OpenRouterService.swift เพื่อเหตุผลสองข้อ:
//    1) ทดสอบได้จริงด้วย unit test ทั้งบน macOS (Xcode) และบน Linux (swift test)
//    2) logic ที่เสี่ยงที่สุดของทั้งแอป (การรวม tool_calls delta + parse JSON) รวมอยู่ที่เดียว
//
//  ไฟล์นี้ต้องไม่มี UIKit / URLSession เพื่อให้คอมไพล์บน Linux ได้
//

import Foundation

// MARK: - Error

enum OpenRouterError: LocalizedError, Equatable {
    case missingAPIKey
    case invalidModelID
    case badURL(String)
    case invalidResponse
    case unauthorized(String)
    case notFound(String)
    case rateLimited(String)
    case serverError(status: Int, message: String)
    case apiError(status: Int, code: String?, message: String)
    case emptyResponse
    case cancelled
    case network(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "ยังไม่ได้ใส่ API Key กรุณาไปที่แท็บตั้งค่าเพื่อบันทึก API Key ของ OpenRouter ก่อน"
        case .invalidModelID:
            return "ยังไม่ได้ระบุ Model ID กรุณากรอกรูปแบบ provider/model เช่น deepseek/deepseek-chat-v3-0324:free"
        case .badURL(let value):
            return "URL ไม่ถูกต้อง: \(value)"
        case .invalidResponse:
            return "เซิร์ฟเวอร์ตอบกลับในรูปแบบที่ไม่รู้จัก"
        case .unauthorized(let message):
            return "401 – API Key ไม่ถูกต้องหรือถูกยกเลิกแล้ว (\(message)) กรุณาตรวจสอบ API Key ในหน้าตั้งค่า"
        case .notFound(let message):
            return "404 – ไม่พบ endpoint ของโมเดลนี้ หรือโมเดลไม่รองรับ tool calling (\(message)) กรุณาเปลี่ยนไปใช้โมเดลอื่น"
        case .rateLimited(let message):
            return "429 – ถูกจำกัดอัตราการเรียกใช้งาน (\(message))"
        case .serverError(let status, let message):
            return "\(status) – เซิร์ฟเวอร์ปลายทางขัดข้องชั่วคราว (\(message))"
        case .apiError(let status, let code, let message):
            let codeText = code.map { " [\($0)]" } ?? ""
            return "\(status)\(codeText) – \(message)"
        case .emptyResponse:
            return "เซิร์ฟเวอร์ไม่ได้ส่งข้อมูลกลับมา"
        case .cancelled:
            return "ยกเลิกคำขอแล้ว"
        case .network(let message):
            return "เชื่อมต่อเครือข่ายไม่สำเร็จ: \(message)"
        }
    }

    /// error ที่ควรลองใหม่ (429/5xx/ปัญหาเครือข่ายเท่านั้น)
    var isRetryable: Bool {
        switch self {
        case .rateLimited, .serverError, .network, .invalidResponse:
            return true
        case .apiError(let status, let code, let message):
            // 400 "Provider returned error" ของ OpenRouter คือ "ผู้ให้บริการปลายทางขัดข้อง"
            // ซึ่งพบบ่อยมากกับโมเดลฟรีและมักหายไปเมื่อลองใหม่ (ไม่ใช่คำขอผิดจริง)
            if status == 400 {
                let text = message.lowercased()
                return text.contains("provider returned error")
                    || text.contains("provider error")
                    || code == "provider_error"
            }
            // 408/409/425 เป็นความขัดข้องชั่วคราวตามสเปก HTTP
            return status == 408 || status == 409 || status == 425
        default:
            return false
        }
    }

    /// error ที่ต้องให้ผู้ใช้เปลี่ยนโมเดลทันที (ห้าม retry)
    var requiresModelChange: Bool {
        if case .notFound = self { return true }
        return false
    }

    /// error ที่ต้องไปแก้ API Key
    var requiresAPIKeyFix: Bool {
        if case .unauthorized = self { return true }
        return false
    }
}

// MARK: - Retry policy

enum RetryPolicy {
    /// จำนวนครั้งสูงสุดที่ "เรียก" ทั้งหมด (ครั้งแรก + ลองใหม่อีก 2) = retry สูงสุด 3 ครั้ง
    static let maxAttempts = 3

    /// exponential backoff: 1s, 2s, 4s … บวก jitter เล็กน้อย (ไม่เกิน ~8.25s)
    static func delayNanoseconds(forAttempt attempt: Int) -> UInt64 {
        let base: Double = pow(2.0, Double(max(0, attempt - 1)))
        let capped = min(base, 8.0)
        let jitter = Double.random(in: 0...0.25)
        return UInt64((capped + jitter) * 1_000_000_000)
    }

    static func sleep(forAttempt attempt: Int) async throws {
        try await Task.sleep(nanoseconds: delayNanoseconds(forAttempt: attempt))
    }
}

// MARK: - ตัวสะสม tool_calls delta

/// รวม delta ของ tool call ที่ถูกแบ่งมาเป็นหลาย chunk
/// (OpenRouter ส่ง id/name มาครั้งเดียว แล้วทยอยส่ง arguments โดยอ้างอิงด้วย index)
struct ToolCallAccumulator {

    private struct Entry {
        var id: String = ""
        var type: String = "function"
        var name: String = ""
        var arguments: String = ""
    }

    private var entries: [Int: Entry] = [:]
    private(set) var notes: [String] = []

    var isEmpty: Bool { entries.isEmpty }

    var hasAnyContent: Bool {
        entries.values.contains { !$0.name.isEmpty || !$0.arguments.isEmpty }
    }

    /// จำนวน tool call ที่กำลังสะสมอยู่
    var count: Int { entries.count }

    /// รับ delta หนึ่งก้อน (อาจมีหลาย tool call พร้อมกันได้ — ระบุด้วย index)
    mutating func ingest(_ deltas: [ToolCallDelta]?) {
        guard let deltas = deltas else { return }
        for (position, delta) in deltas.enumerated() {
            let index = delta.index ?? position
            var entry = entries[index] ?? Entry()

            if let id = delta.id, !id.isEmpty {
                entry.id = id
            }
            if let type = delta.type, !type.isEmpty {
                entry.type = type
            }
            if let name = delta.function?.name, !name.isEmpty {
                entry.name += name
            }
            if let arguments = delta.function?.arguments {
                entry.arguments += arguments
            }
            entries[index] = entry
        }
    }

    /// ปิดการสะสมและคืน tool call ที่ arguments กลายเป็น JSON ที่ parse ได้แล้ว
    /// (ลำดับตาม index จากน้อยไปมาก — ตรงกับลำดับที่โมเดลส่งมา)
    mutating func finish() -> [ToolCall] {
        let sortedKeys = entries.keys.sorted()
        var calls: [ToolCall] = []

        for key in sortedKeys {
            guard let entry = entries[key] else { continue }
            var id = entry.id
            if id.isEmpty {
                id = "call_\(key)_\(UUID().uuidString.prefix(8))"
                notes.append("tool call #\(key) ไม่มี id — สร้าง id ชั่วคราวให้")
            }
            if entry.name.isEmpty {
                notes.append("tool call #\(key) ไม่มีชื่อฟังก์ชัน – ข้ามรายการนี้")
                continue
            }
            let sanitized = ToolArgumentsSanitizer.sanitize(entry.arguments)
            if let note = sanitized.note {
                notes.append("\(entry.name): \(note)")
            }
            calls.append(ToolCall(id: id,
                                  function: FunctionCall(name: entry.name, arguments: sanitized.json)))
        }
        entries.removeAll()
        return calls
    }
}

/// ทำให้ arguments ของ tool call กลายเป็น JSON object ที่ parse ได้เสมอ
enum ToolArgumentsSanitizer {

    struct Result {
        let json: String
        let note: String?
    }

    static func sanitize(_ raw: String) -> Result {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            return Result(json: "{}", note: "arguments ว่าง – ใช้ object ว่างแทน")
        }
        if let value = JSONValue.decode(fromJSONString: trimmed) {
            if value.objectValue != nil {
                return Result(json: value.compactJSONString, note: nil)
            }
            return Result(json: "{}", note: "arguments ไม่ใช่ JSON object – ใช้ object ว่างแทน")
        }
        let repaired = repair(trimmed)
        if let value = JSONValue.decode(fromJSONString: repaired), value.objectValue != nil {
            return Result(json: value.compactJSONString,
                          note: "ซ่อม JSON ที่ไม่สมบูรณ์ให้อัตโนมัติ (สาเหตุ: stream ถูกตัดกลางทาง)")
        }
        return Result(json: "{}",
                      note: "parse JSON ของ arguments ไม่สำเร็จ (ส่ง object ว่างไปแทน): \(preview(trimmed))")
    }

    /// ซ่อม JSON ที่ถูกตัดกลางทาง
    /// 1) ตัดอักขระส่วนเกินท้าย (comma/โคลอน/ช่องว่าง)
    /// 2) ลองปิดปีกกา/วงเล็บ/สตริงที่ขาด แล้วตรวจว่า parse ได้
    /// 3) ถ้ายังไม่ได้ ให้ตัด "สมาชิกท้ายที่ค้าง" (เช่น `{"a":1,"b":`) ออกแล้วลองใหม่
    ///
    /// ทั้งหมดไม่แตะอักขระภายในสตริง (นับ escaped quote ให้ถูกต้อง)
    static func repair(_ text: String) -> String {
        var output = stripTrailingJunk(text)
        output = output.replacingOccurrences(of: ",}", with: "}")
        output = output.replacingOccurrences(of: ",]", with: "]")

        for _ in 0..<8 {
            let candidate = closeOpenStructures(output)
            if JSONValue.decode(fromJSONString: candidate) != nil {
                return candidate
            }
            guard let shortened = dropLastMember(output) else {
                return candidate // ตัดต่อไม่ได้แล้ว — คืนค่าที่ดีที่สุด
            }
            output = shortened
        }
        return closeOpenStructures(output)
    }

    /// ปิดปีกกา/วงเล็บเหลี่ยม/สตริงที่ยังไม่ปิด
    private static func closeOpenStructures(_ text: String) -> String {
        var output = text
        var openBraces = 0
        var openBrackets = 0
        var insideString = false
        var escaped = false

        for character in output {
            if escaped {
                escaped = false
                continue
            }
            switch character {
            case "\\":
                escaped = insideString
            case "\"":
                insideString.toggle()
            case "{":
                if !insideString { openBraces += 1 }
            case "}":
                if !insideString { openBraces = max(0, openBraces - 1) }
            case "[":
                if !insideString { openBrackets += 1 }
            case "]":
                if !insideString { openBrackets = max(0, openBrackets - 1) }
            default:
                break
            }
        }

        if insideString {
            output += "\""
        }
        if openBrackets > 0 {
            output += String(repeating: "]", count: openBrackets)
        }
        if openBraces > 0 {
            output += String(repeating: "}", count: openBraces)
        }
        return output
    }

    /// ตัดสมาชิกท้ายที่ยังไม่ครบค่าออก โดยหาลูกน้ำ comma ตัวสุดท้ายที่ "นอกสตริง"
    /// คืน nil ถ้าไม่มี comma ให้ตัด (แปลว่าเหลือสมาชิกตัวเดียวที่ยังไม่ครบ)
    private static func dropLastMember(_ text: String) -> String? {
        var insideString = false
        var escaped = false
        var lastCommaIndex: String.Index?

        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            if escaped {
                escaped = false
                index = text.index(after: index)
                continue
            }
            switch character {
            case "\\":
                if insideString { escaped = true }
            case "\"":
                insideString.toggle()
            case ",":
                if !insideString { lastCommaIndex = index }
            default:
                break
            }
            index = text.index(after: index)
        }

        guard let commaIndex = lastCommaIndex else { return nil }
        let result = stripTrailingJunk(String(text[text.startIndex..<commaIndex]))
        return result.isEmpty ? nil : result
    }

    /// ตัดอักขระส่วนเกินท้าย (comma/โคลอน/ช่องว่าง)
    private static func stripTrailingJunk(_ text: String) -> String {
        var output = text
        let trailingSet: Set<Character> = [",", ":", " ", "\n", "\t", "\r"]
        while let last = output.last, trailingSet.contains(last) {
            output.removeLast()
        }
        return output
    }

    private static func preview(_ text: String) -> String {
        let limit = 120
        if text.count <= limit { return text }
        return String(text.prefix(limit)) + "…"
    }
}

// MARK: - ตัวถอดรหัส SSE

/// แปลงบรรทัดของ SSE (`data: {...}`) จาก OpenRouter เป็น ChatStreamEvent
///
/// แยกออกมาเป็น struct ธรรมดา (ไม่ผูก URLSession) เพื่อให้ทดสอบได้ด้วย unit test
/// และเพื่อให้ OpenRouterService เหลือหน้าที่แค่ "อ่าน bytes แล้วส่งต่อ"
struct SSEDecoder {

    private var accumulator = ToolCallAccumulator()
    private var didFlushToolCalls = false

    /// true เมื่อเจอ event ที่ตีความได้อย่างน้อยหนึ่งครั้ง (ใช้ตัดสินใจว่าจะ retry หรือไม่)
    private(set) var sawEvent = false
    /// finish_reason ที่เซิร์ฟเวอร์ส่งมา (nil = stream จบกลางทาง)
    private(set) var serverFinishReason: String?
    /// ข้อความแจ้งเตือนที่เกิดระหว่างถอดรหัส (ส่งให้ UI)
    var notes: [String] { accumulator.notes }

    /// จำนวน tool call ที่สะสมไว้แต่ยังไม่ถูกปล่อยออกไป
    var pendingToolCallCount: Int { accumulator.count }

    /// ป้อนบรรทัดหนึ่งบรรทัด (ยังไม่รวม \n) แล้วคืน event ที่ได้
    mutating func consume(line: String) -> [ChatStreamEvent] {
        var events: [ChatStreamEvent] = []

        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return events }
        // ความคิดเห็นของ SSE เช่น ": OPENROUTER PROCESSING" (keep-alive) ไม่ต้องทำอะไร
        guard trimmed.hasPrefix("data:") else { return events }

        let payload = trimmed.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
        guard !payload.isEmpty else { return events }
        guard payload != "[DONE]" else { return events }

        guard let data = payload.data(using: .utf8),
              let chunk = try? JSONDecoder().decode(ChatCompletionChunk.self, from: data) else {
            return events
        }

        sawEvent = true

        if let error = chunk.error {
            events.append(.notice("เซิร์ฟเวอร์แจ้ง: \(error.displayMessage)"))
            return events
        }
        if let usage = chunk.usage {
            events.append(.usage(usage))
        }
        accumulator.ingest(chunk.choices?.first?.delta?.toolCalls)

        guard let choice = chunk.choices?.first else { return events }

        if let reasoning = choice.delta?.reasoning, !reasoning.isEmpty {
            events.append(.reasoningDelta(reasoning))
        }
        if let content = choice.delta?.content, !content.isEmpty {
            events.append(.textDelta(content))
        }
        if let finish = choice.finishReason, !finish.isEmpty {
            serverFinishReason = finish
            // ปล่อย tool call ให้ผู้เรียกก่อน แล้วจึงแจ้ง finish_reason
            events.append(contentsOf: flushToolCallsIfNeeded())
            events.append(.finished(finishReason: finish))
        }
        return events
    }

    /// เรียกเมื่อ stream จบลง (ครบหรือถูกตัด) — ปล่อย tool call ที่ค้างและปิดท้ายด้วย finish_reason
    mutating func finishStream() -> [ChatStreamEvent] {
        var events = flushToolCallsIfNeeded()
        events.append(.finished(finishReason: serverFinishReason))
        return events
    }

    private mutating func flushToolCallsIfNeeded() -> [ChatStreamEvent] {
        guard !didFlushToolCalls, !accumulator.isEmpty else { return [] }
        didFlushToolCalls = true
        let calls = accumulator.finish()
        var events = accumulator.notes.map { ChatStreamEvent.notice($0) }
        if !calls.isEmpty {
            events.append(.toolCallsCompleted(calls))
        }
        return events
    }
}
