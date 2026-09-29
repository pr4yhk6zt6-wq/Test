//
//  AGTasksScreen.swift
//  AgentApp — "งานของฉัน" (พอร์ตจาก phase3: งานที่กำลังทำ · รอคำตอบ · ข้อความรอส่ง · ประวัติงาน)
//
//  ความซื่อสัตย์ที่ยึดถือ: งานที่ค้างตอนแอปถูกปิดจะขึ้นว่า "ถูกปิดกลางทาง" เสมอ (จาก TaskRegistry)
//  ไม่มีตัวเลขประมาณการเวลา และไม่มีงานตามเวลาที่กดแล้วไม่ทำงานจริง
//

import SwiftUI

struct AGTasksScreen: View {

    @ObservedObject private var center: ActivityCenter = .shared
    @ObservedObject private var queue: PendingMessageQueue = .shared
    @ObservedObject private var notifier: AgentNotifier = .shared
    @ObservedObject private var connectivity: ConnectivityMonitor = .shared
    @ObservedObject private var router: AppRouter = .shared

    @AppStorage(SettingsKeys.chatFontScale) private var fontScale: Double = 1

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AGMetric.s5) {
                statusLine

#if DEBUG
                // ภาพตรวจแบบ: ข้ามส่วนบนเพื่อให้เห็นประวัติงานถาวรได้ในจอเดียว
                if AGPreview.screen == "tasks-history" {
                    registrySection
                    scheduledSection
                    logSection
                    return
                }
#endif

                if !connectivity.isConnected {
                    AGBanner(tone: .warning,
                             title: "ตอนนี้อินเทอร์เน็ตขาด",
                             message: "งานที่ต้องต่อเน็ตจะหยุดชั่วคราว ผลที่ทำไว้แล้วยังอยู่ครบ และทำต่อได้เมื่อสัญญาณกลับมา",
                             scale: fontScale)
                }

                if !notifier.isEnabled { notificationCard }

                currentSection
                waitingSection
                queuedSection
                if !isHistoryPreview {
                    registrySection
                    scheduledSection
                    logSection
                }
            }
            .padding(.horizontal, AGMetric.screenPadding)
            .padding(.vertical, AGMetric.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(AGColor.bg)
        .navigationTitle("งานของฉัน")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { center.reloadTasks() }
    }

    private var isHistoryPreview: Bool {
#if DEBUG
        return AGPreview.screen == "tasks-history"
#else
        return false
#endif
    }

    /// บรรทัดสถานะใต้ชื่อหน้า — ตัวเลขจริงจากทะเบียนงานและคิวเท่านั้น
    private var statusLine: some View {
        HStack(spacing: AGMetric.s2) {
            if center.isRunning {
                AGPulseDot(tone: AGColor.accent, size: 12)
            } else {
                Circle()
                    .fill(attentionCount > 0 ? AGColor.warning : AGColor.success)
                    .frame(width: 8, height: 8)
            }
            Text(statusText)
                .font(AGFont.font(AGFont.sub, weight: .semibold, scale: fontScale))
                .foregroundColor(AGColor.t1)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(statusText))
    }

    private var attentionCount: Int {
        center.tasks.filter { $0.outcome == .needsAnswer || $0.outcome == .running }.count
            + center.events.filter { $0.status == .waitingUser }.count
    }

    private var statusText: String {
        let running = center.isRunning ? 1 : 0
        if running > 0 {
            let queued = queue.items.count
            return queued > 0 ? "กำลังทำ \(running) งาน · รอคิว \(queued) งาน" : "กำลังทำ \(running) งาน"
        }
        if attentionCount > 0 { return "มี \(attentionCount) เรื่องรอคุณ" }
        return "ไม่มีงานกำลังทำ"
    }

    // MARK: - แจ้งเตือน (ชี้ชวนตามบริบท ไม่กดดัน)

    private var notificationCard: some View {
        AGCard(padding: AGMetric.s4) {
            VStack(alignment: .leading, spacing: AGMetric.s3) {
                Text("อยากให้ระบบบอกคุณเมื่องานเสร็จ หรือตอนที่ Agent รอคำตอบ?")
                    .font(AGFont.font(AGFont.sub, weight: .semibold, scale: fontScale))
                    .foregroundColor(AGColor.t1)
                    .fixedSize(horizontal: false, vertical: true)
                Text("ตอนนี้การแจ้งเตือนยังปิดอยู่ — เปิดได้จากปุ่มด้านล่าง โดยไม่มีการแจ้งเตือนที่มีปุ่มอนุมัติ เพราะการอนุมัติต้องทำในแอปเสมอ")
                    .font(AGFont.font(AGFont.cap, scale: fontScale))
                    .foregroundColor(AGColor.t2)
                    .fixedSize(horizontal: false, vertical: true)
                AGButton(title: "เปิดการแจ้งเตือน", icon: "bell", kind: .primary, scale: fontScale) {
                    notifier.setEnabled(true)
                }
            }
        }
    }

    // MARK: - กำลังทำอยู่

    private var currentSection: some View {
        VStack(alignment: .leading, spacing: AGMetric.s2) {
            AGSectionTitle(text: "กำลังทำอยู่ตอนนี้", scale: fontScale)

            if center.isRunning {
                AGCard(padding: AGMetric.s4) {
                    VStack(alignment: .leading, spacing: AGMetric.s2) {
                        HStack(spacing: AGMetric.s2) {
                            AGPulseDot(tone: AGColor.accent, size: 14)
                            Text(center.liveLabel.isEmpty ? "กำลังทำงาน" : center.liveLabel)
                                .font(AGFont.font(AGFont.sub, weight: .semibold, scale: fontScale))
                                .foregroundColor(AGColor.t1)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Text("ทำแล้ว \(center.events.filter { $0.status == .succeeded }.count) ขั้น · ใช้เวลาไป \(AGFormat.durationShort(center.elapsed))")
                            .font(AGFont.font(AGFont.cap, scale: fontScale))
                            .foregroundColor(AGColor.t2)
                        AGButton(title: "ไปดูในแชท", icon: "bubble.left", kind: .secondary, scale: fontScale) {
                            router.selectedTab = .chat
                        }
                    }
                }
            } else {
                AGCard(padding: AGMetric.s4) {
                    VStack(alignment: .leading, spacing: AGMetric.s2) {
                        Text("ยังไม่มีงานที่กำลังทำ")
                            .font(AGFont.font(AGFont.sub, weight: .semibold, scale: fontScale))
                            .foregroundColor(AGColor.t1)
                        Text("พิมพ์คำขอให้ Agent ในแท็บแชท แล้วงานจะมาอยู่ที่นี่ พร้อมสถานะว่ากำลังทำอะไรอยู่")
                            .font(AGFont.font(AGFont.cap, scale: fontScale))
                            .foregroundColor(AGColor.t2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    // MARK: - รอคำตอบ (จากไทม์ไลน์ของงานปัจจุบัน)

    @ViewBuilder
    private var waitingSection: some View {
        let waiting = center.events.filter { $0.status == .waitingUser }
        if !waiting.isEmpty {
            VStack(alignment: .leading, spacing: AGMetric.s2) {
                AGSectionTitle(text: "รอคำตอบจากคุณ", scale: fontScale)
                ForEach(waiting) { event in
                    AGCard(padding: AGMetric.s4) {
                        VStack(alignment: .leading, spacing: AGMetric.s2) {
                            HStack(spacing: AGMetric.s2) {
                                AGStatusGlyph(status: .waitingUser, scale: fontScale)
                                Text(event.title)
                                    .font(AGFont.font(AGFont.sub, weight: .semibold, scale: fontScale))
                                    .foregroundColor(AGColor.t1)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Text("Agent หยุดรออยู่ — จะไม่ทำอะไรต่อจนกว่าคุณจะตอบ")
                                .font(AGFont.font(AGFont.cap, scale: fontScale))
                                .foregroundColor(AGColor.t2)
                                .fixedSize(horizontal: false, vertical: true)
                            AGButton(title: "ไปตอบในแชท", icon: "arrow.right", kind: .primary, scale: fontScale) {
                                router.selectedTab = .chat
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - ข้อความรอส่ง

    @ViewBuilder
    private var queuedSection: some View {
        if !queue.items.isEmpty {
            VStack(alignment: .leading, spacing: AGMetric.s2) {
                AGSectionTitle(text: "ข้อความรอส่ง", scale: fontScale)
                ForEach(queue.items) { item in
                    AGCard(padding: AGMetric.s4) {
                        VStack(alignment: .leading, spacing: AGMetric.s2) {
                            Text(item.preview)
                                .font(AGFont.font(AGFont.sub, scale: fontScale))
                                .foregroundColor(AGColor.t1)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("พิมพ์ไว้ระหว่าง Agent ทำงาน — จะถูกส่งให้อัตโนมัติเมื่องานก่อนหน้าจบ")
                                .font(AGFont.font(AGFont.cap, scale: fontScale))
                                .foregroundColor(AGColor.t2)
                                .fixedSize(horizontal: false, vertical: true)
                            HStack(spacing: AGMetric.s2) {
                                AGButton(title: "ไปที่แชท", icon: "bubble.left", kind: .secondary, scale: fontScale) {
                                    if let roomID = item.roomID { router.openRoom(roomID) } else { router.selectedTab = .chat }
                                }
                                AGButton(title: "ยกเลิก", kind: .ghost, scale: fontScale,
                                         hint: "ลบข้อความนี้ออกจากคิว") {
                                    queue.remove(id: item.id)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - ประวัติงานล่าสุด (ทะเบียนงานถาวร)

    @ViewBuilder
    private var registrySection: some View {
        let recent = Array(center.tasks.prefix(12))
        if !recent.isEmpty {
            VStack(alignment: .leading, spacing: AGMetric.s2) {
                HStack {
                    AGSectionTitle(text: "ประวัติงานล่าสุด", scale: fontScale)
                    Spacer(minLength: 0)
                    if recent.contains(where: { $0.outcome.isFinished }) {
                        Button(action: {
                            AGHaptic.light()
                            center.clearFinishedTasks()
                        }) {
                            Text("ล้างงานที่จบแล้ว")
                                .font(AGFont.font(AGFont.cap, scale: fontScale))
                                .foregroundColor(AGColor.t2)
                                .frame(minHeight: 34)
                        }
                        .buttonStyle(AGPressableStyle())
                        .accessibilityLabel(Text("ล้างรายการงานที่จบแล้วออกจากประวัติ"))
                    }
                }
                Text("งานที่ปิดแอปไปแล้วยังอยู่ที่นี่ — งานที่ค้างอยู่ตอนปิดแอปจะขึ้นว่า \"ถูกปิดกลางทาง\" ตามจริง")
                    .font(AGFont.font(AGFont.cap, scale: fontScale))
                    .foregroundColor(AGColor.t2)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(recent) { task in
                    taskCard(task)
                }
            }
        }
    }

    private func taskCard(_ task: TaskRecord) -> some View {
        AGCard(padding: AGMetric.s4) {
            VStack(alignment: .leading, spacing: AGMetric.s2) {
                HStack(alignment: .top, spacing: AGMetric.s2) {
                    AGStatusGlyph(status: glyph(for: task.outcome), scale: fontScale)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(task.title)
                            .font(AGFont.font(AGFont.sub, weight: .semibold, scale: fontScale))
                            .foregroundColor(AGColor.t1)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(taskLine(task))
                            .font(AGFont.font(AGFont.cap, scale: fontScale))
                            .foregroundColor(AGColor.t2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                if let summary = task.summary, !summary.isEmpty {
                    Text(summary)
                        .font(AGFont.font(AGFont.cap, scale: fontScale))
                        .foregroundColor(AGColor.t2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let lastStep = task.lastStepTitle, !lastStep.isEmpty {
                    Text("ขั้นล่าสุด: \(lastStep)")
                        .font(AGFont.font(AGFont.micro, scale: fontScale))
                        .foregroundColor(AGColor.t3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: AGMetric.s3) {
                    if let roomID = task.roomID {
                        AGButton(title: "เปิดห้องนี้", icon: "bubble.left", kind: .secondary, scale: fontScale) {
                            router.openRoom(roomID)
                        }
                    }
                    if task.outcome.canContinue {
                        AGButton(title: "ทำต่อจากจุดเดิม", icon: "arrow.clockwise", kind: .primary, scale: fontScale) {
                            continueTask(task)
                        }
                    }
                }
            }
        }
    }

    private func taskLine(_ task: TaskRecord) -> String {
        var parts: [String] = [task.outcome.thaiLabel]
        if task.stepCount > 0 { parts.append("\(task.stepCount) ขั้น") }
        if let duration = task.duration { parts.append("ใช้เวลา \(AGFormat.durationShort(duration))") }
        if task.touchedFiles { parts.append("แตะไฟล์ \(task.fileChangeCount) ไฟล์") }
        parts.append(dateText(task.startedAt))
        return parts.joined(separator: " · ")
    }

    private func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "th_TH")
        formatter.dateFormat = "d MMM HH:mm"
        return formatter.string(from: date)
    }

    private func glyph(for outcome: TaskOutcome) -> ActivityStatus {
        switch outcome {
        case .running: return .running
        case .done: return .succeeded
        case .needsAnswer: return .waitingUser
        case .failed: return .failed
        case .cancelled, .interrupted, .systemPaused: return .cancelled
        }
    }

    private func continueTask(_ task: TaskRecord) {
        AGHaptic.medium()
        if let roomID = task.roomID { router.pendingRoomID = roomID }
        router.sendToAgent("งานก่อนหน้า (\(task.title)) หยุดกลางทาง — ช่วยทำต่อจากจุดเดิม โดยใช้ผลที่ทำเสร็จแล้ว ไม่ต้องเริ่มใหม่ทั้งหมด")
    }

    // MARK: - บันทึกการเรียกใช้ (แบบย้ายเข้ามาอยู่ในแท็บนี้ ไม่ให้ความสามารถหาย)

    private var logSection: some View {
        VStack(alignment: .leading, spacing: AGMetric.s2) {
            AGSectionTitle(text: "สำหรับผู้ที่ต้องการตรวจสอบ", scale: fontScale)
            AGCard(padding: 0) {
                NavigationLink(destination: AgentLogView()) {
                    AGRow(icon: "list.bullet.rectangle",
                          title: "บันทึกการเรียกใช้",
                          subtitle: "รายละเอียดเชิงเทคนิคของทุกคำขอ (สำหรับตรวจสอบย้อนหลัง)",
                          showsChevron: true,
                          scale: fontScale)
                }
                .buttonStyle(AGPressableStyle())
            }
        }
    }

    // MARK: - งานตามเวลา (บอกตรง ๆ ว่ายังไม่มี)

    private var scheduledSection: some View {
        VStack(alignment: .leading, spacing: AGMetric.s2) {
            AGSectionTitle(text: "งานตามเวลา", scale: fontScale)
            AGCard(padding: AGMetric.s4) {
                VStack(alignment: .leading, spacing: AGMetric.s2) {
                    Text("ยังไม่มีในเวอร์ชันนี้")
                        .font(AGFont.font(AGFont.sub, weight: .semibold, scale: fontScale))
                        .foregroundColor(AGColor.t1)
                    Text("iOS 15 ไม่ให้แอปทำงานเบื้องหลังแบบตั้งเวลาไว้ล่วงหน้าได้จริง ระบบจึงไม่แสดงปุ่มที่กดแล้วไม่ได้ผล — ถ้าเปิดใช้ในอนาคต จะแจ้งให้ทราบก่อนเสมอ")
                        .font(AGFont.font(AGFont.cap, scale: fontScale))
                        .foregroundColor(AGColor.t2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
