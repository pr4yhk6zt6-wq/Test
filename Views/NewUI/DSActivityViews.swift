//
//  DSActivityViews.swift
//  iOS Agent Sandbox — ดีไซน์ v2 (เฟส 5 ส่วนที่ 3)
//
//  ระบบกิจกรรม 3 ระดับของดีไซน์ใหม่
//  A) DSLiveStatusBar  — แถบสถานะสดเหนือช่องพิมพ์ (เวลาจริง + จำนวนขั้นที่ทำแล้ว)
//  B) DSActivityTimeline — ไทม์ไลน์พับได้ พร้อมการ์ดต่อขั้น
//  C) DSActivityDetailView — แผ่นรายละเอียดเต็ม (คำสั่งที่ส่งไป/ผลลัพธ์/ข้อมูลที่ถูกปิดบัง)
//
//  หลักที่ยึด: ไม่มีสปินเนอร์เปล่า • สถานะมีไอคอน+ข้อความเสมอ • ไม่มีตัวเลขประมาณการ
//

import SwiftUI
import Combine
#if canImport(UIKit)
import UIKit
#endif

extension DSFont {
    static func mono(_ base: CGFloat, scale: Double = 1.0) -> Font {
        Font.system(size: size(base, scale: scale), weight: .regular, design: .monospaced)
    }
}

// MARK: - A) แถบสถานะสด

struct DSLiveStatusBar: View {

    @ObservedObject var center: ActivityCenter
    @Binding var isExpanded: Bool
    @AppStorage(SettingsKeys.chatFontScale) private var fontScale: Double = 1.0

