//
//  DSTheme.swift
//  iOS Agent Sandbox — ดีไซน์ v2 (เฟส 5 ส่วนที่ 1)
//
//  โทเคนดีไซน์ทั้งหมดของหน้าจอใหม่: สี (Light/Dark), ตัวอักษร, ระยะห่าง, มุมโค้ง, เงา,
//  การเคลื่อนไหว และ haptic — ค่าทุกตัวตรงกับ design-phase1-style.md และ
//  phase4-component-library.md หมวด 1
//
//  หมายเหตุการเข้ากันได้ (deployment target = iOS 15.0)
//  - ใช้เฉพาะ API ที่มีใน iOS 15 (ตรวจด้วย Scripts/check-ios15-compat.sh)
//  - ไม่ใช้ @ScaledMetric + dynamicTypeSize ของ iOS 16 จึงคูณขนาดด้วย SettingsKeys.chatFontScale เอง
//  - ตัวอักษร: ใช้ Anuphan ถ้าโปรเจกต์ถูกเพิ่มไฟล์ฟอนต์ไว้ ถ้าไม่มีจะถอยไปใช้ฟอนต์ระบบโดยอัตโนมัติ
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - สี

/// สีทั้งหมดของดีไซน์ v2 (ปรับตาม Light/Dark อัตโนมัติด้วย UIColor dynamic provider)
enum DSColor {

    static let bg = dynamic(light: 0xF7F7F4, dark: 0x0F1013)
    static let surface = dynamic(light: 0xFFFFFF, dark: 0x17191E)
    static let surface2 = dynamic(light: 0xEFEFEA, dark: 0x1F2228)
    static let surface3 = dynamic(light: 0xE5E5DF, dark: 0x262A33)

    static let border = dynamic(light: 0xE0E0DA, dark: 0x2A2E37)
    static let borderStrong = dynamic(light: 0xC9C9C2, dark: 0x3A3F4A)

    static let t1 = dynamic(light: 0x15181D, dark: 0xE9EBEF)
    static let t2 = dynamic(light: 0x545B66, dark: 0x9CA3AF)
    static let t3 = dynamic(light: 0x646C77, dark: 0x8A93A1)

    /// สีเน้น "คราม" — โหมดสว่างใช้เป็นตัวอักษร/ปุ่มทึบ, โหมดมืดใช้เป็นตัวเติมสว่าง
    static let accent = dynamic(light: 0x2E4A8A, dark: 0x8CA4E8)
    /// ตัวอักษร/ไอคอนสีเน้นบนพื้นเข้ม (โหมดมืด)
    static let accentInk = dynamic(light: 0x2E4A8A, dark: 0xA7B8EE)
    static let accentSoft = dynamic(light: 0xE8ECF7, dark: 0x1C2233)
    /// ตัวอักษรบนปุ่มทึบสีเน้น (โหมดมืดใช้ตัวอักษรเข้มบนตัวเติมสว่าง)
    static let onAccent = dynamic(light: 0xFFFFFF, dark: 0x0F1013)

    static let success = dynamic(light: 0x17683F, dark: 0x6BC08C)
    static let successSoft = dynamic(light: 0xE3F0E9, dark: 0x16261D)
    static let warning = dynamic(light: 0x8A5A00, dark: 0xDDAE5E)
    static let warningSoft = dynamic(light: 0xFAF0DA, dark: 0x2A2314)
    static let error = dynamic(light: 0xA3241F, dark: 0xEE8B84)
    static let errorSoft = dynamic(light: 0xFBE9E7, dark: 0x2C1A19)

    /// ฉากมืดหลังแผ่นล่าง/ไดอะล็อก
    static let scrim = Color.black.opacity(0.35)

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(dsHex: dark) : UIColor(dsHex: light)
        })
    }
}

extension UIColor {
    /// สร้างสีจากเลขฐานสิบหก 0xRRGGBB
    convenience init(dsHex value: UInt32) {
        let r = CGFloat((value >> 16) & 0xFF) / 255.0
        let g = CGFloat((value >> 8) & 0xFF) / 255.0
        let b = CGFloat(value & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b, alpha: 1.0)
    }
}

// MARK: - ตัวอักษร

/// ขนาดตัวอักษรตั้งต้น (ก่อนคูณด้วยตัวคูณของผู้ใช้) และตัวช่วยสร้าง Font/UIFont
enum DSFont {

