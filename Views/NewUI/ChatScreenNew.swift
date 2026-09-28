//
//  ChatScreenNew.swift
//  iOS Agent Sandbox — ดีไซน์ v2 (เฟส 5 ส่วนที่ 2–4)
//
//  หน้าแชทหลักของดีไซน์ใหม่ (แทน ChatView เดิมเมื่อเปิดสวิตช์ "หน้าจอใหม่")
//  - ใช้ ChatViewModel/AgentEngine/บริการเดิมทั้งหมด (ไม่แตะ backend)
//  - แสดงระบบกิจกรรม 3 ระดับ: แถบสถานะสด → ไทม์ไลน์ → แผ่นรายละเอียด
//  - ปุ่มหยุดอยู่ติดนิ้วโป้งเสมอ และทุกการกระทำที่มีผลกับเครื่องยังต้องขออนุญาต
//

import SwiftUI

/// ระยะจากขอบล่างของพื้นที่อ่าน — ใช้ตัดสินว่าจะเด้งปุ่ม "ข้อความใหม่" หรือไม่
/// หนึ่งรายการในแชท: ข้อความ หรือ กลุ่มขั้นตอนของหนึ่งรอบการทำงาน
private enum ChatStreamItem: Identifiable {

    struct ToolGroup: Identifiable {
        let messages: [ChatMessage]
        var id: String { messages.first?.id.uuidString ?? UUID().uuidString }
        var stepCount: Int { messages.count }
        var totalDuration: TimeInterval { messages.compactMap { $0.toolDuration }.reduce(0, +) }
    }

    case message(ChatMessage)
    case tools(ToolGroup)

    var id: String {
        switch self {
        case .message(let message): return message.id.uuidString
        case .tools(let group): return group.id
        }
    }
}

private struct DSBottomDistanceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct ChatScreenNew: View {

    @StateObject private var viewModel = ChatViewModel()
    @EnvironmentObject private var settings: AppSettings
    @ObservedObject private var usage: TokenUsageTracker = .shared
    @ObservedObject private var center: ActivityCenter = .shared
    @ObservedObject private var router: AppRouter = .shared

    @AppStorage(SettingsKeys.chatFontScale) private var fontScale: Double = 1.0
    @AppStorage(SettingsKeys.activityLevel) private var activityLevelRaw: String = ActivityDetailLevel.normal.rawValue

    @State private var inputText: String = ""
    @State private var composerHeight: CGFloat = 38
    @State private var timelineExpanded: Bool = false
    @State private var expandedEventID: String?
    @State private var detailEvent: ActivityEvent?
    @State private var showDetailSheet: Bool = false
    @State private var showsJumpToLatest: Bool = false
    @State private var showRooms: Bool = false
    @State private var showAttachmentPicker: Bool = false
    @State private var showClearConfirmation: Bool = false
    @State private var showContextSheet: Bool = false
    @State private var showExportSheet: Bool = false
    @State private var showVoiceSheet: Bool = false
    /// กลุ่มไทม์ไลน์ที่ผู้ใช้กางอยู่ (การ์ดไทม์ไลน์ในแชท — กางได้ทีละกลุ่ม)
    @State private var expandedGroupID: String?
    @State private var showSystemPausedBanner: Bool = false
    @State private var wasRunningWhenBackgrounded: Bool = false
    @Environment(\.scenePhase) private var scenePhase

    private let bottomAnchorID = "ds-chat-bottom"

    private var activityLevel: ActivityDetailLevel {
        ActivityDetailLevel(rawValue: activityLevelRaw) ?? .normal
    }

