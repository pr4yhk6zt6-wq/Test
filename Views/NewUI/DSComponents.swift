//
//  DSComponents.swift
//  iOS Agent Sandbox — ดีไซน์ v2 (เฟส 5 ส่วนที่ 1)
//
//  คอมโพเนนต์พื้นฐานของ UI ใหม่ — ปุ่ม ชิป แบนเนอร์ การ์ด โครงร่างรอข้อมูล แถบความคืบหน้า
//  และแผ่นล่างแบบกำหนดเอง (iOS 15 ไม่มี presentationDetents จึงวาดเอง)
//
//  กติกาที่บังคับในไฟล์นี้ (ตามเช็กลิสต์ของดีไซน์ v2)
//  - ขนาดที่จับต้องได้ขั้นต่ำ 44pt
//  - สถานะทุกอย่างมีทั้งไอคอนและข้อความ ไม่พึ่งสีอย่างเดียว
//  - ไม่มีสปินเนอร์เปล่า (ใช้โครงร่างรอข้อมูลหรือแถบความคืบหน้าที่มีข้อความกำกับ)
//  - ข้อความไทยตัดบรรทัดได้ ไม่ย่อขนาดตัวอักษร
//

import SwiftUI

// MARK: - ปุ่ม

struct DSButton: View {

    enum Kind {
        case primary
        case secondary
        case ghost
        case dangerLine
        case dangerSolid
        case small
    }

    let title: String
    var icon: String? = nil
    var kind: Kind = .primary
    var isEnabled: Bool = true
    /// เหตุผลเมื่อปุ่มถูกปิด (แสดงใต้ปุ่มเสมอ เพื่อไม่ให้ผู้ใช้เดาเอง)
    var disabledReason: String? = nil
    var accessibilityHint: String? = nil
    let scale: Double
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(action: {
                guard isEnabled else { return }
                DSHaptic.light()
                action()
            }) {
                HStack(spacing: DSMetrics.s2) {
                    if let icon = icon {
                        Image(systemName: icon)
                            .font(DSFont.font(DSFont.sCallout, weight: .semibold, scale: scale))
                    }
                    Text(title)
                        .font(DSFont.font(kind == .small ? DSFont.sFoot : DSFont.sCallout,
                                          weight: .semibold,
                                          scale: scale))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundColor(foreground)
                .padding(.horizontal, kind == .small ? DSMetrics.s3 : DSMetrics.s4)
                .padding(.vertical, kind == .small ? 8 : 11)
                .frame(minHeight: kind == .small ? DSMetrics.touchSmall : DSMetrics.touch)
                .frame(maxWidth: stretches ? .infinity : nil)
                .background(
                    RoundedRectangle(cornerRadius: kind == .small ? 12 : 14, style: .continuous)
                        .fill(background)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: kind == .small ? 12 : 14, style: .continuous)
                        .stroke(borderColor, lineWidth: borderWidth)
                )
                .opacity(isEnabled ? 1 : 0.45)
            }
            .buttonStyle(DSPressableStyle())
            .disabled(!isEnabled)
            .accessibilityLabel(Text(title))
            .accessibilityHint(Text(accessibilityHint ?? ""))

            if let reason = disabledReason, !isEnabled {
                Text(reason)
                    .font(DSFont.font(DSFont.sCap, scale: scale))
                    .foregroundColor(DSColor.t3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var stretches: Bool { kind != .small }

    private var background: Color {
        switch kind {
        case .primary: return DSColor.accent
        case .secondary, .small: return DSColor.surface2
        case .ghost: return Color.clear
        case .dangerLine: return Color.clear
        case .dangerSolid: return DSColor.error
        }
    }

    private var foreground: Color {
        switch kind {
        case .primary: return DSColor.onAccent
        case .secondary, .small: return DSColor.t1
        case .ghost: return DSColor.accentInk
        case .dangerLine: return DSColor.error
        case .dangerSolid: return DSColor.onAccent
        }
    }

    private var borderColor: Color {
        switch kind {
        case .secondary, .small: return DSColor.border
        case .dangerLine: return DSColor.error.opacity(0.45)
        default: return Color.clear
        }
    }

    private var borderWidth: CGFloat {
        switch kind {
        case .secondary, .small, .dangerLine: return 1
        default: return 0
        }
    }
}

/// ผลตอบสนองตอนกด: จางลงเล็กน้อย + ย่อ 2% (ไม่กี่มิลลิวินาที)
struct DSPressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.88 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(DSMotion.tap, value: configuration.isPressed)
    }
}

