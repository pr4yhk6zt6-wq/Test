//
//  AgentEngine.swift
//  iOS Agent Sandbox
//
//  หัวใจของเฟส 2: ReAct loop (คิด → เรียก tool → อ่านผล → คิดต่อ → ตอบ)
//
//  กติกาความปลอดภัยและความเสถียร:
//  - วนได้สูงสุด 20 รอบต่อหนึ่งคำสั่งของผู้ใช้ (กันการวนไม่จบและกันค่าใช้จ่ายบาน)
//  - ผู้ใช้กด "หยุด" → Task ถูกยกเลิก → คำสั่ง shell ที่ค้างอยู่ถูก kill ทันที
//  - คำสั่ง shell/เครือข่ายมีเพดานเวลา 30 วินาที (ตั้งเพิ่มได้ถึง 120)
//  - ผลลัพธ์ของ tool ถูกจำกัดที่ 10,000 ตัวอักษรก่อนส่งกลับให้โมเดล
//  - โหมดอนุมัติ (ค่าเริ่มต้นเปิด) ถามผู้ใช้ก่อนรัน execute_shell และก่อนเขียนทับไฟล์สำคัญ
//  - บทสนทนายาวเกิน 80% ของ context → ตัดผลลัพธ์ tool ที่เก่าก่อน (เก็บ system prompt + ข้อความล่าสุด)
//
//  engine เป็น "คลาสธรรมดา" ไม่ใช่ ObservableObject เพื่อให้ทดสอบได้นอก SwiftUI
//  ผู้ใช้ engine คือ ChatViewModel ซึ่งแปลง event เป็นสถานะบนหน้าจอ
//
//  Foundation-only (มี guard FoundationNetworking สำหรับ Linux) → รัน E2E ได้ทุกแพลตฟอร์ม
//

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - ค่าตั้งของ engine

struct AgentConfiguration {
    var modelID: String
    var apiKey: String
    var workspacePath: String = PathGuard.defaultWorkspace
    var allowInternet: Bool = true
    var wifiOnly: Bool = false
    var isWiFiConnected: Bool = false
    var requireApproval: Bool = true
    var maxDownloadBytes: Int64 = NetworkPolicy.maxDownloadBytes(megabytes: 200)
    var contextLengthTokens: Int = 32_768
    var temperature: Double = 0.3
    /// จำนวนรอบสูงสุดของ ReAct loop ต่อหนึ่งคำสั่ง
    var maxToolRounds: Int = AgentEngine.maximumToolRounds
    /// ให้ execute_shell ลองสลับ persona เพื่อรันเป็น root (เฟส 3 — ทำงานเมื่อติดตั้งผ่าน TrollStore)
    var preferRootShell: Bool = true
    var baseURLString: String = OpenRouterService.baseURLString
}

// MARK: - การเรียก tool หนึ่งครั้ง

struct ToolInvocation: Identifiable, Equatable {
    /// id ของ tool_call ที่โมเดลส่งมา
    let id: String
    let toolName: String
    let thaiLabel: String
    let category: ToolCategory
    /// arguments ที่ parse แล้ว (อ่านง่ายสำหรับแสดงผล)
    let argumentsText: String
    let arguments: [String: JSONValue]
    let risk: RiskAssessment
}

// MARK: - คำขออนุมัติจากผู้ใช้

struct ApprovalRequest: Identifiable, Equatable {
    /// id ของ "คำขอนี้" — สร้างใหม่ทุกครั้ง เพื่อให้หน้าต่างอนุมัติเด้งทุกครั้งที่ Agent ขอ
    /// (ไม่ผูกกับ id ของ tool_call ซึ่งโมเดลอาจส่งค่าซ้ำ)
    let id: String
    /// id ของ tool_call ที่กำลังขออนุมัติ (ใช้จับคู่ผลลัพธ์)
    let toolCallID: String
    let toolName: String
    let thaiLabel: String
    let summary: String
    /// ข้อความรายละเอียด (เช่น URL + ขนาดไฟล์)
    let detail: String?
    let argumentsText: String
    let risk: RiskAssessment

    var isDestructive: Bool {
        risk.level == .destructive
    }

    init(toolCallID: String,
         toolName: String,
         thaiLabel: String,
         summary: String,
         detail: String?,
         argumentsText: String,
         risk: RiskAssessment) {
        self.id = UUID().uuidString
        self.toolCallID = toolCallID
        self.toolName = toolName
        self.thaiLabel = thaiLabel
        self.summary = summary
        self.detail = detail
        self.argumentsText = argumentsText
        self.risk = risk
    }
}

