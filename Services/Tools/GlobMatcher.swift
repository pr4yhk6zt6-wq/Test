//
//  GlobMatcher.swift
//  iOS Agent Sandbox
//
//  จับคู่ชื่อไฟล์ด้วยรูปแบบ glob แบบเขียนเอง (ไม่ใช้ regex)
//  เขียนเองเพราะ: เร็วกว่า, ไม่มีปัญหา escaping, และทดสอบได้ตรงไปตรงมา
//
//  รองรับ: * (ทุกอย่าง), ? (หนึ่งตัวอักษร), ** (เหมือน * ในบริบทชื่อไฟล์)
//  ตัวอักษรพิเศษอื่น ๆ ถือเป็นตัวอักษรธรรมดา (ปลอดภัยกว่าการตีความเป็น regex)
//
//  Foundation-only → รัน unit test ได้ทุกแพลตฟอร์ม
//

import Foundation

enum GlobMatcher {

    /// ตรวจว่ารูปแบบ glob นี้ใช้ได้ (ไม่ว่าง, ยาวไม่เกิน 200 ตัวอักษร)
    static func isValidPattern(_ pattern: String) -> Bool {
        let trimmed = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.count <= 200
    }

    /// จับคู่ข้อความกับรูปแบบ glob
    /// - Parameter caseSensitive: ค่าเริ่มต้น false เพราะบน iOS ชื่อไฟล์มักไม่แยกตัวพิมพ์เล็ก-ใหญ่
    static func matches(_ pattern: String, _ text: String, caseSensitive: Bool = false) -> Bool {
        let needle: String
        let haystack: String
        if caseSensitive {
            needle = pattern
            haystack = text
        } else {
            needle = pattern.lowercased()
            haystack = text.lowercased()
        }

        let patternChars = Array(needle)
        let textChars = Array(haystack)

        // อัลกอริทึม wildcard แบบ two-pointer + จุดย้อนกลับ (linear time, ไม่ใช้ recursion)
        var patternIndex = 0
        var textIndex = 0
        var starIndex = -1
        var matchIndex = 0

        while textIndex < textChars.count {
            if patternIndex < patternChars.count {
                let current = patternChars[patternIndex]
                if current == "?" || current == textChars[textIndex] {
                    patternIndex += 1
                    textIndex += 1
                    continue
                }
                if current == "*" {
                    starIndex = patternIndex
                    matchIndex = textIndex
                    patternIndex += 1
                    continue
                }
            }
            if starIndex >= 0 {
                // ย้อนกลับไปขยาย "*" ให้กินอีกหนึ่งตัวอักษร
                patternIndex = starIndex + 1
                matchIndex += 1
                textIndex = matchIndex
                continue
            }
            return false
        }

        // เก็บ "*" ที่เหลือท้ายรูปแบบ
        while patternIndex < patternChars.count, patternChars[patternIndex] == "*" {
            patternIndex += 1
        }
        return patternIndex == patternChars.count
    }

    /// true ถ้าตรงกับรูปแบบใดรูปแบบหนึ่งในรายการ
    static func matchesAny(_ patterns: [String], _ text: String, caseSensitive: Bool = false) -> Bool {
        for pattern in patterns where matches(pattern, text, caseSensitive: caseSensitive) {
            return true
        }
        return false
    }

    /// รวบรวมรูปแบบที่ผู้ใช้อาจพิมพ์หลายรูปแบบคั่นด้วย comma/ช่องว่าง
    static func splitPatterns(_ raw: String) -> [String] {
        raw.split(whereSeparator: { $0 == "," || $0 == " " || $0 == "\n" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
