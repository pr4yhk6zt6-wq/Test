//
//  ChatView.swift
//  iOS Agent Sandbox
//
//  เฟส 2: แชทกับ Agent ที่ใช้ tools ได้จริง
//  - bubble ข้อความ, สถานะ "กำลังคิด/กำลังใช้ tool", ปุ่มส่ง/หยุด, Token Usage
//  - การ์ดแสดงการทำงานของ tool 9 ตัว (อ่าน/เขียนไฟล์, shell, ค้นหาเว็บ, ดาวน์โหลด ฯลฯ)
//  - หน้าต่างขออนุมัติก่อน Agent รันคำสั่ง shell หรือเขียนทับไฟล์สำคัญ
//  - ตรวจสิทธิ์การเข้าถึงไฟล์ตอนเปิดแอป และแจ้งถ้าต้อง TrollStore/palera1n
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// ไฟล์ที่รอแชร์ผ่าน Share Sheet (เฟส 5)
struct ShareableURL: Identifiable {
    let id = UUID()
    let url: URL
}

struct ChatView: View {

    @StateObject private var viewModel = ChatViewModel()
    @EnvironmentObject private var settings: AppSettings
    @ObservedObject private var usage: TokenUsageTracker = .shared

    @AppStorage(SettingsKeys.chatFontScale) private var chatFontScale: Double = 1.0

    @ObservedObject private var router = AppRouter.shared

    @State private var inputText: String = ""
    @State private var showClearConfirmation: Bool = false
    @State private var showAttachmentPicker: Bool = false
    @State private var showRooms: Bool = false
    @State private var exportFile: ShareableURL?
    @State private var shareText: ShareableText?
    @State private var accessReport: SystemAccessReport?
    @State private var showAccessNotice: Bool = false
    @State private var autoScrollEnabled: Bool = true
    @State private var composerHeight: CGFloat = 38
    @Environment(\.scenePhase) private var scenePhase

    private let bottomAnchorID = "chat-bottom-anchor"