/// คำตอบของผู้ใช้ต่อคำขออนุมัติ
enum ApprovalDecision: Equatable {
    /// อนุญาตเฉพาะการเรียกครั้งนี้ (ค่าเริ่มต้นของหน้าต่างอนุมัติ)
    case allowOnce
    /// เดิมคือ "อนุญาตตลอดเซสชัน" — ตอนนี้ถือเป็น "อนุญาตครั้งนี้" เหมือนกัน
    /// (คงไว้เพื่อความเข้ากันได้กับโค้ด/เทสต์เดิม แต่ engine จะถามใหม่ทุกครั้งเสมอ)
    case allowForSession
    /// ไม่อนุมัติ — มีผลเฉพาะครั้งนี้ ครั้งต่อไปจะถามใหม่
    case deny

    /// true = ผู้ใช้อนุญาตให้ทำงานต่อ
    var isAllowed: Bool { self != .deny }
}

// MARK: - เหตุการณ์ที่ engine ส่งออก

enum AgentStopReason: Equatable {
    /// ตอบผู้ใช้ครบถ้วนแล้ว
    case answered
    /// ผู้ใช้กดหยุด
    case cancelled
    /// ครบจำนวนรอบสูงสุดแล้วยังต้องใช้ tool ต่อ
    case roundLimitReached
    /// เกิดข้อผิดพลาดร้ายแรง (ส่งข้อความไปแล้วผ่าน event .failed)
    case failed
}

enum AgentEvent {
    /// เริ่มข้อความใหม่ของ assistant (มี id ให้ผูกกับบับเบิล)
    case assistantStarted(UUID)
    /// ข้อความที่ไหลออกมาระหว่างสตรีม
    case assistantDelta(UUID, String)
    /// จบข้อความของ assistant (nil = ไม่มีข้อความ)
    case assistantFinished(UUID, ChatMessage?)
    /// เริ่มเรียก tool
    case toolStarted(ToolInvocation)
    /// ผลของ tool (พร้อมเวลาที่ใช้)
    case toolFinished(invocation: ToolInvocation, result: ToolExecutionResult, duration: TimeInterval)
    /// ขออนุมัติจากผู้ใช้ (หยุดรอจนกว่าจะได้คำตอบ)
    case approvalRequested(ApprovalRequest)
    /// คำขออนุมัติถูกตอบแล้ว (ใช้ซ่อนหน้าต่างอนุมัติ)
    case approvalResolved(id: String, decision: ApprovalDecision, autoApproved: Bool)
    /// ข้อความสถานะสั้น ๆ เช่น "กำลังคิด (รอบ 2/20)"
    case status(String)
    /// ข้อความแจ้งเตือน (ตัด context, โมเดลไม่รองรับ tool ฯลฯ)
    case notice(String)
    /// token usage ของคำขอหนึ่งครั้ง
    case usage(TokenUsage)
    /// จบงานทั้งหมด
    case completed(AgentStopReason)

    /// ข้อความสถานะภาษาไทยสำหรับ AgentLogView/หน้าแชท (เฟส 4 จะใช้บันทึก)
    var logText: String {
        switch self {
        case .assistantStarted: return "เริ่มสร้างคำตอบ"
        case .assistantDelta: return "ข้อความจากโมเดล"
        case .assistantFinished: return "จบคำตอบของโมเดล"
        case .toolStarted(let invocation): return "เรียก tool \(invocation.toolName)"
        case .toolFinished(let invocation, let result, let duration):
            return "tool \(invocation.toolName) \(result.isError ? "ผิดพลาด" : "สำเร็จ") ใน \(String(format: "%.2f", duration)) วินาที"
        case .approvalRequested(let request): return "ขออนุมัติ \(request.toolName)"
        case .approvalResolved(let id, let decision, let auto):
            return "อนุมัติ \(id): \(decision)\(auto ? " (อนุมัติล่วงหน้าแล้ว)" : "")"
        case .status(let text): return text
        case .notice(let text): return text
        case .usage(let usage): return "usage: \(usage.shortText)"
        case .completed(let reason): return "จบงาน (\(reason))"
        }
    }
}

// MARK: - Engine

final class AgentEngine {

    /// จำนวนรอบสูงสุดของ ReAct loop ต่อหนึ่งคำสั่งของผู้ใช้
    static let maximumToolRounds = 20

