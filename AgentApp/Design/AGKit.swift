//
//  AGKit.swift
//  AgentApp — คอมโพเนนต์ทั้งหมด (พอร์ตจาก CSS ของแบบตรงตัว)
//
//  ทุกคอมโพเนนต์ในไฟล์นี้เทียบเคียงกับคลาสใน design-phase1.html / phase4-prototype.html:
//  .step-ico  .pulse  .ribbon  .chip  .livebar  .tl  .step  .bubble  .qchip  .field  .send  .sheet
//  ตัวเลข (ขนาด/ระยะ/มุม/สี) ใช้ค่าเดียวกับแบบ ไม่ปรับตามใจ
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - ปุ่มกดที่มีสถานะกด

struct AGPressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.72 : 1)
            .animation(AGMotion.animation(.easeOut(duration: AGMotion.dur1)), value: configuration.isPressed)
    }
}

// MARK: - วงกลมสถานะ (เทียบ .step-ico)

extension ActivityStatus {

    var agColor: Color {
        switch self {
        case .pending: return AGColor.t3
        case .running: return AGColor.accentInk
        case .waitingUser: return AGColor.warning
        case .succeeded: return AGColor.success
        case .failed: return AGColor.error
        case .skipped: return AGColor.t3
        case .cancelled: return AGColor.t3
        }
    }

    var agBackground: Color {
        switch self {
        case .pending, .skipped, .cancelled: return AGColor.surface2
        case .running: return AGColor.accentSoft
        case .waitingUser: return AGColor.warningSoft
        case .succeeded: return AGColor.successSoft
        case .failed: return AGColor.errorSoft
        }
    }

    var agSymbol: String {
        switch self {
        case .pending: return "clock"
        case .running: return "arrow.triangle.2.circlepath"
        case .waitingUser: return "hand.raised.fill"
        case .succeeded: return "checkmark"
        case .failed: return "exclamationmark"
        case .skipped: return "minus"
        case .cancelled: return "xmark"
        }
    }

    var agThai: String {
        switch self {
        case .pending: return "รอคิว"
        case .running: return "กำลังทำ"
        case .waitingUser: return "รอคุณตอบ"
        case .succeeded: return "เสร็จแล้ว"
        case .failed: return "ไม่สำเร็จ"
        case .skipped: return "ข้ามไป"
        case .cancelled: return "ยกเลิก"
        }
    }
}

struct AGStatusGlyph: View {

    let status: ActivityStatus
    var size: CGFloat = AGMetric.stepIcon
    var scale: Double = 1
    @State private var breathe: Bool = false

    var body: some View {
        let side = AGFont.size(size, scale: scale)
        ZStack {
            Circle().fill(status.agBackground)
            if status != .succeeded, status != .running, status != .failed {
                Circle().stroke(AGColor.border, lineWidth: 1)
            }
            Image(systemName: status.agSymbol)
                .font(AGFont.font(side * 0.45, weight: .semibold, scale: 1))
                .foregroundColor(status.agColor)
                .opacity(status == .running && breathe ? 0.45 : 1)
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
        .onAppear {
            guard status == .running, !AGMotion.reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { breathe = true }
        }
    }
}

// MARK: - จุดเต้น (เทียบ .pulse — วงแหวน 18pt)

struct AGPulseDot: View {

    var tone: Color = AGColor.accent
    var size: CGFloat = 18
    @State private var animate: Bool = false

    var body: some View {
        ZStack {
            Circle().stroke(tone.opacity(0.35), lineWidth: 2)
            Circle()
                .stroke(tone, lineWidth: 2)
                .scaleEffect(animate ? 1 : 0.45)
                .opacity(animate ? 0 : 0.9)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
        .onAppear {
            guard !AGMotion.reduceMotion else { return }
            withAnimation(.easeOut(duration: 1.8).repeatForever(autoreverses: false)) { animate = true }
        }
    }
}

// MARK: - ริบบิ้นความคืบหน้า (เทียบ .ribbon)

struct AGRibbon: View {

    var total: Int = 6
    var done: Int = 0
    var active: Int = -1
    var tone: Color = AGColor.accent

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<max(1, total), id: \.self) { index in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(index < done ? tone : (index == active ? tone.opacity(0.35) : AGColor.surface2))
                    .frame(height: 3)
                    .frame(maxWidth: .infinity)
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - ชิป (เทียบ .chip และ .chip.ok/.err/.run/.warn)

struct AGChip: View {

    enum Tone { case neutral, ok, err, run, warn }

    let text: String
    var tone: Tone = .neutral
    var scale: Double = 1

    var body: some View {
        Text(text)
            .font(AGFont.font(AGFont.micro, weight: .medium, scale: scale))
            .foregroundColor(foreground)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Capsule().fill(background))
            .fixedSize()
    }

    private var foreground: Color {
        switch tone {
        case .neutral: return AGColor.t2
        case .ok: return AGColor.success
        case .err: return AGColor.error
        case .run: return AGColor.accentInk
        case .warn: return AGColor.warning
        }
    }

    private var background: Color {
        switch tone {
        case .neutral: return AGColor.surface2
        case .ok: return AGColor.successSoft
        case .err: return AGColor.errorSoft
        case .run: return AGColor.accentSoft
        case .warn: return AGColor.warningSoft
        }
    }
}

// MARK: - การ์ด (เทียบ .tl / การ์ดขอบ 1px รัศมี 16)

struct AGCard<Content: View>: View {

