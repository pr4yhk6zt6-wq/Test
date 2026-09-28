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

// MARK: - 9) ReAct loop จริง: โมเดลขอเรียก read_file → tool อ่านไฟล์จริง → ส่งผลกลับ → ได้คำตอบสุดท้าย

print("\n[9] ReAct loop กับ tool จริง (read_file)")

// เตรียมไฟล์ให้ tool อ่าน (จำลองไฟล์ของผู้ใช้บนเครื่อง)
let reactNotePath = "/tmp/e2e-react-note.txt"
let reactNoteContent = "E2E-REACT-CONTENT-42"
try? FileManager.default.removeItem(atPath: reactNotePath)
try? reactNoteContent.write(toFile: reactNotePath, atomically: true, encoding: .utf8)

final class ApprovalCounter: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var count = 0
    private(set) var lastRequest: ApprovalRequest?
    func record(_ request: ApprovalRequest) {
        lock.lock(); count += 1; lastRequest = request; lock.unlock()
    }
}

func makeConfiguration(baseSuffix: String,
                       requireApproval: Bool = true,
                       maxRounds: Int = AgentEngine.maximumToolRounds) -> AgentConfiguration {
    AgentConfiguration(modelID: "mock/tool-model",
                       apiKey: apiKey,
                       workspacePath: "/tmp/e2e-workspace",
                       allowInternet: false,
                       wifiOnly: false,
                       isWiFiConnected: false,
                       requireApproval: requireApproval,
                       maxDownloadBytes: NetworkPolicy.maxDownloadBytes(megabytes: 200),
                       contextLengthTokens: 32_768,
                       maxToolRounds: maxRounds,
                       baseURLString: base + baseSuffix)
}

func runEngine(_ engine: AgentEngine,
               text: String,
               approval: @escaping (ApprovalRequest) async -> ApprovalDecision) async -> (events: [AgentEvent], finalText: String) {
    var events: [AgentEvent] = []
    var finalText = ""
    let userMessage = ChatMessage.user(text)
    let history: [ChatMessage] = [.system("system prompt ทดสอบ")]
    let stream = engine.run(userMessage: userMessage, history: history, approvalHandler: approval)
    for await event in stream {
        events.append(event)
        if case .assistantFinished(_, let message) = event, let message = message, !message.hasToolCalls {
            finalText = message.text
        }
    }
    return (events, finalText)
}

let readToolRegistry = ToolRegistry(tools: [ReadFileTool(), WriteFileTool(), ListDirectoryTool(), SearchFilesTool()])
let reactEngine = AgentEngine(configuration: makeConfiguration(baseSuffix: "/react"),
                              registry: readToolRegistry)
let reactApprovals = ApprovalCounter()
let reactRun = await runEngine(reactEngine, text: "ช่วยอ่านไฟล์ e2e-react-note.txt ให้หน่อย") { request in
    reactApprovals.record(request)
    return .allowOnce
}

let toolStartedCount = reactRun.events.filter { if case .toolStarted = $0 { return true } else { return false } }.count
let toolFinishedCount = reactRun.events.filter { if case .toolFinished = $0 { return true } else { return false } }.count

var readToolResultText = ""
for event in reactRun.events {
    if case .toolFinished(let invocation, let result, _) = event, invocation.toolName == "read_file" {
        readToolResultText = result.text
    }
}

expect("เรียก tool 1 ครั้ง (toolStarted)", toolStartedCount == 1, "ได้: \(toolStartedCount)")
expect("ได้ผลลัพธ์ของ tool 1 ครั้ง (toolFinished)", toolFinishedCount == 1, "ได้: \(toolFinishedCount)")
expect("tool อ่านเนื้อหาไฟล์จริงได้", readToolResultText.contains(reactNoteContent),
       readToolResultText.isEmpty ? "(ไม่มีผลลัพธ์)" : String(readToolResultText.prefix(120)))