    var body: some View {
        VStack(spacing: 0) {
            if showSystemPausedBanner {
                systemPausedBanner
            }
            if let notice = viewModel.lastNotice {
                noticeBanner(text: notice)
            }
            if let error = viewModel.errorMessage {
                errorBanner(text: error)
            }
            messagesArea
            if timelineExpanded {
                timelinePanel
            }
            if !center.events.isEmpty || center.isRunning {
                DSLiveStatusBar(center: center, isExpanded: $timelineExpanded)
            }
            composerArea
        }
        .background(DSColor.bg)
        .navigationTitle(currentRoomTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // ตามแบบ: ซ้าย = รายการห้อง · กลาง = ชื่อห้อง + สถานะ Agent · ขวา = เมนูห้องนี้
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: {
                    DSHaptic.light()
                    showRooms = true
                }) {
                    Image(systemName: "line.3.horizontal")
                        .font(DSFont.font(DSFont.sHead, weight: .semibold, scale: fontScale))
                        .foregroundColor(DSColor.t1)
                        .frame(width: DSMetrics.touch, height: DSMetrics.touch)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(Text("รายการห้องสนทนา"))
            }
            ToolbarItem(placement: .principal) {
                VStack(spacing: 1) {
                    Text(currentRoomTitle)
                        .font(DSFont.font(DSFont.sHead, weight: .semibold, scale: fontScale))
                        .foregroundColor(DSColor.t1)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    if let state = headerAgentState {
                        HStack(spacing: 5) {
                            if state.isRunning {
                                DSPulseDot(tone: DSColor.accent, size: 6)
                            } else {
                                Circle().fill(state.tone).frame(width: 6, height: 6)
                            }
                            Text(state.text)
                                .font(DSFont.font(DSFont.sMicro, scale: fontScale))
                                .foregroundColor(DSColor.t3)
                                .lineLimit(1)
                        }
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text(headerAccessibilityLabel))
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button(action: { showRooms = true }) {
                        Label("ห้องสนทนา", systemImage: "bubble.left.and.bubble.right")
                    }
                    Button(action: { showContextSheet = true }) {
                        Label("ต้นทุนและบริบท", systemImage: "chart.bar.doc.horizontal")
                    }
                    Button(action: { showExportSheet = true }) {
                        Label("ส่งออกการสนทนา", systemImage: "square.and.arrow.up")
                    }
                    Button(action: { center.clear(); timelineExpanded = false }) {
                        Label("ล้างไทม์ไลน์ของงานนี้", systemImage: "clock.arrow.circlepath")
                    }
                    Divider()
                    Button(action: { showClearConfirmation = true }) {
                        Label("ล้างการสนทนาทั้งหมด", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(DSFont.font(DSFont.sHead, weight: .semibold, scale: fontScale))
                        .foregroundColor(DSColor.t1)
                }
                .accessibilityLabel(Text("ตัวเลือกของหน้าแชท"))
            }
        }
        .sheet(isPresented: $showRooms) {
            ChatRoomsView(viewModel: viewModel)
        }
        .sheet(isPresented: $showAttachmentPicker) {
            AttachmentPickerSheet(maxBytes: Int(settings.maxDownloadBytes),
                                  onImported: { attachments in
                                      viewModel.addAttachments(attachments)
                                  },
                                  onPasteText: { text in
                                      inputText += text
                                  },
                                  onMessage: { message in
                                      viewModel.showNotice(message)
                                  })
        }
        .sheet(item: approvalBinding) { request in
            DSApprovalSheet(request: request, scale: fontScale) { decision in
                viewModel.resolveApproval(decision)
            }
        }
        .sheet(isPresented: $showContextSheet) {
            ContextCostSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $showVoiceSheet) {
            VoiceInputSheet { text in
                inputText = text
                composerHeight = 38
                DSHaptic.success()
            }
            .environmentObject(settings)
        }
        .sheet(isPresented: $showExportSheet) {
            ExportSheet(viewModel: viewModel)
        }
        .dsBottomSheet(isPresented: $showDetailSheet, title: "รายละเอียดขั้นตอน") {
            if let event = detailEvent {
                DSActivityDetailView(event: event)
            }
        }
        .confirmationDialog("ล้างการสนทนาทั้งหมด?",
                            isPresented: $showClearConfirmation,
                            titleVisibility: .visible) {
            Button("ล้างทั้งหมด", role: .destructive) {
                viewModel.clearConversation()
                center.clear()
            }
            Button("ยกเลิก", role: .cancel) { }
        } message: {
            Text("ข้อความทั้งหมดจะถูกลบทั้งจากหน้าจอและจากไฟล์ประวัติที่บันทึกไว้บนเครื่อง")
        }
        .onAppear {
            viewModel.activityObserver = { event in
                center.consume(event)
            }
            // ให้การแจ้งเตือนผูกกับห้องที่กำลังเปิดอยู่
            center.roomIDProvider = { [weak viewModel] in
                viewModel?.currentRoomID
            }
            viewModel.refreshQueue()
            openPendingRoomIfNeeded()
            handlePendingPromptIfNeeded()
#if DEBUG
            if let screen = UIPreview.screen { applyPreview(screen) }
#endif
        }
        .onChange(of: router.pendingRoomID) { _ in
            openPendingRoomIfNeeded()
        }
        .onChange(of: router.pendingPrompt) { _ in
            handlePendingPromptIfNeeded()
        }
        .onChange(of: scenePhase) { phase in
            if phase != .active {
                viewModel.persistNow()
                // จำไว้ว่ากำลังทำงานอยู่ตอนแอปถูกพัก — เพื่อแยกแยะ "งานถูกระบบระงับ" จาก "งานจบเอง"
                wasRunningWhenBackgrounded = viewModel.isBusy
            } else if wasRunningWhenBackgrounded {
                wasRunningWhenBackgrounded = false
                if !viewModel.isBusy && center.isRunning {
                    center.markSystemPaused()
                    withAnimation(DSMotion.card) { showSystemPausedBanner = true }
                }
            }
        }
    }

    // MARK: - แบนเนอร์

    private func noticeBanner(text: String) -> some View {
        DSBanner(tone: .info, title: "แจ้งให้ทราบ", message: text, scale: fontScale) {
            HStack(spacing: DSMetrics.s3) {
                Button(action: { viewModel.dismissNotice() }) {
                    Text("รับทราบ")
                        .font(DSFont.font(DSFont.sCap, weight: .semibold, scale: fontScale))
                        .foregroundColor(DSColor.accentInk)
                        .frame(minHeight: DSMetrics.touchSmall)
                }
                .buttonStyle(DSPressableStyle())
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, DSMetrics.screenPadding)
        .padding(.top, DSMetrics.s3)
    }

    private func errorBanner(text: String) -> some View {
        DSBanner(tone: .error, title: "มีบางอย่างไม่สำเร็จ", message: text, scale: fontScale) {
            HStack(spacing: DSMetrics.s3) {
                if viewModel.canRetryLastRun {
                    Button(action: { viewModel.retryLastFailedRun() }) {
                        Text("ลองใหม่")
                            .font(DSFont.font(DSFont.sCap, weight: .semibold, scale: fontScale))
                            .foregroundColor(DSColor.error)
                            .frame(minHeight: DSMetrics.touchSmall)
                    }
                    .buttonStyle(DSPressableStyle())
                }
                Button(action: { viewModel.dismissError() }) {
                    Text("ปิด")
                        .font(DSFont.font(DSFont.sCap, weight: .medium, scale: fontScale))
                        .foregroundColor(DSColor.t2)
                        .frame(minHeight: DSMetrics.touchSmall)
                }
                .buttonStyle(DSPressableStyle())
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, DSMetrics.screenPadding)
        .padding(.top, DSMetrics.s3)
    }

    // MARK: - พื้นที่ข้อความ

    private var messagesArea: some View {
        ScrollViewReader { proxy in
            GeometryReader { outer in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: DSMetrics.groupSpacing) {
                        if viewModel.hiddenMessageCount > 0 {
                            loadEarlierRow
                        }
                        ForEach(chatItems) { item in
                            switch item {
                            case .message(let message):
                                messageRow(message)
                            case .tools(let group):
                                activityGroupCard(group)
                            }
                        }
                        Color.clear
                            .frame(height: 1)
                            .id(bottomAnchorID)

                        GeometryReader { inner in
                            Color.clear.preference(
                                key: DSBottomDistanceKey.self,
                                value: inner.frame(in: .named("dsChatScroll")).minY - outer.size.height
                            )
                        }
                        .frame(height: 1)
                    }
                    .padding(.horizontal, DSMetrics.screenPadding)
                    .padding(.vertical, DSMetrics.s4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .coordinateSpace(name: "dsChatScroll")
                .onPreferenceChange(DSBottomDistanceKey.self) { distance in
                    // distance ≈ 0 = อยู่ท้ายสุด • distance > 0 = ผู้ใช้เลื่อนขึ้นไปอ่านข้างบนอยู่
                    // (ห้ามดึงหน้ากลับเองตามข้อกำหนด "ไม่แย่งการเลื่อนของผู้ใช้")
                    showsJumpToLatest = distance > 160
                }
                .overlay(alignment: .bottomTrailing) {
                    if showsJumpToLatest {
                        jumpToLatestButton(proxy: proxy)
                    }
                }
                .onChange(of: viewModel.messages.count) { _ in
                    guard !showsJumpToLatest else { return }
                    scrollToBottom(proxy: proxy, animated: true)
                }
            }
        }
    }

    private var loadEarlierRow: some View {
        Button(action: {
            DSHaptic.light()
            viewModel.loadEarlierMessages()
        }) {
            HStack(spacing: DSMetrics.s2) {
                Image(systemName: "arrow.up.circle")
                    .font(DSFont.font(DSFont.sCap, scale: fontScale))
                    .foregroundColor(DSColor.t2)
                    .accessibilityHidden(true)
                Text("โหลดข้อความก่อนหน้า \(viewModel.hiddenMessageCount) รายการ")
                    .font(DSFont.font(DSFont.sCap, scale: fontScale))
                    .foregroundColor(DSColor.t2)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, DSMetrics.s3)
            .frame(minHeight: DSMetrics.touch)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(DSColor.surface2))
            .contentShape(Rectangle())
        }
        .buttonStyle(DSPressableStyle())
        .accessibilityHint(Text("แสดงข้อความเก่าที่ซ่อนไว้"))
    }

    private func jumpToLatestButton(proxy: ScrollViewProxy) -> some View {
        Button(action: {
            DSHaptic.light()
            scrollToBottom(proxy: proxy, animated: true)
        }) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.down")
                    .font(DSFont.font(DSFont.sCap, weight: .semibold, scale: fontScale))
                Text("ข้อความใหม่")
                    .font(DSFont.font(DSFont.sCap, weight: .semibold, scale: fontScale))
                if center.isRunning {
                    DSStatusGlyph(status: .running, scale: fontScale)
                }
            }
            .foregroundColor(DSColor.onAccent)
            .padding(.horizontal, DSMetrics.s3)
            .frame(minHeight: DSMetrics.touchSmall)
            .background(Capsule().fill(DSColor.accent))
            .dsShadow(DSShadow.bar)
        }
        .buttonStyle(DSPressableStyle())
        .padding(.trailing, DSMetrics.screenPadding)
        .padding(.bottom, DSMetrics.s3)
        .accessibilityLabel(Text("ไปที่ข้อความล่าสุด"))
    }

