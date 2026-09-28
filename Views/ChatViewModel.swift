//
//  ChatViewModel.swift
//  iOS Agent Sandbox
//
//  ตัวเชื่อมระหว่าง UI กับ AgentEngine (เฟส 2)
//  - ส่งข้อความ → เปิด ReAct loop → แสดงข้อความที่ไหลมา + การ์ด tool ทีละใบ
//  - ขออนุมัติจากผู้ใช้ผ่านหน้าต่าง (ค้างงานไว้จนกว่าจะได้คำตอบ)
//  - กดหยุด → ยกเลิก Task → shell ที่ค้างถูก kill
//  - บันทึก/โหลดประวัติการสนทนาลงเครื่องเป็น JSON
//
//  คลาสนี้ทำงานบน main thread ทั้งหมด (สถานะ UI) ส่วนงานหนักอยู่ใน AgentEngine/Task
//

import Foundation

@MainActor
final class ChatViewModel: ObservableObject {

    // MARK: - สถานะที่ UI ใช้

    @Published private(set) var messages: [ChatMessage] = []
    @Published private(set) var isBusy: Bool = false
    /// ข้อความสถานะ เช่น "กำลังคิด…" / "กำลังใช้ tool: อ่านไฟล์"
    @Published private(set) var statusText: String = ""
    /// ข้อความแจ้งเตือนล่าสุด (เช่น กำลัง retry, ตัด context, tool ที่ถูกปฏิเสธ)
    @Published private(set) var lastNotice: String?
    /// ข้อความ error ล่าสุด (แสดงเป็นแถบสีแดง)
    @Published var errorMessage: String?
    /// คำขออนุมัติที่ค้างอยู่ (ไม่ nil = ต้องแสดงหน้าต่างอนุมัติ)
    @Published private(set) var pendingApproval: ApprovalRequest?
    /// จำนวนรอบ ReAct ที่ใช้ไปในงานล่าสุด (แสดงให้ผู้ใช้เห็นว่าทำงานไปกี่รอบ)
    @Published private(set) var usedRounds: Int = 0
    /// ข้อความ error จากการบันทึกประวัติ (ถ้ามี)
    @Published private(set) var historyWarning: String?

    let backgroundKeeper = BackgroundTaskKeeper()
    private let historyStore = ChatHistoryStore()
    private let registry = ToolRegistry.makeDefault()
    private var runTask: Task<Void, Never>?
    private var approvalContinuation: CheckedContinuation<ApprovalDecision, Never>?
    private var saveTask: Task<Void, Never>?

    /// ขีดจำกัดความยาวข้อความที่แสดงใน bubble เดียว (กันหน่วยความจำบนเครื่อง RAM 2GB)
    private let maxRenderedCharacters = 60_000

    init() {
        let stored = historyStore.load()
        if !stored.isEmpty {
            messages = stored
            lastNotice = "โหลดประวัติการสนทนาที่บันทึกไว้ \(stored.count) ข้อความ"
        }
        historyWarning = historyStore.lastErrorText
    }

    // MARK: - ส่งข้อความ

    func send(_ rawText: String) {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard !isBusy else {
            lastNotice = "กำลังทำงานอยู่ — กดปุ่มหยุดก่อนส่งข้อความใหม่"
            return
        }

        let settings = AppSettings.shared
        let apiKey: String
        do {
            guard let stored = try KeychainHelper.shared.string(for: .openRouterAPIKey),
                  !stored.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                errorMessage = OpenRouterError.missingAPIKey.localizedDescription
                return
            }
            apiKey = stored
        } catch {
            errorMessage = "อ่าน API Key ไม่สำเร็จ: \(error.localizedDescription)"
            return
        }

        let modelID = settings.modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !modelID.isEmpty else {
            errorMessage = OpenRouterError.invalidModelID.localizedDescription
            return
        }

        errorMessage = nil
        lastNotice = nil
        usedRounds = 0

        let userMessage = ChatMessage.user(text)
        messages.append(userMessage)
        persistSoon()

        let configuration = AgentConfiguration(modelID: modelID,
                                              apiKey: apiKey,
                                              workspacePath: settings.workspacePath,
                                              allowInternet: settings.allowInternet,
                                              wifiOnly: settings.wifiOnly,
                                              isWiFiConnected: ConnectivityMonitor.shared.isWiFi,
                                              requireApproval: settings.requireApproval,
                                              maxDownloadBytes: settings.maxDownloadBytes,
                                              contextLengthTokens: settings.contextLengthTokens,
                                              preferRootShell: settings.preferRootShell)

        // history ที่ส่งให้ engine ต้องมี system prompt อยู่ข้างหน้าเสมอ
        let history = makeConversationPayload()

        let engine = AgentEngine(configuration: configuration,
                                 registry: registry,
                                 usage: TokenUsageTracker.shared)
        currentEngine = engine

        isBusy = true
        statusText = "กำลังคิด…"
        backgroundKeeper.begin(name: "Agent กำลังทำงาน")