    private let configuration: AgentConfiguration
    private let registry: ToolRegistry
    private let usage: UsageRecording?

    // หมายเหตุสำคัญ (แก้ตามที่ผู้ใช้รายงาน): engine ไม่จำการอนุมัติข้ามครั้งอีกแล้ว
    // ทุกครั้งที่ tool ที่ต้องอนุมัติถูกเรียก จะเด้งหน้าต่างขออนุมัติใหม่เสมอ
    /// จำนวนรอบที่ใช้ไปจริงในงานล่าสุด (ใช้ตรวจสอบในเทสต์)
    private(set) var lastUsedRounds = 0
    private(set) var lastStopReason: AgentStopReason?

    /// Task ที่กำลังวน ReAct อยู่ (เก็บไว้เพื่อสั่งหยุดได้ทันที)
    private var loopTask: Task<Void, Never>?

    init(configuration: AgentConfiguration,
         registry: ToolRegistry = ToolRegistry.makeDefault(),
         usage: UsageRecording? = nil) {
        self.configuration = configuration
        self.registry = registry
        self.usage = usage
    }

    /// หยุดงานที่กำลังทำอยู่ทันที (kill คำสั่ง shell ที่ค้างอยู่ด้วย)
    func cancel() {
        loopTask?.cancel()
        loopTask = nil
        ShellService.shared.terminateCurrentProcess()
    }

    // MARK: - รันงาน

    /// เริ่มงานหนึ่งครั้ง: ส่งข้อความผู้ใช้ แล้ววน ReAct จนได้คำตอบสุดท้าย
    ///
    /// - Parameters:
    ///   - userMessage: ข้อความล่าสุดของผู้ใช้ (อยู่ใน history แล้ว)
    ///   - history: บทสนทนาก่อนหน้า รวม system prompt (ข้อความผู้ใช้ต้องเป็นตัวสุดท้าย)
    ///   - approvalHandler: ถูกเรียกเมื่อต้องขออนุมัติ — ผู้เรียกต้องแสดง UI แล้วคืนคำตอบ
    /// - Returns: สตรีมของ event ที่ผู้เรียกต้องบริโภคจนจบ (ปิดสตรีม = ยกเลิกงาน)
    func run(userMessage: ChatMessage,
             history: [ChatMessage],
             approvalHandler: @escaping (ApprovalRequest) async -> ApprovalDecision) -> AsyncStream<AgentEvent> {
        AsyncStream { continuation in
            let task = Task { [weak self] in
                guard let self = self else {
                    continuation.finish()
                    return
                }
                await self.performReActLoop(userMessage: userMessage,
                                            history: history,
                                            approvalHandler: approvalHandler,
                                            continuation: continuation)
                self.loopTask = nil
                continuation.finish()
            }
            self.loopTask = task
            continuation.onTermination = { _ in
                // ผู้เรียกปิดสตรีม (เช่นผู้ใช้กดหยุด) → ยกเลิกงานทั้งหมด รวมถึง kill shell ที่ค้าง
                task.cancel()
                ShellService.shared.terminateCurrentProcess()
            }
        }
    }

    // MARK: - ลูปหลัก

