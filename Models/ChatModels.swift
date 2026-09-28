//
//  ChatModels.swift
//  iOS Agent Sandbox
//
//  โครงสร้างข้อความแชท, tool call และ tool definition
//  โครงสร้างเหล่านี้ถูกใช้ทั้งใน UI, ประวัติแชท (JSON) และ payload ที่ส่งไป OpenRouter
//

import Foundation

// MARK: - บทบาทของข้อความ

enum ChatRole: String, Codable {
    case system
    case user
    case assistant
    case tool
}

// MARK: - ข้อความในแชท

struct ChatMessage: Identifiable, Codable, Equatable {
    var id: UUID
    var role: ChatRole
    var text: String
    /// tool_call ที่โมเดลสั่งให้เรียก (เฉพาะ role = assistant)
    var toolCalls: [ToolCall]?
    /// id ของ tool_call ที่ข้อความนี้เป็นผลลัพธ์ (เฉพาะ role = tool)
    var toolCallID: String?
    /// ชื่อ tool (เฉพาะ role = tool)
    var name: String?
    var createdAt: Date

    // MARK: ข้อมูลเพิ่มเติมสำหรับแสดงผล (ไม่ถูกส่งไป API — payload() ไม่ใช้ฟิลด์เหล่านี้)
    //
    // ใช้กับการ์ด tool ในหน้าแชท (เฟส 2) และการบันทึกประวัติลงเครื่อง

    /// arguments ที่โมเดลส่งมา (ข้อความ JSON แบบอ่านง่าย)
    var toolArguments: String?
    /// ชื่อไทยของ tool ที่ใช้แสดงบนการ์ด
    var toolThaiLabel: String?
    /// เวลาที่ tool ใช้จริง (วินาที)
    var toolDuration: TimeInterval?
    /// true = tool นี้ทำงานไม่สำเร็จ
    var toolIsError: Bool?

    // MARK: ไฟล์แนบ (เฟส 5)

    /// ไฟล์แนบของผู้ใช้ที่แนบมากับข้อความนี้ (ข้อมูลเล็ก — บันทึกลงประวัติได้)
    var attachments: [Attachment]?
    /// รูปที่ย่อและแปลง base64 แล้ว เพื่อส่งเป็น image_url ให้โมเดลที่รับรูป
    /// ไม่ถูกบันทึกลงไฟล์ประวัติ (กันไฟล์บวมและกันหน่วยความจำเกินบนเครื่อง RAM 2GB)
    var visionImageDataURLs: [String]?

    /// ฟิลด์ที่บันทึกลงประวัติ (ตัด `visionImageDataURLs` ออกโดยเจตนา)
    enum CodingKeys: String, CodingKey {
        case id, role, text, toolCalls, toolCallID, name, createdAt
        case toolArguments, toolThaiLabel, toolDuration, toolIsError
        case attachments
    }

    init(id: UUID = UUID(),
         role: ChatRole,
         text: String,
         toolCalls: [ToolCall]? = nil,
         toolCallID: String? = nil,
         name: String? = nil,
         createdAt: Date = Date(),
         toolArguments: String? = nil,
         toolThaiLabel: String? = nil,
         toolDuration: TimeInterval? = nil,
         toolIsError: Bool? = nil,
         attachments: [Attachment]? = nil,
         visionImageDataURLs: [String]? = nil) {
        self.id = id
        self.role = role
        self.text = text
        self.toolCalls = toolCalls
        self.toolCallID = toolCallID
        self.name = name
        self.createdAt = createdAt
        self.toolArguments = toolArguments
        self.toolThaiLabel = toolThaiLabel
        self.toolDuration = toolDuration
        self.toolIsError = toolIsError
        self.attachments = attachments
        self.visionImageDataURLs = visionImageDataURLs
    }

    // MARK: ตัวสร้างสำเร็จรูป

    static func system(_ text: String) -> ChatMessage {
        ChatMessage(role: .system, text: text)
    }

    static func user(_ text: String) -> ChatMessage {
        ChatMessage(role: .user, text: text)
    }

    /// ข้อความผู้ใช้ที่มีไฟล์แนบ (เฟส 5)
    /// - Parameter visionImageDataURLs: รูปที่ย่อ+base64 แล้ว (เฉพาะเมื่อโมเดลรับรูป)
    static func user(_ text: String,
                     attachments: [Attachment],
                     visionImageDataURLs: [String] = []) -> ChatMessage {
        ChatMessage(role: .user,
                    text: text,
                    attachments: attachments.isEmpty ? nil : attachments,
                    visionImageDataURLs: visionImageDataURLs.isEmpty ? nil : visionImageDataURLs)
    }

