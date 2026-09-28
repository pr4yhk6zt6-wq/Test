//
//  SensitiveMask.swift
//  iOS Agent Sandbox — ดีไซน์ v2 (เฟส 5 ส่วนที่ 3)
//
//  ปิดบังข้อมูลอ่อนไหว "ก่อนแสดง" ในไทม์ไลน์/การ์ด/แผ่นรายละเอียดของ UI ใหม่
//  ตามข้อกำหนดใน design-phase2-cards-controls.md (ค่าเริ่มต้น: ปิดบังไว้)
//
//  หมายเหตุสำคัญ: ตัวปิดบังนี้ทำงานกับ "ข้อความที่จะแสดงและบันทึกในไทม์ไลน์" เท่านั้น
//  ไม่ได้แก้ข้อมูลที่ engine ส่งให้โมเดล (งานนั้นเป็นของชั้นความปลอดภัยของ engine)
//

import Foundation

enum SensitiveMask {

    struct Result: Equatable {
        /// ข้อความที่ปิดบังแล้ว (พร้อมใช้แสดง)
        let text: String
        /// จำนวนจุดที่ถูกปิดบัง (0 = ไม่มีข้อมูลอ่อนไหว)
        let maskedCount: Int
    }

    private struct Rule {
        let pattern: String
        let template: String
    }

    /// กติกาที่ครอบคลุมสิ่งที่แอปนี้เจอบ่อย: คีย์ของ OpenRouter/GitHub, รหัสผ่าน, อีเมล,
    /// เลขบัตร/เลขบัญชี, เบอร์โทรไทย — เรียงจากเฉพาะเจาะจงไปกว้าง
    private static let rules: [Rule] = [
        Rule(pattern: "\\bsk-[A-Za-z0-9._\\-]{8,}\\b", template: "•••"),
        Rule(pattern: "\\bghp_[A-Za-z0-9]{8,}\\b", template: "•••"),
        Rule(pattern: "\\bgithub_pat_[A-Za-z0-9_]{8,}\\b", template: "•••"),
        Rule(pattern: "(?i)\\b(bearer)\\s+[A-Za-z0-9._\\-]{8,}", template: "$1 •••"),
        Rule(pattern: "(?i)((?:api[_-]?key|apikey|access[_-]?token|refresh[_-]?token|"
                + "auth[_-]?token|token|secret|client[_-]?secret|password|passwd|pwd)"
                + "\\s*[:=]\\s*)(\\S+)",
             template: "$1•••"),
        Rule(pattern: "[A-Za-z0-9._%+\\-]+@[A-Za-z0-9.\\-]+\\.[A-Za-z]{2,}", template: "•••@•••"),
        Rule(pattern: "\\b0\\d{8,9}\\b", template: "•••"),
        Rule(pattern: "\\b(?:\\d[ \\-]?){13,19}\\b", template: "•••")
    ]

    /// คู่ (regex, template) ที่คอมไพล์สำเร็จ — จับคู่กันตรงตัวเสมอ ไม่พึ่งลำดับ index ของ rules
    private static let compiled: [(regex: NSRegularExpression, template: String)] = rules.compactMap { rule in
        guard let regex = try? NSRegularExpression(pattern: rule.pattern, options: []) else { return nil }
        return (regex, rule.template)
    }

    /// ปิดบังข้อมูลอ่อนไหวในข้อความ
    static func mask(_ input: String) -> Result {
        guard !input.isEmpty else { return Result(text: input, maskedCount: 0) }

        var working = input
        var total = 0

        for entry in compiled {
            let range = NSRange(working.startIndex..<working.endIndex, in: working)
            let matches = entry.regex.numberOfMatches(in: working, options: [], range: range)
            guard matches > 0 else { continue }
            total += matches
            working = entry.regex.stringByReplacingMatches(in: working,
                                                           options: [],
                                                           range: range,
                                                           withTemplate: entry.template)
        }

        return Result(text: working, maskedCount: total)
    }

    /// ปิดบัง + จำกัดความยาว (กันหน่วยความจำบวมบน iPhone 7)
    static func maskAndLimit(_ input: String, maxCharacters: Int) -> Result {
        let limited: String
        if input.count > maxCharacters {
            limited = String(input.prefix(maxCharacters)) + "\n… (ตัดข้อความที่ยาวเกินไว้)"
        } else {
            limited = input
        }
        return mask(limited)
    }
}