    var body: some View {
        VStack(spacing: 0) {
            Button(action: {
                DSHaptic.light()
                withAnimation(DSMotion.card) { isExpanded.toggle() }
            }) {
                HStack(alignment: .center, spacing: DSMetrics.s3) {
                    leadingGlyph

                    VStack(alignment: .leading, spacing: 1) {
                        Text(headline)
                            .font(DSFont.font(DSFont.sSub, weight: .semibold, scale: fontScale))
                            .foregroundColor(DSColor.t1)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .multilineTextAlignment(.leading)

                        Text(subheadline)
                            .font(DSFont.font(DSFont.sMicro, scale: fontScale))
                            .foregroundColor(DSColor.t3)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .multilineTextAlignment(.leading)
                    }

                    Spacer(minLength: DSMetrics.s1)

                    Text(center.isRunning ? DSFormat.clock(center.elapsed) : DSFormat.durationShort(center.elapsed))
                        .font(DSFont.font(DSFont.sCap, scale: fontScale))
                        .foregroundColor(DSColor.t2)
                        .monospacedDigit()
                        .lineLimit(1)
                        .layoutPriority(1)

                    Image(systemName: "chevron.up")
                        .font(DSFont.font(DSFont.sMicro, weight: .semibold, scale: fontScale))
                        .foregroundColor(DSColor.t3)
                        .rotationEffect(.degrees(isExpanded ? 0 : 180))
                }
                .padding(.horizontal, DSMetrics.cardPadding)
                .frame(minHeight: DSMetrics.liveBarHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(DSPressableStyle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(accessibilityText))
            .accessibilityHint(Text(isExpanded ? "แตะเพื่อพับไทม์ไลน์" : "แตะเพื่อดูไทม์ไลน์ทั้งหมด"))
            .accessibilityAddTraits(isExpanded ? [.isButton, .isSelected] : .isButton)

            if center.isRunning {
                DSRibbon(progress: nil, tone: DSColor.accent)
            }
        }
        .background(DSColor.surface)
        .overlay(
            Rectangle().fill(DSColor.border).frame(height: 1),
            alignment: .top
        )
    }

    /// วงกลมนำ: กำลังทำ = จุดเต้น, รอคุณ = วงกลมเตือน, อื่น ๆ = วงกลมสถานะตามจริง
    @ViewBuilder
    private var leadingGlyph: some View {
        if center.isRunning {
            DSPulseDot(tone: DSColor.accent)
                .frame(width: 22, height: 22)
        } else {
            DSStatusGlyph(status: summaryStatus, scale: fontScale)
        }
    }

    /// สถานะสรุปของงานล่าสุด (สี + ไอคอน + ข้อความ ต้องตรงกันเสมอ)
    private var summaryStatus: ActivityStatus {
        if center.events.contains(where: { $0.status == .waitingUser }) { return .waitingUser }
        if center.events.contains(where: { $0.status == .failed }) { return .failed }
        if center.events.contains(where: { $0.title == "ระบบหยุดงานชั่วคราว" }) { return .cancelled }
        if center.finishedTitle == "ยกเลิกตามที่คุณสั่ง" { return .cancelled }
        return .succeeded
    }

    private var headline: String {
        if center.isRunning {
            return center.liveLabel.isEmpty ? ActivityKind.thinking.runningPhraseTH : center.liveLabel
        }
        if !center.finishedTitle.isEmpty { return center.finishedTitle }
        return "ไทม์ไลน์งานล่าสุด"
    }

    private var subheadline: String {
        var parts: [String] = []
        if center.isRunning {
            let done = center.events.filter { $0.status == .succeeded }.count
            if done > 0 { parts.append("ทำแล้ว \(done) ขั้น") }
            parts.append("แตะเพื่อดูทุกขั้นตอน")
            return parts.joined(separator: " · ")
        }
        let steps = center.events.count
        if steps > 0 { parts.append("\(steps) ขั้นตอน") }
        if let waiting = center.events.last(where: { $0.status == .waitingUser }) {
            parts.append("รอคุณตอบ: \(waiting.title)")
        }
        if parts.isEmpty { parts.append("แตะเพื่อดูว่าระบบทำอะไรไปบ้าง") }
        return parts.joined(separator: " · ")
    }

    private var accessibilityText: String {
        var parts: [String] = ["สถานะปัจจุบัน"]
        parts.append(headline)
        parts.append(subheadline)
        if center.isRunning {
            parts.append("ใช้เวลาไปแล้ว \(DSFormat.duration(center.elapsed))")
        }
        parts.append("มี \(center.events.count) ขั้นตอนในไทม์ไลน์")
        return parts.joined(separator: " ")
    }
}

// MARK: - B) ไทม์ไลน์

struct DSActivityTimeline: View {

    @ObservedObject var center: ActivityCenter
    let level: ActivityDetailLevel
    @Binding var expandedEventID: String?
    let onOpenDetail: (ActivityEvent) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if center.events.isEmpty {
                Text("ยังไม่มีขั้นตอน — เริ่มพิมพ์คำขอให้ Agent ได้เลย")
                    .font(DSFont.font(DSFont.sCap))
                    .foregroundColor(DSColor.t3)
                    .padding(DSMetrics.cardPadding)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach(center.events) { event in
                DSActivityRow(event: event,
                              level: level,
                              isExpanded: expandedEventID == event.id,
                              onToggle: { toggle(event) },
                              onOpenDetail: { onOpenDetail(event) })
                if event.id != center.events.last?.id {
                    Divider()
                        .padding(.leading, DSMetrics.s5 + DSMetrics.s4)
                }
            }
        }
        .background(DSColor.surface)
    }

    private func toggle(_ event: ActivityEvent) {
        withAnimation(DSMotion.card) {
            expandedEventID = (expandedEventID == event.id) ? nil : event.id
        }
    }
}

struct DSActivityRow: View {

    let event: ActivityEvent
    let level: ActivityDetailLevel
    let isExpanded: Bool
    let onToggle: () -> Void
    let onOpenDetail: () -> Void

    @AppStorage(SettingsKeys.chatFontScale) private var fontScale: Double = 1.0

