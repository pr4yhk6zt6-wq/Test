//
//  OpenRouterService.swift
//  iOS Agent Sandbox
//
//  ชั้นติดต่อ OpenRouter API (เฟส 1)
//  - ทดสอบการเชื่อมต่อ / โหลดรายการโมเดล / แชทแบบ streaming ผ่าน SSE
//  - retry + error handling (401/404 ไม่ลองซ้ำ, 429/5xx/เน็ตหลุด ลองใหม่ได้)
//
//  logic ที่ไม่ผูกกับเครือข่าย (error, retry policy, การรวม tool_calls delta, การถอดรหัส SSE)
//  ย้ายไปอยู่ที่ OpenRouterCore.swift เพื่อให้ unit test ได้บนทุกแพลตฟอร์ม
//
//  ทุกเมธอดเป็น static และไม่ผูกกับ actor ใด ๆ เพื่อให้เรียกได้จาก Task ทุกตัว
//  (ค่าที่ต้องอัปเดต UI ให้ผู้เรียกห่อด้วย MainActor.run เอง)
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif
#if canImport(FoundationNetworking)
// บน Linux (ใช้สำหรับรัน unit test/E2E นอก Xcode) URLSession อยู่ใน FoundationNetworking
// บน iOS/macOS ไม่เข้าเงื่อนไขนี้ จึงไม่กระทบแอปจริง
import FoundationNetworking
#endif

// MARK: - Service

struct OpenRouterService {

    static let baseURLString = "https://openrouter.ai/api/v1"
    static let appTitle = "iOS Agent Sandbox"
    static let defaultReferer = "https://localhost/ios-agent-sandbox"

    // MARK: URL

    /// สร้าง URL ของ endpoint
    /// - Parameter baseURLString: เปลี่ยนได้เมื่อใช้ gateway/proxy ของตัวเอง
    ///   หรือเมื่อรันทดสอบกับเซิร์ฟเวอร์จำลอง (ค่าเริ่มต้นคือ OpenRouter อย่างเป็นทางการ)
    static func endpoint(_ path: String, baseURLString: String = OpenRouterService.baseURLString) throws -> URL {
        var base = baseURLString
        while base.hasSuffix("/") { base.removeLast() }
        let full = base + path
        guard let url = URL(string: full) else {
            throw OpenRouterError.badURL(full)
        }
        return url
    }

    // MARK: Session

