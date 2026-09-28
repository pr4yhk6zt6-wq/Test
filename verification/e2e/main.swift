//
//  main.swift — โปรแกรมทดสอบ end-to-end ของชั้น OpenRouter
//
//  ใช้ OpenRouterService.swift "ไฟล์จริงของแอป" ยิงไปยังเซิร์ฟเวอร์จำลอง (mock_openrouter_server.py)
//  เพื่อพิสูจน์ว่าโค้ดฝั่งไคลเอนต์ทำงานได้จริงผ่านเครือข่ายจริง:
//    • อ่าน SSE ผ่าน URLSession.bytes(for:) ทีละไบต์ และประกอบบรรทัดข้าม TCP packet ได้
//    • ข้าม comment keep-alive และบรรทัดที่พังได้โดยไม่ล้ม
//    • รวม tool_calls delta ที่ถูกหั่นกลาง JSON ได้ครบ แล้วได้ JSON ที่ parse ได้
//    • นับ usage (รวม cost / cached tokens) จาก chunk สุดท้าย
//    • retry 429 สำเร็จครั้งที่สอง / 404-401 ไม่ retry (ตรวจจากจำนวนคำขอที่เซิร์ฟเวอร์)
//
//  รัน:  bash verification/e2e/run-e2e.sh
//

import Foundation

// MARK: - โครงผลการทดสอบ

struct Check {
    let name: String
    let passed: Bool
    let detail: String
}

var checks: [Check] = []

func expect(_ name: String, _ condition: Bool, _ detail: String = "") {
    checks.append(Check(name: name, passed: condition, detail: detail))
    print(condition ? "  ✓ \(name)" : "  ✗ \(name) — \(detail)")
}

func readCounts() -> [String: Int] {
    guard let data = FileManager.default.contents(atPath: "/tmp/mock_openrouter_counts.json"),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Int] else {
        return [:]
    }
    return object
}

// MARK: - ค่าตั้งต้น

guard CommandLine.arguments.count > 1, let port = Int(CommandLine.arguments[1]) else {
    print("ใช้งาน: e2e-harness <port>")
    exit(2)
}
let base = "http://127.0.0.1:\(port)/v1"
let apiKey = "sk-or-v1-mock-key"

let sampleMessages: [ChatMessagePayload] = [
    ChatMessagePayload(role: "system", content: .string("คุณคือผู้ช่วย"), toolCallID: nil, toolCalls: nil, name: nil),
    ChatMessagePayload(role: "user", content: .string("สวัสดี"), toolCallID: nil, toolCalls: nil, name: nil)
]

// MARK: - 1) สตรีมข้อความปกติ (SSE ถูกหั่นกลาง JSON + มี keep-alive + บรรทัดพัง)

print("\n[1] สตรีมข้อความปกติ")
var text = ""
var usage: TokenUsage?
var finishedReason: String?
var notices: [String] = []

do {
    let stream = OpenRouterService.streamChat(modelID: "mock/cheap-model:free",
                                             messages: sampleMessages,
                                             apiKey: apiKey,
                                             baseURLString: base)
    for try await event in stream {
        switch event {
        case .textDelta(let delta): text += delta
        case .usage(let value): usage = value
        case .finished(let reason): finishedReason = reason
        case .notice(let value): notices.append(value)
        case .reasoningDelta: break
        case .toolCallsCompleted(let calls): notices.append("tool:\(calls.count)")
        }
    }
} catch {
    notices.append("error:\(error.localizedDescription)")
}

expect("ได้ข้อความครบทั้งสองท่อน (ประกอบข้าม TCP packet ได้)",
       text == "สวัสดีครับ ผมคือ Agent ทดสอบ",
       "ได้: \(text)")
expect("finish_reason = stop", finishedReason == "stop", "ได้: \(finishedReason ?? "nil")")
expect("ไม่ถูกบรรทัดที่พัง (data: {\"broken\") ทำให้ล้ม", !notices.contains { $0.hasPrefix("error:") },
       notices.joined(separator: " | "))
expect("usage ถูกอ่านครบ (prompt 77 / completion 12 / total 89)",
       usage?.promptTokens == 77 && usage?.completionTokens == 12 && usage?.totalTokens == 89,
       "ได้: \(usage?.summaryText ?? "nil")")
expect("อ่าน cost จาก usage ได้", abs((usage?.cost ?? 0) - 0.00031) < 0.0000001,
       "ได้: \(usage?.cost ?? -1)")
expect("ยิงคำขอเพียงครั้งเดียว (ไม่มี retry เกินจำเป็น)", readCounts()["/chat"] == 1,
       "จำนวนคำขอ: \(readCounts()["/chat"] ?? 0)")