    var body: some View {
        VStack(spacing: 0) {
            if showAccessNotice, let report = accessReport {
                accessBanner(report: report)
            }
            messagesArea
            Divider()
            usageBar
            composerArea
        }
        .navigationTitle("AI Agent")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        showRooms = true
                    } label: {
                        Label("ห้องสนทนา", systemImage: "bubble.left.and.bubble.right")
                    }
                    Button {
                        if let url = viewModel.exportMarkdownURL() { exportFile = ShareableURL(url: url) }
                    } label: {
                        Label("ส่งออกเป็น Markdown (.md)", systemImage: "doc.text")
                    }
                    .disabled(viewModel.messages.isEmpty)
                    Button {
                        if let url = viewModel.exportJSONURL() { exportFile = ShareableURL(url: url) }
                    } label: {
                        Label("ส่งออกเป็น JSON (.json)", systemImage: "curlybraces")
                    }
                    .disabled(viewModel.messages.isEmpty)
                    Button {
                        showClearConfirmation = true
                    } label: {
                        Label("ล้างการสนทนา", systemImage: "trash")
                    }
                    Button {
                        shareText = ShareableText(text: transcriptText())
                    } label: {
                        Label("แชร์บทสนทนา", systemImage: "square.and.arrow.up")
                    }
                    .disabled(viewModel.messages.isEmpty)
                    Button {
                        viewModel.stop()
                    } label: {
                        Label("หยุดงานที่กำลังทำ", systemImage: "stop.circle")
                    }
                    .disabled(!viewModel.isBusy)
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("เมนูเพิ่มเติม")
            }
        }
        .onAppear {
            checkSystemAccess()
            handlePendingRouterPrompt()
        }
        .onChange(of: router.pendingPrompt) { _ in
            handlePendingRouterPrompt()
        }
        .sheet(item: $shareText) { item in
            ShareSheet(items: [item.text])
        }
        .sheet(item: $exportFile) { item in
            ShareSheet(items: [item.url])
        }
        .sheet(isPresented: $showAttachmentPicker) {
            AttachmentPickerSheet(maxBytes: Int(settings.maxDownloadBytes),
                                  onImported: { attachments in
                                      showAttachmentPicker = false
                                      viewModel.addAttachments(attachments)
                                  },
                                  onPasteText: { text in
                                      showAttachmentPicker = false
                                      if inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                          inputText = text
                                      } else {
                                          inputText += "\n" + text
                                      }
                                  },
                                  onMessage: { message in
                                      showAttachmentPicker = false
                                      viewModel.showNotice(message)
                                  })
        }
        .sheet(isPresented: $showRooms) {
            ChatRoomsView(viewModel: viewModel)
        }
        .sheet(item: approvalBinding) { request in
            ApprovalSheetView(request: request) { decision in
                viewModel.resolveApproval(decision)
            }
        }
        .onChange(of: scenePhase) { phase in
            // แอปถูกพัก → บันทึกประวัติทันที (ไม่รอ debounce)
            if phase != .active {
                viewModel.persistNow()
            }
        }
        .confirmationDialog("ล้างการสนทนาทั้งหมด?", isPresented: $showClearConfirmation, titleVisibility: .visible) {
            Button("ล้างทั้งหมด", role: .destructive) {
                viewModel.clearConversation()
            }
            Button("ยกเลิก", role: .cancel) { }
        } message: {
            Text("ข้อความทั้งหมดจะถูกลบทั้งจากหน้าจอและจากไฟล์ประวัติที่บันทึกไว้บนเครื่อง")
        }
    }

    // MARK: - พื้นที่แสดงข้อความ

    private var messagesArea: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .bottomTrailing) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        if viewModel.messages.isEmpty {
                            emptyState
                        }
                        ForEach(viewModel.messages) { message in
                            if message.isToolResult {
                                ToolActivityView(message: message,
                                                 fontScale: chatFontScale,
                                                 onShare: { text in shareText = ShareableText(text: text) })
                                    .id(message.id)
                            } else {
                                MessageBubbleView(message: message,
                                                  fontScale: chatFontScale,
                                                  isThinking: viewModel.isThinking(messageID: message.id),
                                                  onDelete: { delete(message) },
                                                  onShare: { text in shareText = ShareableText(text: text) })
                                    .id(message.id)
                            }
                        }
                        statusRow
                        noticeRow
                        errorRow
                        Color.clear
                            .frame(height: 1)
                            .id(bottomAnchorID)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
                .simultaneousGesture(
                    DragGesture().onChanged { value in
                        // ลากขึ้น = ผู้ใช้กำลังอ่านข้อความเก่า → หยุด auto-scroll
                        if value.translation.height > 12 {
                            autoScrollEnabled = false
                        }
                    }
                )
                .onChange(of: viewModel.messages.count) { _ in
                    autoScrollEnabled = true
                    scrollToBottom(proxy: proxy, animated: true)
                }
                .onChange(of: viewModel.messages.last?.text) { _ in
                    guard autoScrollEnabled else { return }
                    scrollToBottom(proxy: proxy, animated: false)
                }

                if !autoScrollEnabled {
                    Button {
                        autoScrollEnabled = true
                        scrollToBottom(proxy: proxy, animated: true)
                    } label: {
                        Label("ไปข้อความล่าสุด", systemImage: "arrow.down.circle.fill")
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .frame(minHeight: 44)
                            .background(
                                Capsule().fill(Color(UIColor.secondarySystemBackground))
                            )
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 12)
                    .padding(.bottom, 8)
                    .shadow(radius: 2)
                    .accessibilityLabel("เลื่อนไปข้อความล่าสุด")
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("เริ่มสนทนากับ Agent", systemImage: "sparkles")
                .font(.headline)
            Text("Agent ตอบตามภาษาที่คุณพิมพ์ และทำงานได้จริงบนเครื่อง: อ่าน/เขียนไฟล์, สำรวจโฟลเดอร์, ค้นหาไฟล์, รันคำสั่ง shell, เรียก HTTP, ดาวน์โหลดไฟล์, ค้นหาเว็บ และดึงเนื้อหาหน้าเว็บ • โหมดอนุมัติเปิดอยู่ ค่าเริ่มต้นจะถามก่อนทำสิ่งที่เปลี่ยนเครื่อง")
                .font(.footnote)
                .foregroundColor(.secondary)
            QuickPromptsView(prompts: QuickPromptsView.defaultPrompts(workspacePath: settings.workspacePath),
                             onSelect: { prompt in
                                 inputText = prompt.text
                             })

            if !settings.hasAPIKey || settings.modelID.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Label("ยังต้องตั้งค่าให้ครบ", systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.orange)
                    Text(!settings.hasAPIKey ? "• ยังไม่มี API Key" : "• ยังไม่ได้เลือกโมเดล")
                        .font(.footnote)
                    Text("ไปที่แท็บ \"ตั้งค่า\" เพื่อใส่ API Key และ Model ID")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.orange.opacity(0.12))
                )
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(UIColor.secondarySystemBackground))
        )
    }

    @ViewBuilder
    private var statusRow: some View {
        if viewModel.isBusy {
            HStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.8)
                Text(viewModel.statusText.isEmpty ? "กำลังทำงาน…" : viewModel.statusText)
                    .font(.footnote)
                    .foregroundColor(.secondary)
                Spacer(minLength: 0)
                if viewModel.backgroundKeeper.isActive {
                    Label("ทำงานเบื้องหลัง", systemImage: "clock.arrow.circlepath")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 4)
        }
    }

    @ViewBuilder
    private var noticeRow: some View {
        if let notice = viewModel.lastNotice {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "info.circle")
                    .font(.caption)
                Text(notice)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button {
                    viewModel.dismissNotice()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("ปิดข้อความแจ้งเตือน")
            }
            .foregroundColor(.secondary)
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(UIColor.tertiarySystemBackground))
            )
        }
    }

    @ViewBuilder
    private var errorRow: some View {
        if let error = viewModel.errorMessage {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "xmark.octagon.fill")
                        .font(.caption)
                    Text(error)
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button {
                        viewModel.dismissError()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("ปิดข้อความผิดพลาด")
                }
                if viewModel.canRetryLastRun {
                    Button {
                        viewModel.retryLastFailedRun()
                    } label: {
                        Label("ลองส่งอีกครั้ง", systemImage: "arrow.clockwise")
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.red.opacity(0.15))
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("ลองส่งข้อความเดิมอีกครั้ง")
                }
            }
            .foregroundColor(.red)
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.red.opacity(0.10))
            )
        }
    }

    // MARK: - แถบ Token Usage

    private var usageBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(usage.hasData ? "Token – \(usage.compactShortText)" : "Token – ยังไม่มีข้อมูล")
                .font(.caption2.monospacedDigit())
                .foregroundColor(.secondary)
                .lineLimit(1)
            if viewModel.usedRounds > 0 {
                Text("• รอบ \(viewModel.usedRounds)/\(AgentEngine.maximumToolRounds)")
                    .font(.caption2.monospacedDigit())
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Text(settings.modelID.isEmpty ? "ยังไม่เลือกโมเดล" : settings.modelID)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 28)
        .background(Color(UIColor.tertiarySystemBackground))
        .accessibilityElement(children: .combine)
    }

    // MARK: - ช่องพิมพ์

    /// พื้นที่ด้านล่าง: ชิปไฟล์แนบ (ถ้ามี) + ช่องพิมพ์
    private var composerArea: some View {
        VStack(spacing: 6) {
            if !viewModel.pendingAttachments.isEmpty {
                AttachmentChipRow(attachments: viewModel.pendingAttachments,
                                  onRemove: { attachment in
                                      viewModel.removeAttachment(attachment)
                                  },
                                  onTap: nil)
                    .padding(.horizontal, 12)
                    .padding(.top, 6)
            }
            composerBar
        }
    }

    private var composerBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Button {
                showAttachmentPicker = true
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 27))
                    .foregroundColor(.accentColor)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("แนบไฟล์หรือรูปภาพ")

            ZStack(alignment: .topLeading) {
                if inputText.isEmpty {
                    Text("พิมพ์คำสั่ง…")
                        .font(.system(size: 16 * chatFontScale))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 14)
                        .allowsHitTesting(false)
                }
                MultilineInputField(text: $inputText,
                                    height: $composerHeight,
                                    font: InputFontProvider.font(scale: chatFontScale),
                                    minHeight: 38,
                                    maxHeight: 118,
                                    isEditable: !viewModel.isBusy)
                    .frame(height: composerHeight)
                    .padding(.horizontal, 5)
            }
            .frame(minHeight: 44)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(UIColor.secondarySystemBackground))
            )

            if viewModel.isBusy {
                Button {
                    viewModel.stop()
                } label: {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 30))
                        .foregroundColor(.red)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("หยุด")
            } else {
                Button {
                    sendCurrentInput()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 30))
                        .foregroundColor(canSend ? .accentColor : .gray)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .accessibilityLabel("ส่งข้อความ")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(UIColor.systemBackground))
    }

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !viewModel.isBusy
    }

    // MARK: - แบนเนอร์แจ้งสิทธิ์

    private func accessBanner(report: SystemAccessReport) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "lock.shield.fill")
                    .font(.footnote)
                Text("ยังเข้าถึงไฟล์ทั้งเครื่องไม่ได้")
                    .font(.footnote.weight(.semibold))
                Spacer(minLength: 0)
                Button {
                    showAccessNotice = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("ปิดคำแนะนำ")
            }
            Text("อ่าน /var/mobile ไม่ได้ แปลว่าแอปถูกจำกัดด้วย sandbox — ต้องติดตั้งผ่าน TrollStore (พร้อม entitlements no-sandbox) หรือเจลเบรคเครื่องด้วย palera1n แล้วรันแอปเป็น root")
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
            Text(report.summaryMessage)
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.yellow.opacity(0.18))
    }

    // MARK: - Binding ของหน้าต่างอนุมัติ

    /// หน้าต่างอนุมัติผูกกับ pendingApproval ของ view model
    /// ถ้าผู้ใช้ปัดปิดหน้าต่างเอง (ไม่กดปุ่ม) ถือว่า "ไม่อนุญาต" เพื่อความปลอดภัย
    private var approvalBinding: Binding<ApprovalRequest?> {
        Binding(get: { viewModel.pendingApproval },
                set: { newValue in
                    if newValue == nil, viewModel.pendingApproval != nil {
                        viewModel.resolveApproval(.deny)
                    }
                })
    }

    // MARK: - Actions

    private func sendCurrentInput() {
        let text = inputText
        inputText = ""
        viewModel.send(text)
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }

    private func delete(_ message: ChatMessage) {
        // ลบออกจากหน้าจอและจากไฟล์ประวัติที่บันทึกไว้ (บันทึกอัตโนมัติหลังลบ)
        withAnimation {
            viewModel.remove(message: message)
        }
    }

    /// รับคำสั่งที่ส่งมาจากแท็บอื่น (เช่น "ให้ Agent แก้ไฟล์นี้" จากหน้าดูไฟล์)
    private func handlePendingRouterPrompt() {
        guard let pending = router.consumePendingPrompt() else { return }
        if inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            inputText = pending.prompt
        } else {
            inputText += "\n" + pending.prompt
        }
        if let path = pending.attachmentPath {
            attachFile(atPath: path)
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

    private func scrollToBottom(proxy: ScrollViewProxy, animated: Bool) {
        if animated {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(bottomAnchorID, anchor: .bottom)
            }
        } else {
            proxy.scrollTo(bottomAnchorID, anchor: .bottom)
        }
    }

    private func checkSystemAccess() {
        let report = SystemAccessChecker.check()
        accessReport = report
        showAccessNotice = report.needsJailbreakNotice
    }

    private func transcriptText() -> String {
        viewModel.messages.map { message in
            switch message.role {
            case .user: return "ผู้ใช้: \(message.text)"
            case .assistant: return "Agent: \(message.text)"
            case .system: return "ระบบ: \(message.text)"
            case .tool: return "tool \(message.name ?? ""): \(message.text)"
            }
        }
        .joined(separator: "\n\n")
    }
}