    var padding: CGFloat = 0
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: AGMetric.rMD, style: .continuous).fill(AGColor.surface))
            .overlay(
                RoundedRectangle(cornerRadius: AGMetric.rMD, style: .continuous)
                    .stroke(AGColor.border, lineWidth: 1)
            )
    }
}

// MARK: - ปุ่ม (ตามแบบ: ปุ่มทึบสีเน้น / ปุ่มขอบ / ปุ่มข้อความ)

struct AGButton: View {

    enum Kind { case primary, secondary, ghost, danger }

    let title: String
    var icon: String? = nil
    var kind: Kind = .primary
    var isEnabled: Bool = true
    var scale: Double = 1
    var hint: String? = nil
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(action: {
                guard isEnabled else { return }
                AGHaptic.light()
                action()
            }) {
                HStack(spacing: AGMetric.s2) {
                    if let icon = icon {
                        Image(systemName: icon)
                            .font(AGFont.font(AGFont.callout, weight: .semibold, scale: scale))
                    }
                    Text(title)
                        .font(AGFont.font(AGFont.callout, weight: .semibold, scale: scale))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundColor(isEnabled ? foreground : AGColor.t3)
                .frame(maxWidth: .infinity)
                .frame(minHeight: kind == .ghost ? 38 : 48)
                .padding(.horizontal, AGMetric.s3)
                .background(background)
                .overlay(
                    RoundedRectangle(cornerRadius: AGMetric.rSM, style: .continuous)
                        .stroke(borderColor, lineWidth: kind == .secondary ? 1 : 0)
                )
            }
            .buttonStyle(AGPressableStyle())
            .disabled(!isEnabled)
            .accessibilityHint(Text(hint ?? ""))

            if let hint = hint, !isEnabled {
                Text(hint)
                    .font(AGFont.font(AGFont.micro, scale: scale))
                    .foregroundColor(AGColor.t3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var foreground: Color {
        switch kind {
        case .primary: return AGColor.onAccent
        case .secondary: return AGColor.t1
        case .ghost: return AGColor.accentInk
        case .danger: return AGColor.error
        }
    }

    @ViewBuilder
    private var background: some View {
        switch kind {
        case .primary:
            RoundedRectangle(cornerRadius: AGMetric.rSM, style: .continuous).fill(AGColor.accent)
        case .secondary:
            RoundedRectangle(cornerRadius: AGMetric.rSM, style: .continuous).fill(AGColor.surface)
        case .ghost:
            RoundedRectangle(cornerRadius: AGMetric.rSM, style: .continuous).fill(Color.clear)
        case .danger:
            RoundedRectangle(cornerRadius: AGMetric.rSM, style: .continuous).fill(AGColor.errorSoft)
        }
    }

    private var borderColor: Color {
        switch kind {
        case .secondary: return AGColor.borderStrong
        case .danger: return AGColor.error.opacity(0.35)
        default: return .clear
        }
    }
}

// MARK: - แบนเนอร์ (ภาษาไทยล้วน + ไอคอนคู่ข้อความเสมอ)

struct AGBanner: View {

    enum Tone { case info, success, warning, error

        var icon: String {
            switch self {
            case .info: return "info.circle.fill"
            case .success: return "checkmark.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .error: return "exclamationmark.octagon.fill"
            }
        }

        var color: Color {
            switch self {
            case .info: return AGColor.accentInk
            case .success: return AGColor.success
            case .warning: return AGColor.warning
            case .error: return AGColor.error
            }
        }

        var background: Color {
            switch self {
            case .info: return AGColor.accentSoft
            case .success: return AGColor.successSoft
            case .warning: return AGColor.warningSoft
            case .error: return AGColor.errorSoft
            }
        }
    }

    let tone: Tone
    let title: String
    var message: String? = nil
    var scale: Double = 1
    var actions: (() -> AnyView)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: AGMetric.s2) {
            HStack(alignment: .top, spacing: AGMetric.s3) {
                Image(systemName: tone.icon)
                    .font(AGFont.font(AGFont.callout, weight: .semibold, scale: scale))
                    .foregroundColor(tone.color)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(AGFont.font(AGFont.sub, weight: .semibold, scale: scale))
                        .foregroundColor(AGColor.t1)
                        .fixedSize(horizontal: false, vertical: true)
                    if let message = message {
                        Text(message)
                            .font(AGFont.font(AGFont.cap, scale: scale))
                            .foregroundColor(AGColor.t2)
                            .lineSpacing(AGFont.lineSpacing(AGFont.cap, scale: scale, multiplier: AGFont.lhMeta))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            if let actions = actions { actions() }
        }
        .padding(AGMetric.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: AGMetric.rSM, style: .continuous).fill(tone.background))
        .overlay(
            RoundedRectangle(cornerRadius: AGMetric.rSM, style: .continuous)
                .stroke(tone.color.opacity(0.22), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }
}

// MARK: - ข้อความคำตอบของ Agent (เทียบ .agent-text)

struct AGAgentText: View {

    let markdown: String
    var scale: Double = 1

    var body: some View {
        VStack(alignment: .leading, spacing: AGMetric.s3) {
            ForEach(MarkdownRenderer.parse(markdown)) { block in
                switch block.kind {
                case .text(let text):
                    Text(MarkdownRenderer.attributedText(from: text))
                        .font(AGFont.font(AGFont.body, scale: scale))
                        .foregroundColor(AGColor.t1)
                        .lineSpacing(AGFont.lineSpacing(AGFont.body, scale: scale))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                case .code(let language, let code):
                    AGCodeBlock(language: language, code: code, scale: scale)
                }
            }
        }
    }
}

struct AGCodeBlock: View {

    let language: String?
    let code: String
    var scale: Double = 1

    @State private var copied: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: AGMetric.s2) {
            HStack {
                Text(language ?? "โค้ด")
                    .font(AGFont.font(AGFont.micro, weight: .medium, scale: scale))
                    .foregroundColor(AGColor.t3)
                Spacer(minLength: 0)
                Button(action: {
                    UIPasteboard.general.string = code
                    AGHaptic.success()
                    copied = true
                }) {
                    Text(copied ? "คัดลอกแล้ว" : "คัดลอก")
                        .font(AGFont.font(AGFont.micro, weight: .semibold, scale: scale))
                        .foregroundColor(AGColor.accentInk)
                        .frame(minHeight: 30)
                }
                .buttonStyle(AGPressableStyle())
            }
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(AGFont.mono(AGFont.foot, scale: scale))
                    .foregroundColor(AGColor.t1)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(AGMetric.s3)
            }
            .background(RoundedRectangle(cornerRadius: AGMetric.rSM, style: .continuous).fill(AGColor.surface2))
        }
    }
}

// MARK: - บับเบิลผู้ใช้ (เทียบ .bubble)

struct AGBubble: View {

