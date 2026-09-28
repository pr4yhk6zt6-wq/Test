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

    /// ไฟล์แนบที่รอส่งพร้อมข้อความถัดไป (เฟส 5)
    @Published private(set) var pendingAttachments: [Attachment] = []
    /// ห้องสนทนาทั้งหมด (เฟส 5)
    @Published private(set) var rooms: [ChatRoom] = []
    /// ห้องที่กำลังเปิดอยู่
    @Published private(set) var currentRoomID: UUID?
    /// true = กำลังเตรียมไฟล์แนบ (ย่อรูป) ก่อนเริ่มงาน
    @Published private(set) var isPreparingAttachments: Bool = false

    /// จำนวนข้อความที่วาดบนจอจริง (เฟส 6) — ข้อความที่เหลือยังอยู่ในหน่วยความจำแต่ไม่ถูกวาด
    /// ช่วยลดภาระการวาด/หน่วยความจำบนเครื่อง RAM 2GB เมื่อคุยกันยาว ๆ
    @Published private(set) var visibleMessageCount: Int = ChatViewModel.defaultVisibleMessages

    /// ค่าเริ่มต้น/ก้าวการโหลดข้อความย้อนหลัง
    static let defaultVisibleMessages = 120
    static let visibleMessageStep = 120

    let backgroundKeeper = BackgroundTaskKeeper()
    private let historyStore = ChatHistoryStore()
    private let roomStore = ChatRoomStore()
    private let registry = ToolRegistry.makeDefault()
    private var runTask: Task<Void, Never>?
    /// คิวข้อความที่ไหลเข้ามา (เฟส 6) — รวมแล้วอัปเดต UI เป็นช่วง ๆ ลดการวาดซ้ำบนเครื่อง RAM 2GB
    private var pendingStreamDelta: String = ""
    private var streamFlushTask: Task<Void, Never>?
    private let streamFlushIntervalNanoseconds: UInt64 = 80_000_000   // 80 มิลลิวินาที
    private var approvalContinuation: CheckedContinuation<ApprovalDecision, Never>?
    private var saveTask: Task<Void, Never>?

    /// ขีดจำกัดความยาวข้อความที่แสดงใน bubble เดียว (กันหน่วยความจำบนเครื่อง RAM 2GB)
    private let maxRenderedCharacters = 60_000

    init() {
        // เฟส 5: ใช้หลายห้องสนทนา — ถ้ามีประวัติแบบเดิม (ไฟล์เดียว) ให้ย้ายเข้าห้อง "แชทเดิม" อัตโนมัติ
        var loadedRooms = roomStore.loadRooms()
        if loadedRooms.isEmpty {
            let legacy = historyStore.load()
            if let migration = try? roomStore.migrateLegacyHistoryIfNeeded(legacyMessages: legacy) {
                loadedRooms = migration.rooms
            }
        }
        if loadedRooms.isEmpty, let created = try? roomStore.createRoom(name: "แชทแรก", existingCount: 0) {
            loadedRooms = [created]
        }

        rooms = loadedRooms
        currentRoomID = loadedRooms.first?.id
        if let roomID = currentRoomID {
            messages = roomStore.loadMessages(roomID: roomID)
        }
        if !messages.isEmpty {
            lastNotice = "โหลดประวัติการสนทนาที่บันทึกไว้ \(messages.count) ข้อความ (ห้อง \(loadedRooms.first?.name ?? "แชทแรก"))"
        }
        historyWarning = historyStore.lastErrorText
    }

    // MARK: - ไฟล์แนบ (เฟส 5)

    /// เพดานจำนวนไฟล์แนบต่อข้อความ (กันข้อความใหญ่เกินและ RAM)
    private let maximumAttachmentsPerMessage = 8

    private var attachmentStore: AttachmentStore {
        AttachmentStore(rootPath: AppSettings.shared.uploadsPath)
    }

    /// เพิ่มไฟล์แนบที่คัดลอกเข้าโฟลเดอร์ทำงานแล้ว
    func addAttachments(_ newAttachments: [Attachment]) {
        var merged = pendingAttachments
        for attachment in newAttachments where !merged.contains(where: { $0.path == attachment.path }) {
            merged.append(attachment)
        }
        if merged.count > maximumAttachmentsPerMessage {
            merged = Array(merged.prefix(maximumAttachmentsPerMessage))
            lastNotice = "แนบได้สูงสุด \(maximumAttachmentsPerMessage) ไฟล์ต่อข้อความ — ส่วนเกินถูกตัดออก"
        }
        pendingAttachments = merged
        if !newAttachments.isEmpty {
            lastNotice = "แนบแล้ว \(newAttachments.count) ไฟล์ (เก็บไว้ใน \(AppSettings.shared.uploadsPath))"
        }
    }

    /// เอาไฟล์แนบออกจากรายการที่รอส่ง (ไฟล์ยังอยู่ในโฟลเดอร์ทำงาน ให้ Agent เปิดใช้ได้)
    func removeAttachment(_ attachment: Attachment) {
        pendingAttachments.removeAll { $0.id == attachment.id }
    }

    func clearAttachments() {
        pendingAttachments.removeAll()
    }

    // MARK: - ส่งข้อความ

    func send(_ rawText: String) {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        let attachments = pendingAttachments
        guard !text.isEmpty || !attachments.isEmpty else { return }
        if isBusy {
            // ดีไซน์ v2: พิมพ์ได้เสมอ — ข้อความระหว่าง Agent ทำงานจะเข้าคิวและส่งต่อเมื่อจบงานนี้
            if !attachments.isEmpty {
                lastNotice = "ไฟล์แนบส่งระหว่าง Agent ทำงานไม่ได้ — รอให้งานนี้จบก่อน แล้วแนบพร้อมข้อความได้เลย"
                return
            }
            queueMessage(text)
            return
        }
        guard let credentials = resolveCredentials() else { return }

        // ถ้ามีรูปแนบ ต้องย่อ + แปลง base64 ก่อน (ทำเบื้องหลังเพื่อไม่ให้ UI ค้าง)
        if attachments.contains(where: { $0.isImage }) {
            isBusy = true
            isPreparingAttachments = true
            statusText = "กำลังเตรียมรูปที่จะส่ง…"
            let includeImages = AppSettings.shared.currentModelSupportsImages
            Task { [weak self] in
                let dataURLs = await ChatViewModel.visionDataURLs(for: attachments, includeImages: includeImages)
                guard let self = self else { return }
                self.isBusy = false
                self.isPreparingAttachments = false
                self.statusText = ""
                self.performSend(text: text, attachments: attachments, visionDataURLs: dataURLs, credentials: credentials)
            }
            return
        }

        performSend(text: text, attachments: attachments, visionDataURLs: [], credentials: credentials)
    }

    /// เตรียมรูปสำหรับส่งเป็น image_url (ย่อในคิวเบื้องหลัง — ไม่บล็อก UI)
    private static func visionDataURLs(for attachments: [Attachment], includeImages: Bool) async -> [String] {
        guard includeImages else { return [] }
        let images = attachments.filter { $0.isImage }
        guard !images.isEmpty else { return [] }
        return await Task.detached(priority: .userInitiated) { () -> [String] in
            var urls: [String] = []
            for image in images {
                if let result = try? ImageDownscaler.downscale(fileAt: image.path) {
                    urls.append(result.dataURL)
                }
            }
            return urls
        }.value
    }

    /// สร้างข้อความผู้ใช้และเริ่มงาน (ใช้ทั้งกรณีมีและไม่มีไฟล์แนบ)
    private func performSend(text: String,
                             attachments: [Attachment],
                             visionDataURLs: [String],
                             credentials: RunCredentials) {
        // กันบับเบิลผู้ใช้ซ้ำ (บั๊กที่เห็นในภาพหน้าจอผู้ใช้): ถ้าเป็นข้อความเดิมกับข้อความผู้ใช้ล่าสุด
        // ที่ยังไม่ได้รับคำตอบ และเพิ่งเกิดข้อผิดพลาด (เช่น 400) → ใช้บับเบิลเดิม ไม่สร้างใหม่
        let isRepeatOfUnansweredMessage: Bool = {
            guard attachments.isEmpty, errorMessage != nil,
                  let last = messages.last, last.role == .user else { return false }
            return last.text.trimmingCharacters(in: .whitespacesAndNewlines) == text
        }()

        errorMessage = nil
        lastNotice = nil
        usedRounds = 0

        if attachments.contains(where: { $0.isImage }), visionDataURLs.isEmpty {
            lastNotice = AttachmentMessageBuilder.noVisionWarning(modelID: credentials.modelID,
                                                                  imageCount: attachments.filter { $0.isImage }.count)
        }

        let userMessage: ChatMessage
        if isRepeatOfUnansweredMessage, let last = messages.last {
            userMessage = last
            lastNotice = "ส่งข้อความเดิมซ้ำ — ใช้บับเบิลเดิมและให้โมเดลตอบใหม่"
        } else {
            let body = text.isEmpty ? "ช่วยดูไฟล์แนบให้หน่อย" : text
            userMessage = ChatMessage.user(body,
                                           attachments: attachments,
                                           visionImageDataURLs: visionDataURLs)
            messages.append(userMessage)
            persistSoon()
        }

        pendingAttachments.removeAll()
        startRun(userMessage: userMessage, credentials: credentials)
    }

    /// มีบับเบิลของผู้ใช้ให้ส่งซ้ำได้หรือไม่ (ใช้โชว์ปุ่ม "ลองส่งอีกครั้ง" บนแถบ error)
    var canRetryLastRun: Bool {
        !isBusy && messages.contains { $0.role == .user }
    }

    /// ลองส่งข้อความล่าสุดของผู้ใช้อีกครั้ง โดยไม่สร้างบับเบิลซ้ำ
    /// (ใช้กับกรณี 400/เน็ตสะดุด — ไม่ต้องให้ผู้ใช้พิมพ์ใหม่)
    func retryLastFailedRun() {
        guard !isBusy else {
            lastNotice = "กำลังทำงานอยู่ — กดปุ่มหยุดก่อนส่งข้อความใหม่"
            return
        }
        guard let lastUser = messages.last(where: { $0.role == .user }) else { return }
        guard let credentials = resolveCredentials() else { return }
        errorMessage = nil
        lastNotice = "ลองส่งข้อความเดิมอีกครั้ง"
        startRun(userMessage: lastUser, credentials: credentials)
    }

    /// ปิดแถบข้อผิดพลาด
    func dismissError() {
        errorMessage = nil
    }

    // MARK: - เริ่มงาน (ใช้ร่วมกันระหว่าง "ส่งใหม่" และ "ลองส่งอีกครั้ง")

    private struct RunCredentials {
        let apiKey: String
        let modelID: String
    }

    /// ตรวจ API Key + Model ID ก่อนเริ่มงาน (ตั้ง errorMessage ให้เองถ้าไม่ผ่าน)
    private func resolveCredentials() -> RunCredentials? {
        let settings = AppSettings.shared
        let apiKey: String
        do {
            guard let stored = try KeychainHelper.shared.string(for: .openRouterAPIKey),
                  !stored.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                errorMessage = OpenRouterError.missingAPIKey.localizedDescription
                return nil
            }
            apiKey = stored
        } catch {
            errorMessage = "อ่าน API Key ไม่สำเร็จ: \(error.localizedDescription)"
            return nil
        }

        let modelID = settings.modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !modelID.isEmpty else {
            errorMessage = OpenRouterError.invalidModelID.localizedDescription
            return nil
        }
        return RunCredentials(apiKey: apiKey, modelID: modelID)
    }

    private func startRun(userMessage: ChatMessage, credentials: RunCredentials) {
        let settings = AppSettings.shared
        let configuration = AgentConfiguration(modelID: credentials.modelID,
                                              apiKey: credentials.apiKey,
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

    /// ลบบับเบิล assistant ที่ไม่มีข้อความเลย (คำตอบว่าง) ออกจากหน้าจอ
    private func removeEmptyAssistantBubbles() {
        let before = messages.count
        messages.removeAll { $0.role == .assistant && $0.isTextEmpty && !$0.hasToolCalls }
        if messages.count != before {
            persistSoon()
        }
    }

    /// บับเบิลนี้กำลัง "คิด" อยู่จริงหรือไม่ (ใช้ตัดสินว่าจะแสดงสปินเนอร์ไหม)
    func isThinking(messageID: UUID) -> Bool {
        isBusy && streamingAssistantID == messageID
    }

    /// ยกเลิกงานที่กำลังทำอยู่ (kill คำสั่ง shell ที่ค้างด้วย)
    func stop() {
        flushPendingStreamDelta()
        runTask?.cancel()
        runTask = nil
        currentEngine?.cancel()
        ShellService.shared.terminateCurrentProcess()
        resolveApprovalIfNeeded(.deny)
        isBusy = false
        statusText = ""
        pendingApproval = nil
        lastNotice = "ผู้ใช้ยกเลิกงาน"
        removeEmptyAssistantBubbles()   // กันสปินเนอร์ค้างหลังกดหยุด
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
        messages.removeAll()
        pendingAttachments.removeAll()
        errorMessage = nil
        lastNotice = "ล้างข้อความในห้องนี้แล้ว (ไฟล์แนบยังอยู่ในโฟลเดอร์ทำงาน)"
        usedRounds = 0
        persistNow()
    }

    func dismissNotice() {
        lastNotice = nil
    }

    /// แสดงข้อความแจ้งเตือนสั้น ๆ (ใช้จาก View เช่นเมื่อแนบไฟล์ไม่สำเร็จ)
    func showNotice(_ text: String) {
        lastNotice = text
    }

    // MARK: - ห้องสนทนา (เฟส 5)

    /// สร้างห้องใหม่แล้วสลับไปห้องนั้นทันที
    func createRoom(named name: String) {
        do {
            let room = try roomStore.createRoom(name: name, existingCount: rooms.count)
            rooms.insert(room, at: 0)
            try roomStore.saveRooms(rooms)
            selectRoom(room)
        } catch {
            historyWarning = "สร้างห้องใหม่ไม่สำเร็จ: \(error.localizedDescription)"
        }
    }

    func renameRoom(_ room: ChatRoom, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = rooms.firstIndex(where: { $0.id == room.id }) else { return }
        rooms[index].name = trimmed
        rooms[index].updatedAt = Date()
        saveRooms()
    }

    func deleteRoom(_ room: ChatRoom) {
        roomStore.deleteRoomFiles(roomID: room.id)
        rooms.removeAll { $0.id == room.id }
        saveRooms()

        guard currentRoomID == room.id else { return }
        if let first = rooms.first {
            currentRoomID = nil
            selectRoom(first)
        } else {
            currentRoomID = nil
            messages.removeAll()
            if let created = try? roomStore.createRoom(name: "แชทแรก", existingCount: 0) {
                rooms = [created]
                saveRooms()
                selectRoom(created)
            }
        }
    }

    /// สลับไปห้องอื่น (บันทึกห้องปัจจุบันก่อน)
    func selectRoom(_ room: ChatRoom) {
        guard !isBusy else {
            lastNotice = "กำลังทำงานอยู่ — กดปุ่มหยุดก่อนเปลี่ยนห้อง"
            return
        }
        persistNow()
        currentRoomID = room.id
        messages = roomStore.loadMessages(roomID: room.id)
        resetVisibleMessages()
        errorMessage = nil
        lastNotice = messages.isEmpty ? "เปิดห้อง \(room.name) แล้ว" : "เปิดห้อง \(room.name) — \(messages.count) ข้อความ"
        refreshQueue()
    }

    private func saveRooms() {
        do {
            try roomStore.saveRooms(rooms)
        } catch {
            historyWarning = "บันทึกสารบัญห้องไม่สำเร็จ: \(error.localizedDescription)"
        }
    }

    // MARK: - ส่งออกการสนทนา (เฟส 5)

    var currentRoomName: String {
        rooms.first { $0.id == currentRoomID }?.name ?? "แชท"
    }

    /// เนื้อหา Markdown ของห้องปัจจุบัน
    func exportMarkdownText() -> String {
        ChatRoomStore.markdownExport(roomName: currentRoomName, messages: messages)
    }

    /// เขียนไฟล์ .md ลงโฟลเดอร์ชั่วคราวเพื่อแชร์ผ่าน Share Sheet
    func exportMarkdownURL() -> URL? {
        let name = ChatRoomStore.safeExportName(currentRoomName)
        return writeTemporaryFile(named: "\(name).md", content: Data(exportMarkdownText().utf8))
    }

    /// เขียนไฟล์ .json ลงโฟลเดอร์ชั่วคราวเพื่อแชร์
    func exportJSONURL() -> URL? {
        let name = ChatRoomStore.safeExportName(currentRoomName)
        do {
            let data = try ChatRoomStore.jsonExport(roomName: currentRoomName, messages: messages)
            return writeTemporaryFile(named: "\(name).json", content: data)
        } catch {
            historyWarning = "สร้างไฟล์ JSON ไม่สำเร็จ: \(error.localizedDescription)"
            return nil
        }
    }

    private func writeTemporaryFile(named name: String, content: Data) -> URL? {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("exports", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent(name)
            try content.write(to: url, options: .atomic)
            return url
        } catch {
            historyWarning = "เขียนไฟล์ส่งออกไม่สำเร็จ: \(error.localizedDescription)"
            return nil
        }
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

    /// รวมข้อความที่ไหลเข้ามาแล้วอัปเดตหน้าจอเป็นช่วงสั้น ๆ (ไม่วาดทุก chunk)
    private func enqueueStreamDelta(_ delta: String, id: UUID?) {
        pendingStreamDelta += delta
        guard streamFlushTask == nil, let targetID = id else { return }

        streamFlushTask = Task { [weak self] in
            guard let self = self else { return }
            try? await Task.sleep(nanoseconds: self.streamFlushIntervalNanoseconds)
            guard !Task.isCancelled else { return }
            let buffered = self.pendingStreamDelta
            self.pendingStreamDelta = ""
            self.streamFlushTask = nil
            if !buffered.isEmpty {
                self.append(text: buffered, to: targetID)
            }
        }
    }

    /// อัปเดตข้อความที่ค้างในคิวทันที (ใช้ตอนผู้ใช้กดหยุด เพื่อไม่ให้ข้อความที่เห็นหายไป)
    private func flushPendingStreamDelta() {
        streamFlushTask?.cancel()
        streamFlushTask = nil
        let buffered = pendingStreamDelta
        pendingStreamDelta = ""
        guard !buffered.isEmpty, let id = streamingAssistantID else { return }
        append(text: buffered, to: id)
    }

    // MARK: - ประมวลผล event จาก engine

    /// จุดเชื่อมสำหรับ UI ใหม่ (ดีไซน์ v2): รับทุกเหตุการณ์ของ engine เพื่อแสดงไทม์ไลน์
    /// เป็นการ "อ่าน" เท่านั้น — ไม่เปลี่ยนพฤติกรรมของ view model หรือ engine
    var activityObserver: ((AgentEvent) -> Void)?

#if DEBUG
    // MARK: - เครื่องมือตรวจงานออกแบบ (มีเฉพาะบิลด์ Debug — เปิดด้วย launch argument -uiPreview)
    /// ใส่ข้อมูลตัวอย่างเพื่อถ่ายภาพหน้าจอใน iOS Simulator — ไม่ทำงานในบิลด์ Release
    func previewSeed(messages newMessages: [ChatMessage],
                     isBusy busy: Bool,
                     statusText text: String,
                     approval: ApprovalRequest?) {
        // แอปจริงลบบับเบิลว่างเมื่อจบงาน — ข้อมูลตัวอย่างต้องสะท้อนแบบเดียวกัน ไม่มีช่องว่างโชว์
        messages = newMessages.filter { !($0.role == .assistant && $0.isTextEmpty && !$0.hasToolCalls) }
        resetVisibleMessages()
        isBusy = busy
        statusText = text
        pendingApproval = approval
        errorMessage = nil
        lastNotice = nil
    }
#endif

    // MARK: - คิวข้อความระหว่าง Agent ทำงาน (ดีไซน์ v2)

    /// ข้อความที่ผู้ใช้พิมพ์ระหว่าง Agent ทำงาน — รอส่งให้อัตโนมัติเมื่องานนี้จบ
    @Published private(set) var queuedMessages: [QueuedMessage] = []

    /// เหตุผลที่งานรอบล่าสุดจบ (ใช้ตัดสินว่าจะส่งคิวต่ออัตโนมัติหรือไม่)
    private var lastStopReason: AgentStopReason?

    /// เพิ่มข้อความเข้าคิว — คืน false พร้อมบอกเหตุผลเสมอเมื่อรับไม่ได้ (ไม่เงียบ)
    @discardableResult
    func queueMessage(_ rawText: String) -> Bool {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }
        guard pendingAttachments.isEmpty else {
            lastNotice = "ไฟล์แนบส่งระหว่าง Agent ทำงานไม่ได้ — รอให้งานนี้จบก่อน แล้วแนบพร้อมข้อความได้เลย"
            return false
        }
        guard PendingMessageQueue.shared.enqueue(text: text, roomID: currentRoomID) != nil else {
            lastNotice = "คิวเต็ม (สูงสุด \(PendingMessageQueue.maxItems) ข้อความ) — รอให้งานนี้จบก่อน แล้วส่งต่อได้เลย"
            return false
        }
        refreshQueue()
        lastNotice = "เก็บข้อความไว้ต่อคิวแล้ว — จะส่งให้ Agent ทันทีที่งานนี้จบ (ยกเลิกได้เหนือช่องพิมพ์)"
        return true
    }

    /// อ่านคิวของห้องปัจจุบันใหม่ (เรียกเมื่อเปิดหน้าแชทหรือเปลี่ยนห้อง)
    func refreshQueue() {
        queuedMessages = PendingMessageQueue.shared.items(for: currentRoomID)
    }

    func removeQueuedMessage(id: String) {
        PendingMessageQueue.shared.remove(id: id)
        refreshQueue()
    }

    /// ส่งข้อความที่ค้างในคิวตอนนี้เลย (ผู้ใช้กดเอง)
    func flushQueue() {
        deliverNextQueued()
    }

    /// ส่งข้อความถัดไปในคิว — ไม่ทำอะไรถ้ากำลังทำงานอยู่ ไม่มีคิว หรือตั้งค่าไม่ครบ (ข้อความไม่หาย)
    private func deliverNextQueued() {
        guard !isBusy else { return }
        guard let next = PendingMessageQueue.shared.first(for: currentRoomID) else { return }
        guard resolveCredentials() != nil else {
            lastNotice = "มีข้อความรออยู่ในคิว แต่ยังตั้งค่าโมเดลหรือคีย์ไม่ครบ — ข้อความยังอยู่ครบ ตรวจการตั้งค่าแล้วกด \"ส่งเลย\" ได้"
            return
        }
        PendingMessageQueue.shared.remove(id: next.id)
        refreshQueue()
        lastNotice = "ส่งข้อความที่ต่อคิวไว้ให้ Agent แล้ว"
        send(next.text)
    }

    /// ปิดท้ายงาน: ส่งคิวต่ออัตโนมัติเฉพาะเมื่องานจบเองตามปกติ
    /// (ถ้าผู้ใช้เป็นคนกดหยุด = ไม่ยิงอัตโนมัติ ให้ผู้ใช้กด "ส่งเลย" เอง)
    private func deliverQueuedAfterRun(_ reason: AgentStopReason?) {
        refreshQueue()
        guard let reason = reason else { return }
        guard reason == .answered || reason == .roundLimitReached else { return }
        deliverNextQueued()
    }

    private var currentEngine: AgentEngine?
    /// id ของข้อความ assistant ที่กำลังสตรีมอยู่ (ชั่วคราว ยังไม่ถูก append จนจบข้อความ)
    private var streamingAssistantID: UUID?
    private var streamingText: String = ""

    private func handle(event: AgentEvent) {
        activityObserver?(event)
        switch event {
        case .assistantStarted(let id):
            streamingAssistantID = id
            streamingText = ""
            statusText = "กำลังคิด…"

        case .assistantDelta(_, let delta):
            guard !delta.isEmpty else { break }   // delta ว่างไม่ควรสร้างบับเบิล
            streamingText += delta
            enqueueStreamDelta(delta, id: streamingAssistantID)

        case .assistantFinished(let id, let message):
            // ทิ้ง delta ที่ค้างในคิว — ข้อความจริงจาก engine จะถูกเขียนทับให้ตรงกันอยู่แล้ว
            streamFlushTask?.cancel()
            streamFlushTask = nil
            pendingStreamDelta = ""
            streamingAssistantID = nil
            streamingText = ""
            if let message = message, !message.isTextEmpty {
                // มีข้อความจริง: เขียนทับข้อความที่สตรีมมาเพื่อให้ตรงกับที่ engine ถืออยู่
                replaceMessage(id: id, with: message)
            } else {
                // ไม่มีข้อความ (โมเดลเรียก tool ทันที) — ลบบับเบิลว่างทิ้ง
                // เดิมปล่อยไว้ทำให้เห็น "สปินเนอร์หมุนค้าง" ทั้งที่งานจบแล้ว
                removeMessage(id: id)
            }
            persistSoon()

        case .toolStarted(let invocation):
            statusText = "กำลังใช้ tool: \(invocation.thaiLabel)…"

        case .toolFinished(let invocation, let result, let duration):
            statusText = "ได้ผลลัพธ์จาก \(invocation.thaiLabel)"
            AgentLogStore.shared.record(toolName: invocation.toolName,
                                        thaiLabel: invocation.thaiLabel,
                                        category: invocation.category,
                                        argumentsText: invocation.argumentsText,
                                        resultText: result.text,
                                        isError: result.isError,
                                        duration: duration,
                                        wasTruncated: result.truncated)
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
            lastNotice = "Agent กำลังรออนุมัติ \(request.thaiLabel) — ระบบถามทุกครั้งเพื่อให้เลือกได้เป็นครั้ง ๆ"

        case .approvalResolved(_, let decision, let autoApproved):
            if autoApproved {
                statusText = "ทำงานต่อ (ได้รับอนุมัติแล้ว)"
            } else {
                switch decision {
                case .allowOnce:
                    statusText = "ผู้ใช้อนุมัติแล้ว — กำลังทำงานต่อ"
                case .allowForSession:
                    lastNotice = "ผู้ใช้อนุมัติแล้ว (มีผลเฉพาะครั้งนี้ — ครั้งต่อไปจะถามใหม่)"
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
        lastStopReason = reason
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

        // เก็บกวาดบับเบิล assistant ที่ว่างเปล่าทุกใบ (ต้นเหตุของ "กล่องหมุนค้าง")
        removeEmptyAssistantBubbles()

        // ถ้าจบงานด้วยการเรียก tool แล้วยังไม่ได้สรุปคำตอบ ให้บอกผู้ใช้ตรง ๆ
        if let last = messages.last, last.isToolResult {
            messages.append(.assistant("_(Agent ใช้ tool เสร็จแล้วแต่ยังไม่ได้สรุป — พิมพ์ถามต่อได้เลย)_"))
        } else if !messages.contains(where: { $0.role == .assistant && !$0.isTextEmpty }) {
            messages.append(.assistant("_(ไม่ได้รับข้อความตอบกลับจากโมเดล — ลองใหม่อีกครั้งหรือเปลี่ยนโมเดล)_"))
        }

        backgroundKeeper.end()
        persistSoon()

        // ดีไซน์ v2: ข้อความที่ต่อคิวไว้ระหว่างงานนี้ — ส่งต่ออัตโนมัติเมื่องานจบเอง
        let reason = lastStopReason
        lastStopReason = nil
        deliverQueuedAfterRun(reason)
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
        let roomID = currentRoomID
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            guard let self = self, let roomID = roomID else { return }
            self.save(snapshot: snapshot, roomID: roomID)
        }
    }

    /// บันทึกทันที (ใช้ตอนสลับห้อง/แอปถูกพัก เพื่อไม่ให้ข้อความหาย)
    func persistNow() {
        saveTask?.cancel()
        guard let roomID = currentRoomID else { return }
        save(snapshot: messages, roomID: roomID)
    }

    private func save(snapshot: [ChatMessage], roomID: UUID) {
        do {
            try roomStore.saveMessages(snapshot, roomID: roomID)
            if let index = rooms.firstIndex(where: { $0.id == roomID }) {
                rooms[index].messageCount = snapshot.count
                rooms[index].preview = ChatRoomStore.previewText(of: snapshot)
                rooms[index].updatedAt = Date()
                try roomStore.saveRooms(rooms)
            }
        } catch {
            historyWarning = "บันทึกประวัติไม่สำเร็จ: \(error.localizedDescription)"
        }
    }

    // MARK: - การแสดงผล/บริบท (เฟส 6)

    /// ข้อความที่จะวาดบนจอ (ล่าสุด N รายการ) — ส่วนอื่นยังใช้ประมวลผลเต็มชุดตามปกติ
    var visibleMessages: [ChatMessage] {
        guard messages.count > visibleMessageCount else { return messages }
        return Array(messages.suffix(visibleMessageCount))
    }

    /// จำนวนข้อความที่ยังซ่อนอยู่ (ถ้ามากกว่า 0 ให้แสดงปุ่ม "โหลดข้อความก่อนหน้า")
    var hiddenMessageCount: Int {
        max(0, messages.count - visibleMessageCount)
    }

    /// โหลดข้อความย้อนหลังเพิ่มขึ้นทีละก้าว
    func loadEarlierMessages() {
        let before = visibleMessageCount
        visibleMessageCount = min(messages.count, visibleMessageCount + ChatViewModel.visibleMessageStep)
        let added = visibleMessageCount - before
        lastNotice = added > 0
            ? "แสดงข้อความย้อนหลังเพิ่ม \(added) รายการ (ยังซ่อนอยู่ \(hiddenMessageCount))"
            : "แสดงครบทุกข้อความแล้ว"
    }

    private func resetVisibleMessages() {
        visibleMessageCount = ChatViewModel.defaultVisibleMessages
    }

    /// ประเมินจำนวนโทเคนของบทสนทนาที่จะส่งไป (หยาบ ๆ อักษรละ ~0.35 โทเคน) — เตือนก่อนชนเพดานบริบท
    var estimatedContextTokens: Int {
        var total = 0
        for message in messages {
            total += ChatViewModel.estimateTokens(message.text)
            if let attachments = message.attachments {
                for attachment in attachments where attachment.isInlineText {
                    total += ChatViewModel.estimateTokens(attachment.inlineText ?? "")
                }
            }
        }
        return total
    }

    static func estimateTokens(_ text: String) -> Int {
        guard !text.isEmpty else { return 0 }
        return max(1, Int(Double(text.count) * 0.35) + 4)
    }

    /// เพดานบริบทที่ตั้งไว้ (โทเคน)
    var contextLimitTokens: Int {
        max(1_000, AppSettings.shared.contextLengthTokens)
    }

    /// สัดส่วนการใช้บริบท 0.0–1.0+ (ใช้เปลี่ยนสีเตือนที่ 80%)
    var contextUsageRatio: Double {
        Double(estimatedContextTokens) / Double(contextLimitTokens)
    }

    /// ข้อความสรุปการใช้บริบทแบบสั้น เช่น "12% • 3.9K/32K"
    var contextUsageText: String {
        let percent = Int((contextUsageRatio * 100).rounded())
        return "\(percent)% • \(ChatViewModel.shortTokenText(estimatedContextTokens))/\(ChatViewModel.shortTokenText(contextLimitTokens))"
    }

    static func shortTokenText(_ tokens: Int) -> String {
        if tokens >= 1_000_000 { return String(format: "%.1fM", Double(tokens) / 1_000_000) }
        if tokens >= 1_000 { return String(format: "%.1fK", Double(tokens) / 1_000) }
        return "\(tokens)"
    }

    /// ตัดประวัติเก่าออกจากบทสนทนาปัจจุบัน (ไม่เรียกโมเดล) — เหลือข้อความล่าสุดตามจำนวนที่กำหนด
    func trimHistoryKeepingLast(_ keep: Int = 60) {
        guard !isBusy else {
            lastNotice = "กำลังทำงานอยู่ — กดปุ่มหยุดก่อนตัดประวัติ"
            return
        }
        let originalCount = messages.count
        guard originalCount > keep else {
            lastNotice = "ยังมีข้อความไม่มากพอที่จะตัด (มี \(originalCount) รายการ)"
            return
        }

        let removed = originalCount - keep
        let divider = ChatMessage.system("(ตัดประวัติเก่า \(removed) ข้อความเพื่อประหยัดบริบท — เหลือข้อความล่าสุด \(keep) รายการ)")
        messages = [divider] + Array(messages.suffix(keep))
        resetVisibleMessages()
        persistNow()
        lastNotice = "ตัดประวัติเก่า \(removed) ข้อความแล้ว — เหลือ \(messages.count) รายการ"
    }

    /// ค้นข้อความย้อนหลังในทุกห้อง (เฟส 6)
    func searchHistory(query: String) -> [ChatSearchHit] {
        ChatSearchIndex.search(query: query,
                               rooms: rooms,
                               messagesForRoom: { roomID in
                                   if roomID == self.currentRoomID { return self.messages }
                                   return self.roomStore.loadMessages(roomID: roomID)
                               })
    }

    // MARK: - ข้อมูลสำหรับหน้าตั้งค่า

    /// โฟลเดอร์ที่เก็บประวัติทุกห้อง (เฟส 5)
    var historyFilePath: String {
        roomStore.directoryPath
    }

    /// สรุปจำนวนห้องและข้อความทั้งหมด (ใช้แสดงในหน้าตั้งค่า)
    var historyFileSizeText: String {
        let messageTotal = rooms.reduce(0) { $0 + $1.messageCount }
        return "\(rooms.count) ห้อง • \(messageTotal) ข้อความ"
    }
}