    // ขนาดพื้นฐานที่ scale = 1.0
    static let sDisplay: CGFloat = 25
    static let sTitle: CGFloat = 20
    static let sHead: CGFloat = 17
    static let sBody: CGFloat = 16
    static let sCallout: CGFloat = 15
    static let sSub: CGFloat = 14
    static let sFoot: CGFloat = 13
    static let sCap: CGFloat = 12
    static let sMicro: CGFloat = 11.5

    /// ความสูงบรรทัดขั้นต่ำสำหรับข้อความไทย (วรรณยุกต์/สระบน-ล่าง)
    static let lineBody: CGFloat = 1.62
    static let lineTight: CGFloat = 1.45
    static let lineCaption: CGFloat = 1.55

    /// ชื่อตระกูลฟอนต์ที่โปรเจกต์รองรับ — ถ้าเพิ่มไฟล์ .ttf ใน Resources แล้วจะถูกใช้ทันที
    private static let familyCandidates = ["Anuphan", "Anuphan-Regular", "IBM Plex Sans Thai"]

    /// ชื่อฟอนต์ที่พร้อมใช้จริงบนเครื่องนี้ (nil = ใช้ฟอนต์ระบบ)
    static var availableFamilyName: String? {
        for name in familyCandidates where UIFont(name: name, size: 12) != nil {
            return name
        }
        return nil
    }

    static func clampScale(_ value: Double) -> CGFloat {
        guard value.isFinite, value > 0 else { return 1.0 }
        return CGFloat(min(max(value, 0.85), 1.6))
    }

    static func size(_ base: CGFloat, scale: Double = 1.0) -> CGFloat {
        (base * clampScale(scale)).rounded()
    }

    static func font(_ base: CGFloat,
                     weight: Font.Weight = .regular,
                     scale: Double = 1.0) -> Font {
        let pointSize = size(base, scale: scale)
        if let family = availableFamilyName {
            return Font.custom(family, size: pointSize)
        }
        return Font.system(size: pointSize, weight: weight)
    }

    /// UIFont สำหรับฝังใน MultilineInputField (ช่องพิมพ์ที่ขยายเองได้)
    static func uiFont(_ base: CGFloat,
                       weight: UIFont.Weight = .regular,
                       scale: Double = 1.0) -> UIFont {
        let pointSize = size(base, scale: scale)
        if let family = availableFamilyName, let font = UIFont(name: family, size: pointSize) {
            return font
        }
        return UIFont.systemFont(ofSize: pointSize, weight: weight)
    }

    /// ระยะห่างบรรทัดที่ทำให้ความสูงรวมประมาณ lineBody เท่าของขนาดตัวอักษร
    /// (ฟอนต์มี line height ธรรมชาติอยู่แล้วประมาณ 1.2 เท่า จึงเติมส่วนที่เหลือด้วย lineSpacing)
    static func lineSpacing(_ base: CGFloat,
                           scale: Double = 1.0,
                           multiplier: CGFloat = DSFont.lineBody) -> CGFloat {
        let extra = max(0, multiplier - 1.2)
        return (base * clampScale(scale) * extra).rounded()
    }
}

// MARK: - ระยะห่าง / มุมโค้ง / ขนาดที่จับต้อง

enum DSMetrics {

    // กริด 4pt
    static let s1: CGFloat = 4
    static let s2: CGFloat = 8
    static let s3: CGFloat = 12
    static let s4: CGFloat = 16
    static let s5: CGFloat = 20
    static let s6: CGFloat = 24
    static let s8: CGFloat = 32

    static let screenPadding: CGFloat = 16
    static let cardPadding: CGFloat = 14
    static let groupSpacing: CGFloat = 16

    // มุมโค้ง
    static let rChip: CGFloat = 16
    static let rCard: CGFloat = 16
    static let rSheet: CGFloat = 20
    static let rComposer: CGFloat = 28
    static let rBubble: CGFloat = 18
    static let rBubbleTail: CGFloat = 6
    static let rField: CGFloat = 12

    // ขนาดที่จับต้อง (ขั้นต่ำ 44pt ตามเช็กลิสต์)
    static let touch: CGFloat = 44
    static let touchSmall: CGFloat = 38
    static let rowHeight: CGFloat = 52
    static let headerHeight: CGFloat = 56
    static let tabBarHeight: CGFloat = 50
    static let composerMinHeight: CGFloat = 44
    static let composerMaxHeight: CGFloat = 112
    static let liveBarHeight: CGFloat = 52
    static let ribbonHeight: CGFloat = 3
    static let glyph: CGFloat = 22
}

