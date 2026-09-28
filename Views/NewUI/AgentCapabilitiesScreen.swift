//
//  AgentCapabilitiesScreen.swift
//  iOS Agent Sandbox — ดีไซน์ v2 (เฟส 5 ส่วนที่ 5)
//
//  หน้า "เครื่องมือและบริการ" — บอกตรง ๆ ว่า Agent ทำอะไรได้/ไม่ได้ ในภาษาคน
//  รายการเครื่องมืออ้างอิงจาก ToolRegistry จริง (15 ตัว) และกติกาขออนุญาตของแต่ละตัว
//

import SwiftUI

struct AgentCapabilitiesScreen: View {

    @EnvironmentObject private var settings: AppSettings
    @ObservedObject private var notifier: AgentNotifier = .shared
    @AppStorage(SettingsKeys.chatFontScale) private var fontScale: Double = 1.0

    /// (ไอคอน, ชื่อไทย, คำอธิบายภาษาคน, ต้องขออนุญาต?, ต้องต่อเน็ต?)
    private struct Capability: Identifiable {
        let id: String
        let icon: String
        let name: String
        let detail: String
        let needsApproval: Bool
        let needsInternet: Bool
    }

    private let capabilities: [Capability] = [
        Capability(id: "read_file", icon: "doc.text", name: "อ่านไฟล์",
                   detail: "เปิดอ่านไฟล์ในเครื่องเพื่อใช้ตอบคำถาม ไม่แก้ไขอะไร",
                   needsApproval: false, needsInternet: false),
        Capability(id: "list_directory", icon: "folder", name: "ดูรายชื่อไฟล์ในโฟลเดอร์",
                   detail: "สำรวจว่ามีไฟล์อะไรอยู่ที่ไหน ก่อนตัดสินใจทำงานต่อ",
                   needsApproval: false, needsInternet: false),
        Capability(id: "search_files", icon: "magnifyingglass", name: "ค้นหาไฟล์ตามเงื่อนไข",
                   detail: "หาไฟล์จากชื่อหรือรูปแบบที่คุณต้องการ",
                   needsApproval: false, needsInternet: false),
        Capability(id: "search_content", icon: "text.magnifyingglass", name: "ค้นข้อความในไฟล์",
                   detail: "หาเนื้อหาภายในไฟล์ข้อความทั้งหมดในโฟลเดอร์",
                   needsApproval: false, needsInternet: false),
        Capability(id: "write_file", icon: "square.and.pencil", name: "เขียนไฟล์ใหม่",
                   detail: "สร้างไฟล์ใหม่หรือเขียนทับไฟล์เดิม",
                   needsApproval: true, needsInternet: false),
        Capability(id: "edit_file", icon: "pencil", name: "แก้ไขบางจุดในไฟล์",
                   detail: "แก้เฉพาะส่วนที่ระบุ โดยเก็บส่วนอื่นของไฟล์ไว้เหมือนเดิม",
                   needsApproval: true, needsInternet: false),
        Capability(id: "create_directory", icon: "folder.badge.plus", name: "สร้างโฟลเดอร์",
                   detail: "สร้างโฟลเดอร์ใหม่ในพื้นที่ทำงาน",
                   needsApproval: true, needsInternet: false),
        Capability(id: "move_file", icon: "arrow.right.doc.on.clipboard", name: "ย้าย / คัดลอกไฟล์",
                   detail: "ย้ายหรือคัดลอกไฟล์ไปตำแหน่งใหม่",
                   needsApproval: true, needsInternet: false),
        Capability(id: "delete_file", icon: "trash", name: "ลบไฟล์",
                   detail: "ลบไฟล์ออกจากเครื่อง — ย้อนกลับไม่ได้ จึงต้องยืนยันทุกครั้ง",
                   needsApproval: true, needsInternet: false),
        Capability(id: "execute_shell", icon: "terminal", name: "รันคำสั่งบนเครื่อง",
                   detail: "สั่งงานผ่านคำสั่ง UNIX — คำสั่งที่เสี่ยงจะถูกถามก่อนเสมอ",
                   needsApproval: true, needsInternet: false),
        Capability(id: "web_search", icon: "magnifyingglass.circle", name: "ค้นหาเว็บ",
                   detail: "ค้นข้อมูลบนอินเทอร์เน็ตด้วยคำค้นของคุณ",
                   needsApproval: false, needsInternet: true),
        Capability(id: "fetch_webpage", icon: "globe", name: "เปิดอ่านหน้าเว็บ",
                   detail: "ดึงเนื้อหาจากหน้าเว็บที่ระบุมาอ่าน",
                   needsApproval: false, needsInternet: true),
        Capability(id: "http_request", icon: "arrow.up.arrow.down.circle", name: "เรียกข้อมูลจากเว็บ",
                   detail: "ติดต่อบริการออนไลน์ตามที่คุณสั่ง",
                   needsApproval: false, needsInternet: true),
        Capability(id: "download_file", icon: "arrow.down.circle", name: "ดาวน์โหลดไฟล์",
                   detail: "ดาวน์โหลดไฟล์จากอินเทอร์เน็ตมาเก็บในเครื่อง",
                   needsApproval: false, needsInternet: true),
        Capability(id: "shell_tools", icon: "wrench.and.screwdriver", name: "เครื่องมือในเครื่อง",
                   detail: "ใช้คำสั่งพื้นฐานของ iOS/UNIX ช่วยงาน เช่น ดูเนื้อหาไฟล์ ค้นข้อความ",
                   needsApproval: false, needsInternet: false)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DSMetrics.groupSpacing) {
                approvalSummary
                servicesSection
                voiceSection
                notificationSummary

                VStack(alignment: .leading, spacing: DSMetrics.s2) {
                    sectionTitle("Agent ทำอะไรได้ในเวอร์ชันนี้")
                    ForEach(capabilities) { item in
                        capabilityRow(item)
                    }
                }
            }
            .padding(.horizontal, DSMetrics.screenPadding)
            .padding(.vertical, DSMetrics.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(DSColor.bg)
        .navigationTitle("เครื่องมือและบริการ")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - ส่วนต่าง ๆ

    private var approvalSummary: some View {
        DSCardContainer(tone: settings.requireApproval ? .success : .warning) {
            HStack(alignment: .top, spacing: DSMetrics.s3) {
                DSIconBadge(icon: settings.requireApproval ? "shield.lefthalf.filled" : "exclamationmark.triangle.fill",
                            tint: settings.requireApproval ? DSColor.success : DSColor.warning,
                            background: settings.requireApproval ? DSColor.successSoft : DSColor.warningSoft,
                            scale: fontScale)
                VStack(alignment: .leading, spacing: 3) {
                    Text(settings.requireApproval ? "โหมดปลอดภัย: ถามก่อนทุกครั้ง" : "โหมดไม่ถาม: ควรระวังเป็นพิเศษ")
                        .font(DSFont.font(DSFont.sSub, weight: .semibold, scale: fontScale))
                        .foregroundColor(DSColor.t1)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(settings.requireApproval
                         ? "ทุกคำสั่งที่มีผลกับเครื่องจะหยุดรอให้คุณกดอนุญาตก่อนเสมอ และจะถามใหม่ทุกครั้ง"
                         : "คุณปิดการถามไว้ — คำสั่งที่มีผลกับเครื่องจะทำงานทันทีโดยไม่รอ เปิดกลับได้ที่หน้าตั้งค่า")
                        .font(DSFont.font(DSFont.sCap, scale: fontScale))
                        .foregroundColor(DSColor.t2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            Text("แอปนี้ไม่จำสิทธิ์ข้ามงาน — ทุกครั้งที่ Agent จะเขียนหรือลบไฟล์ จะถามคุณใหม่")
                .font(DSFont.font(DSFont.sMicro, scale: fontScale))
                .foregroundColor(DSColor.t3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var servicesSection: some View {
        VStack(alignment: .leading, spacing: DSMetrics.s2) {
            sectionTitle("บริการภายนอก (ตัวเชื่อม)")
            DSCardContainer(tone: .surface) {
                Text("ยังไม่มีตัวเชื่อมบริการในเวอร์ชันนี้")
                    .font(DSFont.font(DSFont.sSub, weight: .medium, scale: fontScale))
                    .foregroundColor(DSColor.t1)
                Text("ตัวเชื่อมคือการให้ Agent ทำงานกับบริการอื่น เช่น อีเมล ปฏิทิน หรือไดรฟ์ของคุณ "
                     + "ตอนนี้ Agent ทำงานกับไฟล์ในเครื่องและอินเทอร์เน็ตได้เท่านั้น "
                     + "ถ้าเพิ่มในอนาคต จะมีหน้าขออนุญาตแยกให้เห็นชัดว่าอ่านหรือเขียนอะไรได้")
                    .font(DSFont.font(DSFont.sCap, scale: fontScale))
                    .foregroundColor(DSColor.t2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var voiceSection: some View {
        VStack(alignment: .leading, spacing: DSMetrics.s2) {
            sectionTitle("โหมดเสียง")
            DSCardContainer(tone: .surface) {
                Text("เตรียมไว้ — ยังไม่เปิดใช้งานในบิลด์นี้")
                    .font(DSFont.font(DSFont.sSub, weight: .medium, scale: fontScale))
                    .foregroundColor(DSColor.t1)
                Text("โหมดเสียงต้องขออนุญาตใช้ไมโครโฟนก่อน แอปนี้จะไม่ขอสิทธิ์ใด ๆ เพิ่มโดยไม่บอกคุณ "
                     + "เมื่อคุณอนุญาตแล้วจึงจะเปิดใช้ได้ และการอนุมัติด้วยเสียงจะทำได้เฉพาะงานที่ย้อนกลับได้เท่านั้น "
                     + "ส่วนการลบไฟล์ต้องแตะยืนยันบนหน้าจอเสมอ")
                    .font(DSFont.font(DSFont.sCap, scale: fontScale))
                    .foregroundColor(DSColor.t2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var notificationSummary: some View {
        VStack(alignment: .leading, spacing: DSMetrics.s2) {
            sectionTitle("การแจ้งเตือน")
            DSCardContainer(tone: .surface) {
                Text(notifier.statusExplanation)
                    .font(DSFont.font(DSFont.sCap, scale: fontScale))
                    .foregroundColor(DSColor.t2)
                    .fixedSize(horizontal: false, vertical: true)
                Text("แจ้งเตือนของแอปนี้ไม่แสดงรายละเอียดงานบนหน้าจอล็อก และไม่มีปุ่มอนุมัติ — "
                     + "ต้องเปิดแอปเพื่อดูบริบทให้ครบก่อนตัดสินใจทุกครั้ง")
                    .font(DSFont.font(DSFont.sMicro, scale: fontScale))
                    .foregroundColor(DSColor.t3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func capabilityRow(_ item: Capability) -> some View {
        HStack(alignment: .top, spacing: DSMetrics.s3) {
            DSIconBadge(icon: item.icon, tint: DSColor.t2, background: DSColor.surface2, scale: fontScale)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .font(DSFont.font(DSFont.sSub, weight: .medium, scale: fontScale))
                    .foregroundColor(DSColor.t1)
                    .fixedSize(horizontal: false, vertical: true)
                Text(item.detail)
                    .font(DSFont.font(DSFont.sCap, scale: fontScale))
                    .foregroundColor(DSColor.t2)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    if item.needsApproval {
                        DSChip(text: "ต้องขออนุญาต", tone: .warning, icon: "hand.raised.fill", scale: fontScale)
                    }
                    if item.needsInternet {
                        DSChip(text: "ต้องต่อเน็ต", tone: .accent, icon: "wifi", scale: fontScale)
                    }
                    if !item.needsApproval && !item.needsInternet {
                        DSChip(text: "ทำได้เลย (อ่านอย่างเดียว)", tone: .success, icon: "checkmark", scale: fontScale)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(DSMetrics.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: DSMetrics.rCard, style: .continuous).fill(DSColor.surface))
        .overlay(RoundedRectangle(cornerRadius: DSMetrics.rCard, style: .continuous).stroke(DSColor.border, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(DSFont.font(DSFont.sCap, weight: .semibold, scale: fontScale))
            .foregroundColor(DSColor.t3)
            .fixedSize(horizontal: false, vertical: true)
    }
}
