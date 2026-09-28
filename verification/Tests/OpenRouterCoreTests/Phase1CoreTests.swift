//
//  Phase1CoreTests.swift
//  แบบทดสอบแกนกลางของเฟส 1 (รันได้ทั้งบน macOS และ Linux ด้วย `swift test`)
//
//  ทดสอบ "ไฟล์ต้นฉบับของแอป" โดยตรง (คัดลอกมาพร้อมตรวจ sha256 ใน run-verification.sh)
//  ครอบคลุมจุดที่เสี่ยงที่สุด: tool_calls delta ที่ถูกแบ่งเป็น chunk, JSON ถูกตัดกลางทาง,
//  SSE decoding (usage/finish/tool_calls), การจำแนก error สำหรับ retry, payload encoding
//

import XCTest
@testable import OpenRouterCore

// MARK: - ตัวช่วยอ่านค่า event ในแบบทดสอบ

private extension ChatStreamEvent {
    var textValue: String? {
        if case .textDelta(let value) = self { return value }
        return nil
    }

    var reasoningValue: String? {
        if case .reasoningDelta(let value) = self { return value }
        return nil
    }

    var toolCallsValue: [ToolCall]? {
        if case .toolCallsCompleted(let value) = self { return value }
        return nil
    }

    var usageValue: TokenUsage? {
        if case .usage(let value) = self { return value }
        return nil
    }

    var noticeValue: String? {
        if case .notice(let value) = self { return value }
        return nil
    }

    /// nil = ไม่ใช่ event .finished ; .some(nil) = finished ที่ไม่มี finish_reason
    var finishedValue: String?? {
        if case .finished(let reason) = self { return .some(reason) }
        return nil
    }
}

private func decode(_ lines: [String]) -> (events: [ChatStreamEvent], decoder: SSEDecoder) {
    var decoder = SSEDecoder()
    var events: [ChatStreamEvent] = []
    for line in lines {
        events.append(contentsOf: decoder.consume(line: line))
    }
    return (events, decoder)
}

// MARK: - 1) การรวม tool_calls delta (ข้อกำหนดสำคัญของเฟส 1)

final class ToolCallAccumulatorTests: XCTestCase {

