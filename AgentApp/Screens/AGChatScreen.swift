//
//  AGChatScreen.swift
//  AgentApp — หน้าแชท (พอร์ตจาก design-phase1: แถบหัว · แชท · การ์ดไทม์ไลน์ · แถบสถานะสด · คอมโพเซอร์)
//
//  หลักการจากแบบที่ยึดถือในไฟล์นี้:
//   1. ผู้ใช้เห็นตลอดว่า Agent ทำอะไรอยู่ — สถานะจริงจากเหตุการณ์จริง ไม่มีตัวเลขเดา
//   2. ความละเอียด 3 ระดับ: แถบสถานะสด → การ์ดไทม์ไลน์ → แผ่นรายละเอียดขั้น
//   3. ไม่แย่งการเลื่อนของผู้ใช้ (ขึ้นปุ่ม "ข้อความใหม่" แทนการกระชากกลับ)
//   4. ทุกสถานะมีข้อความไทยที่อ่านออกเสียงได้ และไม่มีสปินเนอร์เปล่า
//

import SwiftUI

// MARK: - ตัวช่วยเลื่อน (คำนวณระยะจากท้ายสุด)

private struct AGBottomDistanceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct AGChatScreen: View {

    @StateObject private var viewModel = ChatViewModel()
    @EnvironmentObject private var settings: AppSettings

    @ObservedObject private var center: ActivityCenter = .shared
    @ObservedObject private var usage: TokenUsageTracker = .shared
    @ObservedObject private var router: AppRouter = .shared

    @AppStorage(SettingsKeys.chatFontScale) private var fontScale: Double = 1
    @AppStorage(SettingsKeys.activityLevel) private var activityLevelRaw: String = ActivityDetailLevel.normal.rawValue

    @State private var inputText: String = ""
    @State private var fieldHeight: CGFloat = 26
    @State private var fieldFocused: Bool = false
    @State private var timelineExpanded: Bool = false
    @State private var showJumpToLatest: Bool = false
    @State private var showRooms: Bool = false
    @State private var showCost: Bool = false
    @State private var showExport: Bool = false
    @State private var showVoice: Bool = false
    @State private var showClearConfirm: Bool = false
    @State private var detailEvent: ActivityEvent?
    @State private var expandedGroups: Set<String> = []
    @State private var pendingDetailStep: ActivityEvent?
    @State private var showSystemPaused: Bool = false
    @State private var wasRunningWhenBackgrounded: Bool = false
    @Environment(\.scenePhase) private var scenePhase

    private let bottomAnchor = "ag-chat-bottom"

    private var activityLevel: ActivityDetailLevel {
        ActivityDetailLevel(rawValue: activityLevelRaw) ?? .normal
    }