    let text: String
    var scale: Double = 1

    var body: some View {
        Text(text)
            .font(AGFont.font(AGFont.body, scale: scale))
            .foregroundColor(AGColor.t1)
            .lineSpacing(AGFont.lineSpacing(AGFont.body, scale: scale))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                AGBubbleShape().fill(AGColor.accentSoft)
            )
            .frame(maxWidth: UIScreen.main.bounds.width * 0.84, alignment: .trailing)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .accessibilityLabel(Text("คุณพูดว่า \(text)"))
    }
}

/// รูปทรงบับเบิลตามแบบ: 18pt ทั้งสามมุม และ 6pt ที่มุมขวาล่าง (หางข้อความ)
struct AGBubbleShape: Shape {

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(roundedRect: rect,
                                byRoundingCorners: [.topLeft, .topRight, .bottomLeft],
                                cornerRadii: CGSize(width: 18, height: 18))
        let tail = UIBezierPath(roundedRect: CGRect(x: rect.maxX - 12, y: rect.maxY - 12, width: 12, height: 12),
                                byRoundingCorners: [.bottomRight],
                                cornerRadii: CGSize(width: 6, height: 6))
        path.append(tail)
        return Path(path.cgPath)
    }
}

// MARK: - แถวขั้นตอน (เทียบ .step + .step-rail + .step-ico)

struct AGStepRow: View {

    let status: ActivityStatus
    let title: String
    var meta: String? = nil
    var right: String? = nil
    var isLast: Bool = false
    var scale: Double = 1
    let action: () -> Void

    /// ป้ายสถานะตามแบบ (.step-meta .chip) — สีต้องมีข้อความกำกับเสมอ
    private var statusChipText: String? {
        switch status {
        case .running: return "กำลังทำ"
        case .failed: return "ล้มเหลว"
        case .skipped: return "ข้ามไป"
        case .pending: return "รอคิว"
        case .waitingUser: return "รอคุณตอบ"
        case .cancelled: return "ยกเลิก"
        case .succeeded: return nil
        }
    }