    private var showsBody: Bool {
        guard level != .concise else { return false }
        return level == .detailed || isExpanded
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: {
                guard level != .concise else {
                    onOpenDetail()
                    return
                }
                DSHaptic.light()
                onToggle()
            }) {
                HStack(alignment: .top, spacing: DSMetrics.s3) {
                    DSIconBadge(icon: event.kind.symbolName,
                                tint: event.kind.dsColor,
                                background: event.kind.dsBackground,
                                scale: fontScale)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.title)
                            .font(DSFont.font(DSFont.sSub, weight: .medium, scale: fontScale))
                            .foregroundColor(DSColor.t1)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)

                        if !showsBody {
                            Text(compactSubtitle)
                                .font(DSFont.font(DSFont.sCap, scale: fontScale))
                                .foregroundColor(DSColor.t3)
                                .multilineTextAlignment(.leading)
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: DSMetrics.s2)

                    VStack(alignment: .trailing, spacing: 2) {
                        DSStatusLabel(status: event.status, scale: fontScale)
                        if let text = timingText {
                            Text(text)
                                .font(DSFont.font(DSFont.sMicro, scale: fontScale))
                                .foregroundColor(DSColor.t3)
                                .lineLimit(1)
                        }
                    }
                }
                .padding(.horizontal, DSMetrics.cardPadding)
                .padding(.vertical, 10)
                .frame(minHeight: DSMetrics.rowHeight, alignment: .top)
                .contentShape(Rectangle())
            }
            .buttonStyle(DSPressableStyle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(accessibilityText))
            .accessibilityHint(Text(level == .concise ? "แตะเพื่อดูรายละเอียดของขั้นนี้" : (isExpanded ? "แตะเพื่อพับ" : "แตะเพื่อดูรายละเอียด")))
            .accessibilityAddTraits(.isButton)

            if showsBody {
                DSActivityCardBody(event: event, scale: fontScale, onOpenDetail: onOpenDetail)
                    .padding(.horizontal, DSMetrics.cardPadding)
                    .padding(.bottom, DSMetrics.s3)
            }
        }
        .background(event.status == .waitingUser ? DSColor.warningSoft.opacity(0.5) : Color.clear)
    }

    private var compactSubtitle: String {
        if let failure = event.failureMessage, !failure.isEmpty { return failure }
        if let note = event.note, !note.isEmpty { return note }
        if !event.artifactNames.isEmpty { return event.artifactNames.joined(separator: ", ") }
        if event.maskedCount > 0 { return "มีข้อมูลส่วนตัวถูกปิดบัง \(event.maskedCount) จุด" }
        return event.kind.explanationTH
    }

    private var timingText: String? {
        if let duration = event.duration, duration >= 1 {
            return "\(Int(duration.rounded())) วิ"
        }
        if let start = event.startedAt, event.status.isActive {
            return DSFormat.time(start)
        }
        return nil
    }

    private var accessibilityText: String {
        var parts: [String] = []
        parts.append(event.title)
        parts.append("สถานะ \(event.status.thaiLabel)")
        if let duration = event.duration, duration >= 1 {
            parts.append("ใช้เวลา \(Int(duration.rounded())) วินาที")
        }
        if let failure = event.failureMessage, !failure.isEmpty {
            parts.append("สาเหตุ: \(failure)")
        }
        if event.maskedCount > 0 {
            parts.append("มีข้อมูลส่วนตัวถูกปิดบัง \(event.maskedCount) จุด")
        }
        return parts.joined(separator: " ")
    }
}

/// เนื้อหาการ์ดของขั้นตอน — แสดงเฉพาะบรรทัดที่จำเป็นต่อการตัดสินใจ
struct DSActivityCardBody: View {

    let event: ActivityEvent
    var scale: Double = 1.0
    let onOpenDetail: () -> Void

    @State private var showsAll: Bool = false