// MARK: - เงา

enum DSShadow {

    struct Spec {
        let color: Color
        let radius: CGFloat
        let y: CGFloat
    }

    static let card = Spec(color: Color.black.opacity(0.06), radius: 2, y: 1)
    static let bar = Spec(color: Color.black.opacity(0.08), radius: 14, y: 4)
    static let sheet = Spec(color: Color.black.opacity(0.14), radius: 32, y: 12)
}

extension View {
    func dsShadow(_ spec: DSShadow.Spec) -> some View {
        shadow(color: spec.color, radius: spec.radius, x: 0, y: spec.y)
    }
}

// MARK: - การเคลื่อนไหว

/// ผู้เฝ้าดูการตั้งค่า "ลดการเคลื่อนไหว" ของระบบ (iOS 15: UIAccessibility)
final class DSAccessibilityObserver: ObservableObject {

    static let shared = DSAccessibilityObserver()

    @Published private(set) var reduceMotion: Bool = UIAccessibility.isReduceMotionEnabled

    private var token: NSObjectProtocol?

    private init() {
        token = NotificationCenter.default.addObserver(
            forName: UIAccessibility.reduceMotionStatusDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.reduceMotion = UIAccessibility.isReduceMotionEnabled
        }
    }

    deinit {
        if let token = token {
            NotificationCenter.default.removeObserver(token)
        }
    }
}

enum DSMotion {

    static let tapDuration: Double = 0.12
    static let stepDuration: Double = 0.24
    static let checkDuration: Double = 0.26
    static let cardDuration: Double = 0.20
    static let sheetDuration: Double = 0.24
    static let toastDuration: Double = 0.18

    static var reduceMotion: Bool { UIAccessibility.isReduceMotionEnabled }

    /// ขั้นตอนใหม่เลื่อนเข้า — ลดการเคลื่อนไหว = fade สั้นลง
    static var step: Animation {
        reduceMotion ? .easeOut(duration: 0.12) : .timingCurve(0.2, 0.8, 0.2, 1, duration: 0.24)
    }

    static var card: Animation { .easeOut(duration: cardDuration) }
    static var sheet: Animation { .easeOut(duration: reduceMotion ? 0.12 : sheetDuration) }
    static var tap: Animation { .easeOut(duration: tapDuration) }

    /// shimmer ของขั้นที่กำลังทำ (ปิดเมื่อ "ลดการเคลื่อนไหว")
    static var shimmer: Animation? {
        reduceMotion ? nil : .linear(duration: 1.5).repeatForever(autoreverses: false)
    }
}

// MARK: - Haptic

enum DSHaptic {

    /// สวิตช์ในอนาคต (ตั้งค่า → การตอบสนอง) ค่าเริ่มต้นเปิด
    static var isEnabled: Bool {
        if UserDefaults.standard.object(forKey: "settings.hapticsEnabled") == nil { return true }
        return UserDefaults.standard.bool(forKey: "settings.hapticsEnabled")
    }

    /// เริ่มงาน/จบงาน
    static func light() {
        guard isEnabled else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// ต้องขออนุญาต/มีขั้นล้มเหลว
    static func medium() {
        guard isEnabled else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    static func success() {
        guard isEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func warning() {
        guard isEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    static func error() {
        guard isEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
}

// MARK: - ตัวช่วยรูปแบบเวลาและข้อความ

enum DSFormat {

    /// เวลาที่ใช้แบบสั้นสำหรับแถบสถานะสด เช่น "42 วินาที", "1 นาที 12 วินาที"
    static func duration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        if total < 60 { return "\(total) วินาที" }
        let minutes = total / 60
        let rest = total % 60
        if rest == 0 { return "\(minutes) นาที" }
        return "\(minutes) นาที \(rest) วินาที"
    }

    /// นาฬิกาจับเวลาแบบย่อสำหรับแถบสถานะสด เช่น "1:12"
    static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let minutes = total / 60
        let rest = total % 60
        return String(format: "%d:%02d", minutes, rest)
    }

    /// เวลาของเหตุการณ์ในไทม์ไลน์ (24 ชม.)
    static func time(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "th_TH")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    /// ขนาดไฟล์อ่านง่าย
    static func bytes(_ count: Int) -> String {
        if count < 1_024 { return "\(count) ไบต์" }
        if count < 1_024 * 1_024 { return String(format: "%.1f KB", Double(count) / 1_024) }
        return String(format: "%.1f MB", Double(count) / (1_024 * 1_024))
    }
}
