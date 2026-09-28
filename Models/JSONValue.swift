//
//  JSONValue.swift
//  iOS Agent Sandbox
//
//  ค่า JSON แบบ type-safe ใช้สำหรับ arguments ของ tool, JSON Schema
//  และ payload ที่ส่งไปยัง OpenRouter (ไม่ต้องพึ่งพา [String: Any])
//

import Foundation

enum JSONValue: Codable, Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    // MARK: - Codable

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
            return
        }
        if let value = try? container.decode(Bool.self) { self = .bool(value); return }
        if let value = try? container.decode(Int.self) { self = .int(value); return }
        if let value = try? container.decode(Double.self) { self = .double(value); return }
        if let value = try? container.decode(String.self) { self = .string(value); return }
        if let value = try? container.decode([JSONValue].self) { self = .array(value); return }
        if let value = try? container.decode([String: JSONValue].self) { self = .object(value); return }
        throw DecodingError.dataCorruptedError(in: container,
                                               debugDescription: "ชนิดข้อมูล JSON ไม่เป็นที่รู้จัก")
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .int(let value):
            try container.encode(value)
        case .double(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }

    // MARK: - ตัวช่วยอ่านค่า

    var isNull: Bool {
        if case .null = self { return true }
        return false
    }

    var stringValue: String? {
        switch self {
        case .string(let value): return value
        case .int(let value): return String(value)
        case .double(let value): return String(value)
        case .bool(let value): return String(value)
        default: return nil
        }
    }

    var intValue: Int? {
        switch self {
        case .int(let value): return value
        case .double(let value): return Int(value)
        case .string(let value): return Int(value)
        default: return nil
        }
    }

    var doubleValue: Double? {
        switch self {
        case .double(let value): return value
        case .int(let value): return Double(value)
        case .string(let value): return Double(value)
        default: return nil
        }
    }

    var boolValue: Bool? {
        switch self {
        case .bool(let value): return value
        case .int(let value): return value != 0
        case .string(let value): return Bool(value)
        default: return nil
        }
    }

    var arrayValue: [JSONValue]? {
        if case .array(let value) = self { return value }
        return nil
    }

    var objectValue: [String: JSONValue]? {
        if case .object(let value) = self { return value }
        return nil
    }

    subscript(key: String) -> JSONValue? {
        objectValue?[key]
    }

    /// เข้าถึงสมาชิกในอาร์เรย์แบบปลอดภัย (คืน nil ถ้าไม่ใช่อาร์เรย์หรือ index เกินขอบ)
    subscript(index: Int) -> JSONValue? {
        guard let values = arrayValue, index >= 0, index < values.count else { return nil }
        return values[index]
    }

    /// อ่านค่า String จาก key ที่กำหนด (คืนค่าเริ่มต้นถ้าไม่พบ)
    func string(forKey key: String, default defaultValue: String = "") -> String {
        self[key]?.stringValue ?? defaultValue
    }

    func int(forKey key: String, default defaultValue: Int = 0) -> Int {
        self[key]?.intValue ?? defaultValue
    }

    func bool(forKey key: String, default defaultValue: Bool = false) -> Bool {
        self[key]?.boolValue ?? defaultValue
    }

    // MARK: - แปลงเป็นข้อความ

    /// JSON แบบบรรทัดเดียว (ใช้ส่งเป็น arguments ของ tool)
    var compactJSONString: String {
        guard let data = try? JSONEncoder().encode(self),
              let text = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return text
    }

    /// JSON แบบจัดบรรทัด (ใช้แสดงผลใน UI)
    var prettyJSONString: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(self),
              let text = String(data: data, encoding: .utf8) else {
            return compactJSONString
        }
        return text
    }

    // MARK: - ตัวช่วยสร้างค่า

    /// สร้าง object จากคู่ key/value (ไม่มีการ throw แม้ key ซ้ำ — ตัวหลังทับตัวแรก)
    ///
    /// หมายเหตุ: ตั้งใจ "ไม่มี" ตัวช่วยชื่อ `array` เพราะจะซ้ำกับ `case array([JSONValue])`
    /// ใช้ `.array([...])` ได้ตรง ๆ อยู่แล้ว (คอมไพเลอร์จับได้ตอนรันทดสอบในแซนด์บล็อก)
    static func object(_ pairs: [(String, JSONValue)]) -> JSONValue {
        var dictionary: [String: JSONValue] = [:]
        for pair in pairs {
            dictionary[pair.0] = pair.1
        }
        return .object(dictionary)
    }

    // MARK: - Parsing

    /// แปลงข้อความ JSON เป็น JSONValue
    static func decode(fromJSONString text: String) -> JSONValue? {
        guard let data = text.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(JSONValue.self, from: data)
    }

    /// แปลงข้อความ JSON ที่ต้องเป็น object เท่านั้น (ใช้กับ arguments ของ tool call)
    static func decodeObject(fromJSONString text: String) -> [String: JSONValue]? {
        guard let value = decode(fromJSONString: text), let object = value.objectValue else { return nil }
        return object
    }
}
