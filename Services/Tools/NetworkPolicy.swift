//
//  NetworkPolicy.swift
//  iOS Agent Sandbox
//
//  นโยบายการใช้อินเทอร์เน็ตของ Agent (เฟส 2)
//  - ต้องเปิดสวิตช์ "อนุญาตให้ใช้ internet" ก่อน
//  - ถ้าเปิด "ใช้เฉพาะ Wi-Fi" จะบล็อกเมื่อไม่ได้ต่อ Wi-Fi
//  - บังคับ HTTPS เสมอ (ยกเว้น localhost สำหรับทดสอบเซิร์ฟเวอร์ในเครื่อง)
//  - จำกัดขนาดไฟล์ดาวน์โหลด (ค่าเริ่มต้น 200MB ปรับได้ในหน้าตั้งค่า)
//
//  Foundation-only → รัน unit test ได้ทุกแพลตฟอร์ม
//  (การตรวจจริงว่าเครือข่ายเป็น Wi-Fi หรือเซลลูลาร์อยู่ใน ConnectivityMonitor ซึ่งใช้ Network framework)
//

import Foundation

// MARK: - ค่าเวลาที่ใช้ทั้งแอป

enum NetworkTimeouts {
    /// เวลาสูงสุดของคำขอเครือข่ายหนึ่งครั้ง
    static let requestSeconds: TimeInterval = 30
    /// เวลาสูงสุดของงานที่ใช้ resource ต่อเนื่อง (ดาวน์โหลด/อัปโหลด)
    static let resourceSeconds: TimeInterval = 600
    /// เวลาสูงสุดของคำสั่ง shell ตามค่าเริ่มต้น
    static let shellSeconds: TimeInterval = 30
    /// เวลาสูงสุดที่ยอมให้ผู้ใช้ตั้งได้เองสำหรับคำสั่ง shell
    static let maximumShellSeconds: TimeInterval = 120
}

// MARK: - ข้อผิดพลาดของนโยบายเครือข่าย

enum NetworkPolicyError: LocalizedError, Equatable {
    case internetDisabled
    case wifiRequired
    case insecureScheme(String)
    case unsupportedScheme(String)
    case invalidURL(String)
    case fileTooLarge(bytes: Int64, limit: Int64)

    var errorDescription: String? {
        switch self {
        case .internetDisabled:
            return "การใช้อินเทอร์เน็ตถูกปิดอยู่ — เปิดได้ที่แท็บตั้งค่า > Agent (อนุญาตให้ใช้ internet)"
        case .wifiRequired:
            return "ตั้งค่าให้ใช้เฉพาะ Wi-Fi แต่ตอนนี้ไม่ได้เชื่อมต่อ Wi-Fi (เปลี่ยนได้ที่แท็บตั้งค่า > Agent)"
        case .insecureScheme(let scheme):
            return "อนุญาตเฉพาะ https:// (หรือ http://localhost สำหรับทดสอบในเครื่อง) — ที่ส่งมาคือ \(scheme)://"
        case .unsupportedScheme(let scheme):
            return "รูปแบบ URL นี้ไม่รองรับ (\(scheme)://) — ใช้ได้เฉพาะ http/https"
        case .invalidURL(let value):
            return "URL ไม่ถูกต้อง: \(value)"
        case .fileTooLarge(let bytes, let limit):
            return "ไฟล์ใหญ่เกินขอบเขต: \(NetworkPolicy.formatBytes(bytes)) เกินเพดาน \(NetworkPolicy.formatBytes(limit)) — " +
                "ปรับเพดานได้ที่แท็บตั้งค่า > Agent"
        }
    }
}

// MARK: - นโยบาย

enum NetworkPolicy {

    /// โฮสต์ที่ยอมให้ใช้ http (ไม่เข้ารหัส) เพราะอยู่ในเครื่องเอง — ใช้ทดสอบเซิร์ฟเวอร์จำลอง
    static let insecureHostsAllowed: Set<String> = ["localhost", "127.0.0.1", "::1", "0.0.0.0"]

    /// ตรวจว่า URL นี้ใช้ได้ตามนโยบายหรือไม่ — คืน nil = ผ่าน
    static func validate(urlString: String,
                         allowInternet: Bool,
                         wifiOnly: Bool,
                         isWiFiConnected: Bool) -> NetworkPolicyError? {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed), let scheme = url.scheme?.lowercased() else {
            return .invalidURL(urlString)
        }

        guard scheme == "http" || scheme == "https" else {
            return .unsupportedScheme(scheme)
        }
        guard let host = url.host?.lowercased(), !host.isEmpty else {
            return .invalidURL(urlString)
        }

        if !allowInternet {
            return .internetDisabled
        }
        if wifiOnly, !isWiFiConnected {
            return .wifiRequired
        }
        if scheme == "http" && !insecureHostsAllowed.contains(host) {
            return .insecureScheme(scheme)
        }
        return nil
    }

    /// ตรวจขนาดไฟล์ก่อน/ระหว่างดาวน์โหลด (nil = ไม่ทราบขนาดล่วงหน้า)
    static func validateDownload(sizeBytes: Int64?, limitBytes: Int64) -> NetworkPolicyError? {
        guard let size = sizeBytes, size > 0 else { return nil }
        if size > limitBytes {
            return .fileTooLarge(bytes: size, limit: limitBytes)
        }
        return nil
    }

    /// แปลงเมกะไบต์เป็นไบต์ (จำกัดช่วง 1MB – 8GB กันค่าที่พิมพ์ผิด)
    static func maxDownloadBytes(megabytes: Int) -> Int64 {
        let clamped = min(max(megabytes, 1), 8 * 1024)
        return Int64(clamped) * 1024 * 1024
    }

    /// แสดงขนาดไฟล์แบบอ่านง่าย
    static func formatBytes(_ bytes: Int64) -> String {
        let units: [(name: String, size: Double)] = [
            ("GB", 1024 * 1024 * 1024),
            ("MB", 1024 * 1024),
            ("KB", 1024)
        ]
        let value = Double(bytes)
        for unit in units where value >= unit.size {
            let scaled = value / unit.size
            let text = scaled >= 100 ? String(format: "%.0f", scaled) : String(format: "%.1f", scaled)
            return "\(text) \(unit.name)"
        }
        return "\(bytes) ไบต์"
    }

    /// ตรวจว่าโค้ดตอบกลับนี้ควรแสดงเป็นข้อความได้หรือไม่ (กันการเอาไบต์ไบนารีไปใส่ใน context)
    static func isLikelyText(contentType: String?) -> Bool {
        guard let contentType = contentType?.lowercased() else { return true }
        let textMarkers = ["text/", "json", "xml", "javascript", "x-www-form-urlencoded", "csv", "html", "plain"]
        return textMarkers.contains { contentType.contains($0) }
    }
}
