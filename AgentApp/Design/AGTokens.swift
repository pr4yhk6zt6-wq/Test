//
//  AGTokens.swift
//  AgentApp — โทเคนดีไซน์ (พอร์ตตรงจากแบบ phase1–phase4)
//
//  ค่าทุกตัวในไฟล์นี้คัดมาจาก CSS ของแบบ (design-phase1.html / phase4-prototype.html)
//  โดยไม่ดัดแปลงตัวเลข — เพื่อให้หน้าจอที่แอปวาดตรงกับแบบ 100%
//
//  การเข้ากันได้: iOS 15.0 / iPhone 7 (ไม่ใช้ API ของ iOS 16+)
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - สี (ตรงกับ :root และ [data-theme="dark"] ของแบบ)

enum AGColor {

    static let bg = dynamic(light: 0xF7F7F4, dark: 0x0F1013)
    static let surface = dynamic(light: 0xFFFFFF, dark: 0x17191E)
    static let surface2 = dynamic(light: 0xEFEFEA, dark: 0x1F2228)
    static let surface3 = dynamic(light: 0xE5E5DF, dark: 0x272B33)

    static let border = dynamic(light: 0xE0E0DA, dark: 0x2A2E37)
    static let borderStrong = dynamic(light: 0xC9C9C2, dark: 0x39404F)

    static let t1 = dynamic(light: 0x15181D, dark: 0xE9EBEF)
    static let t2 = dynamic(light: 0x545B66, dark: 0x9CA3AF)
    static let t3 = dynamic(light: 0x646C77, dark: 0x8A93A1)

    static let accent = dynamic(light: 0x2E4A8A, dark: 0x8CA4E8)
    static let accentSoft = dynamic(light: 0xE8ECF7, dark: 0x252A38)
    static let accentInk = dynamic(light: 0x2E4A8A, dark: 0xA7B8EE)
    static let onAccent = dynamic(light: 0xFFFFFF, dark: 0x0F1013)

    static let success = dynamic(light: 0x17683F, dark: 0x6BC08C)
    static let successSoft = dynamic(light: 0xE3F0E9, dark: 0x1D2A24)
    static let warning = dynamic(light: 0x8A5A00, dark: 0xDDAE5E)
    static let warningSoft = dynamic(light: 0xFAF0DA, dark: 0x2A2519)
    static let error = dynamic(light: 0xA3241F, dark: 0xEE8B84)
    static let errorSoft = dynamic(light: 0xFBE9E7, dark: 0x2C1F1E)

    /// --scrim: rgba(20,22,28,.42) / rgba(6,7,9,.6)
    static let scrim = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 6 / 255, green: 7 / 255, blue: 9 / 255, alpha: 0.6)
            : UIColor(red: 20 / 255, green: 22 / 255, blue: 28 / 255, alpha: 0.42)
    })

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(agHex: dark) : UIColor(agHex: light)
        })
    }
}

extension UIColor {
    convenience init(agHex value: UInt32) {
        self.init(red: CGFloat((value >> 16) & 0xFF) / 255,
                  green: CGFloat((value >> 8) & 0xFF) / 255,
                  blue: CGFloat(value & 0xFF) / 255,
                  alpha: 1)
    }
}

// MARK: - ตัวอักษร (ตรงกับ --fs-* และ --lh-*)

enum AGFont {

    static let display: CGFloat = 25
    static let title: CGFloat = 20
    static let head: CGFloat = 17
    static let body: CGFloat = 16
    static let callout: CGFloat = 15
    static let sub: CGFloat = 14
    static let foot: CGFloat = 13
    static let cap: CGFloat = 12
    static let micro: CGFloat = 11.5

    static let lhBody: CGFloat = 1.62
    static let lhTight: CGFloat = 1.4
    static let lhMeta: CGFloat = 1.5

    static let regular = "IBMPlexSansThai-Regular"
    static let medium = "IBMPlexSansThai-Medium"
    static let semibold = "IBMPlexSansThai-SemiBold"
    static let bold = "IBMPlexSansThai-Bold"

    static let available = UIFont(name: regular, size: 12) != nil

    /// ตัวคูณตัวอักษรของผู้ใช้ (ค่าตั้งในหน้าตั้งค่า) — จำกัดบนจอแคบกันข้อความล้น
    static func scale(_ value: Double) -> CGFloat {
        guard value.isFinite, value > 0 else { return 1 }
        let ceiling: Double = UIScreen.main.bounds.width < 375 ? 1.15 : 1.6
        return CGFloat(min(max(value, 0.85), ceiling))
    }

    static func size(_ base: CGFloat, scale: Double = 1) -> CGFloat {
        (base * AGFont.scale(scale)).rounded()
    }

    static func name(weight: Font.Weight) -> String {
        switch weight {
        case .bold, .heavy, .black: return bold
        case .semibold: return semibold
        case .medium: return medium
        default: return regular
        }
    }

    static func name(weight: UIFont.Weight) -> String {
        if weight == .bold || weight == .heavy || weight == .black { return bold }
        if weight == .semibold { return semibold }
        if weight == .medium { return medium }
        return regular
    }

    static func font(_ base: CGFloat, weight: Font.Weight = .regular, scale: Double = 1) -> Font {
        let point = size(base, scale: scale)
        if available { return Font.custom(name(weight: weight), size: point) }
        return Font.system(size: point, weight: weight)
    }

    static func uiFont(_ base: CGFloat, weight: UIFont.Weight = .regular, scale: Double = 1) -> UIFont {
        let point = size(base, scale: scale)
        if available, let font = UIFont(name: name(weight: weight), size: point) { return font }
        return UIFont.systemFont(ofSize: point, weight: weight)
    }