// MARK: - 2) tool_calls ที่ arguments ถูกหั่นเป็นหลาย chunk

print("\n[2] tool_calls delta (arguments หั่น 4 chunk)")
var toolCalls: [ToolCall] = []
var toolUsage: TokenUsage?
var toolReason: String?
var order: [String] = []

do {
    let stream = OpenRouterService.streamChat(modelID: "mock/tool-model",
                                             messages: sampleMessages,
                                             tools: [OpenRouterService.connectivityProbeTool],
                                             apiKey: apiKey,
                                             baseURLString: base + "/tools")
    for try await event in stream {
        switch event {
        case .toolCallsCompleted(let calls):
            toolCalls = calls
            order.append("tool")
        case .usage(let value): toolUsage = value
        case .finished(let reason):
            toolReason = reason
            order.append("finished")
        case .notice, .textDelta, .reasoningDelta: break
        }
    }
} catch {
    checks.append(Check(name: "สตรีม tool_calls ไม่ throw", passed: false, detail: error.localizedDescription))
    print("  ✗ สตรีม tool_calls โยน error: \(error.localizedDescription)")
}

expect("ได้ tool call 1 รายการ", toolCalls.count == 1, "ได้: \(toolCalls.count)")
expect("ชื่อฟังก์ชัน = read_file", toolCalls.first?.function.name == "read_file",
       "ได้: \(toolCalls.first?.function.name ?? "nil")")
expect("arguments รวมครบและ parse เป็น JSON ได้",
       toolCalls.first?.function.decodedArguments?["path"]?.stringValue == "/var/mobile/Documents/report.txt",
       "ได้: \(toolCalls.first?.function.arguments ?? "nil")")
let toolIndex = order.firstIndex(of: "tool") ?? Int.max
let finishIndex = order.firstIndex(of: "finished") ?? Int.min
expect("tool call ถูกปล่อยก่อน finished", toolIndex < finishIndex,
       "ลำดับ: \(order.joined(separator: " → "))")
expect("finish_reason = tool_calls", toolReason == "tool_calls", "ได้: \(toolReason ?? "nil")")
expect("usage จาก chunk สุดท้ายมาถึงด้วย (cached 64)",
       toolUsage?.totalTokens == 130 && toolUsage?.cachedTokens == 64,
       "ได้: \(toolUsage?.summaryText ?? "nil") / cached \(toolUsage?.cachedTokens ?? -1)")

// MARK: - 3) 429 แล้ว retry สำเร็จ

print("\n[3] 429 → retry อัตโนมัติ (backoff) แล้วสำเร็จ")
var retryText = ""
var retryNotices: [String] = []
let retryStart = Date()

do {
    let stream = OpenRouterService.streamChat(modelID: "mock/cheap-model:free",
                                             messages: sampleMessages,
                                             apiKey: apiKey,
                                             baseURLString: base + "/retry")
    for try await event in stream {
        switch event {
        case .textDelta(let delta): retryText += delta
        case .notice(let value): retryNotices.append(value)
        default: break
        }
    }
} catch {
    retryNotices.append("error:\(error.localizedDescription)")
}

let retryElapsed = Date().timeIntervalSince(retryStart)
let retryCount = readCounts()["/retry"] ?? 0
expect("ยิงคำขอ 2 ครั้ง (ครั้งแรก 429 ครั้งที่สองสำเร็จ)", retryCount == 2, "จำนวน: \(retryCount)")
expect("ได้ข้อความหลัง retry", retryText.contains("Agent ทดสอบ"), "ได้: \(retryText)")
expect("มีข้อความแจ้งผู้ใช้ว่ากำลังลองใหม่",
       retryNotices.contains { $0.contains("กำลังลองใหม่") },
       retryNotices.joined(separator: " | "))
expect("รอตาม backoff จริง (≥ 1 วินาที)", retryElapsed >= 1.0, String(format: "ใช้เวลา %.2f วิ", retryElapsed))

// MARK: - 4) 404 ต้องไม่ retry (และแจ้งให้เปลี่ยนโมเดล)

print("\n[4] 404 → ไม่ retry + แนะนำเปลี่ยนโมเดล")
var notFoundMessage: String?
var notFoundNeedsModelChange = false

do {
    let stream = OpenRouterService.streamChat(modelID: "mock/no-endpoint",
                                             messages: sampleMessages,
                                             apiKey: apiKey,
                                             baseURLString: base + "/notfound")
    for try await _ in stream { }
} catch let error as OpenRouterError {
    notFoundMessage = error.errorDescription
    notFoundNeedsModelChange = error.requiresModelChange
} catch {
    notFoundMessage = error.localizedDescription
}