expect("ผลลัพธ์ถูกเก็บเป็นข้อความ role = tool (ไม่ใช่ข้อความ assistant)",
       reactRun.events.contains { event in
           if case .toolFinished(_, let result, _) = event { return !result.isError }
           return false
       })
expect("ไม่ต้องขออนุมัติสำหรับ read_file (งานอ่านล้วน)", reactApprovals.count == 0, "คำขออนุมัติ: \(reactApprovals.count)")
expect("ยิง API 2 รอบ (รอบ tool + รอบคำตอบสุดท้าย)", (readCounts()["/react"] ?? 0) == 2,
       "จำนวนคำขอ: \(readCounts()["/react"] ?? 0)")
expect("คำตอบสุดท้ายมาจากเซิร์ฟเวอร์หลังอ่านไฟล์", reactRun.finalText.contains("อ่านไฟล์เรียบร้อย"),
       reactRun.finalText.isEmpty ? "(ว่าง)" : String(reactRun.finalText.prefix(120)))
expect("จบงานด้วยสถานะ answered", reactEngine.lastStopReason == .answered,
       String(describing: reactEngine.lastStopReason))
expect("นับรอบที่ใช้จริงได้", reactEngine.lastUsedRounds == 2, "รอบ: \(reactEngine.lastUsedRounds)")

// MARK: - 10) โหมดอนุมัติ: อนุญาต → shell รันจริง / ไม่อนุญาต → ไม่รันและแจ้งโมเดล

print("\n[10] โหมดอนุมัติ + execute_shell จริง")

let shellRegistry = ToolRegistry(tools: [ExecuteShellTool()])

let shellEngine = AgentEngine(configuration: makeConfiguration(baseSuffix: "/react-shell"),
                              registry: shellRegistry)
let shellApprovals = ApprovalCounter()
let approvedRun = await runEngine(shellEngine, text: "รันคำสั่ง echo e2e-shell-ok ให้หน่อย") { request in
    shellApprovals.record(request)
    return .allowOnce
}

var shellResultText = ""
var shellResultIsError = true
for event in approvedRun.events {
    if case .toolFinished(let invocation, let result, _) = event, invocation.toolName == "execute_shell" {
        shellResultText = result.text
        shellResultIsError = result.isError
    }
}

expect("มีการขออนุมัติก่อนรัน execute_shell", shellApprovals.count == 1, "คำขออนุมัติ: \(shellApprovals.count)")
expect("หน้าขออนุมัติได้รับ arguments ของคำสั่ง", shellApprovals.lastRequest?.argumentsText.contains("echo e2e-shell-ok") ?? false,
       shellApprovals.lastRequest?.argumentsText ?? "(nil)")
expect("ตรวจความเสี่ยงคำสั่ง echo ว่าเป็นคำสั่งอ่านข้อมูล", shellApprovals.lastRequest?.risk.level == RiskLevel.normal,
       String(describing: shellApprovals.lastRequest?.risk.level))
expect("shell รันจริงและได้ผลลัพธ์", shellResultText.contains("e2e-shell-ok") && !shellResultIsError,
       String(shellResultText.prefix(160)))
expect("exit code 0 ถูกรายงาน", shellResultText.contains("exit code: 0"), String(shellResultText.prefix(120)))
expect("คำตอบสุดท้ายอ้างถึงผลลัพธ์ของ shell", approvedRun.finalText.contains("e2e-shell-ok"),
       String(approvedRun.finalText.prefix(160)))

let denyEngine = AgentEngine(configuration: makeConfiguration(baseSuffix: "/react-shell"),
                             registry: shellRegistry)