        runTask = Task { [weak self] in
            guard let self = self else { return }
            let stream = engine.run(userMessage: userMessage,
                                    history: history,
                                    approvalHandler: { request in
                                        await self.requestApproval(request)
                                    })
            for await event in stream {
                self.handle(event: event)
                if Task.isCancelled { break }
            }
            self.finishRun(engine: engine)
        }
    }

    /// ยกเลิกงานที่กำลังทำอยู่ (kill คำสั่ง shell ที่ค้างด้วย)
    func stop() {
        runTask?.cancel()
        runTask = nil
        currentEngine?.cancel()
        ShellService.shared.terminateCurrentProcess()
        resolveApprovalIfNeeded(.deny)
        isBusy = false
        statusText = ""
        pendingApproval = nil
        lastNotice = "ผู้ใช้ยกเลิกงาน"
        backgroundKeeper.end()
    }

    /// ลบข้อความเดี่ยวออกจากประวัติ
    func remove(message: ChatMessage) {
        messages.removeAll { $0.id == message.id }
        persistSoon()
    }

    /// ล้างประวัติการสนทนาในหน่วยความจำและบนเครื่อง
    func clearConversation() {
        stop()
        currentEngine?.resetSessionApprovals()
        messages.removeAll()
        errorMessage = nil
        lastNotice = nil
        usedRounds = 0
        do {
            try historyStore.clear()
            historyWarning = nil
        } catch {
            historyWarning = "ลบไฟล์ประวัติไม่สำเร็จ: \(error.localizedDescription)"
        }
    }

    func dismissNotice() {
        lastNotice = nil
    }

    // MARK: - การอนุมัติ

    /// เรียกจาก UI เมื่อผู้ใช้เลือกในหน้าต่างอนุมัติ
    func resolveApproval(_ decision: ApprovalDecision) {
        pendingApproval = nil
        guard let continuation = approvalContinuation else { return }
        approvalContinuation = nil
        continuation.resume(returning: decision)
    }

    private func requestApproval(_ request: ApprovalRequest) async -> ApprovalDecision {
        await withCheckedContinuation { continuation in
            approvalContinuation = continuation
            pendingApproval = request
            statusText = "รอผู้ใช้อนุมัติ: \(request.thaiLabel)"
        }
    }

    private func resolveApprovalIfNeeded(_ decision: ApprovalDecision) {
        guard let continuation = approvalContinuation else { return }
        approvalContinuation = nil
        pendingApproval = nil
        continuation.resume(returning: decision)
    }

    // MARK: - ประมวลผล event จาก engine

    private var currentEngine: AgentEngine?
    /// id ของข้อความ assistant ที่กำลังสตรีมอยู่ (ชั่วคราว ยังไม่ถูก append จนจบข้อความ)
    private var streamingAssistantID: UUID?
    private var streamingText: String = ""

    private func handle(event: AgentEvent) {
        switch event {
        case .assistantStarted(let id):
            streamingAssistantID = id
            streamingText = ""
            statusText = "กำลังคิด…"

        case .assistantDelta(_, let delta):
            streamingText += delta
            append(text: delta, to: streamingAssistantID)

        case .assistantFinished(let id, let message):
            streamingAssistantID = nil
            streamingText = ""
            if let message = message, !message.hasToolCalls {
                // คำตอบสุดท้าย: เขียนทับข้อความที่สตรีมมาเพื่อให้ตรงกับที่ engine ถืออยู่
                replaceMessage(id: id, with: message)
            } else if let message = message, message.hasToolCalls {
                replaceMessage(id: id, with: message)
            } else if !hasMessage(id: id) {
                // ไม่มีข้อความเลย (เช่น โมเดลเรียก tool ทันทีโดยไม่พูด) — ไม่ต้องแสดงบับเบิลว่าง
                removeMessage(id: id)
            }
            persistSoon()

        case .toolStarted(let invocation):
            statusText = "กำลังใช้ tool: \(invocation.thaiLabel)…"

        case .toolFinished(let invocation, let result, let duration):
            statusText = "ได้ผลลัพธ์จาก \(invocation.thaiLabel)"
            let message = ChatMessage.toolResult(result.text,
                                                 toolCallID: invocation.id,
                                                 name: invocation.toolName,
                                                 argumentsText: invocation.argumentsText,
                                                 thaiLabel: invocation.thaiLabel,
                                                 duration: duration,
                                                 isError: result.isError)
            messages.append(message)
            persistSoon()

        case .approvalRequested(let request):
            // ไม่ต้องทำอะไร — requestApproval() เป็นคนตั้งค่า pendingApproval แล้ว
            statusText = "รอผู้ใช้อนุมัติ: \(request.thaiLabel)"

        case .approvalResolved(_, let decision, let autoApproved):
            if autoApproved {
                statusText = "ทำงานต่อ (ได้รับอนุมัติแล้ว)"
            } else {
                switch decision {
                case .allowOnce:
                    statusText = "ผู้ใช้อนุมัติแล้ว — กำลังทำงานต่อ"
                case .allowForSession:
                    lastNotice = "จะไม่ถามอนุมัติ tool นี้อีกในเซสชันนี้"
                case .deny:
                    lastNotice = "ผู้ใช้ไม่อนุมัติ — Agent จะหาทางเลือกอื่น"
                }
            }

        case .status(let text):
            statusText = text

        case .notice(let text):
            lastNotice = text

        case .usage:
            // engine อัปเดต TokenUsageTracker ให้แล้ว (ส่งเข้าไปตอนสร้าง) — ที่นี่ไม่ต้องบวกซ้ำ
            break

        case .completed(let reason):
            handleCompletion(reason)
        }
    }

    private func handleCompletion(_ reason: AgentStopReason) {
        switch reason {
        case .answered:
            statusText = ""
        case .cancelled:
            lastNotice = "งานถูกยกเลิก"
        case .roundLimitReached:
            lastNotice = "หยุดเพราะครบเพดานรอบต่อคำสั่ง — พิมพ์บอก Agent ว่าจะให้ทำอะไรต่อได้เลย"
        case .failed:
            statusText = ""
        }
    }

    private func finishRun(engine: AgentEngine) {
        usedRounds = engine.lastUsedRounds
        isBusy = false
        statusText = ""
        pendingApproval = nil
        runTask = nil
        currentEngine = nil

        // แทนที่ข้อความ assistant ที่ว่างเปล่า (ไม่มีการตอบกลับ) ด้วยข้อความอธิบาย
        if let last = messages.last, last.role == .assistant, last.isTextEmpty, !last.hasToolCalls {
            messages[messages.count - 1].text = "_(ไม่ได้รับข้อความตอบกลับจากโมเดล — ลองใหม่อีกครั้งหรือเปลี่ยนโมเดล)_"
        }

        backgroundKeeper.end()
        persistSoon()
    }

    // MARK: - ตัวช่วยจัดการข้อความ

    private func append(text delta: String, to id: UUID?) {
        guard let id = id else { return }
        if let index = messages.firstIndex(where: { $0.id == id }) {
            if messages[index].text.count >= maxRenderedCharacters { return }
            messages[index].text += delta
            if messages[index].text.count > maxRenderedCharacters {
                let keep = String(messages[index].text.prefix(maxRenderedCharacters))
                messages[index].text = keep + "\n\n_(ตัดข้อความที่ยาวเกินแสดงผลชั่วคราว)_"
            }
        } else {
            // เริ่มบับเบิลใหม่ให้ assistant ที่กำลังสตรีม
            var message = ChatMessage(id: id, role: .assistant, text: delta)
            if delta.count > maxRenderedCharacters {
                message.text = String(delta.prefix(maxRenderedCharacters))
            }
            messages.append(message)
        }
    }

    private func replaceMessage(id: UUID, with message: ChatMessage) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else {
            messages.append(message)
            return
        }
        messages[index] = message
    }

    private func hasMessage(id: UUID) -> Bool {
        messages.contains { $0.id == id }
    }

    private func removeMessage(id: UUID) {
        messages.removeAll { $0.id == id }
    }

    // MARK: - ประวัติการสนทนา

    /// สร้างบทสนทนาที่จะส่งให้โมเดล (system prompt + ประวัติที่กรองข้อความว่างออก)
    private func makeConversationPayload() -> [ChatMessage] {
        // สถานะสิทธิ์จริงของเครื่องนี้ (แคชไว้ ไม่สแกนไบนารีทุกครั้งที่ส่งข้อความ)
        let appSettings = AppSettings.shared
        let privilegeContext = PrivilegeService.cachedPromptContext(workspacePath: appSettings.workspacePath,
                                                                    preferRootShell: appSettings.preferRootShell)
        var conversation: [ChatMessage] = [.system(SystemPrompt.build(tools: registry.definitions,
                                                                     privilegeContext: privilegeContext))]
        for message in messages {
            if message.role == .system { continue }
            if message.role == .assistant && message.isTextEmpty && !message.hasToolCalls { continue }
            if message.role == .tool && message.isTextEmpty { continue }
            conversation.append(message)
        }
        return conversation
    }

    /// บันทึกประวัติแบบหน่วงเวลา (รวมการเปลี่ยนแปลงหลายครั้งติดกันเป็นครั้งเดียว)
    private func persistSoon() {
        saveTask?.cancel()
        let snapshot = messages
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            guard let self = self else { return }
            do {
                try self.historyStore.save(snapshot)
            } catch {
                self.historyWarning = "บันทึกประวัติไม่สำเร็จ: \(error.localizedDescription)"
            }
        }
    }

    /// บันทึกทันที (ใช้เมื่อแอปจะถูกพักการทำงาน)
    func persistNow() {
        saveTask?.cancel()
        saveTask = nil
        do {
            try historyStore.save(messages)
            historyWarning = nil
        } catch {
            historyWarning = "บันทึกประวัติไม่สำเร็จ: \(error.localizedDescription)"
        }
    }

    var historyFilePath: String {
        historyStore.fileURL.path
    }

    var historyFileSizeText: String {
        NetworkPolicy.formatBytes(historyStore.fileSizeBytes)
    }
}
