//
//  ToolOutputLimiter.swift
//  iOS Agent Sandbox
//
//  จำกัดความยาวผลลัพธ์ของ tool ที่จะส่งกลับให้โมเดลและแสดงในหน้าแชท
//  เหตุผล: (1) กัน RAM บนเครื่อง 2GB (2) กันการเผา token โดยไม่จำเป็น
//  (3) ทำให้คำตอบของโมเดลไม่ถูกดันตกขอบ context ด้วยผลลัพธ์ยาว ๆ
//
//  Foundation-only → รัน unit test ได้ทุกแพลตฟอร์ม
//

import Foundation

enum ToolOutputLimiter {

    /// เพดานความยาวผลลัพธ์ของ tool ต่อหนึ่งครั้ง (ตัวอักษร ไม่ใช่ไบต์)
    static let defaultMaxCharacters = 10_000

    /// เพดานไบต์ที่ยอมให้อ่านเข้าหน่วยความจำในครั้งเดียว (ก่อนแปลงเป็นข้อความ)
    static let maxReadBytes = 256 * 1024

    struct Limited: Equatable {
        /// ข้อความที่พร้อมส่งต่อ (อาจมีข้อความแจ้งการตัดต่อท้าย)
        let text: String
        /// true = ข้อความถูกตัด
        let truncated: Bool
        /// จำนวนตัวอักษรของข้อความเดิม
        let originalCount: Int
    }

    /// ตัดข้อความให้ไม่เกิน maxCharacters และต่อท้ายด้วยคำอธิบายภาษาไทย
    static func limit(_ text: String, maxCharacters: Int = ToolOutputLimiter.defaultMaxCharacters) -> Limited {
        let originalCount = text.count
        guard maxCharacters > 0 else {
            return Limited(text: "", truncated: !text.isEmpty, originalCount: originalCount)
        }
        guard originalCount > maxCharacters else {
            return Limited(text: text, truncated: false, originalCount: originalCount)
        }

        // ตัดที่ขอบบรรทัดถ้าทำได้ เพื่อไม่ให้เหลือครึ่งบรรทัดที่อ่านไม่รู้เรื่อง
        let prefix = String(text.prefix(maxCharacters))
        var body = prefix
        if let lastNewline = prefix.lastIndex(of: "\n") {
            let distance = prefix.distance(from: lastNewline, to: prefix.endIndex)
            if distance < 200, lastNewline > prefix.startIndex {
                body = String(prefix[prefix.startIndex..<lastNewline])
            }
        }

        let notice = "\n\n… (ตัดทอนผลลัพธ์: แสดง \(body.count) จาก \(originalCount) ตัวอักษร — " +
            "ถ้าต้องการส่วนที่เหลือให้ระบุช่วงบรรทัดหรือ path ที่แคบลงแล้วเรียก tool อีกครั้ง)"
        return Limited(text: body + notice, truncated: true, originalCount: originalCount)
    }

    /// ข้อความแจ้งเตือนแบบสั้น (ใช้เมื่อต้องบอกผู้ใช้โดยไม่ต้องแนบเนื้อหา)
    static func noticeText(original: Int, shown: Int) -> String {
        "ตัดทอนผลลัพธ์: แสดง \(shown) จาก \(original) ตัวอักษร"
    }
}