    /// ระยะบรรทัดที่ทำให้ความสูงรวมเท่ากับ multiplier ของขนาดตัวอักษร (คำนวณจากเมตริกฟอนต์จริง)
    /// ภาษาไทยต้องการระยะนี้จริง ๆ เพราะสระบน-ล่างจะชนกันถ้าใช้ค่าของภาษาละติน
    static func lineSpacing(_ base: CGFloat, scale: Double = 1, multiplier: CGFloat = lhBody) -> CGFloat {
        let point = base * AGFont.scale(scale)
        let resolved = uiFont(base, scale: scale)
        let natural = resolved.ascender - resolved.descender + resolved.leading
        return max(0, (point * multiplier - natural).rounded())
    }

    static func mono(_ base: CGFloat, scale: Double = 1) -> Font {
        .system(size: size(base, scale: scale), design: .monospaced)
    }
}

// MARK: - ระยะ / มุมโค้ง / เงา (ตรงกับ --sp-*, --r-*, --sh-*)

enum AGMetric {

    static let s1: CGFloat = 4
    static let s2: CGFloat = 8
    static let s3: CGFloat = 12
    static let s4: CGFloat = 16
    static let s5: CGFloat = 20
    static let s6: CGFloat = 24
    static let s8: CGFloat = 32

    static let rXS: CGFloat = 8
    static let rSM: CGFloat = 12
    static let rMD: CGFloat = 16
    static let rLG: CGFloat = 20
    static let rXL: CGFloat = 28
    static let rPill: CGFloat = 999

    /// ขอบข้างของพื้นที่แชท: 16 (จอแคบ 12) — ตามแบบ .chat padding 12px 16px 16px
    static var screenPadding: CGFloat { UIScreen.main.bounds.width < 375 ? 12 : 16 }

    static let touch: CGFloat = 44
    static let liveBarMinHeight: CGFloat = 52
    static let stepIcon: CGFloat = 22
    static let composerFieldMinHeight: CGFloat = 44
    static let composerFieldMaxHeight: CGFloat = 112
    static let tabBarHeight: CGFloat = 52
}

enum AGShadow {
    /// --sh-1 / --sh-2 / --sh-3
    static func apply<V: View>(_ view: V, level: Int) -> some View {
        switch level {
        case 1:
            return AnyView(view.shadow(color: Color.black.opacity(0.06), radius: 1, x: 0, y: 1)
                               .shadow(color: Color.black.opacity(0.04), radius: 1, x: 0, y: 1))
        case 2:
            return AnyView(view.shadow(color: Color.black.opacity(0.08), radius: 7, x: 0, y: 4))
        default:
            return AnyView(view.shadow(color: Color.black.opacity(0.14), radius: 16, x: 0, y: 12))
        }
    }
}

// MARK: - การเคลื่อนไหว (ตรงกับ --dur-* และ --ease)

enum AGMotion {

    static let dur1: Double = 0.12
    static let dur2: Double = 0.18
    static let dur3: Double = 0.24

    /// cubic-bezier(.2,.8,.2,1) ≈ easeOut ที่ให้ความรู้สึกเดียวกัน
    static let ease = Animation.timingCurve(0.2, 0.8, 0.2, 1, duration: dur2)

    /// เคารพการตั้งค่า "ลดการเคลื่อนไหว" ของระบบ (เช็กลิสต์บังคับ)
    static var reduceMotion: Bool {
        UIAccessibility.isReduceMotionEnabled
    }

    static func animation(_ value: Animation) -> Animation? {
        reduceMotion ? nil : value
    }
}

// MARK: - Haptic (ให้ความรู้สึกว่ากดติด)

enum AGHaptic {

    static func light() {
        #if canImport(UIKit)
        guard UserDefaults.standard.object(forKey: AGDefaults.hapticsKey) as? Bool ?? true else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }

    static func medium() {
        #if canImport(UIKit)
        guard UserDefaults.standard.object(forKey: AGDefaults.hapticsKey) as? Bool ?? true else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
    }

    static func success() {
        #if canImport(UIKit)
        guard UserDefaults.standard.object(forKey: AGDefaults.hapticsKey) as? Bool ?? true else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }

    static func warning() {
        #if canImport(UIKit)
        guard UserDefaults.standard.object(forKey: AGDefaults.hapticsKey) as? Bool ?? true else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        #endif
    }
}

enum AGDefaults {
    /// คีย์เดียวกับที่หน้าตั้งค่าใช้ (SettingsKeys.hapticsEnabled) — ไม่ประกาศซ้ำเพื่อไม่ให้ชนกัน
    static let hapticsKey = "settings.hapticsEnabled"
}

// MARK: - รูปแบบข้อความ

enum AGFormat {

    /// "39 วิ" / "2 นาที 5 วิ" (ตามแบบที่แถบสถานะสดใช้)
    static func durationShort(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        if total < 60 { return "\(total) วิ" }
        let minutes = total / 60
        let rest = total % 60
        if rest == 0 { return "\(minutes) นาที" }
        return "\(minutes) นาที \(rest) วิ"
    }

    static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    static func time(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "th_TH")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    static func bytes(_ count: Int) -> String {
        if count < 1_024 { return "\(count) ไบต์" }
        if count < 1_024 * 1_024 { return String(format: "%.1f KB", Double(count) / 1_024) }
        return String(format: "%.1f MB", Double(count) / (1_024 * 1_024))
    }
}