// MARK: - ไอคอนและป้ายสถานะ

struct DSIconBadge: View {
    let icon: String
    var tint: Color = DSColor.accentInk
    var background: Color = DSColor.accentSoft
    var size: CGFloat = 28
    var scale: Double = 1.0

    var body: some View {
        Image(systemName: icon)
            .font(DSFont.font(size * 0.58, weight: .semibold, scale: scale))
            .foregroundColor(tint)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.36, style: .continuous).fill(background))
            .accessibilityHidden(true)
    }
}

/// สถานะต้องมีไอคอน + ข้อความเสมอ
struct DSStatusLabel: View {
    let status: ActivityStatus
    var scale: Double = 1.0
    var showsText: Bool = true

    var body: some View {
        HStack(spacing: 5) {
            DSStatusGlyph(status: status, scale: scale)
            if showsText {
                Text(status.thaiLabel)
                    .font(DSFont.font(DSFont.sCap, weight: .medium, scale: scale))
                    .foregroundColor(status.dsColor)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("สถานะ: \(status.thaiLabel)"))
    }
}

/// วงกลมสถานะ 22 pt ตามแบบ: พื้นอ่อน + ไอคอนสี (สี + ไอคอน + ข้อความ ต้องมาครบทั้งสามเสมอ)
struct DSStatusGlyph: View {

    let status: ActivityStatus
    var size: CGFloat = 22
    var scale: Double = 1.0
    @State private var pulse: Bool = false

    private var side: CGFloat { DSFont.size(size, scale: scale) }

    var body: some View {
        ZStack {
            Circle().fill(status.dsSoftColor)
            if status == .running {
                Circle().stroke(status.dsColor.opacity(pulse ? 0.15 : 0.55), lineWidth: 1.5)
            }
            Image(systemName: status.symbolName)
                .font(DSFont.font(side * 0.5, weight: .semibold, scale: 1.0))
                .foregroundColor(status.dsColor)
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
        .onAppear {
            guard status == .running, !DSMotion.reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

/// จุดเต้นเต้น 8 pt — ใช้กับแถบสถานะสดตอนกำลังทำงาน (ตรงกับแบบ ไม่ใช่สปินเนอร์เปล่า)
struct DSPulseDot: View {

    var tone: Color = DSColor.accent
    var size: CGFloat = 9
    @State private var on: Bool = false

    var body: some View {
        Circle()
            .fill(tone)
            .frame(width: size, height: size)
            .overlay(
                Circle()
                    .stroke(tone.opacity(0.35), lineWidth: on ? 5 : 1)
                    .scaleEffect(on ? 1.6 : 1.0)
                    .opacity(on ? 0 : 1)
            )
            .accessibilityHidden(true)
            .onAppear {
                guard !DSMotion.reduceMotion else { return }
                withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) {
                    on = true
                }
            }
    }
}

struct DSChip: View {

    enum Tone {
        case neutral
        case accent
        case success
        case warning
        case error
    }

    let text: String
    var tone: Tone = .neutral
    var icon: String? = nil
    var scale: Double = 1.0

    var body: some View {
        HStack(spacing: 4) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(DSFont.font(DSFont.sMicro, weight: .semibold, scale: scale))
            }
            Text(text)
                .font(DSFont.font(DSFont.sMicro, weight: .medium, scale: scale))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundColor(ink)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .frame(minHeight: 26)
        .background(Capsule().fill(fill))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(spoken))
    }

    private var fill: Color {
        switch tone {
        case .neutral: return DSColor.surface2
        case .accent: return DSColor.accentSoft
        case .success: return DSColor.successSoft
        case .warning: return DSColor.warningSoft
        case .error: return DSColor.errorSoft
        }
    }

    private var ink: Color {
        switch tone {
        case .neutral: return DSColor.t2
        case .accent: return DSColor.accentInk
        case .success: return DSColor.success
        case .warning: return DSColor.warning
        case .error: return DSColor.error
        }
    }

    private var spoken: String {
        switch tone {
        case .neutral: return text
        case .accent: return "หมายเหตุ: \(text)"
        case .success: return "สำเร็จ: \(text)"
        case .warning: return "ควรระวัง: \(text)"
        case .error: return "ผิดพลาด: \(text)"
        }
    }
}

// MARK: - การ์ดและแถว

enum DSCardTone {
    case surface
    case accent
    case success
    case warning
    case error