    private var chipTone: AGChip.Tone {
        switch status {
        case .running: return .run
        case .failed: return .err
        case .waitingUser: return .warn
        default: return .neutral
        }
    }

    var body: some View {
        Button(action: {
            AGHaptic.light()
            action()
        }) {
            HStack(alignment: .top, spacing: 10) {
                VStack(spacing: 0) {
                    AGStatusGlyph(status: status, scale: scale)
                    Rectangle()
                        .fill(AGColor.border)
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                        .opacity(isLast ? 0 : 1)
                }
                .frame(width: AGMetric.stepIcon)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(AGFont.font(AGFont.callout, weight: .medium, scale: scale))
                        .foregroundColor(status == .skipped || status == .cancelled ? AGColor.t2 : AGColor.t1)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .multilineTextAlignment(.leading)
                    if statusChipText != nil || meta != nil {
                        HStack(spacing: 6) {
                            if let chip = statusChipText {
                                AGChip(text: chip, tone: chipTone, scale: scale)
                            }
                            if let meta = meta {
                                Text(meta)
                                    .font(AGFont.font(AGFont.micro, scale: scale))
                                    .foregroundColor(AGColor.t3)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                    .multilineTextAlignment(.leading)
                            }
                        }
                        .padding(.top, 1)
                    }
                }
                .padding(.top, 1)

                Spacer(minLength: AGMetric.s1)

                if let right = right {
                    Text(right)
                        .font(AGFont.font(AGFont.micro, scale: scale))
                        .foregroundColor(AGColor.t3)
                        .monospacedDigit()
                        .padding(.top, 3)
                }
            }
            .padding(.vertical, AGMetric.s2)
            .contentShape(Rectangle())
        }
        .buttonStyle(AGPressableStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(meta.map { "\(title) \($0)" } ?? title))
        .accessibilityHint(Text("แตะเพื่อดูรายละเอียดของขั้นนี้"))
    }
}

// MARK: - การ์ดไทม์ไลน์ (เทียบ .tl + .tl-head)

struct AGTimelineCard: View {

    let steps: [ActivityEvent]
    var isRunning: Bool = false
    var expanded: Bool
    /// เวลาที่ใช้จริงของงาน (จาก ActivityCenter) — nil = ใช้ผลรวมเวลาของขั้นที่มีข้อมูล
    var elapsedText: String? = nil
    var scale: Double = 1
    let onToggle: () -> Void
    let onOpenStep: (ActivityEvent) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button(action: {
                AGHaptic.light()
                onToggle()
            }) {
                HStack(spacing: 10) {
                    AGRibbon(total: max(steps.count, 4),
                             done: steps.filter { $0.status == .succeeded }.count,
                             active: isRunning ? steps.filter { $0.status == .succeeded }.count : -1)
                        .frame(width: 54)
                        .layoutPriority(1)

                    Spacer(minLength: AGMetric.s2)

                    VStack(alignment: .trailing, spacing: 1) {
                        Text(headline)
                            .font(AGFont.font(AGFont.sub, weight: .semibold, scale: scale))
                            .foregroundColor(AGColor.t1)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Text(meta)
                            .font(AGFont.font(AGFont.micro, scale: scale))
                            .foregroundColor(AGColor.t3)
                            .lineLimit(1)
                    }

                    Image(systemName: "chevron.down")
                        .font(AGFont.font(AGFont.micro, weight: .semibold, scale: scale))
                        .foregroundColor(AGColor.t3)
                        .rotationEffect(.degrees(expanded ? 0 : 180))
                }
                .padding(.horizontal, AGMetric.s3)
                .frame(minHeight: AGMetric.liveBarMinHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(AGPressableStyle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("\(headline) \(meta)"))
            .accessibilityHint(Text(expanded ? "แตะเพื่อพับรายการขั้นตอน" : "แตะเพื่อดูรายการขั้นตอนทั้งหมด"))

            if expanded {
                VStack(spacing: 0) {
                    ForEach(steps) { event in
                        AGStepRow(status: event.status,
                                  title: event.title,
                                  meta: stepMeta(event),
                                  right: event.duration.map { AGFormat.durationShort($0) },
                                  isLast: event.id == steps.last?.id,
                                  scale: scale) {
                            onOpenStep(event)
                        }
                    }
                }
                .padding(.horizontal, AGMetric.s3)
                .padding(.bottom, AGMetric.s3)

                Text("แตะขั้นตอนใดก็ได้เพื่อดูรายละเอียด · ระบบจะพับให้อัตโนมัติเมื่อจบงาน")
                    .font(AGFont.font(AGFont.sub, scale: scale))
                    .foregroundColor(AGColor.t2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, AGMetric.s3)
                    .padding(.bottom, AGMetric.s3)
                    .accessibilityHidden(true)
            }
        }
        .background(RoundedRectangle(cornerRadius: AGMetric.rMD, style: .continuous).fill(AGColor.surface))
        .overlay(
            RoundedRectangle(cornerRadius: AGMetric.rMD, style: .continuous)
                .stroke(AGColor.border, lineWidth: 1)
        )
    }

