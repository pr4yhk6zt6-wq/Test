//
//  MyTasksScreen.swift
//  iOS Agent Sandbox — ดีไซน์ v2 (เฟส 5 ส่วนที่ 5)
//
//  แท็บ "งานของฉัน" — แทนแท็บ "บันทึก" เดิม (บันทึกการทำงานยังเข้าได้จากในหน้านี้ ไม่มีอะไรหาย)
//  แสดง: งานที่กำลังทำ, งานที่รอคำตอบจากผู้ใช้, งานล่าสุดในแต่ละห้อง, งานตามเวลา (ยังไม่รองรับ — บอกตรง ๆ)
//

import SwiftUI

struct MyTasksScreen: View {

    @ObservedObject private var center: ActivityCenter = .shared
    @ObservedObject private var router: AppRouter = .shared
    @ObservedObject private var connectivity: ConnectivityMonitor = .shared
    @ObservedObject private var notifier: AgentNotifier = .shared
    @ObservedObject private var queue: PendingMessageQueue = .shared

    @AppStorage(SettingsKeys.chatFontScale) private var fontScale: Double = 1.0
    @State private var rooms: [ChatRoom] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DSMetrics.groupSpacing) {
                connectionBanner
                notificationHint
                currentSection
                queuedSection
                waitingSection
                registrySection
                recentRoomsSection
                scheduledSection
                logSection
            }
            .padding(.horizontal, DSMetrics.screenPadding)
            .padding(.vertical, DSMetrics.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(DSColor.bg)
        .navigationTitle("งานของฉัน")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            rooms = ChatRoomStore().loadRooms()
            center.reloadTasks()
        }
    }

    // MARK: - ส่วนต่าง ๆ

    @ViewBuilder
    private var connectionBanner: some View {
        if !connectivity.isConnected {
            DSBanner(tone: .warning,
                     title: "ตอนนี้อินเทอร์เน็ตขาด",
                     message: "งานที่ต้องต่อเน็ตจะหยุดชั่วคราว ผลที่ทำไว้แล้วยังอยู่ครบ และจะทำต่อเมื่อสัญญาณกลับมา",
                     scale: fontScale)
        }
    }

    private var currentSection: some View {
        VStack(alignment: .leading, spacing: DSMetrics.s2) {
            sectionTitle("กำลังทำอยู่ตอนนี้")

            if center.isRunning {
                DSCardContainer(tone: .accent) {
                    HStack(alignment: .top, spacing: DSMetrics.s3) {
                        DSStatusGlyph(status: .running, scale: fontScale)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(center.liveLabel.isEmpty ? ActivityKind.thinking.runningPhraseTH : center.liveLabel)
                                .font(DSFont.font(DSFont.sSub, weight: .semibold, scale: fontScale))
                                .foregroundColor(DSColor.t1)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("ทำแล้ว \(doneCount) ขั้น · ใช้เวลาไป \(DSFormat.clock(center.elapsed))")
                                .font(DSFont.font(DSFont.sCap, scale: fontScale))
                                .foregroundColor(DSColor.t2)
                        }
                        Spacer(minLength: 0)
                    }
                    DSButton(title: "ดูรายละเอียดในแชท",
                             icon: "bubble.left",
                             kind: .secondary,
                             scale: fontScale,
                             action: { router.selectedTab = .chat })
                }
            } else if let summary = center.finishedSummary {
                DSCardContainer(tone: .surface) {
                    Text(summary)
                        .font(DSFont.font(DSFont.sSub, scale: fontScale))
                        .foregroundColor(DSColor.t1)
                        .fixedSize(horizontal: false, vertical: true)
                    if !center.events.isEmpty {
                        Text("งานล่าสุดมี \(center.events.count) ขั้นตอน — ดูไทม์ไลน์เต็มได้ที่แท็บแชท")
                            .font(DSFont.font(DSFont.sCap, scale: fontScale))
                            .foregroundColor(DSColor.t2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else {
                DSCardContainer(tone: .surface) {
                    Text("ยังไม่มีงานที่กำลังทำ")
                        .font(DSFont.font(DSFont.sSub, weight: .medium, scale: fontScale))
                        .foregroundColor(DSColor.t1)
                    Text("พิมพ์คำขอให้ Agent ในแท็บแชท แล้วงานจะมาอยู่ที่นี่ — พร้อมสถานะว่ากำลังทำอะไร")
                        .font(DSFont.font(DSFont.sCap, scale: fontScale))
                        .foregroundColor(DSColor.t2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @ViewBuilder
    private var waitingSection: some View {
        let waiting = center.events.filter { $0.status == .waitingUser }
        if !waiting.isEmpty {
            VStack(alignment: .leading, spacing: DSMetrics.s2) {
                sectionTitle("รอคำตอบจากคุณ")
                ForEach(waiting) { event in
                    DSCardContainer(tone: .warning) {
                        HStack(alignment: .top, spacing: DSMetrics.s3) {
                            DSStatusGlyph(status: .waitingUser, scale: fontScale)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(event.title)
                                    .font(DSFont.font(DSFont.sSub, weight: .semibold, scale: fontScale))
                                    .foregroundColor(DSColor.t1)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text("Agent หยุดรออยู่ — จะไม่ทำอะไรต่อจนกว่าคุณจะตอบ")
                                    .font(DSFont.font(DSFont.sCap, scale: fontScale))
                                    .foregroundColor(DSColor.t2)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                        }
                        DSButton(title: "ไปตอบในแชท",
                                 icon: "arrow.right",
                                 kind: .primary,
                                 scale: fontScale,
                                 action: { router.selectedTab = .chat })
                    }
                }
            }
        }
    }

    // MARK: - แจ้งเตือน (ดีไซน์ v2 ส่วนที่ 5 — ชี้ชวนอย่างมีบริบท ไม่กดดัน)

    @ViewBuilder
    private var notificationHint: some View {
        if !notifier.isEnabled {
            DSCardContainer(tone: .accent) {
                Text("อยากให้ระบบบอกคุณเมื่องานเสร็จ หรือตอนที่ Agent รอคำตอบ?")
                    .font(DSFont.font(DSFont.sSub, weight: .semibold, scale: fontScale))
                    .foregroundColor(DSColor.t1)
                    .fixedSize(horizontal: false, vertical: true)
                Text("ตอนนี้การแจ้งเตือนยังปิดอยู่ — เปิดได้จากปุ่มด้านล่าง โดยไม่มีการแจ้งเตือนที่มีปุ่มอนุมัติ เพราะการอนุมัติต้องทำในแอปเสมอ")
                    .font(DSFont.font(DSFont.sCap, scale: fontScale))
                    .foregroundColor(DSColor.t2)
                    .fixedSize(horizontal: false, vertical: true)
                DSButton(title: "เปิดการแจ้งเตือน", icon: "bell", kind: .primary, scale: fontScale) {
                    notifier.setEnabled(true)
                }
            }
        }
    }

    // MARK: - ข้อความรอส่ง (ดีไซน์ v2 ส่วนที่ 8)

    @ViewBuilder
    private var queuedSection: some View {
        if !queue.items.isEmpty {
            VStack(alignment: .leading, spacing: DSMetrics.s2) {
                sectionTitle("ข้อความรอส่ง")
                ForEach(queue.items) { item in
                    DSCardContainer(tone: .accent) {
                        HStack(alignment: .top, spacing: DSMetrics.s3) {
                            DSStatusGlyph(status: .pending, scale: fontScale)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.preview)
                                    .font(DSFont.font(DSFont.sSub, scale: fontScale))
                                    .foregroundColor(DSColor.t1)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text("พิมพ์ไว้ระหว่าง Agent ทำงาน — จะถูกส่งให้อัตโนมัติเมื่องานก่อนหน้าจบ")
                                    .font(DSFont.font(DSFont.sCap, scale: fontScale))
                                    .foregroundColor(DSColor.t2)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                        }
                        HStack(spacing: DSMetrics.s3) {
                            DSButton(title: "ไปที่แชท", icon: "bubble.left", kind: .primary, scale: fontScale) {
                                if let roomID = item.roomID {
                                    router.openRoom(roomID)
                                } else {
                                    router.selectedTab = .chat
                                }
                            }
                            DSButton(title: "ยกเลิกข้อความนี้", icon: "xmark", kind: .ghost, scale: fontScale) {
                                queue.remove(id: item.id)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - ทะเบียนงานถาวร (ดีไซน์ v2 ส่วนที่ 8)

    @ViewBuilder
    private var registrySection: some View {
        let recent = Array(center.tasks.prefix(12))
        if !recent.isEmpty {
            VStack(alignment: .leading, spacing: DSMetrics.s2) {
                HStack(spacing: DSMetrics.s2) {
                    sectionTitle("ประวัติงานล่าสุด")
                    Spacer(minLength: 0)
                    if recent.contains(where: { $0.outcome.isFinished }) {
                        Button(action: {
                            DSHaptic.light()
                            center.clearFinishedTasks()
                        }) {
                            Text("ล้างงานที่จบแล้ว")
                                .font(DSFont.font(DSFont.sCap, weight: .medium, scale: fontScale))
                                .foregroundColor(DSColor.t2)
                                .frame(minHeight: DSMetrics.touchSmall)
                        }
                        .buttonStyle(DSPressableStyle())
                        .accessibilityLabel(Text("ล้างรายการงานที่จบแล้วออกจากประวัติ"))
                    }
                }
                Text("งานที่ปิดแอปไปแล้วยังอยู่ที่นี่ — งานที่ค้างอยู่ตอนปิดแอปจะขึ้นว่า \"ถูกปิดกลางทาง\" ตามจริง")
                    .font(DSFont.font(DSFont.sCap, scale: fontScale))
                    .foregroundColor(DSColor.t2)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(recent) { task in
                    taskCard(task)
                }
            }
        }
    }

    private func taskCard(_ task: TaskRecord) -> some View {
        DSCardContainer(tone: task.outcome == .failed ? .warning : .surface) {
            HStack(alignment: .top, spacing: DSMetrics.s3) {
                DSStatusGlyph(status: glyph(for: task.outcome), scale: fontScale)
                VStack(alignment: .leading, spacing: 4) {
                    Text(task.title)
                        .font(DSFont.font(DSFont.sSub, weight: .semibold, scale: fontScale))
                        .foregroundColor(DSColor.t1)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(taskLine(task))
                        .font(DSFont.font(DSFont.sCap, scale: fontScale))
                        .foregroundColor(DSColor.t2)
                        .fixedSize(horizontal: false, vertical: true)
                    if let summary = task.summary, !summary.isEmpty {
                        Text(summary)
                            .font(DSFont.font(DSFont.sCap, scale: fontScale))
                            .foregroundColor(DSColor.t2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let lastStep = task.lastStepTitle, !lastStep.isEmpty {
                        Text("ขั้นล่าสุด: \(lastStep)")
                            .font(DSFont.font(DSFont.sMicro, scale: fontScale))
                            .foregroundColor(DSColor.t3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            if task.roomID != nil || task.outcome.canContinue {
                HStack(spacing: DSMetrics.s3) {
                    if let roomID = task.roomID {
                        DSButton(title: "เปิดห้องนี้", icon: "bubble.left", kind: .secondary, scale: fontScale) {
                            router.openRoom(roomID)
                        }
                    }
                    if task.outcome.canContinue {
                        DSButton(title: "ทำต่อจากจุดเดิม", icon: "arrow.clockwise", kind: .primary, scale: fontScale) {
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
        if let duration = task.duration { parts.append("ใช้เวลา \(DSFormat.duration(duration))") }
        if task.touchedFiles { parts.append("แตะไฟล์ \(task.fileChangeCount) ไฟล์") }
        parts.append(MyTasksScreen.timeText(task.startedAt))
        return parts.joined(separator: " · ")
    }

    private static func timeText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "th_TH")
        formatter.dateFormat = "d MMM HH:mm"
        return formatter.string(from: date)
    }

    /// แปลงผลลัพธ์งานเป็นสถานะที่ไอคอน/สีของดีไซน์รองรับ (ไอคอนคู่ข้อความเสมอ)
    private func glyph(for outcome: TaskOutcome) -> ActivityStatus {
        switch outcome {
        case .running: return .running
        case .done: return .succeeded
        case .needsAnswer: return .waitingUser
        case .failed: return .failed
        case .cancelled, .interrupted, .systemPaused: return .cancelled
        }
    }

    /// ให้ Agent ทำต่อจากจุดเดิมในห้องที่งานนี้เกิดขึ้น (ไม่เริ่มใหม่ทั้งหมด)
    private func continueTask(_ task: TaskRecord) {
        DSHaptic.medium()
        if let roomID = task.roomID {
            router.pendingRoomID = roomID
        }
        router.sendToAgent("งานก่อนหน้า (\(task.title)) หยุดกลางทาง — ช่วยทำต่อจากจุดเดิม โดยใช้ผลที่ทำเสร็จแล้ว ไม่ต้องเริ่มใหม่ทั้งหมด")
    }

    private var recentRoomsSection: some View {
        VStack(alignment: .leading, spacing: DSMetrics.s2) {
            sectionTitle("งานล่าสุดในแต่ละห้อง")

            if rooms.isEmpty {
                DSCardContainer(tone: .surface) {
                    Text("ยังไม่มีห้องสนทนา")
                        .font(DSFont.font(DSFont.sSub, scale: fontScale))
                        .foregroundColor(DSColor.t1)
                }
            } else {
                ForEach(rooms.prefix(5)) { room in
                    Button(action: {
                        DSHaptic.light()
                        router.openRoom(room.id)
                    }) {
                        HStack(alignment: .top, spacing: DSMetrics.s3) {
                            DSIconBadge(icon: "bubble.left.and.bubble.right",
                                        tint: DSColor.accentInk,
                                        background: DSColor.accentSoft,
                                        scale: fontScale)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(room.name)
                                    .font(DSFont.font(DSFont.sSub, weight: .medium, scale: fontScale))
                                    .foregroundColor(DSColor.t1)
                                    .lineLimit(1)
                                Text(room.preview.isEmpty ? "ยังไม่มีข้อความ" : room.preview)
                                    .font(DSFont.font(DSFont.sCap, scale: fontScale))
                                    .foregroundColor(DSColor.t2)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                Text("\(room.messageCount) ข้อความ · อัปเดต \(DSFormat.time(room.updatedAt))")
                                    .font(DSFont.font(DSFont.sMicro, scale: fontScale))
                                    .foregroundColor(DSColor.t3)
                            }
                            Spacer(minLength: DSMetrics.s2)
                            Image(systemName: "chevron.right")
                                .font(DSFont.font(DSFont.sCap, weight: .semibold, scale: fontScale))
                                .foregroundColor(DSColor.t3)
                        }
                        .padding(DSMetrics.cardPadding)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: DSMetrics.rCard, style: .continuous).fill(DSColor.surface))
                        .overlay(RoundedRectangle(cornerRadius: DSMetrics.rCard, style: .continuous).stroke(DSColor.border, lineWidth: 1))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(DSPressableStyle())
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("ห้อง \(room.name) \(room.messageCount) ข้อความ — แตะเพื่อเปิด"))
                }
            }
        }
    }

    private var scheduledSection: some View {
        VStack(alignment: .leading, spacing: DSMetrics.s2) {
            sectionTitle("งานตามเวลา")
            DSCardContainer(tone: .surface) {
                Text("ยังไม่รองรับในเวอร์ชันนี้")
                    .font(DSFont.font(DSFont.sSub, weight: .medium, scale: fontScale))
                    .foregroundColor(DSColor.t1)
                Text("แอปนี้ยังตั้งเวลาให้ Agent ทำงานเองล่วงหน้าไม่ได้ (iOS 15 ไม่อนุญาตให้ทำงานเบื้องหลังแบบนั้น) "
                     + "เมื่อรองรับ จะแจ้งเตือนคุณตอนงานเริ่มทำงาน ไม่ใช่แจ้งเงียบ ๆ")
                    .font(DSFont.font(DSFont.sCap, scale: fontScale))
                    .foregroundColor(DSColor.t2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var logSection: some View {
        VStack(alignment: .leading, spacing: DSMetrics.s2) {
            sectionTitle("บันทึกการทำงาน")
            NavigationLink(destination: AgentLogView()) {
                HStack(alignment: .center, spacing: DSMetrics.s3) {
                    DSIconBadge(icon: "list.bullet.rectangle",
                                tint: DSColor.t2,
                                background: DSColor.surface2,
                                scale: fontScale)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("ทุกครั้งที่ Agent เรียกเครื่องมือ")
                            .font(DSFont.font(DSFont.sSub, weight: .medium, scale: fontScale))
                            .foregroundColor(DSColor.t1)
                        Text("เวลา คำสั่ง ผลลัพธ์ และข้อผิดพลาด — เก็บไว้บนเครื่องนี้เท่านั้น")
                            .font(DSFont.font(DSFont.sCap, scale: fontScale))
                            .foregroundColor(DSColor.t2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: DSMetrics.s2)
                    Image(systemName: "chevron.right")
                        .font(DSFont.font(DSFont.sCap, weight: .semibold, scale: fontScale))
                        .foregroundColor(DSColor.t3)
                }
                .padding(DSMetrics.cardPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: DSMetrics.rCard, style: .continuous).fill(DSColor.surface))
                .overlay(RoundedRectangle(cornerRadius: DSMetrics.rCard, style: .continuous).stroke(DSColor.border, lineWidth: 1))
            }
            .buttonStyle(DSPressableStyle())
            .accessibilityHint(Text("เปิดหน้ารายการเครื่องมือที่ Agent เรียกทั้งหมด"))

            Text(notifier.statusExplanation)
                .font(DSFont.font(DSFont.sMicro, scale: fontScale))
                .foregroundColor(DSColor.t3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(DSFont.font(DSFont.sCap, weight: .semibold, scale: fontScale))
            .foregroundColor(DSColor.t3)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var doneCount: Int {
        center.events.filter { $0.status == .succeeded }.count
    }
}