    var background: Color {
        switch self {
        case .surface: return DSColor.surface
        case .accent: return DSColor.accentSoft
        case .success: return DSColor.successSoft
        case .warning: return DSColor.warningSoft
        case .error: return DSColor.errorSoft
        }
    }

    var border: Color {
        switch self {
        case .surface: return DSColor.border
        case .accent: return DSColor.accent.opacity(0.25)
        case .success: return DSColor.success.opacity(0.25)
        case .warning: return DSColor.warning.opacity(0.30)
        case .error: return DSColor.error.opacity(0.30)
        }
    }
}

struct DSCardContainer<Content: View>: View {

    let tone: DSCardTone
    let content: () -> Content

    init(tone: DSCardTone = .surface, @ViewBuilder content: @escaping () -> Content) {
        self.tone = tone
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DSMetrics.s2) {
            content()
        }
        .padding(DSMetrics.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DSMetrics.rCard, style: .continuous).fill(tone.background)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DSMetrics.rCard, style: .continuous)
                .stroke(tone.border, lineWidth: 1)
        )
    }
}

/// แถวหัวเรื่องที่กดกาง/พับได้ — ทั้งแถวเป็นปุ่มเดียว มี aria-equivalent ครบ
struct DSDisclosureRow: View {

    let icon: String
    var iconTint: Color = DSColor.accentInk
    var iconBackground: Color = DSColor.accentSoft
    let title: String
    var subtitle: String? = nil
    var status: ActivityStatus? = nil
    var trailingText: String? = nil
    let isExpanded: Bool
    var scale: Double = 1.0
    let onToggle: () -> Void

    var body: some View {
        Button(action: {
            DSHaptic.light()
            onToggle()
        }) {
            HStack(alignment: .center, spacing: DSMetrics.s3) {
                DSIconBadge(icon: icon, tint: iconTint, background: iconBackground, scale: scale)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(DSFont.font(DSFont.sSub, weight: .semibold, scale: scale))
                        .foregroundColor(DSColor.t1)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    if let subtitle = subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(DSFont.font(DSFont.sCap, scale: scale))
                            .foregroundColor(DSColor.t2)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: DSMetrics.s2)
                if let status = status {
                    DSStatusLabel(status: status, scale: scale, showsText: true)
                } else if let trailing = trailingText {
                    Text(trailing)
                        .font(DSFont.font(DSFont.sCap, scale: scale))
                        .foregroundColor(DSColor.t3)
                        .lineLimit(1)
                }
                Image(systemName: "chevron.down")
                    .font(DSFont.font(DSFont.sCap, weight: .semibold, scale: scale))
                    .foregroundColor(DSColor.t3)
                    .rotationEffect(.degrees(isExpanded ? 0 : -90))
            }
            .padding(.horizontal, DSMetrics.cardPadding)
            .frame(minHeight: DSMetrics.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(DSPressableStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityTitle))
        .accessibilityHint(Text(isExpanded ? "แตะเพื่อพับรายละเอียด" : "แตะเพื่อดูรายละเอียด"))
        .accessibilityAddTraits(isExpanded ? [.isButton, .isSelected] : .isButton)
    }

