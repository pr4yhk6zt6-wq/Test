//
//  APIKeySanitizer.swift
//  iOS Agent Sandbox
//
//  ทำความสะอาด/ตรวจรูป API Key และตัดสินใจว่าจะใช้คีย์จากที่เก็บใด
//
//  ไฟล์นี้แก้บั๊กที่ผู้ใช้เจอบนเครื่องจริง: "สร้างคีย์ใหม่แล้ว แต่ยังขึ้น 401 (User not found)"
//  สาเหตุมี 2 อย่างและทั้งคู่ถูกปิดที่นี่
//    1) ที่เก็บสำรอง (UserDefaults) มีคีย์เก่าค้างอยู่ และโค้ดเดิมอ่านสำรอง "ก่อน" Keychain
//       → คีย์ใหม่ที่บันทึกสำเร็จถูกบดบังด้วยคีย์เก่าที่ถูกยกเลิกไปแล้วตลอดไป
//    2) คีย์ที่วางมาจากคลิปบอร์ดมีช่องว่าง/ขึ้นบรรทัดใหม่/อักขระล่องหนติดมา
//       → ส่งไปแล้วเซิร์ฟเวอร์มองไม่เห็นผู้ใช้ (401 "User not found.")
//
//  โค้ดทั้งหมดในไฟล์นี้เป็น Foundation ล้วน → รันทดสอบได้ทั้ง Linux และ macOS
//

import Foundation

// MARK: - ทำความสะอาดคีย์

enum APIKeySanitizer {

    struct Result: Equatable {
        /// คีย์หลังทำความสะอาด (ใช้ค่านี้เสมอเมื่อจะเก็บหรือส่ง)
        let cleaned: String
        /// จำนวนอักขระที่ถูกตัดออก (ช่องว่าง/ขึ้นบรรทัดใหม่/อักขระล่องหน)
        let removedCharacters: Int
        /// true = มีเครื่องหมายคำพูดหรืออัญประกาศครอบอยู่ และถูกตัดออกให้
        let hadWrappingQuotes: Bool

        var didChange: Bool {
            removedCharacters > 0 || hadWrappingQuotes
        }

        /// คำอธิบายภาษาไทยว่าปรับอะไรไปบ้าง (nil = ไม่มีอะไรต้องปรับ)
        var changeDescription: String? {
            var parts: [String] = []
            if removedCharacters > 0 {
                parts.append("ตัดช่องว่าง/อักขระล่องหนออก \(removedCharacters) ตัว")
            }
            if hadWrappingQuotes {
                parts.append("ตัดเครื่องหมายคำพูดที่ครอบออก")
            }
            return parts.isEmpty ? nil : parts.joined(separator: " • ")
        }
    }

    /// อักขระที่ต้องไม่มีในคีย์เด็ดขาด (รวม zero-width และ BOM ที่ติดมากับการคัดลอก)
    private static let invisibleScalars: Set<Unicode.Scalar> = [
        " ", "\t", "\n", "\r", "\u{0000}", "\u{00A0}",
        "\u{200B}", "\u{200C}", "\u{200D}", "\u{2060}", "\u{FEFF}"
    ]

    private static let quoteCharacters: [Character] = ["\"", "'", "“", "”", "‘", "’"]

    /// ตัดช่องว่าง/ขึ้นบรรทัดใหม่/อักขระล่องหน และเครื่องหมายคำพูดที่ครอบอยู่ออก
    static func sanitize(_ raw: String) -> Result {
        var removed = 0
        var cleaned = ""
        cleaned.reserveCapacity(raw.count)

        for scalar in raw.unicodeScalars {
            if invisibleScalars.contains(scalar) {
                removed += 1
            } else {
                cleaned.unicodeScalars.append(scalar)
            }
        }

        var hadQuotes = false
        if let first = cleaned.first, let last = cleaned.last,
           cleaned.count > 1, quoteCharacters.contains(first), quoteCharacters.contains(last) {
            cleaned = String(cleaned.dropFirst().dropLast())
            hadQuotes = true
        }

        return Result(cleaned: cleaned, removedCharacters: removed, hadWrappingQuotes: hadQuotes)
    }

