//
//  ToolArguments.swift
//  iOS Agent Sandbox
//
//  อ่าน arguments ที่โมเดลส่งมาแบบ "ตรวจชนิดให้ครบ" ก่อนใช้งาน
//  โมเดลฟรีหลายตัวส่งค่าเป็น string แทน number/bool (เช่น "max_lines": "50")
//  ชั้นนี้จึงยอมรับการแปลงข้ามชนิดที่สมเหตุสมผล แต่ไม่เดาเมื่อกำกวม
//
//  Foundation-only → รัน unit test ได้ทุกแพลตฟอร์ม
//

import Foundation

// MARK: - ข้อผิดพลาดของ arguments

enum ToolArgumentError: LocalizedError, Equatable {
    case missing(key: String)
    case empty(key: String)
    case wrongType(key: String, expected: String)
    case outOfRange(key: String, allowed: String)
    case unreadableJSON(String)

    var errorDescription: String? {
        switch self {
        case .missing(let key):
            return "ไม่พบพารามิเตอร์ \"\(key)\" (ต้องระบุ)"
        case .empty(let key):
            return "พารามิเตอร์ \"\(key)\" ว่างเปล่า (ต้องมีความยาวอย่างน้อย 1 ตัวอักษร)"
        case .wrongType(let key, let expected):
            return "พารามิเตอร์ \"\(key)\" ต้องเป็น \(expected)"
        case .outOfRange(let key, let allowed):
            return "ค่าของ \"\(key)\" อยู่นอกช่วงที่อนุญาต (\(allowed))"
        case .unreadableJSON(let detail):
            return "อ่าน JSON ของ arguments ไม่สำเร็จ: \(detail)"
        }
    }
}

// MARK: - ตัวอ่าน arguments

struct ToolArguments {

    /// arguments ดิบที่ parse เป็น object แล้ว
    let raw: [String: JSONValue]

    init(_ raw: [String: JSONValue]) {
        self.raw = raw
    }

    /// สร้างจาก tool call ที่โมเดลส่งมา — ซ่อม JSON ที่ถูกตัดกลางทางก่อน แล้วค่อยอ่าน
    static func parse(_ call: ToolCall) throws -> ToolArguments {
        let rawText = call.function.arguments
        if let object = JSONValue.decodeObject(fromJSONString: rawText) {
            return ToolArguments(object)
        }
        // ลองซ่อม (โมเดลฟรีมักส่ง JSON ขาด หรือใส่ข้อความอธิบายปนมา)
        let sanitized = ToolArgumentsSanitizer.sanitize(rawText)
        if let object = JSONValue.decodeObject(fromJSONString: sanitized.json) {
            return ToolArguments(object)
        }
        throw ToolArgumentError.unreadableJSON(sanitized.note ?? "ไม่สามารถแปลง arguments เป็น JSON object ได้")
    }

    var isEmpty: Bool {
        raw.isEmpty
    }

    // MARK: ค่าที่ต้องมี

    func string(_ key: String) throws -> String {
        guard let value = raw[key], !value.isNull else {
            throw ToolArgumentError.missing(key: key)
        }
        guard let text = value.stringValue else {
            throw ToolArgumentError.wrongType(key: key, expected: "ข้อความ")
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ToolArgumentError.empty(key: key)
        }
        return trimmed
    }

    func int(_ key: String) throws -> Int {
        guard let value = raw[key], !value.isNull else {
            throw ToolArgumentError.missing(key: key)
        }
        guard let number = value.intValue else {
            throw ToolArgumentError.wrongType(key: key, expected: "จำนวนเต็ม")
        }
        return number
    }

    // MARK: ค่าที่มีก็ได้ ไม่มีก็ได้

    func optionalString(_ key: String) -> String? {
        guard let value = raw[key], !value.isNull, let text = value.stringValue else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func optionalInt(_ key: String) -> Int? {
        guard let value = raw[key], !value.isNull else { return nil }
        return value.intValue
    }

    func bool(_ key: String, default defaultValue: Bool) -> Bool {
        guard let value = raw[key], !value.isNull, let flag = value.boolValue else { return defaultValue }
        return flag
    }

    /// อ่านจำนวนเต็มพร้อมบีบให้อยู่ในช่วงที่ปลอดภัย (ค่าเริ่มต้นใช้เมื่อไม่มี/อ่านไม่ได้)
    func intInRange(_ key: String, default defaultValue: Int, min lower: Int, max upper: Int) -> Int {
        guard let value = optionalInt(key) else { return defaultValue }
        return Swift.min(Swift.max(value, lower), upper)
    }

    /// รายการข้อความ (รับได้ทั้ง array ของ string และ string เดี่ยวที่คั่นด้วยบรรทัด)
    func stringArray(_ key: String) -> [String] {
        guard let value = raw[key], !value.isNull else { return [] }
        if let list = value.arrayValue {
            return list.compactMap { $0.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        if let single = value.stringValue {
            return single.split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        return []
    }

    /// object ย่อย (เช่น headers ของ http_request) — บังคับให้ค่าข้างในเป็นข้อความ
    func stringDictionary(_ key: String) -> [String: String] {
        guard let value = raw[key], !value.isNull, let object = value.objectValue else { return [:] }
        var result: [String: String] = [:]
        for (name, item) in object {
            if let text = item.stringValue {
                result[name] = text
            }
        }
        return result
    }

    // MARK: สำหรับแสดงให้ผู้ใช้เห็น

    /// ข้อความ JSON แบบอ่านง่าย (ใช้ในหน้าขออนุมัติและบันทึกผลของ tool)
    var displayText: String {
        if raw.isEmpty { return "{}" }
        return JSONValue.object(raw).prettyJSONString
    }

    /// สรุปสั้น ๆ บนบรรทัดเดียว เช่น "path=/var/mobile/a.txt, max_lines=50"
    var inlineSummary: String {
        if raw.isEmpty { return "(ไม่มีพารามิเตอร์)" }
        let parts = raw.keys.sorted().map { key -> String in
            let value = raw[key] ?? .null
            var text = value.stringValue ?? value.compactJSONString
            if text.count > 60 { text = String(text.prefix(60)) + "…" }
            return "\(key)=\(text)"
        }
        return parts.joined(separator: ", ")
    }
}