    private var lineLimit: Int {
        if event.kind == .shell { return showsAll ? 8 : 2 }
        return showsAll ? 6 : 2
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DSMetrics.s2) {
            if let failure = event.failureMessage, !failure.isEmpty {
                Text(failure)
                    .font(DSFont.font(DSFont.sCap, scale: scale))
                    .foregroundColor(DSColor.error)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !event.artifactNames.isEmpty {
                HStack(spacing: 6) {
                    ForEach(event.artifactNames.prefix(3), id: \.self) { name in
                        DSChip(text: name, tone: .neutral, icon: "doc.text", scale: scale)
                    }
                }
            }

            if !previewLines.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(previewLines.enumerated()), id: \.offset) { pair in
                        Text(pair.element)
                            .font(event.kind == .shell
                                  ? DSFont.mono(DSFont.sMicro, scale: scale)
                                  : DSFont.font(DSFont.sCap, scale: scale))
                            .foregroundColor(event.kind == .shell ? DSColor.t2 : DSColor.t2)
                            .multilineTextAlignment(.leading)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            HStack(spacing: DSMetrics.s2) {
                if event.maskedCount > 0 {
                    DSChip(text: "ปิดบังข้อมูลส่วนตัว \(event.maskedCount) จุด",
                           tone: .warning,
                           icon: "lock.fill",
                           scale: scale)
                }
                if let note = event.note, !note.isEmpty, event.status != .waitingUser {
                    DSChip(text: note, tone: noteTone, icon: "exclamationmark.triangle.fill", scale: scale)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: DSMetrics.s3) {
                Button(action: {
                    DSHaptic.light()
                    onOpenDetail()
                }) {
                    Text("ดูรายละเอียดขั้นนี้")
                        .font(DSFont.font(DSFont.sCap, weight: .semibold, scale: scale))
                        .foregroundColor(DSColor.accentInk)
                        .frame(minHeight: DSMetrics.touchSmall)
                }
                .buttonStyle(DSPressableStyle())
                .accessibilityHint(Text("เปิดแผ่นรายละเอียด แสดงคำสั่งและผลลัพธ์เต็ม"))

                if previewLines.count > 2 {
                    Button(action: {
                        DSHaptic.light()
                        withAnimation(DSMotion.card) { showsAll.toggle() }
                    }) {
                        Text(showsAll ? "ย่อ" : "แสดงเพิ่ม")
                            .font(DSFont.font(DSFont.sCap, weight: .medium, scale: scale))
                            .foregroundColor(DSColor.t2)
                            .frame(minHeight: DSMetrics.touchSmall)
                    }
                    .buttonStyle(DSPressableStyle())
                    .accessibilityLabel(Text(showsAll ? "ย่อรายละเอียดที่แสดง" : "แสดงรายละเอียดเพิ่มเติม"))
                }

                Spacer(minLength: 0)
            }
        }
        .padding(.top, 2)
    }

    private var previewLines: [String] {
        event.previewLines(limit: lineLimit)
    }

    private var noteTone: DSChip.Tone {
        if event.status == .failed { return .error }
        if event.isDestructive { return .error }
        return .warning
    }
}

// MARK: - C) แผ่นรายละเอียด

struct DSActivityDetailView: View {

    let event: ActivityEvent
    @AppStorage(SettingsKeys.chatFontScale) private var fontScale: Double = 1.0

    /// การเปิดดูข้อมูลที่ถูกปิดบังมีอายุเฉพาะในแผ่นนี้ และปิดอัตโนมัติเมื่อปิดแผ่น
    @State private var revealed: Bool = false
    @State private var copied: Bool = false