    private func performReActLoop(userMessage: ChatMessage,
                                  history: [ChatMessage],
                                  approvalHandler: @escaping (ApprovalRequest) async -> ApprovalDecision,
                                  continuation: AsyncStream<AgentEvent>.Continuation) async {
        lastUsedRounds = 0
        lastStopReason = nil

        var conversation = history
        if conversation.last?.id != userMessage.id {
            conversation.append(userMessage)
        }

        var rounds = 0
        var stopReason: AgentStopReason = .answered

        while rounds < configuration.maxToolRounds {
            if Task.isCancelled {
                stopReason = .cancelled
                break
            }
            rounds += 1
            lastUsedRounds = rounds

            // 1) ตัด context ถ้าใกล้เต็ม
            let trimResult = ContextTrimmer.trim(conversation, contextLengthTokens: configuration.contextLengthTokens)
            if trimResult.didTrim {
                conversation = trimResult.messages
                if let notice = trimResult.noticeText {
                    continuation.yield(.notice(notice))
                }
            }

            continuation.yield(.status("กำลังคิด\(rounds > 1 ? " (รอบ \(rounds)/\(configuration.maxToolRounds))" : "")…"))

            // 2) เรียกโมเดลแบบสตรีม (โหมด tool calling)
            let assistantID = UUID()
            continuation.yield(.assistantStarted(assistantID))

            let outcome: RoundOutcome
            do {
                outcome = try await streamOneRound(conversation: conversation,
                                                   assistantID: assistantID,
                                                   continuation: continuation)
            } catch let error as OpenRouterError {
                if case .cancelled = error {
                    stopReason = .cancelled
                    break
                }
                if error.requiresModelChange {
                    continuation.yield(.notice("โมเดลนี้ใช้ tool calling ไม่ได้ — เปลี่ยนโมเดลในหน้าตั้งค่าแล้วลองใหม่ (ระบบไม่ลองซ้ำอัตโนมัติ)"))
                }
                continuation.yield(.assistantFinished(assistantID, nil))
                continuation.yield(.notice("เกิดข้อผิดพลาด: \(error.localizedDescription)"))
                stopReason = .failed
                break
            } catch is CancellationError {
                stopReason = .cancelled
                break
            } catch {
                continuation.yield(.assistantFinished(assistantID, nil))
                continuation.yield(.notice("เกิดข้อผิดพลาด: \(error.localizedDescription)"))
                stopReason = .failed
                break
            }

            if Task.isCancelled {
                stopReason = .cancelled
                break
            }

            // 3) ไม่มี tool call → จบงาน (นี่คือคำตอบสุดท้าย)
            guard !outcome.toolCalls.isEmpty else {
                let message = outcome.text.isEmpty ? nil : ChatMessage(id: assistantID,
                                                                       role: .assistant,
                                                                       text: outcome.text)
                continuation.yield(.assistantFinished(assistantID, message))
                stopReason = .answered
                break
            }

            // 4) มี tool call → เก็บข้อความ assistant (ที่มี tool_calls) ลงบทสนทนาแล้วรัน tools
            let assistantMessage = ChatMessage(id: assistantID,
                                               role: .assistant,
                                               text: outcome.text,
                                               toolCalls: outcome.toolCalls)
            conversation.append(assistantMessage)
            continuation.yield(.assistantFinished(assistantID, assistantMessage))

            let results = await executeToolCalls(outcome.toolCalls,
                                                 continuation: continuation,
                                                 approvalHandler: approvalHandler)

            for (call, toolMessage) in results {
                conversation.append(toolMessage)
                if Task.isCancelled {
                    continuation.yield(.notice("งานถูกยกเลิก — หยุดหลัง tool \(call.function.name)"))
                    break
                }
            }

            if Task.isCancelled {
                stopReason = .cancelled
                break
            }

            // ถ้าถึงรอบสุดท้ายแล้วยังต้องใช้ tool ต่อ → แจ้งและจบอย่างสุภาพ
            if rounds >= configuration.maxToolRounds {
                stopReason = .roundLimitReached
                continuation.yield(.notice("ครบ \(configuration.maxToolRounds) รอบแล้ว (เพดานความปลอดภัยต่อหนึ่งคำสั่ง) — " +
                                           "ถ้าต้องทำต่อ ให้พิมพ์บอก Agent ว่าจะให้ทำอะไรต่อในขั้นถัดไป"))
                break
            }
        }

        if rounds >= configuration.maxToolRounds, stopReason == .answered {
            stopReason = .roundLimitReached
        }

        lastStopReason = stopReason
        continuation.yield(.completed(stopReason))
    }

    // MARK: - หนึ่งรอบของการคุยกับโมเดล

    private struct RoundOutcome {
        var text: String = ""
        var toolCalls: [ToolCall] = []
    }

    private func streamOneRound(conversation: [ChatMessage],
                                assistantID: UUID,
                                continuation: AsyncStream<AgentEvent>.Continuation) async throws -> RoundOutcome {
        var outcome = RoundOutcome()

        let payloads = conversation
            .filter { !($0.role == .assistant && $0.isTextEmpty && !$0.hasToolCalls) }
            .map { $0.payload() }

        let stream = OpenRouterService.streamChat(modelID: configuration.modelID,
                                                 messages: payloads,
                                                 tools: registry.definitions,
                                                 temperature: configuration.temperature,
                                                 maxTokens: nil,
                                                 apiKey: configuration.apiKey,
                                                 baseURLString: configuration.baseURLString)

        for try await event in stream {
            if Task.isCancelled { break }
            switch event {
            case .textDelta(let delta):
                outcome.text += delta
                continuation.yield(.assistantDelta(assistantID, delta))
            case .reasoningDelta:
                continuation.yield(.status("กำลังคิด…"))
            case .toolCallsCompleted(let calls):
                outcome.toolCalls = calls
            case .usage(let value):
                usage?.add(value)
                continuation.yield(.usage(value))
            case .finished:
                break
            case .notice(let text):
                continuation.yield(.notice(text))
            }
        }

        return outcome
    }