    /// arguments ถูกแบ่งมาเป็นหลาย chunk พร้อม index — ต้องรวมครบก่อน parse
    func testMergesArgumentsSplitAcrossManyChunks() {
        var accumulator = ToolCallAccumulator()

        accumulator.ingest([ToolCallDelta(index: 0, id: "call_abc", type: "function",
                                          function: FunctionCallDelta(name: "read_file", arguments: nil))])
        accumulator.ingest([ToolCallDelta(index: 0, id: nil, type: nil,
                                          function: FunctionCallDelta(name: nil, arguments: "{\"pa"))])
        accumulator.ingest([ToolCallDelta(index: 0, id: nil, type: nil,
                                          function: FunctionCallDelta(name: nil, arguments: "th\": \"/var/mo"))])
        accumulator.ingest([ToolCallDelta(index: 0, id: nil, type: nil,
                                          function: FunctionCallDelta(name: nil, arguments: "bile/Documents/a.txt\"}"))])

        let calls = accumulator.finish()
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.id, "call_abc")
        XCTAssertEqual(calls.first?.function.name, "read_file")
        XCTAssertEqual(calls.first?.function.decodedArguments?["path"]?.stringValue, "/var/mobile/Documents/a.txt")
    }

    /// โมเดลเรียกหลาย tool พร้อมกัน (parallel tool calls) — delta สลับกันไปมา ต้องแยกตาม index ให้ถูก
    func testMergesParallelToolCallsByIndex() {
        var accumulator = ToolCallAccumulator()

        accumulator.ingest([ToolCallDelta(index: 0, id: "call_1", type: "function",
                                          function: FunctionCallDelta(name: "list_directory", arguments: nil)),
                            ToolCallDelta(index: 1, id: "call_2", type: "function",
                                          function: FunctionCallDelta(name: "execute_shell", arguments: nil))])
        accumulator.ingest([ToolCallDelta(index: 0, id: nil, type: nil,
                                          function: FunctionCallDelta(name: nil, arguments: "{\"path\":\"/var/mobile\"}")),
                            ToolCallDelta(index: 1, id: nil, type: nil,
                                          function: FunctionCallDelta(name: nil, arguments: "{\"command\":\"uname -a\"}"))])

        let calls = accumulator.finish()
        XCTAssertEqual(calls.count, 2)
        XCTAssertEqual(calls[0].id, "call_1")
        XCTAssertEqual(calls[0].function.name, "list_directory")
        XCTAssertEqual(calls[0].function.decodedArguments?["path"]?.stringValue, "/var/mobile")
        XCTAssertEqual(calls[1].id, "call_2")
        XCTAssertEqual(calls[1].function.name, "execute_shell")
        XCTAssertEqual(calls[1].function.decodedArguments?["command"]?.stringValue, "uname -a")
    }

    /// delta ที่ไม่มี index เลย (ผู้ให้บริการบางราย) — ใช้ตำแหน่งในอาร์เรย์แทน
    func testFallsBackToArrayPositionWhenIndexMissing() {
        var accumulator = ToolCallAccumulator()
        accumulator.ingest([ToolCallDelta(index: nil, id: "call_a", type: nil,
                                          function: FunctionCallDelta(name: "write_file", arguments: "{\"path\":\"/tmp/x\"}")),
                            ToolCallDelta(index: nil, id: "call_b", type: nil,
                                          function: FunctionCallDelta(name: "web_search", arguments: "{\"query\":\"swift\"}") )])
        let calls = accumulator.finish()
        XCTAssertEqual(calls.count, 2)
        XCTAssertEqual(calls[0].function.name, "write_file")
        XCTAssertEqual(calls[1].function.name, "web_search")
    }

    /// tool call ที่ไม่มี id ต้องได้ id ชั่วคราว (ไม่ crash / ไม่ทิ้ง call)
    func testGeneratesTemporaryIDWhenMissing() {
        var accumulator = ToolCallAccumulator()
        accumulator.ingest([ToolCallDelta(index: 0, id: nil, type: nil,
                                          function: FunctionCallDelta(name: "read_file", arguments: "{}"))])
        let calls = accumulator.finish()
        XCTAssertEqual(calls.count, 1)
        XCTAssertFalse(calls[0].id.isEmpty)
        XCTAssertTrue(accumulator.notes.contains { $0.contains("ไม่มี id") })
    }

    /// tool call ที่ไม่มีชื่อฟังก์ชัน — ข้ามพร้อมบันทึกเหตุผล
    func testSkipsCallWithoutFunctionName() {
        var accumulator = ToolCallAccumulator()
        accumulator.ingest([ToolCallDelta(index: 0, id: "call_x", type: nil,
                                          function: FunctionCallDelta(name: nil, arguments: "{}"))])
        let calls = accumulator.finish()
        XCTAssertTrue(calls.isEmpty)
        XCTAssertTrue(accumulator.notes.contains { $0.contains("ไม่มีชื่อฟังก์ชัน") })
    }

    /// name ที่ถูกแบ่งเป็นสอง chunk ต้องต่อกันได้
    func testMergesSplitFunctionName() {
        var accumulator = ToolCallAccumulator()
        accumulator.ingest([ToolCallDelta(index: 0, id: "c", type: nil,
                                          function: FunctionCallDelta(name: "execute_", arguments: nil))])
        accumulator.ingest([ToolCallDelta(index: 0, id: nil, type: nil,
                                          function: FunctionCallDelta(name: "shell", arguments: "{\"command\":\"ls\"}"))])
        let calls = accumulator.finish()
        XCTAssertEqual(calls.first?.function.name, "execute_shell")
    }
}

// MARK: - 2) การซ่อม arguments ที่ไม่สมบูรณ์

final class ToolArgumentsSanitizerTests: XCTestCase {

    func testTruncatedArgumentsAreRepaired() {
        let truncated = "{\"path\":\"/var/mobile/Documents/note.txt\",\"content\":\"hello wor"
        let result = ToolArgumentsSanitizer.sanitize(truncated)
        XCTAssertNotNil(result.note)

        let parsed = JSONValue.decode(fromJSONString: result.json)
        XCTAssertNotNil(parsed?.objectValue)
        XCTAssertEqual(parsed?["path"]?.stringValue, "/var/mobile/Documents/note.txt")
    }