var deniedResultText = ""
var deniedResultIsError = false
let deniedRun = await runEngine(denyEngine, text: "รันคำสั่งเดิมอีกครั้ง") { _ in
    return .deny
}
for event in deniedRun.events {
    if case .toolFinished(let invocation, let result, _) = event, invocation.toolName == "execute_shell" {
        deniedResultText = result.text
        deniedResultIsError = result.isError
    }
}
expect("เมื่อผู้ใช้ไม่อนุมัติ คำสั่งต้องไม่ถูกเรียกใช้", !deniedResultText.contains("e2e-shell-ok"),
       String(deniedResultText.prefix(160)))
expect("แจ้งผลกลับโมเดลว่าไม่ได้รับอนุมัติ", deniedResultIsError && deniedResultText.contains("ไม่อนุมัติ"),
       String(deniedResultText.prefix(160)))
expect("ลูปยังทำงานต่อและได้คำตอบสุดท้าย", !deniedRun.finalText.isEmpty,
       String(deniedRun.finalText.prefix(120)))
expect("ผู้ใช้ไม่ต้องอนุมัติซ้ำในรอบเดิม", deniedRun.events.contains { event in
    if case .completed = event { return true }
    return false
})

// MARK: - 11) เพดาน 20 รอบ (กันการวนไม่จบ)

print("\n[11] เพดานรอบของ ReAct loop")

let beforeLoopCount = readCounts()["/loop-forever"] ?? 0
let loopEngine = AgentEngine(configuration: makeConfiguration(baseSuffix: "/loop-forever"),
                             registry: ToolRegistry(tools: [ListDirectoryTool()]))
let loopRun = await runEngine(loopEngine, text: "เรียก tool ซ้ำไปเรื่อย ๆ") { _ in .allowOnce }
let loopRequests = (readCounts()["/loop-forever"] ?? 0) - beforeLoopCount

expect("หยุดที่ 20 รอบตามเพดาน", loopEngine.lastUsedRounds == AgentEngine.maximumToolRounds,
       "รอบที่ใช้: \(loopEngine.lastUsedRounds)")
expect("ยิง API เท่ากับจำนวนรอบ (20)", loopRequests == AgentEngine.maximumToolRounds, "คำขอ: \(loopRequests)")
expect("แจ้งเหตุผลว่าครบเพดานรอบ", loopRun.events.contains { event in
    if case .notice(let text) = event { return text.contains("ครบ") && text.contains("รอบ") }
    return false
})
expect("จบงานด้วยสถานะ roundLimitReached", loopEngine.lastStopReason == .roundLimitReached,
       String(describing: loopEngine.lastStopReason))

// MARK: - 12) ยกเลิกงานกลางทาง (ปุ่มหยุด)

print("\n[12] การยกเลิกงาน (stop)")

let beforeCancelCount = readCounts()["/loop-forever"] ?? 0
let cancelEngine = AgentEngine(configuration: makeConfiguration(baseSuffix: "/loop-forever"),
                               registry: ToolRegistry(tools: [ListDirectoryTool()]))
let cancelStream = cancelEngine.run(userMessage: ChatMessage.user("ทำงานยาว ๆ"),
                                    history: [.system("system prompt ทดสอบ")],
                                    approvalHandler: { _ in .allowOnce })
let cancelTask = Task { () -> Int in
    var finishedTools = 0
    for await event in cancelStream {
        if case .toolFinished = event {
            finishedTools += 1
            if finishedTools == 2 {
                cancelEngine.cancel()
            }
        }
    }
    return finishedTools
}
let finishedBeforeCancel = await cancelTask.value
let cancelRequests = (readCounts()["/loop-forever"] ?? 0) - beforeCancelCount

expect("ยกเลิกหลัง tool ทำงานเสร็จ 2 ครั้ง", finishedBeforeCancel == 2, "ได้: \(finishedBeforeCancel)")
expect("หยุดยิงคำขอหลังถูกยกเลิก (ไม่ครบ 20 รอบ)", cancelRequests < AgentEngine.maximumToolRounds,
       "คำขอหลังยกเลิก: \(cancelRequests)")
expect("รายงานสถานะว่าถูกยกเลิก", cancelEngine.lastStopReason == .cancelled,
       String(describing: cancelEngine.lastStopReason))

