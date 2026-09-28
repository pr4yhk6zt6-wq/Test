//
//  OpenRouterModels.swift
//  iOS Agent Sandbox
//
//  โครงสร้างข้อมูลที่ได้จาก OpenRouter API (chunk ของ SSE, รายการโมเดล, error body)
//

import Foundation

// MARK: - Error body

struct APIErrorBody: Codable, Equatable {
    let code: JSONValue?
    let message: String?

    var displayMessage: String {
        let text = message?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if text.isEmpty {
            return "เซิร์ฟเวอร์ไม่ได้ระบุสาเหตุ"
        }
        return text
    }
}

// MARK: - SSE chunk

struct FunctionCallDelta: Codable, Equatable {
    let name: String?
    let arguments: String?
}

struct ToolCallDelta: Codable, Equatable {
    let index: Int?
    let id: String?
    let type: String?
    let function: FunctionCallDelta?
}

struct ChatCompletionChunk: Codable, Equatable {
    struct Delta: Codable, Equatable {
        let role: String?
        let content: String?
        /// โมเดลสาย reasoning (OpenRouter ส่ง delta ของความคิดแยกมาในฟิลด์นี้)
        let reasoning: String?
        let toolCalls: [ToolCallDelta]?

        enum CodingKeys: String, CodingKey {
            case role
            case content
            case reasoning
            case toolCalls = "tool_calls"
        }
    }

    struct Choice: Codable, Equatable {
        let index: Int?
        let delta: Delta?
        let finishReason: String?

        enum CodingKeys: String, CodingKey {
            case index
            case delta
            case finishReason = "finish_reason"
        }
    }

    let id: String?
    let model: String?
    let choices: [Choice]?
    let usage: TokenUsage?
    let error: APIErrorBody?
}

// MARK: - เหตุการณ์ที่ไหลออกจาก streamChat

enum ChatStreamEvent {
    /// ข้อความปกติที่โมเดลพิมพ์
    case textDelta(String)
    /// ความคิดของโมเดลสาย reasoning (ยังไม่แสดงใน UI เฟส 1)
    case reasoningDelta(String)
    /// tool call ที่รวม delta ครบทุกชิ้นแล้วและ parse JSON เรียบร้อย
    case toolCallsCompleted([ToolCall])
    /// token usage (OpenRouter ส่งมาใน chunk สุดท้ายก่อน [DONE])
    case usage(TokenUsage)
    /// finish_reason จากเซิร์ฟเวอร์
    case finished(finishReason: String?)
    /// ข้อความแจ้งเตือนของผู้ให้บริการเอง (เช่น กำลังลองใหม่, ซ่อม arguments ของ tool call)
    case notice(String)
}

// MARK: - ผลลัพธ์แบบไม่สตรีม (ใช้โดย AgentEngine ในเฟส 2)

struct ChatCompletionResult {
    var text: String = ""
    var reasoning: String = ""
    var toolCalls: [ToolCall] = []
    var usage: TokenUsage?
    var finishReason: String?

    var hasToolCalls: Bool {
        !toolCalls.isEmpty
    }
}

// MARK: - ผลลัพธ์การทดสอบการเชื่อมต่อ

struct ConnectionTestResult {
    let modelID: String
    let modelName: String?
    let latency: TimeInterval
    let supportsToolsFlag: Bool
    let toolCallDetected: Bool
    let replyPreview: String?
    let usage: TokenUsage?
    let checkedAt: Date
}

// MARK: - รายการโมเดล

/// ตัวช่วย decode แบบทนทาน — ถ้าโมเดลตัวใดตัวหนึ่งผิดรูปแบบ จะไม่ทำให้ทั้งลิสต์พัง
struct FailableValue<T: Decodable>: Decodable {
    let value: T?

    init(from decoder: Decoder) throws {
        value = try? T(from: decoder)
    }
}

struct ModelsResponse: Decodable {
    let data: [FailableValue<OpenRouterModel>]
}

/// ตัวเลขที่ OpenRouter ส่งมาเป็น string หรือ number ก็ได้
struct FlexibleNumber: Codable, Equatable {
    let value: Double?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let number = try? container.decode(Double.self) {
            value = number
        } else if let text = try? container.decode(String.self) {
            value = Double(text)
        } else {
            value = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

struct OpenRouterModel: Decodable, Identifiable, Equatable {
    struct Architecture: Decodable, Equatable {
        let inputModalities: [String]?
        let outputModalities: [String]?
        let modality: String?
        let tokenizer: String?

        enum CodingKeys: String, CodingKey {
            case inputModalities = "input_modalities"
            case outputModalities = "output_modalities"
            case modality
            case tokenizer
        }
    }

    struct Pricing: Decodable, Equatable {
        let prompt: FlexibleNumber?
        let completion: FlexibleNumber?
        let request: FlexibleNumber?
        let image: FlexibleNumber?
    }

    struct TopProvider: Decodable, Equatable {
        let contextLength: Int?
        let maxCompletionTokens: Int?
        let isModerated: Bool?

        enum CodingKeys: String, CodingKey {
            case contextLength = "context_length"
            case maxCompletionTokens = "max_completion_tokens"
            case isModerated = "is_moderated"
        }
    }

    let id: String
    let name: String?
    let description: String?
    let contextLength: Int?
    let pricing: Pricing?
    let architecture: Architecture?
    let topProvider: TopProvider?
    let supportedParameters: [String]?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case description
        case contextLength = "context_length"
        case pricing
        case architecture
        case topProvider = "top_provider"
        case supportedParameters = "supported_parameters"
    }

    // MARK: ตัวช่วยแสดงผล

    var displayName: String {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? id : trimmed
    }

    /// โมเดลฟรี (ราคา prompt และ completion เป็น 0)
    var isFree: Bool {
        let promptPrice = pricing?.prompt?.value ?? 1
        let completionPrice = pricing?.completion?.value ?? 1
        return promptPrice == 0 && completionPrice == 0
    }

    var supportsTools: Bool {
        (supportedParameters ?? []).contains("tools")
    }

    var supportsVision: Bool {
        (architecture?.inputModalities ?? []).contains("image")
    }

    var contextLabel: String {
        guard let length = contextLength, length > 0 else { return "—" }
        if length >= 1_000_000 {
            return String(format: "%.1fM ctx", Double(length) / 1_000_000)
        }
        if length >= 1_000 {
            return "\(length / 1_000)K ctx"
        }
        return "\(length) ctx"
    }
}