    private var headline: String {
        let done = steps.filter { $0.status == .succeeded }.count
        if done == steps.count && !isRunning { return "ทำงาน \(steps.count) ขั้นตอน" }
        return "กำลังทำงาน \(steps.count) ขั้นตอน"
    }

    /// บรรทัดรองของหัวการ์ด — ตามแบบ "\(เวลา)\( · N ขั้นผิดพลาด)"
    private var meta: String {
        var parts: [String] = []
        if let elapsed = elapsedText { parts.append(elapsed) } else { parts.append(AGFormat.durationShort(totalDuration)) }
        let failed = steps.filter { $0.status == .failed }.count
        if failed > 0 { parts.append("\(failed) ขั้นผิดพลาด") }
        return parts.joined(separator: " · ")
    }

    private var totalDuration: TimeInterval {
        steps.compactMap { $0.duration }.reduce(0, +)
    }

    private func stepMeta(_ event: ActivityEvent) -> String? {
        if event.status == .failed, let failure = event.failureMessage { return failure }
        if event.status == .running { return "กำลังทำอยู่" }
        if let detail = event.detail, !detail.isEmpty { return detail.split(separator: "\n").first.map(String.init) }
        return event.kind.donePhraseTH
    }
}

// MARK: - การ์ด "กำลังคิด" (เทียบ .tl.always — กางเสมอ ไม่ใช่สปินเนอร์เปล่า)

struct AGThinkingCard: View {

    var title: String = "กำลังคิด"
    var elapsed: TimeInterval = 0
    var message: String
    var note: String = "ขั้นนี้จะไม่แสดงให้เห็นเป็นข้อความยาว ๆ โดยค่าเริ่มต้น — ดูได้ในโหมด ละเอียด"
    var scale: Double = 1

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                AGRibbon(total: 6, done: 0, active: 0).frame(width: 54)
                Spacer(minLength: AGMetric.s2)
                Text(title)
                    .font(AGFont.font(AGFont.sub, weight: .semibold, scale: scale))
                    .foregroundColor(AGColor.t1)
                Text("· \(AGFormat.durationShort(elapsed))")
                    .font(AGFont.font(AGFont.micro, scale: scale))
                    .foregroundColor(AGColor.t3)
                    .monospacedDigit()
            }
            .padding(.horizontal, AGMetric.s3)
            .frame(minHeight: AGMetric.liveBarMinHeight)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("\(title) ใช้เวลา \(AGFormat.durationShort(elapsed))"))
            .accessibilityValue(Text(message))

            VStack(alignment: .leading, spacing: AGMetric.s2) {
                AGShimmerLine(text: message, scale: scale)
                Text(note)
                    .font(AGFont.font(AGFont.sub, scale: scale))
                    .foregroundColor(AGColor.t2)
                    .lineSpacing(AGFont.lineSpacing(AGFont.sub, scale: scale))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, AGMetric.s3)
            .padding(.bottom, AGMetric.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(RoundedRectangle(cornerRadius: AGMetric.rMD, style: .continuous).fill(AGColor.surface))
        .overlay(
            RoundedRectangle(cornerRadius: AGMetric.rMD, style: .continuous)
                .stroke(AGColor.border, lineWidth: 1)
        )
    }
}

// MARK: - เส้นข้อความเรืองแสง (เทียบ .shimmer — ใช้แทนสปินเนอร์)

struct AGShimmerLine: View {

    let text: String
    var scale: Double = 1

    @State private var phase: CGFloat = -0.6

    var body: some View {
        Text(text)
            .font(AGFont.font(AGFont.sub, scale: scale))
            .lineSpacing(AGFont.lineSpacing(AGFont.sub, scale: scale))
            .foregroundColor(.clear)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(
                LinearGradient(gradient: Gradient(stops: [
                    .init(color: AGColor.surface2, location: 0),
                    .init(color: AGColor.surface3, location: 0.5),
                    .init(color: AGColor.surface2, location: 1)
                ]),
                               startPoint: UnitPoint(x: phase - 0.6, y: 0.5),
                               endPoint: UnitPoint(x: phase + 0.6, y: 0.5))
                    .mask(
                        Text(text)
                            .font(AGFont.font(AGFont.sub, scale: scale))
                            .lineSpacing(AGFont.lineSpacing(AGFont.sub, scale: scale))
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    )
            )
            .accessibilityHidden(true)
            .onAppear {
                guard !AGMotion.reduceMotion else { return }
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) { phase = 1.6 }
            }
    }
}

