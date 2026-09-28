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

    @AppStorage(SettingsKeys.chatFontScale) private var fontScale: Double = 1.0
    @State private var rooms: [ChatRoom] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DSMetrics.groupSpacing) {
                connectionBanner
                currentSection
                waitingSection
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
        .onAppear { rooms = ChatRoomStore().loadRooms() }
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
