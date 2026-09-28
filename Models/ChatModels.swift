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

    init(id: UUID = UUID(),
         role: ChatRole,
         text: String,
         toolCalls: [ToolCall]? = nil,
         toolCallID: String? = nil,
         name: String? = nil,
         createdAt: Date = Date()) {
        self.id = id
        self.role = role
        self.text = text
        self.toolCalls = toolCalls
        self.toolCallID = toolCallID
        self.name = name
        self.createdAt = createdAt
    }

    // MARK: ตัวสร้างสำเร็จรูป

    static func system(_ text: String) -> ChatMessage {
        ChatMessage(role: .system, text: text)
    }

    static func user(_ text: String) -> ChatMessage {
        ChatMessage(role: .user, text: text)
    }

    static func assistant(_ text: String, toolCalls: [ToolCall]? = nil) -> ChatMessage {
        ChatMessage(role: .assistant, text: text, toolCalls: toolCalls)
    }

    static func toolResult(_ text: String, toolCallID: String, name: String) -> ChatMessage {
        ChatMessage(role: .tool, text: text, toolCallID: toolCallID, name: name)
    }

    // MARK: ตัวช่วย

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
        } else {
            content = .string(text)
        }
        return ChatMessagePayload(role: role.rawValue,
                                  content: content,
                                  toolCallID: toolCallID,
                                  toolCalls: hasToolCalls ? toolCalls : nil,
                                  name: role == .tool ? name : nil)
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