// MARK: - สถานะว่างของหน้าแชท (เทียบ .hello + .caps + .safe-strip)

struct AGChatEmptyState: View {

    var fontScale: Double = 1
    var onCapabilityTap: ((String) -> Void)? = nil

    private let capabilities: [(String, String, String)] = [
        ("อ่านและสรุปไฟล์", "PDF · รูป · ข้อความ ในเครื่องคุณ", "ช่วยสรุปไฟล์ในโฟลเดอร์ทำงานให้หน่อย"),
        ("ค้นข้อมูลจากเว็บ", "พร้อมบอกแหล่งที่มาให้ตรวจสอบ", "ค้นในเว็บว่าวันนี้มีข่าวอะไรเกี่ยวกับ iPhone"),
        ("สร้างและแก้ไฟล์ให้", "ทำเสร็จแล้วย้อนกลับได้ในระยะหนึ่ง", "ช่วยสร้างไฟล์โน้ต.md ในโฟลเดอร์ทำงาน"),
        ("ทำงานยาว ๆ ให้", "ปิดแอปแล้วกลับมาดูผลได้", "ช่วยจัดระเบียบไฟล์ในโฟลเดอร์ทำงาน แล้วรายงานผล")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: AGMetric.s4) {
            VStack(alignment: .leading, spacing: AGMetric.s2) {
                Text("สวัสดีครับ")
                    .font(AGFont.font(AGFont.display, weight: .semibold, scale: fontScale))
                    .foregroundColor(AGColor.t1)
                Text("จะให้ช่วยทำอะไรดี")
                    .font(AGFont.font(AGFont.display, weight: .semibold, scale: fontScale))
                    .foregroundColor(AGColor.t1)
                Text("บอกรายละเอียดเป็นภาษาคนได้เลย ผมจะบอกทุกขั้นตอนว่ากำลังทำอะไร และจะขออนุญาตก่อนแก้หรือลบไฟล์ทุกครั้ง")
                    .font(AGFont.font(AGFont.body, scale: fontScale))
                    .foregroundColor(AGColor.t2)
                    .lineSpacing(AGFont.lineSpacing(AGFont.body, scale: fontScale))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, AGMetric.s1)
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: AGMetric.s2),
                                GridItem(.flexible(), spacing: AGMetric.s2)],
                      spacing: AGMetric.s2) {
                ForEach(capabilities, id: \.0) { item in
                    Button(action: {
                        AGHaptic.light()
                        onCapabilityTap?(item.2)
                    }) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.0)
                                .font(AGFont.font(AGFont.foot, weight: .semibold, scale: fontScale))
                                .foregroundColor(AGColor.t1)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(item.1)
                                .font(AGFont.font(AGFont.micro, scale: fontScale))
                                .foregroundColor(AGColor.t3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, minHeight: 62, alignment: .topLeading)
                        .padding(.horizontal, AGMetric.s3)
                        .padding(.vertical, AGMetric.s3)
                        .background(RoundedRectangle(cornerRadius: AGMetric.rMD, style: .continuous).fill(AGColor.surface))
                        .overlay(RoundedRectangle(cornerRadius: AGMetric.rMD, style: .continuous)
                            .stroke(AGColor.border, lineWidth: 1))
                    }
                    .buttonStyle(AGPressableStyle())
                    .disabled(onCapabilityTap == nil)
                    .accessibilityLabel(Text("\(item.0) — \(item.1)"))
                    .accessibilityHint(Text("แตะเพื่อใช้คำขอนี้"))
                }
            }

            HStack(alignment: .top, spacing: AGMetric.s2) {
                Image(systemName: "lock.fill")
                    .font(AGFont.font(AGFont.foot, scale: fontScale))
                    .foregroundColor(AGColor.accentInk)
                    .accessibilityHidden(true)
                Text("ทุกการกระทำที่เปลี่ยนเครื่องคุณ (เขียน ลบ ย้ายไฟล์) ต้องได้รับการอนุญาตจากคุณก่อนเสมอ")
                    .font(AGFont.font(AGFont.foot, scale: fontScale))
                    .foregroundColor(AGColor.accentInk)
                    .lineSpacing(AGFont.lineSpacing(AGFont.foot, scale: fontScale))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, AGMetric.s3)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: AGMetric.rSM, style: .continuous).fill(AGColor.accentSoft))
        }
    }
}

// MARK: - แถบสถานะสด (เทียบ .livebar + .ribbon)

struct AGLiveBar: View {