    /// นาฬิกาสำหรับนับถอยหลังหน้าต่างย้อนกลับ (เวลาจริง ไม่ใช่การประมาณ)
    @State private var now: Date = Date()
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @State private var undoMessage: String?
    @State private var undoFailed: Bool = false
    @State private var awaitingDeleteConfirm: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: DSMetrics.s4) {

            HStack(alignment: .top, spacing: DSMetrics.s3) {
                DSIconBadge(icon: event.kind.symbolName,
                            tint: event.kind.dsColor,
                            background: event.kind.dsBackground,
                            size: 34,
                            scale: fontScale)
                VStack(alignment: .leading, spacing: 4) {
                    Text(event.title)
                        .font(DSFont.font(DSFont.sHead, weight: .semibold, scale: fontScale))
                        .foregroundColor(DSColor.t1)
                        .fixedSize(horizontal: false, vertical: true)
                    DSStatusLabel(status: event.status, scale: fontScale)
                }
                Spacer(minLength: 0)
            }

            Text(event.kind.explanationTH)
                .font(DSFont.font(DSFont.sSub, scale: fontScale))
                .foregroundColor(DSColor.t2)
                .fixedSize(horizontal: false, vertical: true)

            if let note = event.note, !note.isEmpty {
                DSBanner(tone: event.isDestructive ? .error : .warning,
                         title: "ข้อควรระวัง",
                         message: note,
                         scale: fontScale)
            }

            detailSection(title: "เวลาที่ใช้",
                          value: timingText,
                          monospaced: true)

            undoSection

            if let summary = summaryText {
                detailSection(title: "สรุปสิ่งที่เกิดขึ้น", value: summary, monospaced: false)
            }

            if event.maskedCount > 0 {
                VStack(alignment: .leading, spacing: DSMetrics.s2) {
                    DSChip(text: "ปิดบังข้อมูลส่วนตัว \(event.maskedCount) จุด",
                           tone: .warning,
                           icon: "lock.fill",
                           scale: fontScale)
                    Text("แอปปิดบังข้อมูลที่อาจเป็นส่วนตัว เช่น รหัสผ่าน อีเมล เบอร์โทร ก่อนแสดงในไทม์ไลน์")
                        .font(DSFont.font(DSFont.sCap, scale: fontScale))
                        .foregroundColor(DSColor.t3)
                        .fixedSize(horizontal: false, vertical: true)
                    DSButton(title: revealed ? "ซ่อนข้อมูลอีกครั้ง" : "แตะเพื่อแสดงข้อความเดิม",
                             icon: revealed ? "eye.slash" : "eye",
                             kind: .secondary,
                             scale: fontScale,
                             action: {
                                 withAnimation(DSMotion.card) { revealed.toggle() }
                             })
                }
            }

            if let body = displayBody {
                detailSection(title: "รายละเอียดที่ได้จากขั้นนี้", value: body, monospaced: true)
            }

            HStack(spacing: DSMetrics.s3) {
                DSButton(title: copied ? "คัดลอกแล้ว" : "คัดลอก",
                         icon: copied ? "checkmark" : "doc.on.doc",
                         kind: .secondary,
                         scale: fontScale,
                         action: {
                             UIPasteboard.general.string = rawTextForCopy
                             copied = true
                             DSHaptic.success()
                         })
            }
        }
        .onReceive(ticker) { value in
            // เดินเฉพาะเมื่อมีอะไรให้เดิน (กันการวาดซ้ำโดยไม่จำเป็นบนเครื่อง 2GB)
            if event.artifactPath != nil { now = value }
        }
    }

    // MARK: - ย้อนกลับ (Undo) — ทำงานจริงเฉพาะเมื่อมีสำเนาสำรอง

    @ViewBuilder
    private var undoSection: some View {
        if let path = event.artifactPath,
           let record = WorkspaceBackup.shared.latest(forPath: path) {
            VStack(alignment: .leading, spacing: DSMetrics.s2) {
                DSChip(text: record.canUndo ? "ย้อนกลับได้อีก \(record.remainingText)" : "ย้อนกลับไม่ได้",
                       tone: record.canUndo ? .accent : .warning,
                       icon: "arrow.uturn.backward",
                       scale: fontScale)

                Text(record.kind.thaiExplanation)
                    .font(DSFont.font(DSFont.sCap, scale: fontScale))
                    .foregroundColor(DSColor.t2)
                    .fixedSize(horizontal: false, vertical: true)

                if let skipped = record.skippedReason, !record.canUndo {
                    Text(skipped)
                        .font(DSFont.font(DSFont.sCap, scale: fontScale))
                        .foregroundColor(DSColor.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if record.canUndo {
                    if record.kind == .created, awaitingDeleteConfirm {
                        Text("ยืนยันลบไฟล์ที่ Agent สร้างขึ้น? การลบย้อนกลับไม่ได้")
                            .font(DSFont.font(DSFont.sCap, weight: .semibold, scale: fontScale))
                            .foregroundColor(DSColor.error)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: DSMetrics.s3) {
                            DSButton(title: "ยืนยันลบ",
                                     icon: "trash",
                                     kind: .dangerSolid,
                                     scale: fontScale,
                                     action: { performUndo(record) })
                            DSButton(title: "ยกเลิก",
                                     kind: .secondary,
                                     scale: fontScale,
                                     action: {
                                         DSHaptic.light()
                                         awaitingDeleteConfirm = false
                                     })
                        }
                    } else {
                        DSButton(title: record.kind.thaiTitle,
                                 icon: "arrow.uturn.backward",
                                 kind: record.kind == .created ? .dangerLine : .secondary,
                                 accessibilityHint: "คืนค่าไฟล์จากสำเนาที่ระบบเก็บไว้ให้",
                                 scale: fontScale,
                                 action: {
                                     if record.kind == .created {
                                         DSHaptic.medium()
                                         awaitingDeleteConfirm = true
                                     } else {
                                         performUndo(record)
                                     }
                                 })
                    }
                }

                if let undoMessage = undoMessage {
                    DSBanner(tone: undoFailed ? .error : .success,
                             title: undoFailed ? "ย้อนกลับไม่สำเร็จ" : "ย้อนกลับสำเร็จ",
                             message: undoMessage,
                             scale: fontScale)
                }

                Text("สำเนาถูกเก็บไว้ในโฟลเดอร์ข้อมูลของแอป และจะถูกลบอัตโนมัติเมื่อเลยเวลา 10 นาที")
                    .font(DSFont.font(DSFont.sMicro, scale: fontScale))
                    .foregroundColor(DSColor.t3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func performUndo(_ record: BackupRecord) {
        DSHaptic.medium()
        awaitingDeleteConfirm = false
        do {
            try WorkspaceBackup.shared.restore(record)
            undoFailed = false
            undoMessage = record.kind == .created
                ? "ลบไฟล์ที่ Agent สร้างเรียบร้อยแล้ว"
                : "คืนไฟล์เรียบร้อยแล้ว — เปิดดูได้จากแท็บไฟล์"
            DSHaptic.success()
        } catch {
            undoFailed = true
            undoMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            DSHaptic.error()
        }
    }

    private var summaryText: String? {
        guard let first = event.previewLines(limit: 1).first, first.count < 160 else { return nil }
        return first
    }

    private var timingText: String {
        var parts: [String] = []
        if let duration = event.duration, duration >= 1 {
            parts.append(DSFormat.duration(duration))
        }
        if let start = event.startedAt {
            parts.append("เริ่ม \(DSFormat.time(start))")
        }
        if let end = event.endedAt, event.startedAt != nil {
            parts.append("จบ \(DSFormat.time(end))")
        }
        if parts.isEmpty { parts.append("—") }
        return parts.joined(separator: " · ")
    }

    private var displayBody: String? {
        let raw = event.rawDetail ?? event.detail
        guard let text = raw, !text.isEmpty else { return nil }
        if revealed { return text }
        return event.detail
    }

    private var rawTextForCopy: String {
        let raw = event.rawDetail ?? event.detail ?? ""
        return revealed ? raw : (event.detail ?? "")
    }

    private func detailSection(title: String, value: String, monospaced: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(DSFont.font(DSFont.sCap, weight: .semibold, scale: fontScale))
                .foregroundColor(DSColor.t3)
            Text(value)
                .font(monospaced ? DSFont.mono(DSFont.sMicro, scale: fontScale)
                                 : DSFont.font(DSFont.sSub, scale: fontScale))
                .foregroundColor(DSColor.t1)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