    var body: some View {
        VStack(spacing: 0) {
            if showSystemPaused { systemPausedBanner }

            if let notice = viewModel.lastNotice {
                inlineNotice(notice)
            }

            chatArea

            VStack(spacing: AGMetric.s2) {
                if center.isRunning {
                    VStack(spacing: AGMetric.s2) {
                        AGLiveBar(isRunning: true,
                                  title: liveTitle,
                                  subtitle: activityLevel == .detailed ? liveSubtitle : nil,
                                  elapsed: center.elapsed,
                                  isExpanded: timelineExpanded,
                                  activeDotTone: liveTone,
                                  scale: fontScale) {
                            toggleRunCard()
                        }
                        AGRibbon(total: max(center.events.count, 6),
                                 done: center.events.filter { $0.status == .succeeded }.count,
                                 active: center.events.firstIndex(where: { $0.status == .running }) ?? -1,
                                 tone: AGColor.accent)
                            .padding(.horizontal, AGMetric.s1)
                            .accessibilityHidden(true)
                    }
                    .padding(.horizontal, AGMetric.screenPadding)
                    .padding(.bottom, 10)
                }
                composer
            }
            .padding(.top, 10)
            .background(AGColor.surface)
            .overlay(Rectangle().fill(AGColor.border).frame(height: 1), alignment: .top)
        }
        .background(AGColor.bg)
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle(currentRoomTitle)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                headerButton(icon: "line.3.horizontal", label: "รายการห้องสนทนา") { showRooms = true }
            }
            ToolbarItem(placement: .principal) {
                VStack(spacing: 1) {
                    Text(currentRoomTitle)
                        .font(AGFont.font(AGFont.head, weight: .semibold, scale: fontScale))
                        .foregroundColor(AGColor.t1)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    headerState
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text("ห้อง \(currentRoomTitle)\(headerStateText.map { " — \($0)" } ?? "")"))
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button(action: { showRooms = true }) { Label("ห้องสนทนา", systemImage: "bubble.left.and.bubble.right") }
                    Button(action: { showCost = true }) { Label("ต้นทุนและบริบท", systemImage: "chart.bar.doc.horizontal") }
                    Button(action: { showExport = true }) { Label("ส่งออกการสนทนา", systemImage: "square.and.arrow.up") }
                    Button(action: {
                        center.clear()
                        timelineExpanded = false
                    }) { Label("ล้างไทม์ไลน์ของงานนี้", systemImage: "clock.arrow.circlepath") }
                    Divider()
                    Button(action: { showClearConfirm = true }) { Label("ล้างการสนทนาทั้งหมด", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(AGFont.font(AGFont.head, weight: .semibold, scale: fontScale))
                        .foregroundColor(AGColor.t1)
                }
                .accessibilityLabel(Text("ตัวเลือกของหน้าแชท"))
            }
        }
        .sheet(isPresented: $showRooms) {
            AGRoomsSheet(rooms: viewModel.rooms,
                         currentRoomID: viewModel.currentRoomID,
                         onSelect: { room in
                             viewModel.selectRoom(room)
                             showRooms = false
                         },
                         onCreate: { name in
                             viewModel.createRoom(named: name)
                             AGHaptic.success()
                         },
                         onDelete: { room in
                             viewModel.deleteRoom(room)
                         },
                         onClose: { showRooms = false },
                         fontScale: fontScale)
        }
        .sheet(isPresented: $showCost) {
            AGCostSheet(fontScale: fontScale)
        }
        .sheet(isPresented: $showExport) {
            AGExportSheet(fontScale: fontScale, markdown: viewModel.exportMarkdownText())
        }
        .sheet(isPresented: $showVoice) {
            AGVoiceSheet(fontScale: fontScale) { text in
                inputText = text
                fieldHeight = 26
            }
        }
        .sheet(item: approvalBinding) { request in
            AGApprovalSheet(request: request,
                            fontScale: fontScale,
                            onDecide: { decision in
                                viewModel.resolveApproval(decision)
                            },
                            onKeepBackup: {
                                let target = request.detail ?? request.summary
                                viewModel.resolveApproval(.deny)
                                viewModel.send("อย่าลบ \(target) — ให้เก็บสำเนาไว้ในโฟลเดอร์สำรองแทน แล้วบอกผมว่าเก็บไว้ที่ไหน")
                            },
                            onEdit: {
                                viewModel.resolveApproval(.deny)
                                inputText = "ขอแก้คำสั่งก่อน: "
                                fieldHeight = 26
                            })
        }
        .alert("ล้างการสนทนาทั้งหมด?", isPresented: $showClearConfirm, actions: {
            Button("ล้างทั้งหมด", role: .destructive) { viewModel.clearConversation() }
            Button("ยกเลิก", role: .cancel) { }
        }, message: {
            Text("ข้อความทั้งหมดจะถูกลบทั้งจากหน้าจอและจากไฟล์ประวัติที่บันทึกไว้บนเครื่อง")
        })
        .overlay {
            if let event = detailEvent {
                ZStack {
                    AGSheet(title: "รายละเอียดขั้นตอน", scale: fontScale, onClose: { detailEvent = nil }) {
                        AGActivityDetail(event: event, fontScale: fontScale, onUndoMessage: { message in
                            viewModel.showNotice(message)
                        })
                    }
                }
                .zIndex(10)
            }
        }
        .onAppear {
            viewModel.activityObserver = { event in
                center.consume(event)
            }
            center.roomIDProvider = { [weak viewModel] in viewModel?.currentRoomID }
            viewModel.refreshQueue()
            openPendingRoomIfNeeded()
            consumePendingPromptIfNeeded()
#if DEBUG
            if let screen = AGPreview.screen { applyPreview(screen) }
#endif
        }
        .onChange(of: router.pendingRoomID) { _ in openPendingRoomIfNeeded() }
        .onChange(of: router.pendingPrompt) { _ in consumePendingPromptIfNeeded() }
        .onChange(of: viewModel.messages.count) { _ in
            if let step = pendingDetailStep {
                pendingDetailStep = nil
                detailEvent = step
            }
        }
        .onChange(of: scenePhase) { phase in
            if phase != .active {
                viewModel.persistNow()
                wasRunningWhenBackgrounded = viewModel.isBusy
            } else if wasRunningWhenBackgrounded {
                wasRunningWhenBackgrounded = false
                if !viewModel.isBusy && center.isRunning {
                    center.markSystemPaused()
                    withAnimation(AGMotion.animation(AGMotion.ease)) { showSystemPaused = true }
                }
            }
        }
    }

    // MARK: - ส่วนหัว

    private func headerButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: {
            AGHaptic.light()
            action()
        }) {
            Image(systemName: icon)
                .font(AGFont.font(AGFont.head, weight: .semibold, scale: fontScale))
                .foregroundColor(AGColor.t1)
                .frame(width: AGMetric.touch, height: AGMetric.touch)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(Text(label))
    }

    private var currentRoomTitle: String {
        guard let id = viewModel.currentRoomID,
              let room = viewModel.rooms.first(where: { $0.id == id }) else { return "แชทแรก" }
        return room.name
    }

    @ViewBuilder
    private var headerState: some View {
        if let state = headerStateInfo {
            HStack(spacing: 5) {
                if state.isRunning {
                    AGPulseDot(tone: state.tone, size: 7)
                } else {
                    Circle().fill(state.tone).frame(width: 7, height: 7)
                }
                Text(state.text)
                    .font(AGFont.font(AGFont.micro, scale: fontScale))
                    .foregroundColor(AGColor.t2)
                    .lineLimit(1)
            }
        }
    }

    private var headerStateText: String? { headerStateInfo?.text }

    private var headerStateInfo: (text: String, tone: Color, isRunning: Bool)? {
        if let request = viewModel.pendingApproval {
            return ("รอคุณอนุญาต: \(request.thaiLabel)", AGColor.warning, false)
        }
        let waitingCount = center.events.filter { $0.status == .waitingUser }.count
            + (viewModel.pendingApproval == nil ? 0 : 1)
        if waitingCount > 0, !center.isRunning {
            return ("มี \(waitingCount) ขั้นที่ต้องให้คุณตัดสินใจ", AGColor.warning, false)
        }
        if center.isRunning {
            let done = center.events.filter { $0.status == .succeeded }.count
            if center.events.isEmpty {
                return ("กำลังคิด", AGColor.accent, true)
            }
            if let index = center.events.firstIndex(where: { $0.status == .running }) {
                return ("กำลังทำงาน · ขั้น \(index + 1) จาก \(center.events.count)", AGColor.accent, true)
            }
            if done > 0 { return ("กำลังทำงาน · ทำแล้ว \(done) ขั้น", AGColor.accent, true) }
            return ("กำลังทำงาน", AGColor.accent, true)
        }
        if !viewModel.queuedMessages.isEmpty {
            return ("มีข้อความรอส่ง \(viewModel.queuedMessages.count) ข้อความ", AGColor.accent, false)
        }
        if center.finishedTitle == "ทำเสร็จแล้ว" || center.finishedTitle == "ทำงานเสร็จแล้ว" {
            return ("ทำงานเสร็จแล้ว · ใช้เวลา \(AGFormat.durationShort(center.elapsed))", AGColor.success, false)
        }
        if !center.finishedTitle.isEmpty {
            return (center.finishedTitle, AGColor.t3, false)
        }
        return ("พร้อมทำงาน · ยังไม่มีงานค้าง", AGColor.success, false)
    }

    // MARK: - แถบสถานะสด

    private var liveTitle: String {
        center.liveLabel.isEmpty ? "กำลังทำงาน" : center.liveLabel
    }

    private var liveSubtitle: String? {
        let done = center.events.filter { $0.status == .succeeded }.count
        return done > 0 ? "ทำแล้ว \(done) ขั้น · แตะเพื่อดูทุกขั้นตอน" : "แตะเพื่อดูทุกขั้นตอน"
    }

    private var liveTone: Color {
        if center.events.contains(where: { $0.status == .waitingUser }) { return AGColor.warning }
        return AGColor.accent
    }

    /// แตะแถบสถานะสด = กาง/พับการ์ดไทม์ไลน์ในแชท (การ์ดเดียว ไม่มีรายการซ้ำ)
    private func toggleRunCard() {
        withAnimation(AGMotion.animation(AGMotion.ease)) { timelineExpanded.toggle() }
    }

    // MARK: - พื้นที่แชท

    private var chatArea: some View {
        ScrollViewReader { proxy in
            GeometryReader { outer in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: AGMetric.s4) {
                        if viewModel.visibleMessages.isEmpty, center.events.isEmpty, !viewModel.isBusy {
                            AGChatEmptyState(fontScale: fontScale) { prompt in
                                inputText = prompt
                                fieldHeight = 26
                            }
                        }

                        if viewModel.hiddenMessageCount > 0 { loadEarlierRow }

                        ForEach(transcriptItems) { item in
                            switch item {
                            case .message(let message):
                                messageView(message)
                            case .steps(let group):
                                AGTimelineCard(steps: group.events,
                                               isRunning: false,
                                               expanded: expandedGroups.contains(group.id),
                                               scale: fontScale,
                                               onToggle: { toggleGroup(group.id) },
                                               onOpenStep: { event in detailEvent = event })
                            }
                        }

                        if !center.events.isEmpty { currentRunCard }

                        Color.clear.frame(height: 1).id(bottomAnchor)

                        GeometryReader { inner in
                            Color.clear.preference(key: AGBottomDistanceKey.self,
                                                   value: inner.frame(in: .named("agChat")).minY - outer.size.height)
                        }
                        .frame(height: 1)
                    }
                    .padding(.horizontal, AGMetric.screenPadding)
                    .padding(.vertical, AGMetric.s3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .coordinateSpace(name: "agChat")
                .onPreferenceChange(AGBottomDistanceKey.self) { distance in
                    showJumpToLatest = distance > 160
                }
                .overlay(alignment: .bottomTrailing) {
                    if showJumpToLatest { jumpToLatest(proxy: proxy) }
                }
                .onChange(of: viewModel.messages.count) { _ in
                    guard !showJumpToLatest else { return }
                    scrollToBottom(proxy: proxy, animated: true)
                }
            }
        }
    }

    private func jumpToLatest(proxy: ScrollViewProxy) -> some View {
        Button(action: {
            AGHaptic.light()
            scrollToBottom(proxy: proxy, animated: true)
        }) {
            HStack(spacing: 6) {
                Circle().fill(AGColor.accent).frame(width: 7, height: 7)
                Text("ข้อความใหม่")
                    .font(AGFont.font(AGFont.cap, scale: fontScale))
                    .foregroundColor(AGColor.t1)
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(Capsule().fill(AGColor.surface))
            .overlay(Capsule().stroke(AGColor.border, lineWidth: 1))
            .shadow(color: Color.black.opacity(0.08), radius: 7, x: 0, y: 4)
        }
        .buttonStyle(AGPressableStyle())
        .padding(.trailing, 14)
        .padding(.bottom, 14)
        .accessibilityLabel(Text("ไปที่ข้อความล่าสุด"))
    }

    private var loadEarlierRow: some View {
        Button(action: {
            AGHaptic.light()
            viewModel.loadEarlierMessages()
        }) {
            HStack(spacing: AGMetric.s2) {
                Image(systemName: "arrow.up.circle")
                    .font(AGFont.font(AGFont.cap, scale: fontScale))
                    .foregroundColor(AGColor.t2)
                    .accessibilityHidden(true)
                Text("โหลดข้อความก่อนหน้า \(viewModel.hiddenMessageCount) รายการ")
                    .font(AGFont.font(AGFont.cap, scale: fontScale))
                    .foregroundColor(AGColor.t2)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, AGMetric.s3)
            .frame(minHeight: AGMetric.touch)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: AGMetric.rSM, style: .continuous).fill(AGColor.surface2))
        }
        .buttonStyle(AGPressableStyle())
    }

    @ViewBuilder
    private func messageView(_ message: ChatMessage) -> some View {
        switch message.role {
        case .user:
            VStack(alignment: .trailing, spacing: AGMetric.s2) {
                let attachments = message.attachments ?? []
                if !attachments.isEmpty {
                    ForEach(attachments) { attachment in
                        HStack(spacing: AGMetric.s2) {
                            Image(systemName: "paperclip")
                                .font(AGFont.font(AGFont.cap, scale: fontScale))
                                .foregroundColor(AGColor.t2)
                            Text("\(attachment.originalName) · \(AGFormat.bytes(attachment.byteSize))")
                                .font(AGFont.font(AGFont.cap, scale: fontScale))
                                .foregroundColor(AGColor.t2)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, AGMetric.s3)
                        .frame(minHeight: 34)
                        .background(Capsule().fill(AGColor.surface2))
                    }
                }
                if !message.text.isEmpty { AGBubble(text: message.text, scale: fontScale) }
            }
        case .assistant:
            if message.isTextEmpty {
                if viewModel.isThinking(messageID: message.id) { thinkingRow }
            } else {
                VStack(alignment: .leading, spacing: AGMetric.s2) {
                    AGAgentText(markdown: message.text, scale: fontScale)
                    if viewModel.isThinking(messageID: message.id) { thinkingRow }
                }
            }
        case .tool:
            // ขั้นตอนแสดงผ่านการ์ดไทม์ไลน์เท่านั้น (ไม่วาดซ้ำเป็นแถวเดี่ยว)
            EmptyView()
        case .system:
            EmptyView()
        }
    }

    /// การ์ดไทม์ไลน์ของงานปัจจุบัน (สร้างจากเหตุการณ์จริงของ ActivityCenter)
    private var currentRunCard: some View {
        AGTimelineCard(steps: center.events,
                       isRunning: center.isRunning,
                       expanded: timelineExpanded,
                       elapsedText: AGFormat.durationShort(center.elapsed),
                       scale: fontScale,
                       onToggle: {
                           withAnimation(AGMotion.animation(AGMotion.ease)) { timelineExpanded.toggle() }
                       },
                       onOpenStep: { event in detailEvent = event })
    }

    private func toggleGroup(_ id: String) {
        withAnimation(AGMotion.animation(AGMotion.ease)) {
            if expandedGroups.contains(id) { expandedGroups.remove(id) } else { expandedGroups.insert(id) }
        }
    }

    /// การ์ด "กำลังคิด" (เทียบ .tl.always ของแบบ) — มีข้อความจริงจากสถานะ Agent ไม่ใช่สปินเนอร์เปล่า
    private var thinkingRow: some View {
        AGThinkingCard(elapsed: center.elapsed,
                       message: thinkingMessage,
                       scale: fontScale)
    }

    private var thinkingMessage: String {
        if !center.liveLabel.isEmpty { return center.liveLabel }
        return "กำลังอ่านคำขอของคุณและตรวจไฟล์ที่เกี่ยวข้อง…"
    }

    // MARK: - รายการในแชท

    private enum TranscriptItem: Identifiable {
        case message(ChatMessage)
        case steps(StepGroup)

        struct StepGroup: Identifiable {
            let messages: [ChatMessage]
            var id: String { messages.first?.id.uuidString ?? UUID().uuidString }
            var events: [ActivityEvent] { ActivityCenter.historyEvents(from: messages) }
        }

        var id: String {
            switch self {
            case .message(let message): return message.id.uuidString
            case .steps(let group): return group.id
            }
        }
    }

    private var transcriptItems: [TranscriptItem] {
        var items: [TranscriptItem] = []
        var buffer: [ChatMessage] = []

        func flush() {
            guard !buffer.isEmpty else { return }
            items.append(.steps(TranscriptItem.StepGroup(messages: buffer)))
            buffer.removeAll()
        }

        for message in viewModel.visibleMessages {
            if message.role == .tool {
                if belongsToCurrentRun(message) {
                    continue
                }
                buffer.append(message)
            } else {
                flush()
                items.append(.message(message))
            }
        }
        flush()
        return items
    }

    /// ขั้นที่เป็นของงานที่ ActivityCenter กำลังแสดงอยู่ → วาดด้วยการ์ดไทม์ไลน์ของการ์ดงานปัจจุบัน
    private func belongsToCurrentRun(_ message: ChatMessage) -> Bool {
        guard !center.events.isEmpty, let startedAt = center.startedAt else { return false }
        return message.createdAt >= startedAt.addingTimeInterval(-1)
    }

    // MARK: - คอมโพเซอร์

    private var composer: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !viewModel.queuedMessages.isEmpty { queueArea }

            if inputText.isEmpty && !viewModel.isBusy && !center.isRunning { quickChips }

            HStack(alignment: .bottom, spacing: AGMetric.s2) {
                Button(action: {
                    AGHaptic.light()
                    showAttachmentHint()
                }) {
                    Image(systemName: "plus")
                        .font(AGFont.font(AGFont.title, weight: .medium, scale: fontScale))
                        .foregroundColor(AGColor.t2)
                        .frame(width: AGMetric.touch, height: AGMetric.touch)
                        .background(Circle().fill(AGColor.surface2))
                        .contentShape(Rectangle())
                }
                .buttonStyle(AGPressableStyle())
                .accessibilityLabel(Text("แนบไฟล์หรือรูป"))
                .accessibilityHint(Text("การแนบไฟล์ในบิลด์นี้ทำได้จากหน้าตั้งค่า > โฟลเดอร์ทำงาน ก่อน แล้วพิมพ์บอก Agent ให้เปิดไฟล์นั้น"))

                HStack(alignment: .bottom, spacing: 6) {
                    ZStack(alignment: .topLeading) {
                        AGMultilineField(text: $inputText,
                                         height: $fieldHeight,
                                         font: AGFont.uiFont(AGFont.body, scale: fontScale),
                                         minHeight: 26,
                                         maxHeight: AGMetric.composerFieldMaxHeight - 40,
                                         isEditable: true,
                                         onFocusChange: { focused in fieldFocused = focused })
                            .frame(height: fieldHeight)
                            .padding(.vertical, 3)

                        if inputText.isEmpty {
                            Text(viewModel.isBusy ? "พิมพ์ได้ — ข้อความจะต่อคิว" : "พิมพ์ข้อความ ถามงาน หรือแนบไฟล์…")
                                .font(AGFont.font(AGFont.body, scale: fontScale))
                                .foregroundColor(AGColor.t3)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .padding(.top, 9)
                                .padding(.leading, 1)
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                        }
                    }

                    Button(action: {
                        AGHaptic.light()
                        showVoice = true
                    }) {
                        Image(systemName: "mic")
                            .font(AGFont.font(AGFont.callout, scale: fontScale))
                            .foregroundColor(AGColor.t2)
                            .frame(width: 40, height: 40)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(AGPressableStyle())
                    .accessibilityLabel(Text("พูดแทนการพิมพ์"))
                }
                .padding(.leading, 8)
                .padding(.trailing, 6)
                .padding(.vertical, 6)
                .frame(minHeight: AGMetric.composerFieldMinHeight)
                .background(RoundedRectangle(cornerRadius: AGMetric.rXL, style: .continuous)
                    .fill(fieldFocused ? AGColor.surface : AGColor.surface2))
                .overlay(RoundedRectangle(cornerRadius: AGMetric.rXL, style: .continuous)
                    .stroke(fieldFocused ? AGColor.accent : Color.clear, lineWidth: 1))

                if viewModel.isBusy && inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button(action: {
                        AGHaptic.medium()
                        viewModel.stop()
                    }) {
                        Image(systemName: "stop.fill")
                            .font(AGFont.font(AGFont.callout, weight: .semibold, scale: fontScale))
                            .foregroundColor(.white)
                            .frame(width: AGMetric.touch, height: AGMetric.touch)
                            .background(Circle().fill(AGColor.error))
                    }
                    .buttonStyle(AGPressableStyle())
                    .accessibilityLabel(Text("หยุดงานนี้"))
                    .accessibilityHint(Text("Agent จะหยุดที่ขั้นปัจจุบัน ผลที่ทำแล้วจะถูกเก็บไว้"))
                } else {
                    Button(action: send) {
                        Image(systemName: "paperplane.fill")
                            .font(AGFont.font(AGFont.callout, weight: .semibold, scale: fontScale))
                            .foregroundColor(canSend ? AGColor.onAccent : AGColor.t3)
                            .frame(width: AGMetric.touch, height: AGMetric.touch)
                            .background(Circle().fill(canSend ? AGColor.accent : AGColor.surface3))
                    }
                    .buttonStyle(AGPressableStyle())
                    .disabled(!canSend)
                    .accessibilityLabel(Text(viewModel.isBusy ? "ต่อคิวข้อความนี้" : "ส่งข้อความ"))
                    .accessibilityHint(Text(canSend ? "" : "พิมพ์ข้อความก่อน"))
                }
            }
            .padding(.horizontal, AGMetric.s3)
            .padding(.bottom, 10)

            if usage.hasData { usageLine.padding(.horizontal, AGMetric.s3).padding(.bottom, 8) }
        }
        .padding(.top, 10)
        .background(AGColor.surface)
    }

    private var quickChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AGMetric.s2) {
                ForEach(AGChatScreen.defaultPrompts(workspace: settings.workspacePath), id: \.self) { prompt in
                    AGQuickChip(text: prompt, scale: fontScale) {
                        inputText = prompt
                    }
                }
            }
            .padding(.horizontal, AGMetric.s3)
            .padding(.bottom, 10)
        }
    }

    private var queueArea: some View {
        VStack(alignment: .leading, spacing: AGMetric.s2) {
            HStack(spacing: AGMetric.s2) {
                Image(systemName: "clock")
                    .font(AGFont.font(AGFont.cap, scale: fontScale))
                    .foregroundColor(AGColor.accentInk)
                    .accessibilityHidden(true)
                Text(viewModel.isBusy ? "รอส่งหลังงานนี้จบ (\(viewModel.queuedMessages.count))"
                                      : "มีข้อความรอส่ง (\(viewModel.queuedMessages.count))")
                    .font(AGFont.font(AGFont.cap, weight: .semibold, scale: fontScale))
                    .foregroundColor(AGColor.t1)
                Spacer(minLength: 0)
                if !viewModel.isBusy {
                    Button(action: {
                        AGHaptic.medium()
                        viewModel.flushQueue()
                    }) {
                        Text("ส่งเลย")
                            .font(AGFont.font(AGFont.cap, weight: .semibold, scale: fontScale))
                            .foregroundColor(AGColor.accentInk)
                            .frame(minHeight: 34)
                    }
                    .buttonStyle(AGPressableStyle())
                    .accessibilityLabel(Text("ส่งข้อความที่รออยู่ตอนนี้"))
                }
            }

            ForEach(viewModel.queuedMessages) { item in
                HStack(alignment: .top, spacing: AGMetric.s2) {
                    Text(item.preview)
                        .font(AGFont.font(AGFont.cap, scale: fontScale))
                        .foregroundColor(AGColor.t2)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button(action: {
                        AGHaptic.light()
                        viewModel.removeQueuedMessage(id: item.id)
                    }) {
                        Image(systemName: "xmark")
                            .font(AGFont.font(AGFont.micro, weight: .semibold, scale: fontScale))
                            .foregroundColor(AGColor.t3)
                            .frame(width: 34, height: 34)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(AGPressableStyle())
                    .accessibilityLabel(Text("ยกเลิกข้อความนี้จากคิว"))
                }
                .padding(.horizontal, AGMetric.s3)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: AGMetric.rSM, style: .continuous).fill(AGColor.surface2))
            }
        }
        .padding(.horizontal, AGMetric.s3)
        .padding(.bottom, AGMetric.s2)
    }

    private var usageLine: some View {
        HStack(spacing: AGMetric.s2) {
            Image(systemName: "chart.bar.doc.horizontal")
                .font(AGFont.font(AGFont.micro, scale: fontScale))
                .foregroundColor(AGColor.t3)
                .accessibilityHidden(true)
            Text("ใช้ไป \(usage.compactShortText)\(costSuffix)")
                .font(AGFont.font(AGFont.micro, scale: fontScale))
                .foregroundColor(AGColor.t3)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("การใช้โทเคนของห้องนี้: \(usage.compactShortText)\(costSuffix)"))
    }

    private var costSuffix: String {
        if let cost = usage.costCredits { return String(format: " · %.4f เครดิต", cost) }
        return " · ค่าใช้จ่ายไม่ระบุ"
    }

    /// ผูกคำขออนุมัติกับชีต: ปิดชีตโดยไม่เลือก = ไม่อนุญาต (ไม่ค้างงานไว้เงียบ ๆ)
    private var approvalBinding: Binding<ApprovalRequest?> {
        Binding(get: { viewModel.pendingApproval },
                set: { newValue in
                    if newValue == nil, viewModel.pendingApproval != nil {
                        viewModel.resolveApproval(.deny)
                    }
                })
    }

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - แบนเนอร์

    private func inlineNotice(_ text: String) -> some View {
        HStack(alignment: .top, spacing: AGMetric.s2) {
            Image(systemName: "info.circle.fill")
                .font(AGFont.font(AGFont.micro, scale: fontScale))
                .foregroundColor(AGColor.accentInk)
                .accessibilityHidden(true)
            Text(text)
                .font(AGFont.font(AGFont.cap, scale: fontScale))
                .foregroundColor(AGColor.t2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(action: viewModel.dismissNotice) {
                Image(systemName: "xmark")
                    .font(AGFont.font(AGFont.micro, weight: .semibold, scale: fontScale))
                    .foregroundColor(AGColor.t3)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(AGPressableStyle())
            .accessibilityLabel(Text("ปิดข้อความแจ้ง"))
        }
        .padding(.horizontal, AGMetric.screenPadding)
        .padding(.vertical, AGMetric.s2)
        .background(AGColor.surface2)
    }

    private var systemPausedBanner: some View {
        VStack(alignment: .leading, spacing: AGMetric.s2) {
            AGBanner(tone: .warning,
                     title: "ระบบหยุดงานชั่วคราว",
                     message: "iOS ไม่ให้แอปทำงานเบื้องหลังได้นาน งานจึงหยุดที่ขั้นล่าสุด — ผลที่ทำไว้แล้วยังอยู่ครบ",
                     scale: fontScale)
            HStack(spacing: AGMetric.s3) {
                Button(action: continueAfterSystemPause) {
                    Text("ให้ Agent ทำต่อจากจุดนี้")
                        .font(AGFont.font(AGFont.cap, weight: .semibold, scale: fontScale))
                        .foregroundColor(AGColor.warning)
                        .frame(minHeight: 38)
                }
                .buttonStyle(AGPressableStyle())
                Button(action: { withAnimation(AGMotion.animation(AGMotion.ease)) { showSystemPaused = false } }) {
                    Text("ไว้ก่อน")
                        .font(AGFont.font(AGFont.cap, scale: fontScale))
                        .foregroundColor(AGColor.t2)
                        .frame(minHeight: 38)
                }
                .buttonStyle(AGPressableStyle())
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, AGMetric.screenPadding)
        .padding(.top, AGMetric.s3)
    }

    // MARK: - การทำงาน

    private func send() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""
        fieldHeight = 26
        if viewModel.isBusy {
            viewModel.queueMessage(text)
            return
        }
        center.beginRun(title: text)
        viewModel.send(text)
    }

    private func showAttachmentHint() {
        viewModel.showNotice("การแนบไฟล์: วางไฟล์ไว้ในโฟลเดอร์ทำงาน (\(settings.workspacePath)) แล้วพิมพ์บอก Agent ว่าชื่อไฟล์อะไร · หน้าแนบไฟล์แบบเต็มจะมาในรอบถัดไป")
    }

    private func scrollToBottom(proxy: ScrollViewProxy, animated: Bool) {
        if animated {
            withAnimation(AGMotion.animation(.easeOut(duration: AGMotion.dur3))) {
                proxy.scrollTo(bottomAnchor, anchor: .bottom)
            }
        } else {
            proxy.scrollTo(bottomAnchor, anchor: .bottom)
        }
    }

    /// ถ้ามีคำสั่งที่ส่งข้ามแท็บมา (เช่น กด "ทำต่อจากจุดเดิม" ในหน้างานของฉัน) → ส่งให้ Agent ทันที
    private func consumePendingPromptIfNeeded() {
        guard let pending = router.consumePendingPrompt() else { return }
        AGHaptic.medium()
        inputText = pending.prompt
        fieldHeight = 26
        if !viewModel.isBusy { send() }
    }

    private func openPendingRoomIfNeeded() {
        guard let roomID = router.pendingRoomID else { return }
        router.consumePendingRoom()
        guard viewModel.currentRoomID != roomID,
              let room = viewModel.rooms.first(where: { $0.id == roomID }) else { return }
        viewModel.selectRoom(room)
    }

    private func continueAfterSystemPause() {
        AGHaptic.medium()
        withAnimation(AGMotion.animation(AGMotion.ease)) { showSystemPaused = false }
        guard !viewModel.isBusy else { return }
        center.beginRun(title: "ทำต่องานที่ถูกระงับ")
        viewModel.send("งานก่อนหน้าถูก iOS ระงับกลางทาง ช่วยทำต่อจากจุดที่ค้างไว้ โดยใช้ผลลัพธ์ที่ทำเสร็จแล้ว ไม่ต้องเริ่มใหม่ทั้งหมด")
    }

    static func defaultPrompts(workspace: String) -> [String] {
        ["ดูว่ามีไฟล์อะไรใน \((workspace as NSString).lastPathComponent) บ้าง",
         "สรุปไฟล์ล่าสุดในโฟลเดอร์ทำงานให้หน่อย",
         "ช่วยจัดระเบียบไฟล์ในโฟลเดอร์ทำงาน",
         "ค้นในเว็บว่าวันนี้มีข่าวอะไรเกี่ยวกับ iPhone"]
    }

#if DEBUG
    // MARK: - โหมดตรวจงานออกแบบ (บิลด์ Debug เท่านั้น)
    private func applyPreview(_ screen: String) {
        switch screen {
        case "chat", "chat-open":
            center.previewSeed(events: AGPreview.events(), running: false, liveLabel: "",
                               finishedTitle: "ทำเสร็จแล้ว",
                               startedAt: Date().addingTimeInterval(-96), elapsed: 15)
            viewModel.previewSeed(messages: AGPreview.messages(finished: true), isBusy: false,
                                  statusText: "", approval: nil)
            timelineExpanded = (screen == "chat-open")
        case "running":
            center.previewSeed(events: AGPreview.runningEvents(), running: true,
                               liveLabel: "กำลังอ่านหน้าเว็บที่เกี่ยวข้อง", finishedTitle: "",
                               startedAt: Date().addingTimeInterval(-24), elapsed: 24)
            viewModel.previewSeed(messages: AGPreview.messages(finished: false), isBusy: true,
                                  statusText: "กำลังอ่านหน้าเว็บ", approval: nil)
            timelineExpanded = false
        case "approval":
            center.previewSeed(events: AGPreview.runningEvents(), running: true,
                               liveLabel: "รอคุณอนุญาต: ลบไฟล์", finishedTitle: "",
                               startedAt: Date().addingTimeInterval(-40), elapsed: 40)
            viewModel.previewSeed(messages: AGPreview.messages(finished: false), isBusy: true,
                                  statusText: "รออนุมัติ", approval: AGPreview.approvalRequest())
        case "detail":
            center.previewSeed(events: AGPreview.events(), running: false, liveLabel: "",
                               finishedTitle: "ทำเสร็จแล้ว",
                               startedAt: Date().addingTimeInterval(-96), elapsed: 15)
            viewModel.previewSeed(messages: AGPreview.messages(finished: true), isBusy: false,
                                  statusText: "", approval: nil)
            detailEvent = AGPreview.events().first(where: { $0.kind == .fileWrite })
        default:
            break
        }
    }
#endif
}