    let isRunning: Bool
    let title: String
    let subtitle: String?
    let elapsed: TimeInterval
    var isExpanded: Bool = false
    var activeDotTone: Color = AGColor.accent
    var scale: Double = 1
    let onTap: () -> Void

    var body: some View {
        Button(action: {
            AGHaptic.light()
            onTap()
        }) {
            HStack(spacing: 10) {
                if isRunning {
                    AGPulseDot(tone: activeDotTone)
                } else {
                    Circle()
                        .fill(activeDotTone)
                        .frame(width: 9, height: 9)
                        .frame(width: 18, height: 18)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(AGFont.font(AGFont.sub, weight: .semibold, scale: scale))
                        .foregroundColor(AGColor.t1)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .multilineTextAlignment(.leading)
                    if let subtitle = subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(AGFont.font(AGFont.micro, scale: scale))
                            .foregroundColor(AGColor.t3)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .multilineTextAlignment(.leading)
                    }
                }

                Spacer(minLength: AGMetric.s2)

                Text(isRunning ? AGFormat.clock(elapsed) : AGFormat.durationShort(elapsed))
                    .font(AGFont.font(AGFont.cap, scale: scale))
                    .foregroundColor(AGColor.t2)
                    .monospacedDigit()

                Image(systemName: "chevron.up")
                    .font(AGFont.font(AGFont.micro, weight: .semibold, scale: scale))
                    .foregroundColor(AGColor.t3)
                    .rotationEffect(.degrees(isExpanded ? 0 : 180))
            }
            .padding(.horizontal, AGMetric.s3)
            .padding(.vertical, 9)
            .frame(minHeight: AGMetric.liveBarMinHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(AGPressableStyle())
        .background(
            RoundedRectangle(cornerRadius: AGMetric.rMD, style: .continuous).fill(AGColor.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AGMetric.rMD, style: .continuous)
                .stroke(AGColor.border, lineWidth: 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(title)\(subtitle.map { " — \($0)" } ?? "")"))
        .accessibilityValue(Text(isRunning ? "ใช้เวลาไป \(AGFormat.durationShort(elapsed))" : "ใช้เวลา \(AGFormat.durationShort(elapsed))"))
        .accessibilityHint(Text(isExpanded ? "แตะเพื่อพับไทม์ไลน์" : "แตะเพื่อดูขั้นตอนทั้งหมด"))
    }
}

// MARK: - ชิปคำสั่งด่วน (เทียบ .qchip)

struct AGQuickChip: View {

    let text: String
    var scale: Double = 1
    let action: () -> Void

    var body: some View {
        Button(action: {
            AGHaptic.light()
            action()
        }) {
            Text(text)
                .font(AGFont.font(AGFont.foot, scale: scale))
                .foregroundColor(AGColor.t1)
                .lineLimit(1)
                .padding(.horizontal, 14)
                .frame(minHeight: 36)
                .background(Capsule().fill(AGColor.surface2))
        }
        .buttonStyle(AGPressableStyle())
    }
}

// MARK: - แถวในหน้าตั้งค่า (ไอคอน + หัวข้อ + คำอธิบาย + ลูกศร)

struct AGRow: View {

    var icon: String? = nil
    let title: String
    var subtitle: String? = nil
    var value: String? = nil
    var showsChevron: Bool = false
    var tone: Color = AGColor.t1
    var scale: Double = 1
    /// อุปกรณ์เสริมด้านขวา (สวิตช์/ชิป/ปุ่มเล็ก) — วางไว้ในแถวเดียวกันโดยไม่ทำให้ทั้งแถวเป็นปุ่ม
    var accessory: AnyView? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        Button(action: {
            guard let action = action else { return }
            AGHaptic.light()
            action()
        }) {
            HStack(alignment: .center, spacing: AGMetric.s3) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(AGFont.font(AGFont.callout, scale: scale))
                        .foregroundColor(tone)
                        .frame(width: 26, height: 26)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(AGFont.font(AGFont.body, scale: scale))
                        .foregroundColor(tone)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(AGFont.font(AGFont.cap, scale: scale))
                            .foregroundColor(AGColor.t2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: AGMetric.s2)
                if let value = value {
                    Text(value)
                        .font(AGFont.font(AGFont.sub, scale: scale))
                        .foregroundColor(AGColor.t2)
                        .lineLimit(1)
                }
                if let accessory = accessory {
                    accessory
                }
                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(AGFont.font(AGFont.micro, weight: .semibold, scale: scale))
                        .foregroundColor(AGColor.t3)
                }
            }
            .padding(.horizontal, AGMetric.screenPadding)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(AGPressableStyle())
        .disabled(action == nil)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - หัวข้อกลุ่ม

struct AGSectionTitle: View {

    let text: String
    var scale: Double = 1

    var body: some View {
        Text(text)
            .font(AGFont.font(AGFont.foot, weight: .semibold, scale: scale))
            .foregroundColor(AGColor.t2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - ตัวช่วยรอข้อมูล (ห้ามสปินเนอร์เปล่า — ต้องมีข้อความกำกับ)

struct AGSkeleton: View {

    var lines: Int = 2
    var scale: Double = 1
    @State private var dim: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: AGMetric.s2) {
            ForEach(0..<max(1, lines), id: \.self) { index in
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(AGColor.surface2)
                    .frame(height: 11)
                    .opacity(dim ? 0.55 : 1)
                    .frame(maxWidth: index == max(1, lines) - 1 ? 180 : .infinity, alignment: .leading)
            }
        }
        .animation(AGMotion.animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)), value: dim)
        .onAppear { dim = true }
        .accessibilityHidden(true)
    }
}

// MARK: - แผ่นล่าง (แทน .sheet ของแบบ — iOS 15 ไม่มี bottom sheet มาตรฐาน)

struct AGSheet<Content: View>: View {

    let title: String
    var scale: Double = 1
    let onClose: () -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                AGColor.scrim
                    .ignoresSafeArea()
                    .onTapGesture { onClose() }
                    .accessibilityHidden(true)

                VStack(spacing: 0) {
                    Capsule()
                        .fill(AGColor.border)
                        .frame(width: 36, height: 4)
                        .padding(.top, AGMetric.s2)

                    HStack(alignment: .center, spacing: AGMetric.s2) {
                        Text(title)
                            .font(AGFont.font(AGFont.title, weight: .semibold, scale: scale))
                            .foregroundColor(AGColor.t1)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        Button(action: {
                            AGHaptic.light()
                            onClose()
                        }) {
                            Image(systemName: "xmark")
                                .font(AGFont.font(AGFont.callout, weight: .semibold, scale: scale))
                                .foregroundColor(AGColor.t2)
                                .frame(width: AGMetric.touch, height: AGMetric.touch)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(AGPressableStyle())
                        .accessibilityLabel(Text("ปิด"))
                    }
                    .padding(.horizontal, AGMetric.screenPadding)
                    .padding(.top, AGMetric.s2)

                    ScrollView {
                        VStack(alignment: .leading, spacing: AGMetric.s4) {
                            content()
                        }
                        .padding(.horizontal, AGMetric.screenPadding)
                        .padding(.top, AGMetric.s2)
                        .padding(.bottom, AGMetric.s8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: proxy.size.height * 0.72)
                }
                .frame(maxWidth: .infinity)
                .background(
                    RoundedCorner(radius: AGMetric.rLG, corners: [.topLeft, .topRight]).fill(AGColor.surface)
                )
                .shadow(color: Color.black.opacity(0.14), radius: 16, x: 0, y: 12)
            }
        }
        .transition(.opacity)
        .accessibilityAddTraits(.isModal)
    }
}

/// มุมโค้งเฉพาะด้านบน (iOS 15 ไม่มี UnevenRoundedRectangle)
struct RoundedCorner: Shape {