    /// คีย์ของ OpenRouter ขึ้นต้นด้วย "sk-or-"
    static func looksLikeOpenRouterKey(_ key: String) -> Bool {
        sanitize(key).cleaned.hasPrefix("sk-or-")
    }

    /// ข้อความระบุตัวคีย์โดยไม่เปิดเผยคีย์เต็ม (ใช้เทียบกับหน้าเว็บ OpenRouter)
    static func fingerprint(_ key: String) -> String {
        let value = sanitize(key).cleaned
        guard !value.isEmpty else { return "(ยังไม่มีคีย์)" }
        if value.count <= 16 {
            return "\(value.prefix(4))…\(value.suffix(2)) • \(value.count) ตัวอักษร"
        }
        return "\(value.prefix(11))…\(value.suffix(4)) • \(value.count) ตัวอักษร"
    }

    /// ตรวจรูปคีย์ก่อนบันทึก — คืนข้อความเตือน (nil = ดูปกติ)
    static func validate(_ key: String) -> String? {
        let value = sanitize(key).cleaned
        if value.isEmpty {
            return "ยังไม่ได้กรอก API Key"
        }
        if !value.hasPrefix("sk-or-") {
            return "คีย์นี้ไม่ได้ขึ้นต้นด้วย sk-or- — คีย์ของ OpenRouter ต้องขึ้นต้นแบบนั้น " +
                "(คีย์ของบริการอื่น เช่น sk-… ของ OpenAI ใช้กับ OpenRouter ไม่ได้)"
        }
        if value.count < 20 {
            return "คีย์สั้นผิดปกติ (\(value.count) ตัวอักษร) — อาจคัดลอกมาไม่ครบ"
        }
        return nil
    }
}

// MARK: - ตัดสินใจว่าจะใช้คีย์จากที่เก็บใด

/// กติกาการเลือกคีย์: **Keychain มาก่อนเสมอ** และถ้าพบคีย์เก่าค้างในที่เก็บสำรอง
/// ขณะที่ Keychain มีค่าใหม่กว่า ต้องล้างสำรองทิ้ง (ไม่งั้นคีย์เก่าจะถูกใช้ตลอดไป)
enum APIKeyStoragePolicy {

    struct Resolution: Equatable {
        /// ค่าที่ควรใช้ (nil = ยังไม่มีคีย์)
        let value: String?
        /// true = ค่ามาจากที่เก็บสำรอง (UserDefaults) เพราะ Keychain ใช้ไม่ได้
        let isUsingFallback: Bool
        /// true = พบคีย์เก่าค้างในที่เก็บสำรองทั้งที่มีค่าใหม่กว่าใน Keychain → ต้องลบทิ้ง
        let shouldPurgeFallback: Bool
    }

    static func resolve(keychainValue: String?, fallbackValue: String?) -> Resolution {
        let keychain = normalized(keychainValue)
        let fallback = normalized(fallbackValue)

        if let keychain = keychain {
            return Resolution(value: keychain,
                              isUsingFallback: false,
                              shouldPurgeFallback: fallback != nil && fallback != keychain)
        }
        if let fallback = fallback {
            return Resolution(value: fallback, isUsingFallback: true, shouldPurgeFallback: false)
        }
        return Resolution(value: nil, isUsingFallback: false, shouldPurgeFallback: false)
    }

    /// ค่าที่ว่างหรือมีแต่ช่องว่างถือว่า "ไม่มีค่า"
    private static func normalized(_ value: String?) -> String? {
        guard let value = value else { return nil }
        let cleaned = APIKeySanitizer.sanitize(value).cleaned
        return cleaned.isEmpty ? nil : cleaned
    }
}