    private var accessibilityTitle: String {
        var parts: [String] = [title]
        if let subtitle = subtitle, !subtitle.isEmpty { parts.append(subtitle) }
        if let status = status { parts.append("สถานะ \(status.thaiLabel)") }
        if let trailing = trailingText { parts.append(trailing) }
        return parts.joined(separator: " ")
    }
}

// MARK: - แบนเนอร์

struct DSBanner<Actions: View>: View {

    enum Tone {
        case info
        case success
        case warning
        case error

        var icon: String {
            switch self {
            case .info: return "info.circle.fill"
            case .success: return "checkmark.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .error: return "exclamationmark.octagon.fill"
            }
        }
    }

    let tone: Tone
    let title: String
    var message: String? = nil
    var scale: Double = 1.0
    let actions: () -> Actions

    init(tone: Tone,
         title: String,
         message: String? = nil,
         scale: Double = 1.0,
         @ViewBuilder actions: @escaping () -> Actions) {
        self.tone = tone
        self.title = title
        self.message = message
        self.scale = scale
        self.actions = actions
    }

    var body: some View {
        HStack(alignment: .top, spacing: DSMetrics.s3) {
            Image(systemName: tone.icon)
                .font(DSFont.font(DSFont.sSub, weight: .semibold, scale: scale))
                .foregroundColor(ink)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(DSFont.font(DSFont.sSub, weight: .semibold, scale: scale))
                    .foregroundColor(DSColor.t1)
                    .fixedSize(horizontal: false, vertical: true)
                if let message = message, !message.isEmpty {
                    Text(message)
                        .font(DSFont.font(DSFont.sCap, scale: scale))
                        .foregroundColor(DSColor.t2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                actions()
            }
            Spacer(minLength: 0)
        }
        .padding(DSMetrics.s3)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(fill))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(ink.opacity(0.28), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
    }

    private var fill: Color {
        switch tone {
        case .info: return DSColor.accentSoft
        case .success: return DSColor.successSoft
        case .warning: return DSColor.warningSoft
        case .error: return DSColor.errorSoft
        }
    }

    private var ink: Color {
        switch tone {
        case .info: return DSColor.accentInk
        case .success: return DSColor.success
        case .warning: return DSColor.warning
        case .error: return DSColor.error
        }
    }
}

extension DSBanner where Actions == EmptyView {
    init(tone: Tone, title: String, message: String? = nil, scale: Double = 1.0) {
        self.init(tone: tone, title: title, message: message, scale: scale) { EmptyView() }
    }
}

// MARK: - รอข้อมูล / ความคืบหน้า

/// โครงร่างรอข้อมูล — ใช้แทนสปินเนอร์เปล่าเสมอ (มีข้อความกำกับที่อ่านออกเสียงได้)
struct DSSkeleton: View {

    var lines: Int = 2
    var scale: Double = 1.0
    @State private var dim: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: DSMetrics.s2) {
            ForEach(0..<max(1, lines), id: \.self) { index in
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(DSColor.surface2)
                    .frame(height: 11)
                    .frame(maxWidth: index == max(1, lines) - 1 ? 180 : .infinity, alignment: .leading)
                    .opacity(dim ? 0.55 : 1)
            }
        }
        .animation(DSMotion.reduceMotion ? nil : .easeInOut(duration: 0.9).repeatForever(autoreverses: true),
                   value: dim)
        .onAppear { dim = true }
        .accessibilityHidden(true)
    }
}

struct DSProgressBar: View {