    var radius: CGFloat
    var corners: UIRectCorner

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(roundedRect: rect,
                                byRoundingCorners: corners,
                                cornerRadii: CGSize(width: radius, height: radius))
        return Path(path.cgPath)
    }
}

// MARK: - แถบแท็บล่าง (4 แท็บตามแบบ)

struct AGTabBar: View {

    @Binding var selection: Int
    var scale: Double = 1

    private let items: [(icon: String, label: String)] = [
        ("bubble.left.and.bubble.right", "แชท"),
        ("folder", "ไฟล์"),
        ("square.stack.3d.up", "งานของฉัน"),
        ("gearshape", "ตั้งค่า")
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items.indices, id: \.self) { index in
                Button(action: {
                    guard selection != index else { return }
                    AGHaptic.light()
                    selection = index
                }) {
                    VStack(spacing: 3) {
                        Image(systemName: items[index].icon)
                            .font(AGFont.font(AGFont.title, scale: scale))
                        Text(items[index].label)
                            .font(AGFont.font(AGFont.micro, weight: selection == index ? .semibold : .regular, scale: scale))
                    }
                    .foregroundColor(selection == index ? AGColor.accentInk : AGColor.t3)
                    .frame(maxWidth: .infinity)
                    .frame(height: AGMetric.tabBarHeight)
                    .contentShape(Rectangle())
                }
                .buttonStyle(AGPressableStyle())
                .accessibilityLabel(Text(items[index].label))
                .accessibilityAddTraits(selection == index ? [.isButton, .isSelected] : .isButton)
            }
        }
        .background(AGColor.surface)
        .overlay(Rectangle().fill(AGColor.border).frame(height: 1), alignment: .top)
    }
}
