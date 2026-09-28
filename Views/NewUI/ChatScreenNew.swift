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
    @Environment(\.scenePhase) private var scenePhase

    private let bottomAnchorID = "ds-chat-bottom"

    private var activityLevel: ActivityDetailLevel {
        ActivityDetailLevel(rawValue: activityLevelRaw) ?? .normal
    }

    var body: some View {
        VStack(spacing: 0) {
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
        .navigationTitle("AI Agent")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button(action: { showRooms = true }) {
                        Label("ห้องสนทนา", systemImage: "bubble.left.and.bubble.right")
                    }
                    Button(action: { center.clear(); timelineExpanded = false }) {
                        Label("ล้างไทม์ไลน์ของงานนี้", systemImage: "clock.arrow.circlepath")
                    }
                    Divider()
                    Button(action: { showClearConfirmation = true }) {
                        Label("ล้างการสนทนาทั้งหมด", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(DSFont.font(DSFont.sHead, scale: fontScale))
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
        }
        .onChange(of: scenePhase) { phase in
            if phase != .active {
                viewModel.persistNow()
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
                        ForEach(viewModel.visibleMessages) { message in
                            messageRow(message)
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
            toolHistoryRow(message)
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
                MessageContentView(markdown: message.text,
                                   textColor: DSColor.t1,
                                   fontScale: fontScale)
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

    /// ประวัติการเรียกเครื่องมือ — แถวเดียวต่อหนึ่งครั้ง กดดูรายละเอียดเต็มได้
    private func toolHistoryRow(_ message: ChatMessage) -> some View {
        Button(action: {
            DSHaptic.light()
            detailEvent = ActivityEvent.fromToolMessage(message)
            showDetailSheet = true
        }) {
            HStack(alignment: .center, spacing: DSMetrics.s3) {
                DSIconBadge(icon: ActivityKind.from(toolName: message.name ?? "").symbolName,
                            tint: DSColor.t2,
                            background: DSColor.surface2,
                            size: 26,
                            scale: fontScale)
                VStack(alignment: .leading, spacing: 2) {
                    Text(message.toolDisplayName)
                        .font(DSFont.font(DSFont.sCap, weight: .medium, scale: fontScale))
                        .foregroundColor(DSColor.t2)
                        .lineLimit(1)
                    Text(historySubtitle(message))
                        .font(DSFont.font(DSFont.sMicro, scale: fontScale))
                        .foregroundColor(DSColor.t3)
                        .lineLimit(1)
                }
                Spacer(minLength: DSMetrics.s2)
                DSStatusLabel(status: message.toolIsError == true ? .failed : .succeeded,
                              scale: fontScale,
                              showsText: false)
            }
            .padding(.horizontal, DSMetrics.s3)
            .frame(minHeight: DSMetrics.touch)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(DSColor.surface2))
            .contentShape(Rectangle())
        }
        .buttonStyle(DSPressableStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityForHistory(message)))
        .accessibilityHint(Text("แตะเพื่อดูรายละเอียดของขั้นนี้"))
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
                                        minHeight: 22,
                                        maxHeight: DSMetrics.composerMaxHeight - 22,
                                        isEditable: true)
                        .frame(height: composerHeight)
                        .padding(.horizontal, DSFont.size(4, scale: fontScale))

                    if inputText.isEmpty {
                        Text(viewModel.isBusy ? "Agent กำลังทำงาน — กดหยุดได้ทุกเมื่อ" : "พิมพ์บอก Agent ว่าจะให้ทำอะไร")
                            .font(DSFont.font(DSFont.sBody, scale: fontScale))
                            .foregroundColor(DSColor.t3)
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

                if viewModel.isBusy {
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

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !viewModel.isBusy
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
            return String(format: " · ค่าใช้จ่าย %.4f เครดิต", cost)
        }
        return " · ค่าใช้จ่าย: ไม่ระบุ"
    }

    // MARK: - การกระทำ

    private func send() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !viewModel.isBusy else { return }
        inputText = ""
        composerHeight = 38
        expandedEventID = nil
        center.beginRun()
        viewModel.send(text)
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