    static func assistant(_ text: String, toolCalls: [ToolCall]? = nil) -> ChatMessage {
        ChatMessage(role: .assistant, text: text, toolCalls: toolCalls)
    }

    static func toolResult(_ text: String,
                           toolCallID: String,
                           name: String,
                           argumentsText: String? = nil,
                           thaiLabel: String? = nil,
                           duration: TimeInterval? = nil,
                           isError: Bool = false) -> ChatMessage {
        ChatMessage(role: .tool,
                    text: text,
                    toolCallID: toolCallID,
                    name: name,
                    toolArguments: argumentsText,
                    toolThaiLabel: thaiLabel,
                    toolDuration: duration,
                    toolIsError: isError)
    }

    /// ชื่อที่ใช้แสดงบนการ์ด tool (ชื่อไทยถ้ามี ไม่งั้นใช้ชื่อจริง)
    var toolDisplayName: String {
        if let thai = toolThaiLabel, !thai.isEmpty { return thai }
        return name ?? "tool"
    }

    /// true = ข้อความนี้เป็นผลลัพธ์ของ tool
    var isToolResult: Bool {
        role == .tool
    }

    // MARK: ตัวช่วย

    /// true = ข้อความนี้มีไฟล์แนบ
    var hasAttachments: Bool {
        !(attachments ?? []).isEmpty
    }

    var isTextEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasToolCalls: Bool {
        !(toolCalls ?? []).isEmpty
    }

    /// แปลงเป็น payload ที่ OpenRouter รับได้
    /// - assistant ที่มีแต่ tool_calls จะส่ง content เป็น null
    /// - ข้อความอื่นส่ง content เป็น string เสมอ
    func payload() -> ChatMessagePayload {
        let content: JSONValue
        if role == .assistant && isTextEmpty {
            content = .null
        } else if role == .tool && isTextEmpty {
            // ผู้ให้บริการบางราย (โดยเฉพาะโมเดลฟรี) ปฏิเสธข้อความผลลัพธ์ของ tool ที่ว่างเปล่า
            content = .string("(ไม่มีผลลัพธ์)")
        } else if role == .user, let attachments = attachments, !attachments.isEmpty {
            // ไฟล์แนบ: ถ้ามีรูปและโมเดลรับรูป → ส่งเป็น array ของ parts (text + image_url)
            // ถ้าไม่มีรูป (หรือโมเดลไม่รับ) → ส่งข้อความ + รายการพาธ + เนื้อหาไฟล์ข้อความเล็ก
            let dataURLs = visionImageDataURLs ?? []
            content = AttachmentMessageBuilder.content(text: text,
                                                       attachments: attachments,
                                                       imageDataURLs: dataURLs,
                                                       includeImages: !dataURLs.isEmpty)
        } else {
            content = .string(text)
        }
        return ChatMessagePayload(role: role.rawValue,
                                  content: content,
                                  toolCallID: toolCallID,
                                  toolCalls: hasToolCalls ? toolCalls : nil,
                                  // ไม่ส่งฟิลด์ name ของ role=tool: สเปก OpenAI ไม่มีฟิลด์นี้
                                  // และผู้ให้บริการที่ตรวจเข้มจะตอบ 400 ถ้าได้รับ
                                  name: nil)
    }
}

/// รูปแบบข้อความบนสาย (wire format) ของ OpenRouter / OpenAI
///
/// เขียน encode เองเพื่อ "ไม่ส่งฟิลด์ที่เป็น nil" — ผู้ให้บริการโมเดลฟรีบางราย
/// จะปฏิเสธคำขอถ้าเจอฟิลด์อย่าง `tools: null` หรือ `name: null` ปนมา
struct ChatMessagePayload: Encodable {
    let role: String
    let content: JSONValue
    let toolCallID: String?
    let toolCalls: [ToolCall]?
    let name: String?