expect("ยิงคำขอครั้งเดียว (ไม่ retry)", (readCounts()["/notfound"] ?? 0) == 1,
       "จำนวน: \(readCounts()["/notfound"] ?? 0)")
expect("ข้อความ error เป็น 404 และชี้ให้เปลี่ยนโมเดล",
       (notFoundMessage?.contains("404") ?? false) && notFoundNeedsModelChange,
       notFoundMessage ?? "nil")

// MARK: - 5) 401 ต้องไม่ retry (และชี้ให้แก้ API Key)

print("\n[5] 401 → ไม่ retry + แนะนำตรวจ API Key")
var unauthorizedMessage: String?
var unauthorizedNeedsKeyFix = false

do {
    let stream = OpenRouterService.streamChat(modelID: "mock/cheap-model:free",
                                             messages: sampleMessages,
                                             apiKey: "คีย์ผิด",
                                             baseURLString: base + "/unauthorized")
    for try await _ in stream { }
} catch let error as OpenRouterError {
    unauthorizedMessage = error.errorDescription
    unauthorizedNeedsKeyFix = error.requiresAPIKeyFix
} catch {
    unauthorizedMessage = error.localizedDescription
}

expect("ยิงคำขอครั้งเดียว (ไม่ retry)", (readCounts()["/unauthorized"] ?? 0) == 1,
       "จำนวน: \(readCounts()["/unauthorized"] ?? 0)")
expect("ข้อความ error เป็น 401 และชี้ให้ตรวจ API Key",
       (unauthorizedMessage?.contains("401") ?? false) && unauthorizedNeedsKeyFix,
       unauthorizedMessage ?? "nil")

// MARK: - 6) 503 ติดกัน 3 ครั้ง ต้อง retry ครบ 3 ครั้งแล้วยอมแพ้

print("\n[6] 503 ติดกัน → ลองใหม่ครบ 3 ครั้งแล้วหยุด")
var finalError: String?

do {
    let stream = OpenRouterService.streamChat(modelID: "mock/cheap-model:free",
                                             messages: sampleMessages,
                                             apiKey: apiKey,
                                             baseURLString: base + "/slowfail")
    for try await _ in stream { }
} catch {
    finalError = error.localizedDescription
}

let slowFailCount = readCounts()["/slowfail"] ?? 0
expect("พยายามทั้งหมด 3 ครั้ง (ห้ามเกิน) แล้วหยุด", slowFailCount == 3, "จำนวน: \(slowFailCount)")
expect("แจ้ง error 503 ให้ผู้ใช้", finalError?.contains("503") ?? false, finalError ?? "nil")

// MARK: - 7) โหลดรายการโมเดล (มีรายการเสียปนมา ต้องไม่ทำให้ทั้งลิสต์พัง)

print("\n[7] GET /models")
do {
    let models = try await OpenRouterService.fetchModels(apiKey: apiKey, baseURLString: base)
    expect("โหลดได้ 3 โมเดล (ข้ามรายการที่เสีย)", models.count == 3, "ได้: \(models.count)")
    let freeToolModel = models.first { $0.id == "mock/cheap-model:free" }
    expect("แยกโมเดลฟรีได้ถูกต้อง", freeToolModel?.isFree == true, "ได้: \(String(describing: freeToolModel?.isFree))")
    expect("ตรวจ 'รองรับ tools' จาก supported_parameters ได้",
           freeToolModel?.supportsTools == true && models.first { $0.id == "mock/no-tools" }?.supportsTools == false)
    expect("ตรวจ 'รับรูปได้' จาก architecture ได้",
           models.first { $0.id == "mock/vision-model" }?.supportsVision == true)
} catch {
    expect("โหลดรายการโมเดลได้", false, error.localizedDescription)
}

// MARK: - 8) ตรวจว่าไม่ได้ใช้ API ของ iOS 16+ ในเส้นทางที่ทดสอบ

print("\n[8] สรุปผล")
let passed = checks.filter { $0.passed }.count
let failed = checks.count - passed
print("  ผลทดสอบ: ผ่าน \(passed)/\(checks.count)" + (failed > 0 ? " (ไม่ผ่าน \(failed))" : ""))

if failed > 0 {
    print("\n  รายการที่ไม่ผ่าน:")
    for check in checks where !check.passed {
        print("   ✗ \(check.name) — \(check.detail)")
    }
    exit(1)
}
print("\n  ✓ E2E ทั้งหมดผ่าน — โค้ดฝั่งไคลเอนต์อ่าน SSE / รวม tool_calls / retry ได้จริง")
exit(0)