    @ViewBuilder
    private func messageRow(_ message: ChatMessage) -> some View {
        switch message.role {
        case .user:
            userBubble(message)
        case .assistant:
            assistantBlock(message)
        case .tool:
            // ขั้นตอนของเครื่องมือวาดรวมเป็นการ์ดไทม์ไลน์ (ดู activityGroupCard) — ไม่วาดซ้ำที่นี่
            EmptyView()
        case .system:
            EmptyView()
        }
    }

    private func userBubble(_ message: ChatMessage) -> some View {
        HStack {
            Spacer(minLength: DSMetrics.s6)
            VStack(alignment: .trailing, spacing: DSMetrics.s2) {
                let attachments = message.attachments ?? []
                if !attachments.isEmpty {
                    VStack(alignment: .trailing, spacing: 6) {
                        ForEach(attachments) { attachment in
                            DSAttachmentChip(name: attachment.originalName,
                                             detail: DSFormat.bytes(attachment.byteSize),
                                             scale: fontScale)
                        }
                    }
                }
                if !message.text.isEmpty {
                    Text(message.text)
                        .font(DSFont.font(DSFont.sBody, scale: fontScale))
                        .lineSpacing(DSFont.lineSpacing(DSFont.sBody, scale: fontScale))
                        .foregroundColor(DSColor.t1)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, DSMetrics.s3)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: DSMetrics.rBubble, style: .continuous)
                                .fill(DSColor.accentSoft)
                        )
                        .textSelection(.enabled)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("คุณพูดว่า \(message.text)"))
    }

    @ViewBuilder
    private func assistantBlock(_ message: ChatMessage) -> some View {
        let isStreaming = viewModel.isThinking(messageID: message.id)
        if message.isTextEmpty && isStreaming {
            thinkingPlaceholder
        } else if !message.isTextEmpty {
            VStack(alignment: .leading, spacing: DSMetrics.s2) {
                DSMarkdownText(markdown: message.text,
                               color: DSColor.t1,
                               scale: fontScale)
                if isStreaming {
                    HStack(spacing: DSMetrics.s2) {
                        DSStatusGlyph(status: .running, scale: fontScale)
                        Text(center.liveLabel.isEmpty ? "กำลังพิมพ์คำตอบ" : center.liveLabel)
                            .font(DSFont.font(DSFont.sCap, scale: fontScale))
                            .foregroundColor(DSColor.t3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("Agent กำลังพิมพ์คำตอบ"))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var thinkingPlaceholder: some View {
        VStack(alignment: .leading, spacing: DSMetrics.s2) {
            HStack(spacing: DSMetrics.s2) {
                DSStatusGlyph(status: .running, scale: fontScale)
                Text(center.liveLabel.isEmpty ? ActivityKind.thinking.runningPhraseTH : center.liveLabel)
                    .font(DSFont.font(DSFont.sSub, scale: fontScale))
                    .foregroundColor(DSColor.t2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            DSSkeleton(lines: 2, scale: fontScale)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Agent กำลังทำงาน: \(center.liveLabel)"))
    }

    // MARK: - กลุ่มไทม์ไลน์ในแชท (ตรงกับแบบ: การ์ดเดียวต่อหนึ่งรอบ + แถวขั้นตอนแบบแบน)

    /// รายการที่จะวาดในแชท: ข้อความทั่วไป + กลุ่มขั้นตอนที่อยู่ติดกัน
    private var chatItems: [ChatStreamItem] {
        var items: [ChatStreamItem] = []
        var buffer: [ChatMessage] = []

        func flushBuffer() {
            guard !buffer.isEmpty else { return }
            items.append(.tools(ChatStreamItem.ToolGroup(messages: buffer)))
            buffer.removeAll()
        }

        for message in viewModel.visibleMessages {
            let isStep = message.role == .tool
            // ขั้นตอนของงานที่กำลังทำอยู่: แสดงผ่านแถบสถานะสด/ไทม์ไลน์ ไม่ซ้ำซ้อนในแชท
            let belongsToLiveRun = isStep && isPartOfLiveRun(message)
            if isStep && !belongsToLiveRun {
                buffer.append(message)
            } else {
                flushBuffer()
                if !belongsToLiveRun {
                    items.append(.message(message))
                }
            }
        }
        flushBuffer()
        return items
    }

    private func isPartOfLiveRun(_ message: ChatMessage) -> Bool {
        guard viewModel.isBusy else { return false }
        guard let startedAt = center.startedAt else { return true }
        return message.createdAt >= startedAt.addingTimeInterval(-1)
    }

    /// การ์ดไทม์ไลน์ของหนึ่งรอบการทำงาน (หัวการ์ดกาง/พับได้ แถวในกางแล้วกดดูรายละเอียดได้)
    private func activityGroupCard(_ group: ChatStreamItem.ToolGroup) -> some View {
        let expanded = expandedGroupID == group.id
        let failed = group.messages.filter { $0.toolIsError == true }.count

        var headParts: [String] = ["ทำเสร็จแล้ว \(group.stepCount) ขั้นตอน"]
        if failed > 0 { headParts.append("\(failed) ขั้นล้มเหลว") }

        return VStack(spacing: 0) {
            Button(action: {
                DSHaptic.light()
                withAnimation(DSMotion.card) {
                    expandedGroupID = expanded ? nil : group.id
                }
            }) {
                HStack(alignment: .center, spacing: DSMetrics.s3) {
                    DSRibbon(progress: 1.0,
                             tone: failed > 0 ? DSColor.warning : DSColor.success)
                        .frame(width: 54)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(headParts.joined(separator: " · "))
                            .font(DSFont.font(DSFont.sSub, weight: .semibold, scale: fontScale))
                            .foregroundColor(DSColor.t1)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Text("ใช้เวลา \(DSFormat.durationShort(group.totalDuration))")
                            .font(DSFont.font(DSFont.sMicro, scale: fontScale))
                            .foregroundColor(DSColor.t3)
                            .lineLimit(1)
                    }

                    Spacer(minLength: DSMetrics.s1)

                    Image(systemName: "chevron.down")
                        .font(DSFont.font(DSFont.sMicro, weight: .semibold, scale: fontScale))
                        .foregroundColor(DSColor.t3)
                        .rotationEffect(.degrees(expanded ? 0 : 180))
                }
                .padding(.horizontal, DSMetrics.s3)
                .frame(minHeight: 52)
                .contentShape(Rectangle())
            }
            .buttonStyle(DSPressableStyle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("\(headParts.joined(separator: " ")) · ใช้เวลา \(DSFormat.durationShort(group.totalDuration))"))
            .accessibilityHint(Text(expanded ? "แตะเพื่อพับรายการขั้นตอน" : "แตะเพื่อดูรายการขั้นตอนทั้งหมด"))

            if expanded {
                VStack(spacing: 0) {
                    ForEach(group.messages) { message in
                        toolStepRow(message)
                    }
                }
                .padding(.horizontal, DSMetrics.s3)
                .padding(.bottom, DSMetrics.s3)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: DSMetrics.rCard, style: .continuous).fill(DSColor.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DSMetrics.rCard, style: .continuous)
                .stroke(DSColor.border, lineWidth: 1)
        )
    }

    /// แถวขั้นตอนแบบแบนตามแบบ: วงกลม 22 + ชื่อขั้น 15 pt + บรรทัดย่อย + เวลาที่ใช้
    private func toolStepRow(_ message: ChatMessage) -> some View {
        Button(action: {
            DSHaptic.light()
            detailEvent = ActivityEvent.fromToolMessage(message)
            showDetailSheet = true
        }) {
            HStack(alignment: .top, spacing: DSMetrics.s3) {
                VStack(spacing: 0) {
                    DSStatusGlyph(status: message.toolIsError == true ? .failed : .succeeded,
                                  scale: fontScale)
                    Rectangle()
                        .fill(DSColor.border)
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                        .opacity(isLastStep(message) ? 0 : 1)
                }
                .frame(width: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text(message.toolDisplayName)
                        .font(DSFont.font(DSFont.sCallout, weight: .medium, scale: fontScale))
                        .foregroundColor(DSColor.t1)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(historySubtitle(message))
                        .font(DSFont.font(DSFont.sMicro, scale: fontScale))
                        .foregroundColor(DSColor.t3)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .padding(.top, 1)

                Spacer(minLength: DSMetrics.s1)

                if let duration = message.toolDuration {
                    Text(DSFormat.durationShort(duration))
                        .font(DSFont.font(DSFont.sMicro, scale: fontScale))
                        .foregroundColor(DSColor.t3)
                        .monospacedDigit()
                        .padding(.top, 3)
                }
            }
            .padding(.vertical, DSMetrics.s2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(DSPressableStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityForHistory(message)))
        .accessibilityHint(Text("แตะเพื่อดูรายละเอียดของขั้นนี้"))
    }

    private func isLastStep(_ message: ChatMessage) -> Bool {
        let steps = viewModel.visibleMessages.filter { $0.role == .tool }
        return steps.last?.id == message.id
    }

    private func historySubtitle(_ message: ChatMessage) -> String {
        if message.toolIsError == true { return "ขั้นนี้ไม่สำเร็จ — แตะเพื่อดูสาเหตุ" }
        if let duration = message.toolDuration, duration >= 1 {
            return "ใช้เวลา \(Int(duration.rounded())) วินาที — แตะเพื่อดูรายละเอียด"
        }
        return "สำเร็จ — แตะเพื่อดูรายละเอียด"
    }

    private func accessibilityForHistory(_ message: ChatMessage) -> String {
        let status = message.toolIsError == true ? "ไม่สำเร็จ" : "สำเร็จ"
        return "\(message.toolDisplayName) สถานะ\(status)"
    }

    // MARK: - ไทม์ไลน์ที่กางอยู่

    private var timelinePanel: some View {
        VStack(spacing: 0) {
            Divider()
            ScrollView {
                DSActivityTimeline(center: center,
                                   level: activityLevel,
                                   expandedEventID: $expandedEventID,
                                   onOpenDetail: { event in
                                       detailEvent = event
                                       showDetailSheet = true
                                   })
                    .padding(.vertical, DSMetrics.s2)
            }
            .frame(maxHeight: 260)
        }
        .background(DSColor.surface)
    }

    // MARK: - ช่องพิมพ์

    private var composerArea: some View {
        VStack(spacing: 0) {
            Divider()
            if !viewModel.pendingAttachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DSMetrics.s2) {
                        ForEach(viewModel.pendingAttachments) { attachment in
                            DSAttachmentChip(name: attachment.originalName,
                                             detail: DSFormat.bytes(attachment.byteSize),
                                             scale: fontScale,
                                             onRemove: { viewModel.removeAttachment(attachment) })
                        }
                    }
                    .padding(.horizontal, DSMetrics.screenPadding)
                    .padding(.vertical, DSMetrics.s2)
                }
            }
            if !viewModel.queuedMessages.isEmpty {
                queueArea
            }
            HStack(alignment: .bottom, spacing: DSMetrics.s2) {
                Button(action: {
                    DSHaptic.light()
                    showAttachmentPicker = true
                }) {
                    Image(systemName: "plus")
                        .font(DSFont.font(DSFont.sHead, weight: .semibold, scale: fontScale))
                        .foregroundColor(DSColor.t1)
                        .frame(width: DSMetrics.touch, height: DSMetrics.touch)
                        .contentShape(Rectangle())
                }
                .buttonStyle(DSPressableStyle())
                .accessibilityLabel(Text("แนบไฟล์หรือรูป"))

                ZStack(alignment: .topLeading) {
                    MultilineInputField(text: $inputText,
                                        height: $composerHeight,
                                        font: DSFont.uiFont(DSFont.sBody, scale: fontScale),
                                        minHeight: 20,
                                        maxHeight: (DSMetrics.isCompactWidth ? 88 : DSMetrics.composerMaxHeight) - 20,
                                        isEditable: true)
                        .frame(height: composerHeight)
                        .padding(.horizontal, DSFont.size(4, scale: fontScale))

                    if inputText.isEmpty {
                        Text(viewModel.isBusy
                             ? "พิมพ์ได้ — ข้อความจะต่อคิว"
                             : "พิมพ์บอก Agent ว่าจะให้ทำอะไร")
                            .font(DSFont.font(DSFont.sCallout, scale: fontScale))
                            .foregroundColor(DSColor.t3)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .padding(.horizontal, DSFont.size(4, scale: fontScale) + 5)
                            .padding(.top, 11)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
                .padding(.horizontal, DSMetrics.s2)
                .padding(.vertical, 11)
                .background(
                    RoundedRectangle(cornerRadius: DSMetrics.rComposer, style: .continuous)
                        .fill(DSColor.surface2)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DSMetrics.rComposer, style: .continuous)
                        .stroke(DSColor.border, lineWidth: 1)
                )

                if settings.voiceInputEnabled && !viewModel.isBusy {
                    Button(action: {
                        DSHaptic.light()
                        showVoiceSheet = true
                    }) {
                        Image(systemName: "mic.fill")
                            .font(DSFont.font(DSFont.sHead, scale: fontScale))
                            .foregroundColor(DSColor.t1)
                            .frame(width: DSMetrics.touch, height: DSMetrics.touch)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(DSPressableStyle())
                    .accessibilityLabel(Text("พูดแทนการพิมพ์"))
                    .accessibilityHint(Text("เปิดชีตโหมดเสียง แล้วนำข้อความมาใส่ในช่องพิมพ์"))
                }

                if viewModel.isBusy {
                    if canSend {
                        Button(action: send) {
                            Image(systemName: "text.badge.plus")
                                .font(DSFont.font(DSFont.sHead, scale: fontScale))
                                .foregroundColor(DSColor.onAccent)
                                .frame(width: DSMetrics.touch, height: DSMetrics.touch)
                                .background(Circle().fill(DSColor.accent))
                        }
                        .buttonStyle(DSPressableStyle())
                        .accessibilityLabel(Text("ต่อคิวข้อความนี้"))
                        .accessibilityHint(Text("ข้อความจะถูกส่งให้ Agent ทันทีที่งานนี้จบ"))
                    }
                    Button(action: {
                        DSHaptic.medium()
                        viewModel.stop()
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "stop.fill")
                                .font(DSFont.font(DSFont.sFoot, weight: .semibold, scale: fontScale))
                            Text("หยุด")
                                .font(DSFont.font(DSFont.sFoot, weight: .semibold, scale: fontScale))
                        }
                        .foregroundColor(DSColor.error)
                        .padding(.horizontal, DSMetrics.s3)
                        .frame(minHeight: DSMetrics.touch)
                        .background(Capsule().fill(DSColor.errorSoft))
                        .overlay(Capsule().stroke(DSColor.error.opacity(0.45), lineWidth: 1))
                    }
                    .buttonStyle(DSPressableStyle())
                    .accessibilityLabel(Text("หยุดงานนี้"))
                    .accessibilityHint(Text("Agent จะหยุดที่ขั้นปัจจุบัน ผลที่ทำแล้วจะถูกเก็บไว้"))
                } else {
                    Button(action: send) {
                        Image(systemName: "paperplane.fill")
                            .font(DSFont.font(DSFont.sHead, scale: fontScale))
                            .foregroundColor(DSColor.onAccent)
                            .frame(width: DSMetrics.touch, height: DSMetrics.touch)
                            .background(Circle().fill(canSend ? DSColor.accent : DSColor.surface3))
                    }
                    .buttonStyle(DSPressableStyle())
                    .disabled(!canSend)
                    .accessibilityLabel(Text("ส่งข้อความ"))
                    .accessibilityHint(Text(canSend ? "" : "พิมพ์ข้อความก่อน"))
                }
            }
            .padding(.horizontal, DSMetrics.screenPadding)
            .padding(.vertical, DSMetrics.s2)

            if !usage.hasData {
                emptySuggestions
            } else {
                usageLine
            }
        }
        .background(DSColor.surface)
    }

    /// ดีไซน์ v2: ส่งได้เสมอ — ถ้า Agent กำลังทำงาน ข้อความจะเข้าคิว (ไม่ปิดช่องพิมพ์)
    /// ชื่อห้องที่กำลังเปิด (ตามแบบ: หัวจอบอกว่าคุยเรื่องอะไร ไม่ใช่ชื่อแอป)
    private var currentRoomTitle: String {
        guard let id = viewModel.currentRoomID,
              let room = viewModel.rooms.first(where: { $0.id == id }) else {
            return "AI Agent"
        }
        return room.name
    }

    /// บรรทัดสถานะใต้ชื่อห้อง — แสดงเฉพาะตอนที่มีเรื่องต้องบอก (จริงจาก ActivityCenter เท่านั้น)
    private var headerAgentState: (text: String, tone: Color, isRunning: Bool)? {
        if let request = viewModel.pendingApproval {
            return ("รอคุณอนุญาต: \(request.thaiLabel)", DSColor.warning, false)
        }
        if center.isRunning {
            let label = center.liveLabel.isEmpty ? "กำลังทำงาน" : center.liveLabel
            return (label, DSColor.accent, true)
        }
        if !viewModel.queuedMessages.isEmpty {
            return ("มีข้อความรอส่ง \(viewModel.queuedMessages.count) ข้อความ", DSColor.accent, false)
        }
        if center.events.contains(where: { $0.status == .waitingUser }) {
            return ("Agent รอคำตอบจากคุณ", DSColor.warning, false)
        }
        return nil
    }

    private var headerAccessibilityLabel: String {
        if let state = headerAgentState {
            return "ห้อง \(currentRoomTitle) — \(state.text)"
        }
        return "ห้อง \(currentRoomTitle)"
    }

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// แถวคิวข้อความ — มองเห็นได้ตลอด ยกเลิกได้ทีละข้อความ และกด "ส่งเลย" ได้เมื่อไม่ได้ทำงานอยู่
    private var queueArea: some View {
        VStack(alignment: .leading, spacing: DSMetrics.s2) {
            HStack(spacing: DSMetrics.s2) {
                Image(systemName: "clock")
                    .font(DSFont.font(DSFont.sCap, scale: fontScale))
                    .foregroundColor(DSColor.accentInk)
                    .accessibilityHidden(true)
                Text(viewModel.isBusy
                     ? "รอส่งหลังงานนี้จบ (\(viewModel.queuedMessages.count))"
                     : "มีข้อความรอส่ง (\(viewModel.queuedMessages.count))")
                    .font(DSFont.font(DSFont.sCap, weight: .semibold, scale: fontScale))
                    .foregroundColor(DSColor.t1)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if !viewModel.isBusy {
                    Button(action: {
                        DSHaptic.medium()
                        viewModel.flushQueue()
                    }) {
                        Text("ส่งเลย")
                            .font(DSFont.font(DSFont.sCap, weight: .semibold, scale: fontScale))
                            .foregroundColor(DSColor.accentInk)
                            .frame(minHeight: DSMetrics.touchSmall)
                    }
                    .buttonStyle(DSPressableStyle())
                    .accessibilityLabel(Text("ส่งข้อความที่รออยู่ตอนนี้"))
                }
            }

            ForEach(viewModel.queuedMessages) { item in
                HStack(alignment: .top, spacing: DSMetrics.s2) {
                    Text(item.preview)
                        .font(DSFont.font(DSFont.sCap, scale: fontScale))
                        .foregroundColor(DSColor.t2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button(action: {
                        DSHaptic.light()
                        viewModel.removeQueuedMessage(id: item.id)
                    }) {
                        Image(systemName: "xmark")
                            .font(DSFont.font(DSFont.sMicro, weight: .semibold, scale: fontScale))
                            .foregroundColor(DSColor.t3)
                            .frame(width: DSMetrics.touchSmall, height: DSMetrics.touchSmall)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(DSPressableStyle())
                    .accessibilityLabel(Text("ยกเลิกข้อความนี้จากคิว"))
                }
                .padding(.horizontal, DSMetrics.s3)
                .padding(.vertical, DSMetrics.s1)
                .background(RoundedRectangle(cornerRadius: DSMetrics.rChip, style: .continuous).fill(DSColor.surface2))
            }
        }
        .padding(.horizontal, DSMetrics.screenPadding)
        .padding(.top, DSMetrics.s2)
    }

#if DEBUG
    /// จัดฉากหน้าจอตาม launch argument เพื่อถ่ายภาพตรวจงานออกแบบ (เฉพาะบิลด์ Debug)
    private func applyPreview(_ screen: String) {
        switch screen {
        case "chat":
            center.previewSeed(events: UIPreview.events(), running: false, liveLabel: "",
                               finishedTitle: "ทำเสร็จแล้ว",
                               startedAt: Date().addingTimeInterval(-96), elapsed: 15)
            viewModel.previewSeed(messages: UIPreview.messages(finished: true),
                                  isBusy: false, statusText: "", approval: nil)
        case "chat-open":
            applyPreview("chat")
            expandedGroupID = viewModel.visibleMessages.first(where: { $0.role == .tool })?.id.uuidString
        case "running":
            center.previewSeed(events: UIPreview.runningEvents(), running: true,
                               liveLabel: "กำลังอ่านหน้าเว็บที่เกี่ยวข้อง", finishedTitle: "",
                               startedAt: Date().addingTimeInterval(-24), elapsed: 24)
            viewModel.previewSeed(messages: UIPreview.messages(finished: false),
                                  isBusy: true, statusText: "กำลังอ่านหน้าเว็บ", approval: nil)
            timelineExpanded = true
        case "approval":
            center.previewSeed(events: UIPreview.runningEvents(), running: true,
                               liveLabel: "รอคุณอนุญาต: ลบไฟล์", finishedTitle: "",
                               startedAt: Date().addingTimeInterval(-40), elapsed: 40)
            viewModel.previewSeed(messages: UIPreview.messages(finished: false),
                                  isBusy: true, statusText: "รออนุมัติ",
                                  approval: UIPreview.approvalRequest())
        case "detail":
            applyPreview("chat")
            detailEvent = UIPreview.events().first(where: { $0.kind == .fileWrite }) ?? UIPreview.events().first
            showDetailSheet = true
        default:
            break
        }
    }
#endif

    /// รับคำสั่ง/ไฟล์ที่ส่งมาจากแท็บอื่น (เช่น "ให้ Agent แก้ไฟล์นี้" จากหน้าดูไฟล์)
    private func handlePendingPromptIfNeeded() {
        guard let pending = router.consumePendingPrompt() else { return }
        if let path = pending.attachmentPath {
            attachFile(atPath: path)
        }
        guard !pending.prompt.isEmpty else { return }
        if viewModel.isBusy {
            viewModel.queueMessage(pending.prompt)
        } else if !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            inputText += "\n" + pending.prompt
        } else {
            center.beginRun(title: pending.prompt)
            viewModel.send(pending.prompt)
        }
    }

    /// แนบไฟล์ที่มีอยู่แล้วบนเครื่อง (ใช้กับ "ให้ Agent แก้ไฟล์นี้")
    private func attachFile(atPath path: String) {
        let store = AttachmentStore(rootPath: settings.uploadsPath)
        let maxBytes = Int(settings.maxDownloadBytes)
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let attachment = try store.importFile(at: URL(fileURLWithPath: path), maxBytes: maxBytes)
                DispatchQueue.main.async {
                    viewModel.addAttachments([attachment])
                }
            } catch {
                DispatchQueue.main.async {
                    viewModel.showNotice("แนบไฟล์ไม่สำเร็จ: \(error.localizedDescription)")
                }
            }
        }
    }

    private var emptySuggestions: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DSMetrics.s2) {
                ForEach(QuickPromptsView.defaultPrompts(workspacePath: settings.workspacePath)) { prompt in
                    Button(action: {
                        DSHaptic.light()
                        inputText = prompt.text
                    }) {
                        Text(prompt.title)
                            .font(DSFont.font(DSFont.sCap, weight: .medium, scale: fontScale))
                            .foregroundColor(DSColor.accentInk)
                            .padding(.horizontal, DSMetrics.s3)
                            .frame(minHeight: DSMetrics.touchSmall)
                            .background(Capsule().fill(DSColor.accentSoft))
                    }
                    .buttonStyle(DSPressableStyle())
                    .accessibilityLabel(Text(prompt.title))
                    .accessibilityHint(Text(prompt.detail))
                }
            }
            .padding(.horizontal, DSMetrics.screenPadding)
            .padding(.bottom, DSMetrics.s2)
        }
    }

    private var usageLine: some View {
        HStack(spacing: DSMetrics.s2) {
            Image(systemName: "chart.bar.doc.horizontal")
                .font(DSFont.font(DSFont.sMicro, scale: fontScale))
                .foregroundColor(DSColor.t3)
                .accessibilityHidden(true)
            Text("ใช้ไป \(usage.compactShortText)\(costSuffix)")
                .font(DSFont.font(DSFont.sMicro, scale: fontScale))
                .foregroundColor(DSColor.t3)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DSMetrics.screenPadding)
        .padding(.bottom, DSMetrics.s2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("การใช้โทเคนของห้องนี้: \(usage.compactShortText)\(costSuffix)"))
    }

    /// ค่าใช้จ่ายแสดงเฉพาะเมื่อผู้ให้บริการส่งตัวเลขจริงมา ไม่มีการประมาณเอง
    private var costSuffix: String {
        if let cost = usage.costCredits {
            return String(format: " · %.4f เครดิต", cost)
        }
        return " · ค่าใช้จ่ายไม่ระบุ"
    }

    // MARK: - การกระทำ

    private func send() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""
        composerHeight = 38
        expandedEventID = nil
        if viewModel.isBusy {
            // กำลังทำงานอยู่ → ต่อคิว (ไทม์ไลน์รอบใหม่จะเริ่มเองเมื่อข้อความถูกส่งจริง)
            viewModel.queueMessage(text)
            return
        }
        center.beginRun(title: text)
        viewModel.send(text)
    }

    /// เปิดห้องตามคำขอจากที่อื่น (แตะการแจ้งเตือน หรือกดจากหน้า "งานของฉัน")
    private func openPendingRoomIfNeeded() {
        guard let roomID = router.pendingRoomID else { return }
        router.consumePendingRoom()
        guard viewModel.currentRoomID != roomID,
              let room = viewModel.rooms.first(where: { $0.id == roomID }) else { return }
        viewModel.selectRoom(room)
    }

    private var systemPausedBanner: some View {
        DSBanner(tone: .warning,
                 title: "ระบบหยุดงานชั่วคราว",
                 message: "iOS ไม่ให้แอปทำงานเบื้องหลังได้นาน งานจึงหยุดที่ขั้นล่าสุด — ผลที่ทำไว้แล้วยังอยู่ครบ",
                 scale: fontScale) {
            HStack(spacing: DSMetrics.s3) {
                Button(action: continueAfterSystemPause) {
                    Text("ให้ Agent ทำต่อจากจุดนี้")
                        .font(DSFont.font(DSFont.sCap, weight: .semibold, scale: fontScale))
                        .foregroundColor(DSColor.warning)
                        .frame(minHeight: DSMetrics.touchSmall)
                }
                .buttonStyle(DSPressableStyle())

                Button(action: {
                    DSHaptic.light()
                    withAnimation(DSMotion.card) { showSystemPausedBanner = false }
                }) {
                    Text("ไว้ก่อน")
                        .font(DSFont.font(DSFont.sCap, weight: .medium, scale: fontScale))
                        .foregroundColor(DSColor.t2)
                        .frame(minHeight: DSMetrics.touchSmall)
                }
                .buttonStyle(DSPressableStyle())
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, DSMetrics.screenPadding)
        .padding(.top, DSMetrics.s3)
    }

    private func continueAfterSystemPause() {
        DSHaptic.medium()
        withAnimation(DSMotion.card) { showSystemPausedBanner = false }
        guard !viewModel.isBusy else { return }
        center.beginRun()
        inputText = ""
        composerHeight = 38
        viewModel.send("งานก่อนหน้าถูก iOS ระงับกลางทาง ช่วยทำต่อจากจุดที่ค้างไว้ โดยใช้ผลลัพธ์ที่ทำเสร็จแล้ว ไม่ต้องเริ่มใหม่ทั้งหมด")
    }

    private func scrollToBottom(proxy: ScrollViewProxy, animated: Bool) {
        if animated {
            withAnimation(DSMotion.card) {
                proxy.scrollTo(bottomAnchorID, anchor: .bottom)
            }
        } else {
            proxy.scrollTo(bottomAnchorID, anchor: .bottom)
        }
    }

    private var approvalBinding: Binding<ApprovalRequest?> {
        Binding(get: { viewModel.pendingApproval },
                set: { newValue in
                    if newValue == nil, viewModel.pendingApproval != nil {
                        viewModel.resolveApproval(.deny)
                    }
                })
    }
}