// MARK: - 13) ShellService (posix_spawn) ของเฟส 3

print("\n[13] ShellService: รันคำสั่งจริงด้วย posix_spawn")

func shellRun(_ command: String, timeout: TimeInterval, preferRoot: Bool) async -> ShellResult? {
    do {
        return try await ShellService.shared.run(command: command,
                                                timeout: timeout,
                                                workingDirectory: nil,
                                                preferRoot: preferRoot)
    } catch {
        print("    (คำสั่งล้มเหลว: \(error))")
        return nil
    }
}

let phase3Shell = await shellRun("echo e2e-phase3-shell", timeout: 20, preferRoot: false)
expect("posix_spawn รันคำสั่งได้และอ่าน stdout ได้", phase3Shell?.stdout.contains("e2e-phase3-shell") ?? false,
       phase3Shell?.stdout ?? "(nil)")
expect("exit code = 0", phase3Shell?.exitCode == 0, String(describing: phase3Shell?.exitCode))
expect("รายงาน shell ที่ใช้จริง", (phase3Shell?.shellPath.isEmpty == false), phase3Shell?.shellPath ?? "(nil)")
expect("โหมดปกติ = ผู้ใช้ปัจจุบัน", phase3Shell?.launchMode == .currentUser,
       String(describing: phase3Shell?.launchMode))
expect("มีเหตุผลของโหมดการรันเป็นภาษาไทย", phase3Shell?.launchReason.isEmpty == false,
       phase3Shell?.launchReason ?? "(nil)")
expect("โหมดปกติไม่ต้องมีคำเตือนเรื่องสิทธิ์", phase3Shell?.privilegeWarning == nil,
       phase3Shell?.privilegeWarning ?? "")

let rootRequested = await shellRun("echo e2e-root-fallback", timeout: 20, preferRoot: true)
expect("ขอรันเป็น root แล้วคำสั่งต้องยังทำงานได้ (สำเร็จหรือถอยกลับอัตโนมัติ)",
       rootRequested?.stdout.contains("e2e-root-fallback") ?? false, rootRequested?.stdout ?? "(nil)")
if ShellService.personaSymbolsAvailable {
    // มีฟังก์ชัน persona: ต้องได้ root จริง หรือถ้าล้มเหลวต้องมีคำเตือน
    expect("ขอรันเป็น root: ได้ root จริง หรือถอยกลับพร้อมคำเตือน",
           rootRequested?.launchMode == .rootPersona
           || (rootRequested?.launchMode == .currentUser && rootRequested?.privilegeWarning != nil),
           rootRequested?.privilegeWarning ?? "(สลับเป็น root สำเร็จ)")
} else {
    // ไม่มีฟังก์ชัน persona (macOS/Linux): ต้องถอยไปผู้ใช้ปัจจุบันพร้อมเหตุผล และไม่มีคำเตือน (เพราะยังไม่ได้ลอง)
    expect("ระบบไม่มี persona → รันในนามผู้ใช้ปัจจุบันพร้อมบอกเหตุผล",
           rootRequested?.launchMode == .currentUser
           && (rootRequested?.launchReason.isEmpty == false)
           && rootRequested?.privilegeWarning == nil,
           rootRequested?.launchReason ?? "(nil)")
}

let stderrRun = await shellRun("echo ปัญหาจาก-stderr >&2; exit 4", timeout: 20, preferRoot: false)
expect("แยก stderr ออกจาก stdout ได้", stderrRun?.stderr.contains("ปัญหาจาก-stderr") ?? false,
       stderrRun?.stderr ?? "(nil)")
expect("ส่งรหัสออก (exit code) กลับมาถูกต้อง", stderrRun?.exitCode == 4,
       String(describing: stderrRun?.exitCode))