    enum CodingKeys: String, CodingKey {
        case role
        case content
        case toolCallID = "tool_call_id"
        case toolCalls = "tool_calls"
        case name
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(role, forKey: .role)
        if content.isNull {
            // assistant ที่มีแต่ tool_calls ต้องส่ง content เป็น null ตามสเปก OpenAI
            try container.encodeNil(forKey: .content)
        } else {
            try container.encode(content, forKey: .content)
        }
        if let toolCallID = toolCallID, !toolCallID.isEmpty {
            try container.encode(toolCallID, forKey: .toolCallID)
        }
        if let toolCalls = toolCalls, !toolCalls.isEmpty {
            try container.encode(toolCalls, forKey: .toolCalls)
        }
        if let name = name, !name.isEmpty {
            try container.encode(name, forKey: .name)
        }
    }
}

// MARK: - Tool call

struct ToolCall: Identifiable, Codable, Equatable {
    var id: String
    var type: String
    var function: FunctionCall

    init(id: String, function: FunctionCall, type: String = "function") {
        self.id = id
        self.type = type
        self.function = function
    }
}

struct FunctionCall: Codable, Equatable {
    var name: String
    /// arguments ดิบที่โมเดลส่งมา (เป็นข้อความ JSON — อาจไม่สมบูรณ์ถ้า parse ไม่ได้)
    var arguments: String

    init(name: String, arguments: String) {
        self.name = name
        self.arguments = arguments
    }

    /// arguments ที่ parse เป็น object แล้ว (nil = parse ไม่สำเร็จ)
    var decodedArguments: [String: JSONValue]? {
        JSONValue.decodeObject(fromJSONString: arguments)
    }

    var argumentsDisplayText: String {
        JSONValue.decode(fromJSONString: arguments)?.prettyJSONString ?? arguments
    }
}

// MARK: - Tool definition (OpenAI function schema)

struct ToolDefinition: Codable, Equatable {
    struct ToolFunction: Codable, Equatable {
        let name: String
        let description: String
        /// JSON Schema ของพารามิเตอร์
        let parameters: JSONValue
    }

    let type: String
    let function: ToolFunction

    init(name: String, description: String, parameters: JSONValue) {
        self.type = "function"
        self.function = ToolFunction(name: name, description: description, parameters: parameters)
    }
}

// MARK: - Token usage

struct TokenUsage: Codable, Equatable {
    var promptTokens: Int
    var completionTokens: Int
    var totalTokens: Int
    /// ค่าใช้จ่ายเป็นเครดิต (OpenRouter ส่งมาให้เสมอในค่ายใหม่)
    var cost: Double?
    var cachedTokens: Int?

    init(promptTokens: Int, completionTokens: Int, totalTokens: Int, cost: Double? = nil, cachedTokens: Int? = nil) {
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.totalTokens = totalTokens
        self.cost = cost
        self.cachedTokens = cachedTokens
    }

    enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case totalTokens = "total_tokens"
        case cost
        case promptTokensDetails = "prompt_tokens_details"
    }

    enum DetailsKeys: String, CodingKey {
        case cachedTokens = "cached_tokens"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let prompt = try container.decodeIfPresent(Int.self, forKey: .promptTokens) ?? 0
        let completion = try container.decodeIfPresent(Int.self, forKey: .completionTokens) ?? 0
        let total = try container.decodeIfPresent(Int.self, forKey: .totalTokens) ?? (prompt + completion)
        self.promptTokens = prompt
        self.completionTokens = completion
        self.totalTokens = total
        self.cost = try container.decodeIfPresent(Double.self, forKey: .cost)
        if let details = try? container.nestedContainer(keyedBy: DetailsKeys.self, forKey: .promptTokensDetails) {
            self.cachedTokens = try details.decodeIfPresent(Int.self, forKey: .cachedTokens)
        } else {
            self.cachedTokens = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(promptTokens, forKey: .promptTokens)
        try container.encode(completionTokens, forKey: .completionTokens)
        try container.encode(totalTokens, forKey: .totalTokens)
        try container.encodeIfPresent(cost, forKey: .cost)
    }

    static let zero = TokenUsage(promptTokens: 0, completionTokens: 0, totalTokens: 0)

    var isEmpty: Bool {
        promptTokens == 0 && completionTokens == 0 && totalTokens == 0
    }

    var summaryText: String {
        "prompt \(promptTokens) / completion \(completionTokens) / total \(totalTokens)"
    }

    /// ข้อความสั้นสำหรับแสดงในแถบสถานะ
    var shortText: String {
        "↑\(promptTokens) ↓\(completionTokens) รวม \(totalTokens)"
    }
}