    /// nil = ไม่รู้จำนวนจริง → แสดงแถบวิ่ง ไม่แสดงตัวเลข
    var progress: Double?
    var tone: Color = DSColor.accent
    var caption: String? = nil
    var scale: Double = 1.0

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            DSRibbon(progress: progress, tone: tone)
            if let caption = caption, !caption.isEmpty {
                Text(caption)
                    .font(DSFont.font(DSFont.sCap, scale: scale))
                    .foregroundColor(DSColor.t3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(caption ?? "กำลังทำงาน"))
        .accessibilityValue(Text(progress.map { "ทำแล้ว \(Int(($0 * 100).rounded())) เปอร์เซ็นต์" } ?? "ยังไม่ทราบความคืบหน้า"))
    }
}

/// ริบบิ้นความคืบหน้า 3pt — รู้จำนวนจริงจึงแสดงสัดส่วน ไม่รู้จำนวนให้วิ่งไปมา
struct DSRibbon: View {

    var progress: Double?
    var tone: Color = DSColor.accent
    @State private var shift: CGFloat = -0.4

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(tone.opacity(0.16))
                if let value = progress {
                    Capsule()
                        .fill(tone)
                        .frame(width: max(6, geo.size.width * CGFloat(min(max(value, 0), 1))))
                } else if DSMotion.reduceMotion {
                    Capsule().fill(tone.opacity(0.65))
                } else {
                    Capsule()
                        .fill(tone)
                        .frame(width: geo.size.width * 0.32)
                        .offset(x: shift * geo.size.width)
                }
            }
        }
        .frame(height: DSMetrics.ribbonHeight)
        .clipShape(Capsule())
        .accessibilityHidden(true)
        .onAppear {
            guard progress == nil, !DSMotion.reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                shift = 0.72
            }
        }
    }
}

// MARK: - แผ่นล่าง (bottom sheet) ที่วาดเอง

struct DSBottomSheetModifier<SheetContent: View>: ViewModifier {

    @Binding var isPresented: Bool
    let title: String
    var onClose: () -> Void = {}
    let sheetContent: () -> SheetContent

    @State private var dragOffset: CGFloat = 0

    func body(content base: Content) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                base

                if isPresented {
                    DSColor.scrim
                        .ignoresSafeArea()
                        .onTapGesture { close() }
                        .transition(.opacity)

                    sheetBody(maxHeight: geo.size.height * 0.82)
                        .transition(.move(edge: .bottom))
                }
            }
            .animation(DSMotion.sheet, value: isPresented)
        }
    }

    private func sheetBody(maxHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            VStack(spacing: DSMetrics.s2) {
                Capsule()
                    .fill(DSColor.borderStrong)
                    .frame(width: 36, height: 5)
                    .padding(.top, 8)

                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                        .font(DSFont.font(DSFont.sHead, weight: .semibold, scale: 1.0))
                        .foregroundColor(DSColor.t1)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: DSMetrics.s2)
                    Button(action: { close() }) {
                        Image(systemName: "xmark")
                            .font(DSFont.font(DSFont.sCallout, weight: .semibold))
                            .foregroundColor(DSColor.t2)
                            .frame(width: DSMetrics.touch, height: DSMetrics.touch)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(DSPressableStyle())
                    .accessibilityLabel(Text("ปิด"))
                }
                .padding(.horizontal, DSMetrics.s4)
            }
            .background(DSColor.surface)
            .gesture(
                DragGesture()
                    .onChanged { value in dragOffset = max(0, value.translation.height) }
                    .onEnded { value in
                        if value.translation.height > 110 {
                            close()
                        } else {
                            withAnimation(DSMotion.card) { dragOffset = 0 }
                        }
                    }
            )

            ScrollView {
                VStack(alignment: .leading, spacing: DSMetrics.s4) {
                    sheetContent()
                }
                .padding(DSMetrics.s4)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(DSColor.surface)
        }
        .frame(maxHeight: maxHeight)
        .background(DSColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: DSMetrics.rSheet, style: .continuous))
        .dsShadow(DSShadow.sheet)
        .offset(y: dragOffset)
        .accessibilityAddTraits(.isModal)
    }

    private func close() {
        withAnimation(DSMotion.sheet) { isPresented = false }
        dragOffset = 0
        onClose()
    }
}