    func testTruncatedInsideNestedObjectIsRepaired() {
        let truncated = "{\"path\":\"/tmp/a\",\"options\":{\"recursive\":true"
        let result = ToolArgumentsSanitizer.sanitize(truncated)
        let parsed = JSONValue.decode(fromJSONString: result.json)
        XCTAssertEqual(parsed?["options"]?["recursive"]?.boolValue, true)
    }

    func testTrailingCommaAndColonAreRepaired() {
        XCTAssertEqual(JSONValue.decode(fromJSONString: ToolArgumentsSanitizer.sanitize("{\"a\":1,}").json)?["a"]?.intValue, 1)
        let colon = ToolArgumentsSanitizer.sanitize("{\"a\":1,\"b\":")
        XCTAssertEqual(JSONValue.decode(fromJSONString: colon.json)?["a"]?.intValue, 1)
    }

    /// เคสที่เคยพังจริง (เจอจากการรันในแซนด์บล็อก): stream ถูกตัดกลางคีย์ `{"a":1,"b":`
    /// ต้องตัดสมาชิกที่ค้างออกแล้วคืน JSON ที่ parse ได้ (ไม่ทิ้งค่าที่อ่านมาแล้ว)
    func testTruncatedAtKeyInsideObjectIsRepaired() {
        let truncated = ToolArgumentsSanitizer.sanitize(#"{"path":"/var/mobile/a.txt","content":"#)
        let parsed = JSONValue.decode(fromJSONString: truncated.json)
        XCTAssertEqual(parsed?["path"]?.stringValue, "/var/mobile/a.txt")

        let midKey = ToolArgumentsSanitizer.sanitize(#"{"a":1,"b"#)
        XCTAssertEqual(JSONValue.decode(fromJSONString: midKey.json)?["a"]?.intValue, 1)

        let danglingComma = ToolArgumentsSanitizer.sanitize(#"{"a":1,"#)
        XCTAssertEqual(JSONValue.decode(fromJSONString: danglingComma.json)?["a"]?.intValue, 1)
    }

    func testEscapedQuotesInsideStringsDoNotBreakRepair() {
        let raw = "{\"command\":\"echo \\\"hi\\\" > /tmp/x\""
        let result = ToolArgumentsSanitizer.sanitize(raw)
        let parsed = JSONValue.decode(fromJSONString: result.json)
        XCTAssertEqual(parsed?["command"]?.stringValue, "echo \"hi\" > /tmp/x")
    }

    func testEmptyArgumentsBecomeEmptyObjectWithNote() {
        let result = ToolArgumentsSanitizer.sanitize("   ")
        XCTAssertEqual(result.json, "{}")
        XCTAssertNotNil(result.note)
    }

    func testNonObjectArgumentsBecomeEmptyObjectWithNote() {
        let arrayJSON = ToolArgumentsSanitizer.sanitize("[1,2,3]")
        XCTAssertEqual(arrayJSON.json, "{}")
        XCTAssertNotNil(arrayJSON.note)
    }

    func testUnparsableArgumentsDoNotThrow() {
        let result = ToolArgumentsSanitizer.sanitize("นี่ไม่ใช่ JSON เลย")
        XCTAssertEqual(result.json, "{}")
        XCTAssertNotNil(result.note)
        XCTAssertNotNil(JSONValue.decode(fromJSONString: result.json))
    }
}

// MARK: - 3) การถอดรหัส SSE

final class SSEDecoderTests: XCTestCase {

    // ใช้ raw string (#"..."#) เพื่อให้เห็น "ไบต์จริงบนสาย" ตรง ๆ ไม่ต้องหนี backslash ซ้อน
    private let textChunkA = #"data: {"id":"gen-1","object":"chat.completion.chunk","model":"test/model","choices":[{"index":0,"delta":{"role":"assistant","content":"สวัสดี"},"finish_reason":null}]}"#
    private let textChunkB = #"data: {"id":"gen-1","choices":[{"index":0,"delta":{"content":"ครับ"},"finish_reason":null}]}"#
    private let finishStop = #"data: {"id":"gen-1","choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}"#
    private let usageChunk = #"data: {"object":"chat.completion.chunk","usage":{"prompt_tokens":194,"completion_tokens":2,"total_tokens":196,"cost":0.00095,"prompt_tokens_details":{"cached_tokens":32}},"choices":[]}"#

    func testTextDeltasAccumulateInOrder() {
        let (events, _) = decode([textChunkA, textChunkB, finishStop, "data: [DONE]"])
        let texts = events.compactMap { $0.textValue }
        XCTAssertEqual(texts, ["สวัสดี", "ครับ"])
        XCTAssertEqual(events.compactMap { $0.finishedValue }.count, 1)
    }

    func testKeepAliveCommentsAndMalformedLinesAreIgnored() {
        let (events, decoder) = decode([": OPENROUTER PROCESSING", "", "data:not-json", "data: {\"broken\"", textChunkA])
        XCTAssertEqual(events.compactMap { $0.textValue }, ["สวัสดี"])
        XCTAssertTrue(decoder.sawEvent)
    }

    func testUsageChunkIsSurfacedWithCostAndCachedTokens() {
        let (events, _) = decode([usageChunk])
        let usage = events.compactMap { $0.usageValue }.first
        XCTAssertEqual(usage?.promptTokens, 194)
        XCTAssertEqual(usage?.completionTokens, 2)
        XCTAssertEqual(usage?.totalTokens, 196)
        XCTAssertEqual(usage?.cachedTokens, 32)
        XCTAssertEqual(usage?.cost ?? 0, 0.00095, accuracy: 0.0000001)
    }

    /// tool call ต้องถูกปล่อย "ก่อน" finish_reason เสมอ เพื่อให้ engine รู้ว่าได้ tool call ก่อนจบรอบ
    func testToolCallsAreFlushedBeforeFinishedEvent() {
        let lines = [
            #"data: {"choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"id":"call_1","type":"function","function":{"name":"read_file","arguments":""}}]},"finish_reason":null}]}"#,
            #"data: {"choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"{\"path\":\"/var/mobile\"}"}}]},"finish_reason":null}]}"#,
            #"data: {"choices":[{"index":0,"delta":{},"finish_reason":"tool_calls"}]}"#
        ]
        let (events, _) = decode(lines)

        let toolIndex = events.firstIndex { $0.toolCallsValue != nil }
        let finishIndex = events.firstIndex { $0.finishedValue != nil }
        XCTAssertNotNil(toolIndex)
        XCTAssertNotNil(finishIndex)
        XCTAssertLessThan(toolIndex ?? 99, finishIndex ?? -1)

        let calls = events.compactMap { $0.toolCallsValue }.first
        XCTAssertEqual(calls?.count, 1)
        XCTAssertEqual(calls?.first?.function.name, "read_file")
        XCTAssertEqual(calls?.first?.function.decodedArguments?["path"]?.stringValue, "/var/mobile")
    }

    /// stream ถูกตัดกลางทาง (ไม่มี finish_reason เลย) — finishStream() ต้องปล่อย tool call ที่ค้างให้ครบ
    func testFinishStreamFlushesPendingToolCallsWhenStreamIsCut() {
        var decoder = SSEDecoder()
        var events: [ChatStreamEvent] = []
        // arguments ถูกตัดกลางค่า: {"command":"ls -la /v  (ไม่มีปีกกาปิด)
        events.append(contentsOf: decoder.consume(line: #"data: {"choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"id":"call_9","type":"function","function":{"name":"execute_shell","arguments":"{\"command\":\"ls -la /v"}}]},"finish_reason":null}]}"#))
        events.append(contentsOf: decoder.finishStream())

        let calls = events.compactMap { $0.toolCallsValue }.first
        XCTAssertEqual(calls?.count, 1)
        XCTAssertEqual(calls?.first?.function.name, "execute_shell")
        // arguments ถูกซ่อมให้ parse ได้ แม้ stream จะขาดกลางคำ
        XCTAssertEqual(calls?.first?.function.decodedArguments?["command"]?.stringValue, "ls -la /v")
        XCTAssertEqual(events.compactMap { $0.finishedValue }.count, 1)
    }

    func testToolCallsAreNotFlushedTwice() {
        let lines = [
            #"data: {"choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"id":"call_1","type":"function","function":{"name":"read_file","arguments":"{}"}}]},"finish_reason":null}]}"#,
            #"data: {"choices":[{"index":0,"delta":{},"finish_reason":"tool_calls"}]}"#
        ]
        var decoder = SSEDecoder()
        var events: [ChatStreamEvent] = []
        for line in lines { events.append(contentsOf: decoder.consume(line: line)) }
        events.append(contentsOf: decoder.finishStream())
        XCTAssertEqual(events.compactMap { $0.toolCallsValue }.count, 1)
    }

    func testReasoningDeltaIsSeparatedFromContent() {
        let line = #"data: {"choices":[{"index":0,"delta":{"reasoning":"คิดก่อน...","content":"คำตอบ"},"finish_reason":null}]}"#
        let (events, _) = decode([line])
        XCTAssertEqual(events.compactMap { $0.reasoningValue }, ["คิดก่อน..."])
        XCTAssertEqual(events.compactMap { $0.textValue }, ["คำตอบ"])
    }

    func testServerErrorChunkBecomesNotice() {
        let line = #"data: {"error":{"code":429,"message":"Rate limit exceeded"}}"#
        let (events, _) = decode([line])
        let notice = events.compactMap { $0.noticeValue }.first
        XCTAssertNotNil(notice)
        XCTAssertTrue(notice?.contains("Rate limit exceeded") ?? false)
    }
}

// MARK: - 4) การจำแนก error และ retry policy

final class ErrorAndRetryTests: XCTestCase {

    func testUnauthorizedIsNotRetryableAndNeedsAPIKeyFix() {
        let error = OpenRouterError.unauthorized("No auth credentials found")
        XCTAssertFalse(error.isRetryable)
        XCTAssertTrue(error.requiresAPIKeyFix)
        XCTAssertTrue(error.errorDescription?.contains("401") ?? false)
    }

    func testNotFoundIsNotRetryableAndNeedsModelChange() {
        let error = OpenRouterError.notFound("No endpoints found that support tool use")
        XCTAssertFalse(error.isRetryable)
        XCTAssertTrue(error.requiresModelChange)
        XCTAssertTrue(error.errorDescription?.contains("404") ?? false)
    }

    func testRateLimitAndServerErrorsAreRetryable() {
        XCTAssertTrue(OpenRouterError.rateLimited("slow down").isRetryable)
        XCTAssertTrue(OpenRouterError.serverError(status: 502, message: "bad gateway").isRetryable)
        XCTAssertTrue(OpenRouterError.serverError(status: 503, message: "unavailable").isRetryable)
        XCTAssertTrue(OpenRouterError.network("offline").isRetryable)
    }

    func testClientErrorsAndCancellationAreNotRetryable() {
        XCTAssertFalse(OpenRouterError.apiError(status: 400, code: "bad_request", message: "x").isRetryable)
        XCTAssertFalse(OpenRouterError.apiError(status: 402, code: "insufficient_credits", message: "x").isRetryable)
        XCTAssertFalse(OpenRouterError.cancelled.isRetryable)
        XCTAssertFalse(OpenRouterError.missingAPIKey.isRetryable)
    }

    func testBackoffGrowsExponentiallyAndIsCapped() {
        let attempts = [1, 2, 3, 4, 5, 6]
        let delays = attempts.map { Double(RetryPolicy.delayNanoseconds(forAttempt: $0)) / 1_000_000_000 }
        // 1s, 2s, 4s, 8s, 8s, 8s (+ jitter ไม่เกิน 0.25s)
        XCTAssertGreaterThanOrEqual(delays[0], 1.0); XCTAssertLessThanOrEqual(delays[0], 1.25)
        XCTAssertGreaterThanOrEqual(delays[1], 2.0); XCTAssertLessThanOrEqual(delays[1], 2.25)
        XCTAssertGreaterThanOrEqual(delays[2], 4.0); XCTAssertLessThanOrEqual(delays[2], 4.25)
        for delay in delays.dropFirst(3) {
            XCTAssertGreaterThanOrEqual(delay, 8.0)
            XCTAssertLessThanOrEqual(delay, 8.25)
        }
        XCTAssertEqual(RetryPolicy.maxAttempts, 3)
    }
}

// MARK: - 5) JSON และ payload ที่ส่งขึ้น OpenRouter

final class JSONAndPayloadTests: XCTestCase {

    func testJSONValueRoundTripKeepsAllCases() {
        let json = """
        {"s":"ข้อความ","i":42,"d":3.5,"b":true,"n":null,"a":[1,"สอง"],"o":{"x":1}}
        """
        guard let value = JSONValue.decode(fromJSONString: json) else {
            return XCTFail("decode ไม่สำเร็จ")
        }
        XCTAssertEqual(value["s"]?.stringValue, "ข้อความ")
        XCTAssertEqual(value["i"]?.intValue, 42)
        XCTAssertEqual(value["d"]?.doubleValue, 3.5)
        XCTAssertEqual(value["b"]?.boolValue, true)
        XCTAssertTrue(value["n"]?.isNull ?? false)
        XCTAssertEqual(value["a"]?.arrayValue?.count, 2)
        XCTAssertEqual(value["o"]?["x"]?.intValue, 1)

        // encode แล้ว decode กลับได้ค่าเดิม
        let roundTrip = JSONValue.decode(fromJSONString: value.compactJSONString)
        XCTAssertEqual(roundTrip, value)
    }

    /// ข้อกำหนด OpenAI: assistant ที่มีแต่ tool_calls ต้องส่ง content = null
    func testAssistantWithToolCallsEncodesNullContent() throws {
        let message = ChatMessage.assistant("", toolCalls: [
            ToolCall(id: "call_1", function: FunctionCall(name: "read_file", arguments: "{\"path\":\"/tmp\"}"))
        ])
        let data = try JSONEncoder().encode(message.payload())
        let json = try XCTUnwrap(JSONValue.decode(fromJSONString: String(data: data, encoding: .utf8) ?? ""))

        XCTAssertNotNil(json["tool_calls"]?.arrayValue)
        XCTAssertTrue(json["content"]?.isNull ?? false)
        XCTAssertNil(json["name"])          // ไม่ส่งฟิลด์ที่ไม่มีค่า
        XCTAssertNil(json["tool_call_id"])
        XCTAssertEqual(json["tool_calls"]?[0]?["function"]?["name"]?.stringValue, "read_file")
    }

    func testToolResultMessageCarriesToolCallID() throws {
        let message = ChatMessage.toolResult("ผลลัพธ์", toolCallID: "call_1", name: "read_file")
        let data = try JSONEncoder().encode(message.payload())
        let json = try XCTUnwrap(JSONValue.decode(fromJSONString: String(data: data, encoding: .utf8) ?? ""))
        XCTAssertEqual(json["role"]?.stringValue, "tool")
        XCTAssertEqual(json["tool_call_id"]?.stringValue, "call_1")
        XCTAssertEqual(json["name"]?.stringValue, "read_file")
        XCTAssertEqual(json["content"]?.stringValue, "ผลลัพธ์")
    }

    func testUserAndSystemMessagesHaveStringContent() throws {
        for message in [ChatMessage.system("sys"), ChatMessage.user("ผู้ใช้")] {
            let data = try JSONEncoder().encode(message.payload())
            let json = try XCTUnwrap(JSONValue.decode(fromJSONString: String(data: data, encoding: .utf8) ?? ""))
            XCTAssertNotNil(json["content"]?.stringValue)
            XCTAssertNil(json["tool_calls"])
        }
    }

    func testTokenUsageComputesTotalWhenMissing() throws {
        let json = "{\"prompt_tokens\":10,\"completion_tokens\":5}"
        let usage = try JSONDecoder().decode(TokenUsage.self, from: Data(json.utf8))
        XCTAssertEqual(usage.totalTokens, 15)
        XCTAssertNil(usage.cost)
        XCTAssertTrue(usage.shortText.contains("รวม 15"))
    }

    func testToolDefinitionEncodesOpenAISchema() throws {
        let tool = ToolDefinition(name: "read_file",
                                  description: "อ่านไฟล์",
                                  parameters: .object([
                                    ("type", .string("object")),
                                    ("properties", .object([
                                        ("path", .object([("type", .string("string"))]))
                                    ])),
                                    ("required", .array([.string("path")]))
                                  ]))
        let data = try JSONEncoder().encode(tool)
        let json = try XCTUnwrap(JSONValue.decode(fromJSONString: String(data: data, encoding: .utf8) ?? ""))
        XCTAssertEqual(json["type"]?.stringValue, "function")
        XCTAssertEqual(json["function"]?["name"]?.stringValue, "read_file")
        XCTAssertEqual(json["function"]?["parameters"]?["required"]?[0]?.stringValue, "path")
    }
}