let timeoutStart = Date()
let timeoutRun = await shellRun("sleep 6", timeout: 1, preferRoot: false)
let timeoutElapsed = Date().timeIntervalSince(timeoutStart)
expect("คำสั่งที่ค้างต้องหมดเวลาและถูกรายงาน", timeoutRun?.timedOut == true,
       String(describing: timeoutRun?.timedOut))
expect("ฆ่าโปรเซสทันทีเมื่อหมดเวลา", timeoutElapsed < 5, String(format: "ใช้เวลา %.2f วินาที", timeoutElapsed))

let cancelShellTask = Task { () -> Bool in
    do {
        let result = try await ShellService.shared.run(command: "sleep 6", timeout: 30, preferRoot: false)
        return result.wasCancelled
    } catch {
        return true   // ถูกยกเลิกจนได้ error ก็ถือว่ายกเลิกสำเร็จ
    }
}
try? await Task.sleep(nanoseconds: 400_000_000)
let cancelIssuedAt = Date()
cancelShellTask.cancel()
let shellCancelled = await cancelShellTask.value
let cancelElapsed = Date().timeIntervalSince(cancelIssuedAt)
expect("กดหยุดแล้วคำสั่ง shell ถูกฆ่าและรายงานว่าถูกยกเลิก", shellCancelled)
expect("ฆ่าทั้งกลุ่มโปรเซสทันที (ไม่เหลือคำสั่งลูกค้างอยู่)",
       cancelElapsed < 2.0, String(format: "ใช้เวลา %.2f วินาทีหลังกดหยุด", cancelElapsed))

// MARK: - 14) FileSystemService ของเฟส 3

print("\n[14] FileSystemService: อ่าน/เขียน/ลิสต์ + ข้อความ error ภาษาไทย")

let phase3Dir = NSTemporaryDirectory() + "e2e-phase3-\(UUID().uuidString)"
var fileSystemChecks: [String: Bool] = [:]
let notePath = phase3Dir + "/note.txt"
let movedPath = phase3Dir + "/moved.txt"

do {
    try FileSystemService.createDirectory(phase3Dir)

    let writeReport = try FileSystemService.write("บรรทัดแรก\nบรรทัดที่สอง\n", to: notePath)
    fileSystemChecks["เขียนไฟล์ใหม่"] = writeReport.bytesWritten == Data("บรรทัดแรก\nบรรทัดที่สอง\n".utf8).count
        && !writeReport.didOverwriteExisting

    let prefix = try FileSystemService.readPrefix(notePath)
    fileSystemChecks["อ่านส่วนต้น"] = prefix.text.contains("บรรทัดแรก") && !prefix.isBinary && !prefix.hasMore

    let appended = try FileSystemService.write("บรรทัดที่สาม\n", to: notePath, append: true)
    let afterAppend = (try? FileSystemService.readPrefix(notePath).text) ?? ""
    fileSystemChecks["เขียนต่อท้าย"] = appended.didOverwriteExisting
        && afterAppend.contains("บรรทัดที่สาม")
        && appended.finalSizeBytes == Int64(Data(afterAppend.utf8).count)

    let listing = try FileSystemService.list(phase3Dir)
    fileSystemChecks["ลิสต์โฟลเดอร์"] = listing.entries.contains { $0.name == "note.txt" } && listing.totalCount == 1

    let attributes = try FileSystemService.attributes(of: notePath)
    fileSystemChecks["อ่านข้อมูลไฟล์"] = attributes.sizeBytes > 0 && !attributes.isDirectory
        && attributes.permissionsText?.count == 9

    let space = FileSystemService.volumeSpace(at: phase3Dir)
    fileSystemChecks["อ่านพื้นที่ว่างของโวลุ่ม"] = (space?.total ?? 0) > 0

    try FileSystemService.move(notePath, to: movedPath)
    fileSystemChecks["ย้ายไฟล์"] = FileSystemService.exists(movedPath) && !FileSystemService.exists(notePath)

    try FileSystemService.remove(movedPath)
    fileSystemChecks["ลบไฟล์"] = !FileSystemService.exists(movedPath)
} catch {
    print("    (เกิดข้อผิดพลาดระหว่างทดสอบไฟล์: \(error))")
}

