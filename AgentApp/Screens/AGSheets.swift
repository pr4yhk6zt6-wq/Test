//
//  AGSheets.swift
//  AgentApp — แผ่นรายละเอียด · อนุมัติ · ต้นทุน/บริบท · ส่งออก · โหมดเสียง · ห้องสนทนา
//
//  ทุกแผ่นใช้ AGSheet (มุมโค้งบน + ฉากมืด + รัศมี 20) ตามแบบ และยึดหลัก:
//  บอกความจริง (ไม่มีข้อมูล → บอกว่าไม่มี) · ทุกสถานะมีทางไปต่อ · ไม่มีปุ่มที่กดแล้วไม่ได้ผลจริง
//

import SwiftUI

// MARK: - รายละเอียดขั้นตอน (ชั้นที่ 3 ของระบบกิจกรรม)

struct AGActivityDetail: View {

    let event: ActivityEvent
    var fontScale: Double = 1
    var onUndoMessage: ((String) -> Void)? = nil

    @State private var revealed: Bool = false
    @State private var undoState: UndoState = .checking
    @State private var tick: Int = 0

    private enum UndoState {
        case checking
        case available(secondsLeft: Int, kind: String)
        case unavailable(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AGMetric.s4) {
            header
            if event.maskedCount > 0 { sensitiveBlock }
            if let note = event.note, !note.isEmpty { block(title: "สิ่งที่ควรรู้", text: note) }
            if let failure = event.failureMessage, !failure.isEmpty { failureBlock(failure) }
            if let detail = displayedDetail, !detail.isEmpty {
                block(title: event.maskedCount > 0 ? "รายละเอียดจากขั้นนี้ (ปิดบังข้อมูลแล้ว)" : "รายละเอียดจากขั้นนี้",
                      text: detail,
                      monospaced: true)
            }
            undoSection
        }
        .onAppear(perform: refreshUndo)
        .onReceive(timer) { _ in
            tick += 1
            refreshUndo()
        }
    }

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var header: some View {
        HStack(alignment: .top, spacing: AGMetric.s3) {
            AGStatusGlyph(status: event.status, size: 34, scale: fontScale)
            VStack(alignment: .leading, spacing: 4) {
                Text(event.title)
                    .font(AGFont.font(AGFont.title, weight: .semibold, scale: fontScale))
                    .foregroundColor(AGColor.t1)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: AGMetric.s2) {
                    AGChip(text: event.status.agThai, tone: toneChip, scale: fontScale)
                    if event.isDestructive { AGChip(text: "ย้อนกลับไม่ได้", tone: .err, scale: fontScale) }
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var toneChip: AGChip.Tone {
        switch event.status {
        case .succeeded: return .ok
        case .failed: return .err
        case .running: return .run
        case .waitingUser: return .warn
        default: return .neutral
        }
    }

    private var displayedDetail: String? {
        if revealed { return event.rawDetail ?? event.detail }
        return event.detail
    }

    private var sensitiveBlock: some View {
        VStack(alignment: .leading, spacing: AGMetric.s2) {
            AGBanner(tone: .info,
                     title: "พบข้อมูลอ่อนไหว \(event.maskedCount) จุด และปิดบังไว้แล้ว",
                     message: "ระบบปิดบังอัตโนมัติ (คีย์ รหัสผ่าน อีเมล เบอร์โทร เลขบัตร) — กดด้านล่างถ้าจำเป็นต้องเห็น",
                     scale: fontScale)
            AGButton(title: revealed ? "ซ่อนข้อมูลอีกครั้ง" : "แตะเพื่อแสดงข้อมูลที่ปิดบัง",
                     icon: revealed ? "eye.slash" : "eye",
                     kind: .secondary,
                     scale: fontScale) {
                revealed.toggle()
            }
        }
    }

    private func block(title: String, text: String, monospaced: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: AGMetric.s2) {
            Text(title)
                .font(AGFont.font(AGFont.cap, weight: .semibold, scale: fontScale))
                .foregroundColor(AGColor.t2)
            Text(text)
                .font(monospaced ? AGFont.mono(AGFont.foot, scale: fontScale) : AGFont.font(AGFont.sub, scale: fontScale))
                .foregroundColor(AGColor.t1)
                .lineSpacing(AGFont.lineSpacing(AGFont.sub, scale: fontScale, multiplier: AGFont.lhMeta))
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .padding(AGMetric.s3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: AGMetric.rSM, style: .continuous).fill(AGColor.surface2))
        }
    }

    private func failureBlock(_ failure: String) -> some View {
        AGBanner(tone: .error,
                 title: "ขั้นนี้ไม่สำเร็จ",
                 message: failure,
                 scale: fontScale)
    }

    // MARK: - ย้อนกลับ (จริง ไม่ใช่ปุ่มหลอก)

    private var undoSection: some View {
        Group {
            switch undoState {
            case .checking:
                EmptyView()
            case .available(let secondsLeft, let kind):
                VStack(alignment: .leading, spacing: AGMetric.s2) {
                    Text("ย้อนกลับการกระทำนี้")
                        .font(AGFont.font(AGFont.cap, weight: .semibold, scale: fontScale))
                        .foregroundColor(AGColor.t2)
                    Text("ทำได้อีก \(AGFormat.durationShort(TimeInterval(secondsLeft))) — ระบบเก็บสำเนาไฟล์ไว้ก่อน Agent ลงมือ")
                        .font(AGFont.font(AGFont.cap, scale: fontScale))
                        .foregroundColor(AGColor.t3)
                        .fixedSize(horizontal: false, vertical: true)
                    AGButton(title: kind, icon: "arrow.uturn.backward", kind: .secondary, scale: fontScale) {
                        performUndo(kind: kind)
                    }
                }
                .id(tick)
            case .unavailable(let reason):
                Text(reason)
                    .font(AGFont.font(AGFont.cap, scale: fontScale))
                    .foregroundColor(AGColor.t3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func refreshUndo() {
        guard let path = event.artifactPath else {
            undoState = .unavailable("ขั้นนี้ไม่เกี่ยวกับไฟล์ จึงไม่มีอะไรต้องย้อนกลับ")
            return
        }
        guard let record = WorkspaceBackup.shared.latest(forPath: path) else {
            undoState = .unavailable("ไม่มีสำเนาสำรองของไฟล์นี้แล้ว (เกินเวลาที่เก็บไว้ หรือไฟล์ใหญ่เกินกว่าจะสำรอง)")
            return
        }
        guard record.backupPath != nil else {
            undoState = .unavailable(record.skippedReason ?? "ไม่มีสำเนาเก็บไว้ของไฟล์นี้ จึงย้อนกลับไม่ได้")
            return
        }
        let left = record.remainingSeconds
        guard left > 0 else {
            undoState = .unavailable("เลยเวลาที่ย้อนกลับได้ของขั้นนี้แล้ว (เก็บสำเนาไว้ 10 นาที)")
            return
        }
        undoState = .available(secondsLeft: left, kind: record.kind.thaiTitle)
    }

    private func performUndo(kind: String) {
        guard let path = event.artifactPath,
              let record = WorkspaceBackup.shared.latest(forPath: path) else { return }
        AGHaptic.medium()
        do {
            try WorkspaceBackup.shared.restore(record)
            onUndoMessage?("ย้อนกลับสำเร็จ — \(record.kind.thaiExplanation)")
            AGHaptic.success()
            refreshUndo()
        } catch let error as WorkspaceBackup.UndoError {
            onUndoMessage?("ย้อนกลับไม่สำเร็จ: \(error.errorDescription ?? "ไม่ทราบสาเหตุ") — ไฟล์ปัจจุบันยังอยู่ครบ")
        } catch {
            onUndoMessage?("ย้อนกลับไม่สำเร็จ — ไฟล์ปัจจุบันยังอยู่ครบ")
        }
    }
}

// MARK: - แผ่นขออนุมัติ (บอก "จะทำอะไร ที่ไหน ผลคืออะไร" + ยืนยันก่อนลบ)

struct AGApprovalSheet: View {

    let request: ApprovalRequest
    var fontScale: Double = 1
    let onDecide: (ApprovalDecision) -> Void

    @State private var confirmedDestructive: Bool = false

    var body: some View {
        ZStack {
            AGColor.scrim.ignoresSafeArea()
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: AGMetric.s4) {
                        header
                        if request.isDestructive { destructiveWarning }
                        block(title: "จะทำอะไร", text: request.summary)
                        if let detail = request.detail, !detail.isEmpty {
                            block(title: "ที่ไหน", text: detail, monospaced: true)
                        }
                        if !request.risk.reasons.isEmpty { riskBlock }
                        block(title: "สิ่งที่ Agent จะส่งไป", text: request.argumentsText, monospaced: true)
                        scopeBlock
                    }
                    .padding(.horizontal, AGMetric.screenPadding)
                    .padding(.vertical, AGMetric.s4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                actions
            }
            .background(RoundedCorner(radius: AGMetric.rLG, corners: [.topLeft, .topRight]).fill(AGColor.surface))
            .frame(maxHeight: UIScreen.main.bounds.height * 0.86)
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .accessibilityAddTraits(.isModal)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: AGMetric.s3) {
            Image(systemName: request.isDestructive ? "exclamationmark.triangle.fill" : "hand.raised.fill")
                .font(AGFont.font(AGFont.title, scale: fontScale))
                .foregroundColor(request.isDestructive ? AGColor.error : AGColor.warning)
                .frame(width: AGMetric.touch, height: AGMetric.touch)
                .background(RoundedRectangle(cornerRadius: AGMetric.rSM, style: .continuous)
                    .fill(request.isDestructive ? AGColor.errorSoft : AGColor.warningSoft))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("ต้องการอนุญาตก่อนทำต่อ")
                    .font(AGFont.font(AGFont.title, weight: .semibold, scale: fontScale))
                    .foregroundColor(AGColor.t1)
                    .fixedSize(horizontal: false, vertical: true)
                Text(request.isDestructive ? "Agent กำลังจะทำสิ่งที่ย้อนกลับไม่ได้" : "Agent ขออนุญาตก่อนลงมือ")
                    .font(AGFont.font(AGFont.sub, scale: fontScale))
                    .foregroundColor(AGColor.t2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private var destructiveWarning: some View {
        AGBanner(tone: .error,
                 title: "การกระทำนี้ย้อนกลับไม่ได้",
                 message: "การลบไฟล์บน iPhone ที่ยังไม่เจลเบรคเต็มรูปแบบกู้คืนไม่ได้ ถ้าไม่แน่ใจ ให้กด \"ไม่อนุญาต\" แล้วบอก Agent ว่าต้องการเก็บไฟล์ไว้",
                 scale: fontScale)
    }

    private func block(title: String, text: String, monospaced: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: AGMetric.s2) {
            Text(title)
                .font(AGFont.font(AGFont.cap, weight: .semibold, scale: fontScale))
                .foregroundColor(AGColor.t2)
            Text(text)
                .font(monospaced ? AGFont.mono(AGFont.foot, scale: fontScale) : AGFont.font(AGFont.sub, scale: fontScale))
                .foregroundColor(AGColor.t1)
                .lineSpacing(AGFont.lineSpacing(AGFont.sub, scale: fontScale, multiplier: AGFont.lhMeta))
                .fixedSize(horizontal: false, vertical: true)
                .padding(AGMetric.s3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: AGMetric.rSM, style: .continuous).fill(AGColor.surface2))
        }
    }

    private var riskBlock: some View {
        VStack(alignment: .leading, spacing: AGMetric.s2) {
            Text("เหตุที่ระบบจัดว่าเสี่ยง")
                .font(AGFont.font(AGFont.cap, weight: .semibold, scale: fontScale))
                .foregroundColor(AGColor.t2)
            ForEach(request.risk.reasons, id: \.self) { reason in
                HStack(alignment: .top, spacing: AGMetric.s2) {
                    Circle().fill(AGColor.warning).frame(width: 6, height: 6).padding(.top, 6)
                    Text(reason)
                        .font(AGFont.font(AGFont.sub, scale: fontScale))
                        .foregroundColor(AGColor.t1)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var scopeBlock: some View {
        VStack(alignment: .leading, spacing: AGMetric.s2) {
            Text("ขอบเขตของสิทธิ์")
                .font(AGFont.font(AGFont.cap, weight: .semibold, scale: fontScale))
                .foregroundColor(AGColor.t2)
            Text("บิลด์นี้ให้เลือกได้ 2 ทาง: อนุญาตครั้งนี้ แล้วระบบจะถามใหม่ทุกครั้ง · หรือไม่อนุญาต (ยังไม่มีโหมด \"จำไว้ตลอดไป\" เพราะยังไม่มีระบบเพิกถอนสิทธิ์ในแอป)")
                .font(AGFont.font(AGFont.cap, scale: fontScale))
                .foregroundColor(AGColor.t3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var actions: some View {
        VStack(spacing: AGMetric.s2) {
            if request.isDestructive {
                Button(action: {
                    AGHaptic.light()
                    confirmedDestructive.toggle()
                }) {
                    HStack(spacing: AGMetric.s2) {
                        Image(systemName: confirmedDestructive ? "checkmark.square.fill" : "square")
                            .font(AGFont.font(AGFont.callout, scale: fontScale))
                            .foregroundColor(confirmedDestructive ? AGColor.error : AGColor.t3)
                        Text("ฉันเข้าใจว่าการลบนี้กู้คืนไม่ได้")
                            .font(AGFont.font(AGFont.sub, scale: fontScale))
                            .foregroundColor(AGColor.t1)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: AGMetric.touch)
                    .contentShape(Rectangle())
                }
                .buttonStyle(AGPressableStyle())
                .accessibilityLabel(Text("ยืนยันว่าเข้าใจว่าการลบกู้คืนไม่ได้"))
                .accessibilityValue(Text(confirmedDestructive ? "เลือกแล้ว" : "ยังไม่เลือก"))
            }

            AGButton(title: "อนุญาตครั้งนี้",
                     icon: "checkmark.circle.fill",
                     kind: .primary,
                     isEnabled: !request.isDestructive || confirmedDestructive,
                     scale: fontScale,
                     hint: request.isDestructive && !confirmedDestructive ? "ต้องติ๊กยืนยันก่อน เพราะการลบกู้คืนไม่ได้" : nil) {
                onDecide(.allowOnce)
            }

            AGButton(title: "ไม่อนุญาต", icon: "xmark", kind: .secondary, scale: fontScale) {
                onDecide(.deny)
            }

            DSScopeNote()
        }
        .padding(.horizontal, AGMetric.screenPadding)
        .padding(.top, AGMetric.s2)
        .padding(.bottom, AGMetric.s4)
        .background(AGColor.surface)
        .overlay(Rectangle().fill(AGColor.border).frame(height: 1), alignment: .top)
    }

    private struct DSScopeNote: View {
        var body: some View {
            Text("ทุกครั้งที่ Agent จะมีผลกับเครื่อง จะถามแบบนี้เสมอ ถ้าปิดสวิตช์ \"ถามก่อนทุกครั้ง\" ในหน้าตั้งค่า แอปจะแสดงแบนเนอร์เตือนค้างไว้")
                .font(AGFont.font(AGFont.micro))
                .foregroundColor(AGColor.t3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - ต้นทุนและบริบท (ตัวเลขจริงเท่านั้น)

struct AGCostSheet: View {

    var fontScale: Double = 1
    @ObservedObject private var usage: TokenUsageTracker = .shared
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AGMetric.s4) {
                AGCard(padding: AGMetric.s4) {
                    VStack(alignment: .leading, spacing: AGMetric.s3) {
                        kv("โทเคนที่ใช้ในห้องนี้", usage.hasData ? usage.compactShortText : "ยังไม่มีข้อมูล")
                        kv("ค่าใช้จ่าย", costText)
                        kv("ขอบเขตบทสนทนาที่ตั้งไว้", "\(settings.contextLengthTokens) โทเคน")
                    }
                }
                AGBanner(tone: .info,
                         title: "ตัวเลขทั้งหมดมาจากผู้ให้บริการจริง",
                         message: "โทเคนนับจากคำขอจริง ถ้าโมเดลไม่ส่งค่าใช้จ่ายกลับมา ระบบจะบอกว่า \"ไม่ระบุ\" ไม่เดาให้ และไม่มีการประมาณเวลาที่เหลือ",
                         scale: fontScale)
            }
            .padding(.horizontal, AGMetric.screenPadding)
            .padding(.vertical, AGMetric.s3)
        }
        .frame(maxHeight: 420)
    }

    private var costText: String {
        if let cost = usage.costCredits { return String(format: "%.6f เครดิต", cost) }
        return "ไม่ระบุ — โมเดลนี้ไม่ส่งข้อมูลค่าใช้จ่าย"
    }

    private func kv(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: AGMetric.s2) {
            Text(title)
                .font(AGFont.font(AGFont.sub, scale: fontScale))
                .foregroundColor(AGColor.t2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: AGMetric.s2)
            Text(value)
                .font(AGFont.font(AGFont.sub, weight: .semibold, scale: fontScale))
                .foregroundColor(AGColor.t1)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - ส่งออกการสนทนา (เตือนข้อมูลอ่อนไหว + ปิดบังให้ก่อน)

struct AGExportSheet: View {

    var fontScale: Double = 1
    let markdown: String

    @State private var masked: Bool = true
    @State private var savedURL: URL?
    @State private var message: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AGMetric.s4) {
                AGBanner(tone: .warning,
                         title: "ก่อนส่งออก ลองอ่านตรงนี้ก่อน",
                         message: "ไฟล์ที่ส่งออกจะมีการสนทนาทั้งหมด รวมสิ่งที่ Agent อ่านจากเครื่องของคุณ ถ้ามีข้อมูลอ่อนไหว ระบบจะปิดบังให้ก่อนตามที่เลือกไว้ด้านล่าง",
                         scale: fontScale)

                Button(action: {
                    AGHaptic.light()
                    masked.toggle()
                }) {
                    HStack(spacing: AGMetric.s2) {
                        Image(systemName: masked ? "checkmark.square.fill" : "square")
                            .font(AGFont.font(AGFont.callout, scale: fontScale))
                            .foregroundColor(masked ? AGColor.accentInk : AGColor.t3)
                        Text("ปิดบังข้อมูลอ่อนไหวก่อนบันทึก")
                            .font(AGFont.font(AGFont.sub, scale: fontScale))
                            .foregroundColor(AGColor.t1)
                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: AGMetric.touch)
                    .contentShape(Rectangle())
                }
                .buttonStyle(AGPressableStyle())
                .accessibilityLabel(Text("ปิดบังข้อมูลอ่อนไหวก่อนบันทึก"))
                .accessibilityValue(Text(masked ? "เปิดอยู่" : "ปิดอยู่"))

                AGCard(padding: AGMetric.s3) {
                    VStack(alignment: .leading, spacing: AGMetric.s2) {
                        Text("ตัวอย่างไฟล์ที่จะได้ (ย่อ)")
                            .font(AGFont.font(AGFont.cap, weight: .semibold, scale: fontScale))
                            .foregroundColor(AGColor.t2)
                        Text(previewText)
                            .font(AGFont.mono(AGFont.cap, scale: fontScale))
                            .foregroundColor(AGColor.t2)
                            .lineLimit(8)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                AGButton(title: "บันทึกเป็นไฟล์ .md", icon: "square.and.arrow.down", kind: .primary, scale: fontScale) {
                    export()
                }

                if let message = message {
                    Text(message)
                        .font(AGFont.font(AGFont.cap, scale: fontScale))
                        .foregroundColor(AGColor.t2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, AGMetric.screenPadding)
            .padding(.vertical, AGMetric.s3)
        }
        .frame(maxHeight: 520)
    }

    private var previewText: String {
        let body = masked ? SensitiveMask.mask(markdown).text : markdown
        return String(body.prefix(600))
    }

    private func export() {
        let body = masked ? SensitiveMask.mask(markdown).text : markdown
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("บทสนทนา-\(Int(Date().timeIntervalSince1970)).md")
        do {
            try body.write(to: url, atomically: true, encoding: .utf8)
            savedURL = url
            message = "บันทึกแล้ว: \(url.lastPathComponent) — เปิดได้จากแอปไฟล์หรือแชร์ต่อจากที่นี่"
        } catch {
            message = "บันทึกไม่สำเร็จ: \(error.localizedDescription)"
        }
    }
}

// MARK: - โหมดเสียง (พูดแล้วได้ข้อความ ตรวจก่อนส่ง)

struct AGVoiceSheet: View {

    var fontScale: Double = 1
    let onUseText: (String) -> Void

    @StateObject private var voice = VoiceInputService()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AGMetric.s4) {
                AGBanner(tone: .info,
                         title: voice.onDeviceOnly ? "เครื่องนี้ถอดเสียงให้ในตัว" : "เครื่องนี้อาจต้องใช้อินเทอร์เน็ตในการถอดเสียง",
                         message: voice.onDeviceOnly
                            ? "เสียงไม่ถูกส่งออกไปที่อื่นเลย และแอปไม่เก็บไฟล์เสียงไว้"
                            : "ถ้าเครื่องถอดเสียงในตัวไม่ได้ ระบบจะส่งเสียงไปประมวลผลออนไลน์ (ไม่ได้เก็บไว้) — ข้อความที่ได้จะรอให้คุณตรวจก่อนส่งเสมอ",
                         scale: fontScale)

                stateArea
            }
            .padding(.horizontal, AGMetric.screenPadding)
            .padding(.vertical, AGMetric.s3)
        }
        .frame(maxHeight: 460)
        .onAppear { voice.prepare() }
        .onDisappear { voice.stop() }
    }

    @ViewBuilder
    private var stateArea: some View {
        switch voice.phase {
        case .listening:
            VStack(alignment: .leading, spacing: AGMetric.s3) {
                HStack(spacing: AGMetric.s2) {
                    AGPulseDot(tone: AGColor.accent, size: 14)
                    Text("กำลังฟัง… พูดได้เลย")
                        .font(AGFont.font(AGFont.sub, weight: .semibold, scale: fontScale))
                        .foregroundColor(AGColor.t1)
                }
                if !voice.transcript.isEmpty { transcriptBox }
                AGButton(title: "หยุดและใช้ข้อความนี้", icon: "stop.fill", kind: .primary, scale: fontScale) {
                    voice.stop()
                }
            }
        case .denied:
            AGBanner(tone: .warning, title: "ยังไม่ได้รับอนุญาตใช้ไมโครโฟน",
                     message: "เปิดได้ที่ ตั้งค่า → ความเป็นส่วนตัวและความปลอดภัย → ไมโครโฟน → AI Agent", scale: fontScale)
        case .unavailable(let text), .failed(let text):
            AGBanner(tone: .warning, title: "ยังใช้โหมดเสียงไม่ได้", message: text, scale: fontScale)
        case .preparing:
            VStack(alignment: .leading, spacing: AGMetric.s2) {
                Text("กำลังขออนุญาตจากระบบ")
                    .font(AGFont.font(AGFont.sub, weight: .semibold, scale: fontScale))
                    .foregroundColor(AGColor.t1)
                AGSkeleton(lines: 2, scale: fontScale)
            }
        case .idle:
            VStack(alignment: .leading, spacing: AGMetric.s3) {
                if voice.transcript.isEmpty {
                    Text("พร้อมฟังแล้ว — กดปุ่มด้านล่างแล้วพูดเป็นภาษาไทย")
                        .font(AGFont.font(AGFont.sub, scale: fontScale))
                        .foregroundColor(AGColor.t2)
                        .fixedSize(horizontal: false, vertical: true)
                    AGButton(title: "เริ่มพูด", icon: "mic.fill", kind: .primary, scale: fontScale) {
                        voice.start()
                    }
                } else {
                    transcriptBox
                    AGButton(title: "ใช้ข้อความนี้", icon: "checkmark.circle.fill", kind: .primary, scale: fontScale) {
                        let text = voice.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                        voice.reset()
                        onUseText(text)
                    }
                }
            }
        }
    }

    private var transcriptBox: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(voice.transcript)
                .font(AGFont.font(AGFont.body, scale: fontScale))
                .foregroundColor(AGColor.t1)
                .fixedSize(horizontal: false, vertical: true)
            Text("ยังไม่ถูกส่ง — จะไปอยู่ในช่องพิมพ์ให้ตรวจก่อน")
                .font(AGFont.font(AGFont.micro, scale: fontScale))
                .foregroundColor(AGColor.t3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(AGMetric.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: AGMetric.rSM, style: .continuous).fill(AGColor.surface2))
    }
}

// MARK: - ห้องสนทนา (ไม่ถือสถานะเอง — ส่งคำสั่งกลับไปที่หน้าแชท)

struct AGRoomsSheet: View {

    let rooms: [ChatRoom]
    let currentRoomID: UUID?
    let onSelect: (ChatRoom) -> Void
    let onCreate: (String) -> Void
    let onDelete: (ChatRoom) -> Void
    let onClose: () -> Void
    var fontScale: Double = 1

    @State private var newRoomName: String = ""
    @State private var pendingDelete: ChatRoom?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("ห้องสนทนา")
                    .font(AGFont.font(AGFont.title, weight: .semibold, scale: fontScale))
                    .foregroundColor(AGColor.t1)
                Spacer(minLength: 0)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(AGFont.font(AGFont.callout, weight: .semibold, scale: fontScale))
                        .foregroundColor(AGColor.t2)
                        .frame(width: AGMetric.touch, height: AGMetric.touch)
                        .contentShape(Rectangle())
                }
                .buttonStyle(AGPressableStyle())
                .accessibilityLabel(Text("ปิด"))
            }
            .padding(.horizontal, AGMetric.screenPadding)
            .padding(.top, AGMetric.s3)

            ScrollView {
                VStack(alignment: .leading, spacing: AGMetric.s3) {
                    HStack(spacing: AGMetric.s2) {
                        TextField("ชื่อห้องใหม่", text: $newRoomName)
                            .font(AGFont.font(AGFont.body, scale: fontScale))
                            .padding(.horizontal, AGMetric.s3)
                            .frame(minHeight: AGMetric.touch)
                            .background(RoundedRectangle(cornerRadius: AGMetric.rSM, style: .continuous).fill(AGColor.surface2))
                        AGButton(title: "สร้างห้อง", kind: .primary, scale: fontScale) {
                            let name = newRoomName.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !name.isEmpty else { return }
                            newRoomName = ""
                            onCreate(name)
                        }
                        .frame(width: 118)
                    }

                    ForEach(rooms) { room in
                        AGCard(padding: 0) {
                            AGRow(icon: room.id == currentRoomID ? "checkmark.circle.fill" : "bubble.left",
                                  title: room.name,
                                  subtitle: room.id == currentRoomID ? "ห้องที่กำลังเปิดอยู่" : nil,
                                  showsChevron: true,
                                  scale: fontScale) {
                                onSelect(room)
                            }
                        }
                        .contextMenu {
                            Button(action: { pendingDelete = room }) {
                                Label("ลบห้องนี้", systemImage: "trash")
                            }
                        }
                    }

                    Text("แตะค้างที่ห้องเพื่อลบ · การลบจะลบประวัติของห้องนั้นออกจากเครื่อง")
                        .font(AGFont.font(AGFont.micro, scale: fontScale))
                        .foregroundColor(AGColor.t3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, AGMetric.screenPadding)
                .padding(.vertical, AGMetric.s3)
            }
            .frame(maxHeight: 460)
        }
        .alert(item: $pendingDelete) { room in
            Alert(title: Text("ลบห้อง \"\(room.name)\"?"),
                  message: Text("ประวัติการสนทนาของห้องนี้จะถูกลบจากเครื่อง และย้อนกลับไม่ได้"),
                  primaryButton: .destructive(Text("ลบห้อง")) { onDelete(room) },
                  secondaryButton: .cancel(Text("ยกเลิก")))
        }
    }
}