    /// สร้าง session ใหม่ทุกครั้งเพื่อไม่ให้ข้อมูลค้างในหน่วยความจำ (RAM 2GB)
    private static func makeSession(requestTimeout: TimeInterval = 30,
                                    resourceTimeout: TimeInterval = 600) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = requestTimeout
        configuration.timeoutIntervalForResource = resourceTimeout
        #if canImport(Darwin)
        configuration.waitsForConnectivity = false
        #endif
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpAdditionalHeaders = ["User-Agent": userAgent]
        return URLSession(configuration: configuration)
    }

    private static var userAgent: String {
        #if canImport(UIKit)
        let version = UIDevice.current.systemVersion
        #else
        let version = "unknown"
        #endif
        return "iOSAgentSandbox/0.1 (iOS \(version))"
    }

    private static func makeHeaders(apiKey: String,
                                    reference: String?,
                                    needsJSONBody: Bool) -> [String: String] {
        // ทำความสะอาดคีย์ก่อนส่งเสมอ: กันช่องว่าง/ขึ้นบรรทัดใหม่จากการวาง
        // (คีย์ที่มีอักขระแปลกปลอมจะได้ 401 "User not found." จากเซิร์ฟเวอร์)
        let cleanKey = APIKeySanitizer.sanitize(apiKey).cleaned
        var headers: [String: String] = [
            "Authorization": "Bearer \(cleanKey)",
            "HTTP-Referer": (reference?.isEmpty == false ? reference ?? defaultReferer : defaultReferer),
            "X-Title": appTitle,
            "Accept": "application/json"
        ]
        if needsJSONBody {
            headers["Content-Type"] = "application/json"
        }
        return headers
    }

    // MARK: - ตัวช่วยจัดการ error

    private static func mapURLError(_ error: Error) -> OpenRouterError {
        if error is CancellationError { return .cancelled }
        if let openRouterError = error as? OpenRouterError { return openRouterError }
        let urlError = error as? URLError
        switch urlError?.code {
        case .some(.cancelled):
            return .cancelled
        case .some(.timedOut):
            return .network("หมดเวลาเชื่อมต่อ (timeout 30 วินาที)")
        default:
            return .network(urlError?.localizedDescription ?? error.localizedDescription)
        }
    }

    private static func errorFromResponse(status: Int, data: Data) -> OpenRouterError {
        let body = String(data: data, encoding: .utf8) ?? ""
        let decoded = JSONValue.decode(fromJSONString: body)
        let baseMessage = decoded?["error"]?["message"]?.stringValue
            ?? decoded?["message"]?.stringValue
            ?? fallbackMessage(for: status)
        let code = decoded?["error"]?["code"]?.stringValue

        // OpenRouter ซ่อนสาเหตุจริงจากผู้ให้บริการปลายทางไว้ใน error.metadata
        // (เช่น raw: "... 400 ..." และ provider_name) — ดึงมาแสดงให้ผู้ใช้เห็นจะได้รู้ว่าต้องแก้ตรงไหน
        let metadata = decoded?["error"]?["metadata"]
        var details: [String] = []
        if let providerName = metadata?["provider_name"]?.stringValue, !providerName.isEmpty {
            details.append("ผู้ให้บริการ: \(providerName)")
        }
        if let modelName = metadata?["model"]?.stringValue, !modelName.isEmpty {
            details.append("โมเดลที่ผู้ให้บริการใช้: \(modelName)")
        }
        if let raw = metadata?["raw"]?.stringValue, !raw.isEmpty {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            let limit = 400
            details.append("สาเหตุจากผู้ให้บริการ: \(trimmed.count > limit ? String(trimmed.prefix(limit)) + "…" : trimmed)")
        }
        let message = details.isEmpty ? baseMessage : baseMessage + "\n" + details.joined(separator: "\n")

        switch status {
        case 401:
            return .unauthorized(message)
        case 404:
            return .notFound(message)
        case 429:
            return .rateLimited(message)
        case 500...599:
            return .serverError(status: status, message: message)
        case 400:
            return .apiError(status: status, code: code,
                             message: message + "\n\nคำแนะนำ: 400 แบบนี้มักเกิดจากผู้ให้บริการปลายทางขัดข้องชั่วคราว " +
                                "(พบบ่อยกับโมเดลฟรี) — แอปลองใหม่ให้อัตโนมัติแล้ว กด \"ลองส่งอีกครั้ง\" ได้ " +
                                "หรือเปลี่ยนเป็นโมเดลอื่นที่ขึ้นป้าย \"ใช้ tools ได้\"")
        default:
            return .apiError(status: status, code: code, message: message)
        }
    }

    private static func fallbackMessage(for status: Int) -> String {
        switch status {
        case 400: return "คำขอไม่ถูกต้อง (ตรวจสอบชื่อโมเดล/พารามิเตอร์)"
        case 402: return "เครดิตไม่พอสำหรับโมเดลนี้ (โมเดลฟรีบางตัวต้องเปิดใช้ Privacy/Data policy ในหน้าเว็บ OpenRouter)"
        case 403: return "ไม่ได้รับอนุญาตให้ใช้โมเดลนี้"
        case 408: return "เซิร์ฟเวอร์หมดเวลารอคำขอ"
        case 429: return "เรียกใช้งานถี่เกินไป"
        case 401: return "API Key ไม่ถูกต้อง"
        case 404: return "ไม่พบ endpoint หรือโมเดลนี้ไม่รองรับ tool calling"
        case 502, 503, 504: return "ผู้ให้บริการโมเดลขัดข้องชั่วคราว"
        default: return "HTTP \(status) – ไม่มีรายละเอียดจากเซิร์ฟเวอร์"
        }
    }

    // MARK: - Retry

    /// เรียกงานที่อาจล้มเหลว โดยลองใหม่เฉพาะ error ที่ควรลอง (429/5xx/เครือข่าย) สูงสุด 3 ครั้ง
    static func withRetry<T>(_ operation: () async throws -> T) async throws -> T {
        var attempt = 1
        while true {
            do {
                return try await operation()
            } catch {
                let mapped = mapURLError(error)
                guard mapped.isRetryable, attempt < RetryPolicy.maxAttempts else { throw mapped }
                try await RetryPolicy.sleep(forAttempt: attempt)
                attempt += 1
            }
        }
    }

    // MARK: - คำขอแบบไม่สตรีม

    /// ยิงคำขอและคืนข้อมูลดิบ พร้อม mapping error เป็นภาษาไทย
    static func data(for url: URL,
                     method: String,
                     body: Data?,
                     apiKey: String,
                     reference: String?,
                     requestTimeout: TimeInterval = 30) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.timeoutInterval = requestTimeout
        let headers = makeHeaders(apiKey: apiKey, reference: reference, needsJSONBody: body != nil)
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let session = makeSession(requestTimeout: requestTimeout)
        defer { session.finishTasksAndInvalidate() }

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw OpenRouterError.invalidResponse
            }
            guard (200..<300).contains(http.statusCode) else {
                throw errorFromResponse(status: http.statusCode, data: data)
            }
            return data
        } catch {
            throw mapURLError(error)
        }
    }

    // MARK: - โหลดรายการโมเดล

    /// GET /models — ใช้เติมรายการให้ผู้ใช้เลือก (ไม่บังคับ)
    static func fetchModels(apiKey: String,
                            reference: String? = nil,
                            baseURLString: String = OpenRouterService.baseURLString) async throws -> [OpenRouterModel] {
        let url = try endpoint("/models", baseURLString: baseURLString)
        let data = try await withRetry {
            try await self.data(for: url, method: "GET", body: nil, apiKey: apiKey, reference: reference)
        }
        do {
            let decoded = try JSONDecoder().decode(ModelsResponse.self, from: data)
            let models = decoded.data.compactMap { $0.value }
            if models.isEmpty {
                throw OpenRouterError.emptyResponse
            }
            return models.sorted { $0.id.lowercased() < $1.id.lowercased() }
        } catch let error as OpenRouterError {
            throw error
        } catch {
            throw OpenRouterError.apiError(status: 200,
                                            code: "decode_error",
                                            message: "อ่านรายการโมเดลไม่สำเร็จ: \(error.localizedDescription)")
        }
    }

    // MARK: - Body ของ chat completion

    /// การเลือกผู้ให้บริการของ OpenRouter
    struct ProviderPreferences: Encodable {
        /// true = เลือกเฉพาะผู้ให้บริการที่รองรับ "ทุกพารามิเตอร์" ในคำขอ
        /// ใช้เมื่อมีการเรียก tool เพื่อไม่ให้ OpenRouter ส่งงานไปยังผู้ให้บริการที่รองรับไม่ครบ
        /// (ต้นเหตุของ 400 "Provider returned error" ที่พบบ่อยกับโมเดลฟรี)
        let requireParameters: Bool

        enum CodingKeys: String, CodingKey {
            case requireParameters = "require_parameters"
        }
    }

    struct ChatRequestBody: Encodable {
        let model: String
        let messages: [ChatMessagePayload]
        let stream: Bool
        let temperature: Double?
        let maxTokens: Int?
        let tools: [ToolDefinition]?
        let parallelToolCalls: Bool?
        let provider: ProviderPreferences?

        enum CodingKeys: String, CodingKey {
            case model
            case messages
            case stream
            case temperature
            case tools
            case maxTokens = "max_tokens"
            case parallelToolCalls = "parallel_tool_calls"
            case provider
        }

        /// ส่งเฉพาะฟิลด์ที่มีค่า — กันผู้ให้บริการที่ปฏิเสธคำขอเมื่อเจอฟิลด์ null
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(model, forKey: .model)
            try container.encode(messages, forKey: .messages)
            try container.encode(stream, forKey: .stream)
            if let temperature = temperature {
                try container.encode(temperature, forKey: .temperature)
            }
            if let maxTokens = maxTokens {
                try container.encode(maxTokens, forKey: .maxTokens)
            }
            if let tools = tools, !tools.isEmpty {
                try container.encode(tools, forKey: .tools)
            }
            if let parallelToolCalls = parallelToolCalls {
                try container.encode(parallelToolCalls, forKey: .parallelToolCalls)
            }
            if let provider = provider {
                // บังคับให้ OpenRouter เลือกผู้ให้บริการที่รองรับ "ทุกพารามิเตอร์" ในคำขอ (รวม tools)
                // — ตัวลด 400 "Provider returned error" ที่พบบ่อยกับโมเดลฟรี
                try container.encode(provider, forKey: .provider)
            }
        }
    }

    private static func makeBody(modelID: String,
                                 messages: [ChatMessagePayload],
                                 stream: Bool,
                                 tools: [ToolDefinition]?,
                                 temperature: Double?,
                                 maxTokens: Int?,
                                 parallelToolCalls: Bool?,
                                 requireParameters: Bool) throws -> Data {
        let hasTools = tools?.isEmpty == false
        let payload = ChatRequestBody(model: modelID,
                                      messages: messages,
                                      stream: stream,
                                      temperature: temperature,
                                      maxTokens: maxTokens,
                                      tools: hasTools ? tools : nil,
                                      parallelToolCalls: hasTools ? parallelToolCalls : nil,
                                      provider: (hasTools && requireParameters)
                                          ? ProviderPreferences(requireParameters: true) : nil)
        do {
            return try JSONEncoder().encode(payload)
        } catch {
            throw OpenRouterError.apiError(status: 0,
                                            code: "encode_error",
                                            message: "สร้างคำขอไม่สำเร็จ: \(error.localizedDescription)")
        }
    }

    // MARK: - Streaming

    /// สตรีมคำตอบเป็น SSE event
    ///
    /// - 401/404: แจ้งทันที ไม่ retry
    /// - 429/5xx/เครือข่าย: retry สูงสุด 3 ครั้งด้วย exponential backoff (เฉพาะกรณียังไม่ได้รับข้อมูลใด ๆ)
    static func streamChat(modelID: String,
                           messages: [ChatMessagePayload],
                           tools: [ToolDefinition]? = nil,
                           temperature: Double? = 0.3,
                           maxTokens: Int? = nil,
                           // ไม่ส่ง parallel_tool_calls โดยค่าเริ่มต้น: ผู้ให้บริการปลายทางหลายราย
                           // (โดยเฉพาะโมเดลฟรี) ไม่รองรับพารามิเตอร์นี้และตอบ 400 กลับมา
                           parallelToolCalls: Bool? = nil,
                           apiKey: String,
                           reference: String? = nil,
                           baseURLString: String = OpenRouterService.baseURLString) -> AsyncThrowingStream<ChatStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let cleanModel = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !cleanModel.isEmpty else { throw OpenRouterError.invalidModelID }
                    guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        throw OpenRouterError.missingAPIKey
                    }
                    let url = try endpoint("/chat/completions", baseURLString: baseURLString)

                    var attempt = 1
                    // ให้ OpenRouter เลือกเฉพาะผู้ให้บริการที่รองรับ "ทุกพารามิเตอร์" (รวม tools)
                    // นี่คือวิธีที่ OpenRouter แนะนำให้ใช้เมื่อเรียก tool → ลด 400 "Provider returned error"
                    // ที่เกิดจากการถูกส่งไปยังผู้ให้บริการซึ่งรองรับไม่ครบ
                    var requireParameters = tools?.isEmpty == false
                    while true {
                        do {
                            _ = try await performStreamRequest(
                                url: url,
                                modelID: cleanModel,
                                messages: messages,
                                tools: tools,
                                temperature: temperature,
                                maxTokens: maxTokens,
                                parallelToolCalls: parallelToolCalls,
                                requireParameters: requireParameters,
                                apiKey: apiKey,
                                reference: reference,
                                continuation: continuation
                            )
                            continuation.finish()
                            return
                        } catch {
                            let mapped = mapURLError(error)
                            if mapped == .cancelled {
                                continuation.finish(throwing: OpenRouterError.cancelled)
                                return
                            }
                            // 404 ที่บอกว่าไม่มี endpoint รองรับ tool → ลองใหม่แบบไม่บังคับพารามิเตอร์ (ครั้งเดียว)
                            // เพื่อไม่ให้ผู้ใช้ที่โมเดลรองรับ tool แบบมีเงื่อนไขต้องเจอทางตัน
                            if requireParameters, case .notFound(let notFoundMessage) = mapped,
                               notFoundMessage.lowercased().contains("tool") {
                                requireParameters = false
                                continuation.yield(.notice("ไม่พบผู้ให้บริการที่รองรับการเรียก tool แบบบังคับพารามิเตอร์ทั้งหมด — ลองใหม่โดยไม่บังคับให้"))
                                try await RetryPolicy.sleep(forAttempt: attempt)
                                attempt += 1
                                continue
                            }
                            guard mapped.isRetryable, attempt < RetryPolicy.maxAttempts else {
                                continuation.finish(throwing: mapped)
                                return
                            }
                            continuation.yield(.notice("เกิดข้อผิดพลาดชั่วคราว (\(mapped.localizedDescription)) กำลังลองใหม่ครั้งที่ \(attempt + 1)/\(RetryPolicy.maxAttempts)…"))
                            try await RetryPolicy.sleep(forAttempt: attempt)
                            attempt += 1
                        }
                    }
                } catch {
                    continuation.finish(throwing: mapURLError(error))
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    /// อ่าน SSE จาก URLSession.bytes(for:) แล้วแปลงเป็น ChatStreamEvent
    /// - Returns: true ถ้าได้รับ event ใด ๆ แล้ว (ใช้ตัดสินใจว่าจะ retry หรือไม่)
    private static func performStreamRequest(url: URL,
                                             modelID: String,
                                             messages: [ChatMessagePayload],
                                             tools: [ToolDefinition]?,
                                             temperature: Double?,
                                             maxTokens: Int?,
                                             parallelToolCalls: Bool?,
                                             requireParameters: Bool,
                                             apiKey: String,
                                             reference: String?,
                                             continuation: AsyncThrowingStream<ChatStreamEvent, Error>.Continuation) async throws -> Bool {
        let body = try makeBody(modelID: modelID,
                                messages: messages,
                                stream: true,
                                tools: tools,
                                temperature: temperature,
                                maxTokens: maxTokens,
                                parallelToolCalls: parallelToolCalls,
                                requireParameters: requireParameters)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.timeoutInterval = 30
        let headers = makeHeaders(apiKey: apiKey, reference: reference, needsJSONBody: true)
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let session = makeSession(requestTimeout: 30, resourceTimeout: 600)
        defer { session.finishTasksAndInvalidate() }

        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw OpenRouterError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            // อ่าน body ของ error แบบจำกัดขนาด
            var errorData = Data()
            do {
                for try await byte in bytes {
                    errorData.append(byte)
                    if errorData.count >= 32 * 1024 { break }
                }
            } catch {
                // ถ้าอ่าน body ไม่ได้ก็ใช้ข้อความมาตรฐาน
            }
            throw errorFromResponse(status: http.statusCode, data: errorData)
        }

        var decoder = SSEDecoder()
        var buffer = Data()

        for try await byte in bytes {
            if byte == 0x0A { // \n
                if let line = String(data: buffer, encoding: .utf8) {
                    for event in decoder.consume(line: line) {
                        continuation.yield(event)
                    }
                }
                buffer.removeAll(keepingCapacity: true)
            } else {
                buffer.append(byte)
                // กันบรรทัดที่ยาวผิดปกติ (กันหน่วยความจำเต็มบนเครื่อง RAM 2GB)
                if buffer.count > 512 * 1024 {
                    throw OpenRouterError.invalidResponse
                }
            }
        }
        if !buffer.isEmpty, let line = String(data: buffer, encoding: .utf8) {
            for event in decoder.consume(line: line) {
                continuation.yield(event)
            }
        }

        // stream จบลงแล้ว (ครบหรือถูกตัดกลางทาง): ปล่อย tool call ที่ค้างไว้ + แจ้ง finish_reason
        for event in decoder.finishStream() {
            continuation.yield(event)
        }

        return decoder.sawEvent
    }

    // MARK: - คำขอแบบรอผลลัพธ์ครบ (ใช้ในเฟส 2 และปุ่มทดสอบการเชื่อมต่อ)

    static func completeChat(modelID: String,
                             messages: [ChatMessagePayload],
                             tools: [ToolDefinition]? = nil,
                             temperature: Double? = 0.3,
                             maxTokens: Int? = nil,
                             apiKey: String,
                             reference: String? = nil,
                             baseURLString: String = OpenRouterService.baseURLString) async throws -> ChatCompletionResult {
        var result = ChatCompletionResult()
        let stream = streamChat(modelID: modelID,
                                messages: messages,
                                tools: tools,
                                temperature: temperature,
                                maxTokens: maxTokens,
                                apiKey: apiKey,
                                reference: reference,
                                baseURLString: baseURLString)
        for try await event in stream {
            switch event {
            case .textDelta(let text):
                result.text += text
            case .reasoningDelta(let text):
                result.reasoning += text
            case .toolCallsCompleted(let calls):
                result.toolCalls = calls
            case .usage(let usage):
                result.usage = usage
            case .finished(let reason):
                if let reason = reason { result.finishReason = reason }
            case .notice:
                continue
            }
        }
        if result.text.isEmpty && result.toolCalls.isEmpty && result.finishReason == nil {
            throw OpenRouterError.emptyResponse
        }
        return result
    }

    // MARK: - ทดสอบการเชื่อมต่อ

    /// tool ขนาดเล็กมากสำหรับทดสอบว่าโมเดลรองรับ function calling จริง
    static let connectivityProbeTool = ToolDefinition(
        name: "ping",
        description: "Respond by calling this function with a short greeting in Thai. ใช้เพื่อทดสอบว่ารองรับ tool calling",
        parameters: .object([
            ("type", .string("object")),
            ("properties", .object([
                ("message", .object([
                    ("type", .string("string")),
                    ("description", .string("ข้อความทักทายสั้น ๆ"))
                ]))
            ])),
            ("required", .array([.string("message")]))
        ])
    )

    /// ทดสอบว่า API Key + Model ID ใช้งานได้ และโมเดลรองรับ tool calling หรือไม่
    static func testConnection(modelID: String,
                               apiKey: String,
                               reference: String? = nil) async throws -> ConnectionTestResult {
        let cleanModel = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanModel.isEmpty else { throw OpenRouterError.invalidModelID }
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OpenRouterError.missingAPIKey
        }

        let probeMessages: [ChatMessagePayload] = [
            ChatMessagePayload(role: "user",
                               content: .string("ตอบสั้น ๆ ว่า พร้อมใช้งาน และเรียกฟังก์ชัน ping ด้วยข้อความสวัสดี"),
                               toolCallID: nil,
                               toolCalls: nil,
                               name: nil)
        ]

        let started = Date()
        let result = try await completeChat(modelID: cleanModel,
                                            messages: probeMessages,
                                            tools: [connectivityProbeTool],
                                            temperature: 0,
                                            maxTokens: 128,
                                            apiKey: apiKey,
                                            reference: reference)
        let latency = Date().timeIntervalSince(started)

        let reply = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let preview: String?
        if reply.isEmpty {
            preview = nil
        } else if reply.count > 200 {
            preview = String(reply.prefix(200)) + "…"
        } else {
            preview = reply
        }

        return ConnectionTestResult(modelID: cleanModel,
                                    modelName: nil,
                                    latency: latency,
                                    supportsToolsFlag: result.toolCalls.contains { $0.function.name == "ping" },
                                    toolCallDetected: result.hasToolCalls,
                                    replyPreview: preview,
                                    usage: result.usage,
                                    checkedAt: Date())
    }
}