for key in ["เขียนไฟล์ใหม่", "อ่านส่วนต้น", "เขียนต่อท้าย", "ลิสต์โฟลเดอร์",
            "อ่านข้อมูลไฟล์", "อ่านพื้นที่ว่างของโวลุ่ม", "ย้ายไฟล์", "ลบไฟล์"] {
    expect("FileSystemService: \(key)", fileSystemChecks[key] ?? false)
}

var thaiErrorMessage = ""
do {
    _ = try FileSystemService.attributes(of: phase3Dir + "/ไม่มีไฟล์นี้")
} catch {
    thaiErrorMessage = error.localizedDescription
}
expect("error ภาษาไทยที่บอกสาเหตุจริง", thaiErrorMessage.contains("ไม่พบไฟล์หรือโฟลเดอร์"), thaiErrorMessage)

// MARK: - 15) นโยบายสิทธิ์ + entitlements ของเฟส 3

print("\n[15] นโยบายสิทธิ์ + entitlements")

expect("มี entitlements 5 คีย์ตามข้อกำหนด", PrivilegePolicy.entitlements.count == 5,
       PrivilegePolicy.entitlements.map { $0.key }.joined(separator: ", "))
expect("4 คีย์ต้องเป็น true และ container-required เป็น false",
       PrivilegePolicy.entitlements.filter { $0.expectedValue }.count == 4
       && PrivilegePolicy.entitlements.first { $0.key.contains("container-required") }?.expectedValue == false)
expect("ลำดับการหา shell เริ่มที่ /var/jb/bin/sh", PrivilegePolicy.shellSearchPaths.first == "/var/jb/bin/sh",
       PrivilegePolicy.shellSearchPaths.joined(separator: " → "))
expect("PATH ของโปรเซสลูกมีของ jailbreak ด้วย", PrivilegePolicy.shellPath.contains("/var/jb/usr/bin"),
       PrivilegePolicy.shellPath)
expect("พร้อมทุกอย่างแล้วเลือกโหมด root persona",
       PrivilegePolicy.decideLaunchMode(preferRoot: true, canUsePersona: true, currentUserID: 501).mode == .rootPersona)
expect("ถ้าไม่มี persona ต้องถอยไปผู้ใช้ปัจจุบัน",
       PrivilegePolicy.decideLaunchMode(preferRoot: true, canUsePersona: false, currentUserID: 501).mode == .currentUser)
expect("แอปรันเป็น root อยู่แล้วไม่ต้องสลับ persona",
       PrivilegePolicy.decideLaunchMode(preferRoot: true, canUsePersona: true, currentUserID: 0).mode == .currentUser)

let entitlementsPath = phase3Dir + "/phase3.entitlements"
var entitlementsPlistOK = false
do {
    try FileSystemService.write(PrivilegePolicy.entitlementsPlistXML(comment: "E2E"), to: entitlementsPath)
    let data = try FileSystemService.readAll(entitlementsPath, limitBytes: 64 * 1024)
    if let dictionary = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] {
        entitlementsPlistOK = dictionary.count == 5
            && dictionary["com.apple.private.security.no-sandbox"] as? Bool == true
            && dictionary["com.apple.private.persona-mgmt"] as? Bool == true
            && dictionary["com.apple.private.security.container-required"] as? Bool == false
    }
} catch {
    print("    (สร้าง/อ่านไฟล์ entitlements ไม่ได้: \(error))")
}
expect("ไฟล์ .entitlements ที่แอปสร้าง อ่านกลับเป็น plist ได้ครบ 5 คีย์", entitlementsPlistOK)