    // MARK: - รัน tool calls

    private func executeToolCalls(_ calls: [ToolCall],
                                  continuation: AsyncStream<AgentEvent>.Continuation,
                                  approvalHandler: @escaping (ApprovalRequest) async -> ApprovalDecision) async -> [(ToolCall, ChatMessage)] {
        var output: [(ToolCall, ChatMessage)] = []

        for call in calls {
            if Task.isCancelled {
                let cancelled = ToolExecutionResult.failure(.cancelled, "ผู้ใช้ยกเลิกก่อนที่ tool นี้จะเริ่มทำงาน")
                let invocation = ToolInvocation(id: call.id,
                                                toolName: call.function.name,
                                                thaiLabel: registry.tool(named: call.function.name)?.descriptor.thaiLabel ?? "tool",
                                                category: registry.tool(named: call.function.name)?.descriptor.category ?? .fileSystem,
                                                argumentsText: call.function.arguments,
                                                arguments: [:],
                                                risk: .safe)
                continuation.yield(.toolStarted(invocation))
                continuation.yield(.toolFinished(invocation: invocation, result: cancelled, duration: 0))
                output.append((call, makeToolMessage(call: call, result: cancelled, invocation: invocation, duration: 0)))
                continue
            }

            // 1) หา tool — ถ้าไม่รู้จัก ให้แจ้งทั้งผู้ใช้ (การ์ด) และโมเดล (ข้อความผลลัพธ์)
            guard let tool = registry.tool(named: call.function.name) else {
                let available = registry.toolNames.joined(separator: ", ")
                let unknown = ToolInvocation(id: call.id,
                                             toolName: call.function.name,
                                             thaiLabel: "ไม่รู้จัก tool นี้",
                                             category: .fileSystem,
                                             argumentsText: call.function.arguments,
                                             arguments: [:],
                                             risk: .safe)
                let result = ToolExecutionResult.failure(.invalidArguments,
                                                        "ไม่มี tool ชื่อ \"\(call.function.name)\" ในระบบ — ที่ใช้ได้คือ: \(available)")
                continuation.yield(.toolStarted(unknown))
                continuation.yield(.toolFinished(invocation: unknown, result: result, duration: 0))
                output.append((call, makeToolMessage(call: call, result: result, invocation: unknown, duration: 0)))
                continue
            }

            // 2) อ่าน arguments
            let arguments: [String: JSONValue]
            do {
                arguments = try ToolArguments.parse(call).raw
            } catch {
                let broken = ToolInvocation(id: call.id,
                                            toolName: tool.descriptor.name,
                                            thaiLabel: tool.descriptor.thaiLabel,
                                            category: tool.descriptor.category,
                                            argumentsText: call.function.arguments,
                                            arguments: [:],
                                            risk: .safe)
                let result = ToolExecutionResult.failure(.invalidArguments,
                                                        "อ่าน arguments ของ \(call.function.name) ไม่สำเร็จ: \(error.localizedDescription)\n" +
                                                        "arguments ที่ส่งมา: \(call.function.arguments.prefix(400))")
                continuation.yield(.toolStarted(broken))
                continuation.yield(.toolFinished(invocation: broken, result: result, duration: 0))
                output.append((call, makeToolMessage(call: call, result: result, invocation: broken, duration: 0)))
                continue
            }

            let risk = tool.assessRisk(arguments: arguments, workspace: configuration.workspacePath)
            let invocation = ToolInvocation(id: call.id,
                                            toolName: tool.descriptor.name,
                                            thaiLabel: tool.descriptor.thaiLabel,
                                            category: tool.descriptor.category,
                                            argumentsText: ToolArguments(arguments).displayText,
                                            arguments: arguments,
                                            risk: risk)

            // 3) ขออนุมัติ "ทุกครั้ง" ที่จำเป็น (ไม่จำคำตอบข้ามครั้งอีกแล้ว)
            //    - ถ้าปิดโหมดอนุมัติในตั้งค่า → ไม่ถามเลย
            //    - ถ้าเปิด → ถามทุกครั้งที่ tool นั้นต้องอนุมัติ (แม้เพิ่งไม่อนุมัติไปเมื่อกี้)
            //      คำตอบมีผลเฉพาะ "การเรียกครั้งนี้" เท่านั้น
            var approved = true

            if configuration.requireApproval {
                let requiresPrompt = tool.descriptor.alwaysRequiresApproval || risk.needsApproval
                if requiresPrompt {
                    let detail = await tool.approvalDetail(arguments: arguments)
                    let request = ApprovalRequest(toolCallID: call.id,
                                                  toolName: tool.descriptor.name,
                                                  thaiLabel: tool.descriptor.thaiLabel,
                                                  summary: tool.descriptor.summary,
                                                  detail: detail,
                                                  argumentsText: invocation.argumentsText,
                                                  risk: risk)
                    continuation.yield(.approvalRequested(request))

                    let decision = await approvalHandler(request)
                    continuation.yield(.approvalResolved(id: call.id,
                                                         decision: decision,
                                                         autoApproved: false))
                    approved = decision != .deny
                } else {
                    // tool ที่ไม่ต้องอนุมัติ (อ่านไฟล์/ค้นหา ฯลฯ) — เดินหน้าต่อได้เลย
                    continuation.yield(.approvalResolved(id: call.id,
                                                         decision: .allowOnce,
                                                         autoApproved: true))
                }
            }

            guard approved else {
                let summary = "ผู้ใช้กด “ไม่อนุมัติ” คำขอนี้ — อย่าทำสิ่งที่ต้องอนุมัติต่อในรอบนี้ " +
                    "ให้สรุปสั้น ๆ ว่ายังไม่ได้ทำอะไร และบอกผู้ใช้ว่าถ้าต้องการให้ทำจริง ให้สั่งอีกครั้งได้ " +
                    "(ระบบจะถามอนุมัติใหม่ทุกครั้ง — การไม่อนุมัติครั้งนี้ไม่ใช่การห้ามถาวร)"
                let refusal = ToolExecutionResult.failure(.blocked, summary)
                // ส่ง event ให้ UI แสดงการ์ดว่า "ถูกปฏิเสธ" ด้วย เพื่อให้ผู้ใช้เห็นว่าเกิดอะไรขึ้น
                continuation.yield(.toolStarted(invocation))
                continuation.yield(.toolFinished(invocation: invocation, result: refusal, duration: 0))
                output.append((call, makeToolMessage(call: call, result: refusal, invocation: invocation, duration: 0)))
                continue
            }

            // 4) รันจริง
            let approvalFlag = approved && (risk.needsApproval || tool.descriptor.alwaysRequiresApproval)
            let context = ToolExecutionContext(workspacePath: configuration.workspacePath,
                                              allowInternet: configuration.allowInternet,
                                              wifiOnly: configuration.wifiOnly,
                                              isWiFiConnected: configuration.isWiFiConnected,
                                              maxDownloadBytes: configuration.maxDownloadBytes,
                                              isApproved: approvalFlag,
                                              runShellAsRoot: configuration.preferRootShell,
                                              reportProgress: { text in
                                                  continuation.yield(.status(text))
                                              })

            continuation.yield(.toolStarted(invocation))
            let started = Date()

            let result: ToolExecutionResult
            if Task.isCancelled {
                result = .failure(.cancelled, "ผู้ใช้ยกเลิกก่อนที่ tool จะเริ่มทำงาน")
            } else {
                result = await tool.execute(arguments: arguments, context: context)
            }

            let duration = Date().timeIntervalSince(started)
            continuation.yield(.toolFinished(invocation: invocation, result: result, duration: duration))
            output.append((call, makeToolMessage(call: call,
                                                 result: result,
                                                 invocation: invocation,
                                                 duration: duration)))
        }

        return output
    }

    /// สร้างข้อความ role = "tool" สำหรับส่งกลับให้โมเดลในรอบถัดไป
    /// (แนบข้อมูลสำหรับแสดงบนการ์ดด้วย: arguments, ชื่อไทย, เวลาที่ใช้, สถานะผิดพลาด)
    private func makeToolMessage(call: ToolCall,
                                 result: ToolExecutionResult,
                                 invocation: ToolInvocation? = nil,
                                 duration: TimeInterval? = nil) -> ChatMessage {
        ChatMessage.toolResult(result.text,
                               toolCallID: call.id,
                               name: call.function.name,
                               argumentsText: invocation?.argumentsText,
                               thaiLabel: invocation?.thaiLabel,
                               duration: duration,
                               isError: result.isError)
    }
}