extension View {
    func dsBottomSheet<C: View>(isPresented: Binding<Bool>,
                                title: String,
                                onClose: @escaping () -> Void = {},
                                @ViewBuilder content: @escaping () -> C) -> some View {
        modifier(DSBottomSheetModifier(isPresented: isPresented,
                                       title: title,
                                       onClose: onClose,
                                       sheetContent: content))
    }
}

// MARK: - ไฟล์แนบ

struct DSAttachmentChip: View {

    let name: String
    var detail: String? = nil
    var scale: Double = 1.0
    var onRemove: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: DSMetrics.s2) {
            Image(systemName: "paperclip")
                .font(DSFont.font(DSFont.sCap, weight: .semibold, scale: scale))
                .foregroundColor(DSColor.t2)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(DSFont.font(DSFont.sCap, weight: .medium, scale: scale))
                    .foregroundColor(DSColor.t1)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let detail = detail, !detail.isEmpty {
                    Text(detail)
                        .font(DSFont.font(DSFont.sMicro, scale: scale))
                        .foregroundColor(DSColor.t3)
                        .lineLimit(1)
                }
            }
            if let onRemove = onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(DSFont.font(DSFont.sCallout, scale: scale))
                        .foregroundColor(DSColor.t3)
                        .frame(width: 34, height: 34)
                        .contentShape(Rectangle())
                }
                .buttonStyle(DSPressableStyle())
                .accessibilityLabel(Text("เอาไฟล์ \(name) ออก"))
            }
        }
        .padding(.horizontal, DSMetrics.s3)
        .padding(.vertical, 7)
        .frame(minHeight: DSMetrics.touch)
        .background(Capsule().fill(DSColor.surface2))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("ไฟล์แนบ \(name)\(detail.map { " ขนาด \($0)" } ?? "")"))
    }
}

// MARK: - สีและข้อความของสถานะกิจกรรม

extension ActivityStatus {

    var dsColor: Color {
        switch self {
        case .pending: return DSColor.t3
        case .running: return DSColor.accentInk
        case .waitingUser: return DSColor.warning
        case .succeeded: return DSColor.success
        case .failed: return DSColor.error
        case .skipped: return DSColor.t3
        case .cancelled: return DSColor.t2
        }
    }

    /// พื้นอ่อนของวงกลมสถานะ (ตามแบบ: ไอคอนเข้มบนพื้นอ่อน ไม่ใช่ตัวทึบสีจัด)
    var dsSoftColor: Color {
        switch self {
        case .pending, .skipped, .cancelled: return DSColor.surface2
        case .running: return DSColor.accentSoft
        case .waitingUser: return DSColor.warningSoft
        case .succeeded: return DSColor.successSoft
        case .failed: return DSColor.errorSoft
        }
    }
}

extension ActivityKind {

    var dsColor: Color {
        switch self {
        case .thinking, .plan: return DSColor.accentInk
        case .webSearch, .browse: return DSColor.accentInk
        case .fileRead: return DSColor.t2
        case .fileWrite, .fileEdit: return DSColor.warning
        case .fileDelete: return DSColor.error
        case .shell: return DSColor.warning
        case .connector, .subagent: return DSColor.accentInk
        case .askUser, .permission: return DSColor.warning
        case .other: return DSColor.t2
        }
    }

    var dsBackground: Color {
        switch self {
        case .fileDelete, .permission: return DSColor.errorSoft
        case .fileWrite, .fileEdit, .shell, .askUser: return DSColor.warningSoft
        default: return DSColor.accentSoft
        }
    }
}