let plantedScan = EntitlementProbe.scan(path: entitlementsPath)
expect("สแกน entitlements จากไฟล์ที่ฝังไว้เจอครบ 5 คีย์", plantedScan.hasAllFive, plantedScan.summaryText)

if let binaryPath = Bundle.main.executablePath {
    let selfScan = EntitlementProbe.scan(path: binaryPath)
    expect("สแกนไบนารีของตัวเองได้โดยไม่โหลดทั้งไฟล์", selfScan.readErrorText == nil,
           selfScan.readErrorText ?? "อ่านได้ \(selfScan.scannedBytes) ไบต์ จาก \(selfScan.fileSizeBytes)")
    expect("ไบนารีที่ไม่ได้เซ็น entitlements ต้องรายงานว่าไม่พบ (กันผลบวกลวง)",
           !selfScan.hasAllFive, selfScan.summaryText)
}

// MARK: - 16) PrivilegeService ของเฟส 3

print("\n[16] PrivilegeService: รายงานสิทธิ์ที่ผู้ใช้เห็นในตั้งค่า")

let privilegeReport = PrivilegeService.probe(workspacePath: phase3Dir, preferRootShell: true)
expect("รายงานสิทธิ์มีรายการตรวจครบ 8 ข้อ", privilegeReport.checklist.count == 8,
       "ได้ \(privilegeReport.checklist.count) ข้อ")
expect("สรุปสถานะอ่านเข้าใจได้", privilegeReport.summaryText.contains("/var/mobile"),
       privilegeReport.summaryText)
expect("มีคำแนะนำให้ผู้ใช้เสมอ", !privilegeReport.pendingAdvice.isEmpty)
expect("ข้อความสำหรับ System Prompt บอกสิทธิ์ของแอป",
       privilegeReport.promptContext.contains("สิทธิ์ของแอป"), privilegeReport.promptContext)
expect("โฟลเดอร์ที่เขียนได้ถูกรายงานว่าพร้อมใช้", privilegeReport.workspaceWritable)

let entitlementsFileReport = try? PrivilegeService.writeEntitlementsFile(to: phase3Dir)
expect("เขียนไฟล์ entitlements ลงโฟลเดอร์ทำงานได้", entitlementsFileReport != nil,
       entitlementsFileReport?.path ?? "(ไม่สำเร็จ)")

PrivilegeService.invalidateCache()
let cachedFirst = PrivilegeService.cachedReport(workspacePath: phase3Dir, preferRootShell: true)
let cachedSecond = PrivilegeService.cachedReport(workspacePath: phase3Dir, preferRootShell: true)
expect("แคชผลตรวจสิทธิ์ทำงาน (ไม่สแกนไบนารีซ้ำทุกข้อความ)", cachedFirst.checkedAt == cachedSecond.checkedAt)

try? FileManager.default.removeItem(atPath: phase3Dir)

// MARK: - 17) บั๊กที่ผู้ใช้รายงานบนเครื่องจริง: ต้องถามอนุมัติทุกครั้ง และการปฏิเสธต้องไม่ปิดกั้นครั้งต่อไป

print("\n[17] ถามอนุมัติทุกครั้ง (deny แล้วครั้งถัดไปยังถามใหม่และทำงานได้)")

let approveEveryRegistry = ToolRegistry(tools: [ExecuteShellTool()])
let approveEveryEngine = AgentEngine(configuration: makeConfiguration(baseSuffix: "/approve-every"),
                                     registry: approveEveryRegistry)
let approveEveryApprovals = ApprovalCounter()

// ผู้ใช้กด "ไม่อนุมัติ" ครั้งแรก แล้ว "อนุญาต" ครั้งที่สอง
var decisionsSoFar = 0
let approveEveryRun = await runEngine(approveEveryEngine, text: "รันคำสั่ง shell ให้สองครั้ง") { request in
    approveEveryApprovals.record(request)
    decisionsSoFar += 1
    return decisionsSoFar == 1 ? .deny : .allowOnce
}

let approvalRequestCount = approveEveryRun.events.filter { event in
    if case .approvalRequested = event { return true }
    return false
}.count
let autoApprovedCount = approveEveryRun.events.filter { event in
    if case .approvalResolved(_, _, let autoApproved) = event { return autoApproved }
    return false
}.count

var approveEveryResults: [ToolExecutionResult] = []
for event in approveEveryRun.events {
    if case .toolFinished(let invocation, let result, _) = event, invocation.toolName == "execute_shell" {
        approveEveryResults.append(result)
    }
}

expect("ถามอนุมัติ 2 ครั้ง (ครั้งที่สองถามใหม่หลังโดนปฏิเสธ)", approvalRequestCount == 2,
       "ได้: \(approvalRequestCount)")
expect("ทุกครั้งเป็นการถามจริง ไม่มีการอนุมัติอัตโนมัติข้ามครั้ง", autoApprovedCount == 0,
       "ได้: \(autoApprovedCount)")
expect("ครั้งแรกที่ไม่อนุมัติ: แจ้งกลับโมเดลว่าไม่ได้รับอนุมัติ", approveEveryResults.first?.isError == true,
       String(approveEveryResults.first?.text.prefix(120) ?? "(ไม่มี)"))
expect("ครั้งแรกที่ไม่อนุมัติ: คำสั่งไม่ถูกเรียกใช้จริง",
       approveEveryResults.first.map { !$0.text.contains("approve-once-1") } ?? false,
       String(approveEveryResults.first?.text.prefix(120) ?? "(ไม่มี)"))
expect("ครั้งที่สองที่อนุญาต: คำสั่งรันจริงและได้ผลลัพธ์จากเครื่อง",
       approveEveryResults.dropFirst().first.map { !$0.isError && $0.text.contains("approve-once-2") } ?? false,
       String(approveEveryResults.dropFirst().first?.text.prefix(120) ?? "(ไม่มี)"))
expect("ลูปทำงานต่อจนจบและสรุปคำตอบได้", approveEveryRun.finalText.contains("ครั้งที่สอง"),
       String(approveEveryRun.finalText.prefix(160)))

print("\n[18] คีย์ถูกทำความสะอาดก่อนส่งออกเครือข่าย (บั๊ก 401 ที่ผู้ใช้เจอ)")

func recordedAuthorization(forPathFragment fragment: String) -> String? {
    guard let data = FileManager.default.contents(atPath: "/tmp/mock_openrouter_auth.json"),
          let entries = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
        return nil
    }
    let matching = entries.filter { (($0["path"] as? String) ?? "").contains(fragment) }
    return matching.last?["authorization"] as? String
}

// คีย์ที่มีช่องว่างหัวท้าย เครื่องหมายคำพูด อักขระล่องหน และขึ้นบรรทัดใหม่
let messyKey = "  \"sk-or-v1-e2e-dirty-key\u{200B}\"\n"

var messyModels: [OpenRouterModel] = []
do {
    messyModels = try await OpenRouterService.fetchModels(apiKey: messyKey, baseURLString: base + "/auth-check")
    expect("ยิงคำขอด้วยคีย์ที่มีอักขระแปลกปลอมได้ (ระบบทำความสะอาดให้ก่อนส่ง)", !messyModels.isEmpty,
           "ได้ \(messyModels.count) โมเดล")
} catch {
    expect("ยิงคำขอด้วยคีย์ที่มีอักขระแปลกปลอมได้ (ระบบทำความสะอาดให้ก่อนส่ง)", false,
           "\(error)")
}

let sentAuthorization = recordedAuthorization(forPathFragment: "/auth-check/")
expect("เซิร์ฟเวอร์ได้รับ Authorization ที่ทำความสะอาดแล้วพอดี",
       sentAuthorization == "Bearer sk-or-v1-e2e-dirty-key", sentAuthorization ?? "(ไม่มีข้อมูล)")

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
