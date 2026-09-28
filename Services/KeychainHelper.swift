//
//  KeychainHelper.swift
//  iOS Agent Sandbox
//
//  เก็บข้อมูลลับ (API Key) ไว้ใน Keychain ของอุปกรณ์
//
//  หมายเหตุสำคัญสำหรับแอปที่รันนอก sandbox (TrollStore / palera1n):
//  ถ้าแอปถูกเซ็นโดยไม่มี entitlement `application-identifier` / `keychain-access-groups`
//  การเรียก SecItem* จะล้มเหลวด้วย errSecMissingEntitlement (-34018)
//  คลาสนี้จะตรวจจับกรณีนั้นแล้วสลับไปใช้ที่เก็บสำรอง (UserDefaults) อัตโนมัติ
//  พร้อมตั้งค่าธง `isUsingFallback` เพื่อให้หน้าตั้งค่าเตือนผู้ใช้
//

import Foundation
import Security

// MARK: - Error

enum KeychainError: LocalizedError {
    case unexpectedStatus(OSStatus)
    case dataConversionFailed
    case missingEntitlement(String)
    case emptyValue

    var errorDescription: String? {
        switch self {
        case .unexpectedStatus(let status):
            let message = SecCopyErrorMessageString(status, nil) as String? ?? "ไม่ทราบสาเหตุ"
            return "Keychain ตอบกลับผิดพลาด (OSStatus \(status)): \(message)"
        case .dataConversionFailed:
            return "แปลงข้อมูลสำหรับ Keychain ไม่สำเร็จ"
        case .missingEntitlement(let message):
            return "แอปไม่มีสิทธิ์ใช้ Keychain: \(message)"
        case .emptyValue:
            return "ไม่มีข้อมูลให้บันทึก"
        }
    }

    /// error ที่เกิดจากแอปไม่ได้เซ็นด้วย entitlements (ใช้ตัดสินใจว่าจะสลับไปที่เก็บสำรองไหม)
    var isEntitlementRelated: Bool {
        switch self {
        case .missingEntitlement:
            return true
        case .unexpectedStatus(let status):
            // -34018 = errSecMissingEntitlement, -25300 = errSecItemNotFound (ไม่นับ),
            // -25291 = errSecNotAvailable, -25303 = errSecInvalidKeychain
            return status == -34018 || status == -25291 || status == -25303
        case .dataConversionFailed, .emptyValue:
            return false
        }
    }
}

// MARK: - Helper

final class KeychainHelper {

    static let shared = KeychainHelper()

    enum Key: String {
        case openRouterAPIKey = "openrouter.api.key"
    }

    /// ขอบเขตของ Keychain item
    private let service: String
    private let accessGroup: String?

    /// true = Keychain ใช้ไม่ได้ จึงเก็บใน UserDefaults แทน (ไม่เข้ารหัส) — UI ต้องเตือนผู้ใช้
    private(set) var isUsingFallback: Bool = false
    /// ข้อความ error ล่าสุดจาก Keychain (ไว้แสดงในหน้าตั้งค่า)
    private(set) var lastErrorMessage: String?

    private let fallbackPrefix = "keychain.fallback."

    init(service: String = "com.example.iosagentsandbox", accessGroup: String? = nil) {
        self.service = service
        self.accessGroup = accessGroup
    }

    // MARK: - Public API

    /// บันทึกค่า (ถ้าค่าเป็น "" จะลบรายการทิ้ง)
    func set(_ value: String, for key: Key) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            try remove(key)
            return
        }
        guard let data = trimmed.data(using: .utf8) else {
            throw KeychainError.dataConversionFailed
        }
        do {
            try writeToKeychain(data: data, key: key)
            isUsingFallback = false
            lastErrorMessage = nil
        } catch let error as KeychainError where error.isEntitlementRelated {
            // Keychain ใช้ไม่ได้ -> เก็บสำรองเพื่อให้แอปยังใช้งานได้ พร้อมเตือนใน UI
            UserDefaults.standard.set(trimmed, forKey: fallbackPrefix + key.rawValue)
            isUsingFallback = true
            lastErrorMessage = error.localizedDescription
        }
    }

    /// อ่านค่า (nil = ยังไม่มีข้อมูล)
    func string(for key: Key) throws -> String? {
        do {
            // 1) ลองอ่านจากสำรองก่อน (กรณีที่เคยสลับโหมดไปแล้ว)
            if let fallback = UserDefaults.standard.string(forKey: fallbackPrefix + key.rawValue),
               !fallback.isEmpty {
                isUsingFallback = true
                return fallback
            }
            // 2) อ่านจาก Keychain
            let data = try readFromKeychain(key: key)
            if let data = data {
                isUsingFallback = false
                lastErrorMessage = nil
                return String(data: data, encoding: .utf8)
            }
            return nil
        } catch let error as KeychainError where error.isEntitlementRelated {
            isUsingFallback = true
            lastErrorMessage = error.localizedDescription
            let fallback = UserDefaults.standard.string(forKey: fallbackPrefix + key.rawValue)
            return (fallback?.isEmpty == false) ? fallback : nil
        }
    }

    /// ลบค่าทั้งจาก Keychain และที่เก็บสำรอง
    func remove(_ key: Key) throws {
        UserDefaults.standard.removeObject(forKey: fallbackPrefix + key.rawValue)
        do {
            try deleteFromKeychain(key: key)
            isUsingFallback = false
        } catch let error as KeychainError where error.isEntitlementRelated {
            isUsingFallback = true
            lastErrorMessage = error.localizedDescription
        }
    }

    /// ตรวจว่ามีค่าอยู่หรือไม่ (ไม่โยน error)
    func hasValue(for key: Key) -> Bool {
        guard let value = try? string(for: key) else { return false }
        return !value.isEmpty
    }

    // MARK: - Keychain primitives

    private func baseQuery(key: Key) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue
        ]
        if let accessGroup = accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }

    private func writeToKeychain(data: Data, key: Key) throws {
        let query = baseQuery(key: key)
        let attributes: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError.unexpectedStatus(addStatus)
            }
        default:
            throw KeychainError.unexpectedStatus(updateStatus)
        }
    }

    private func readFromKeychain(key: Key) throws -> Data? {
        var query = baseQuery(key: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data else { return nil }
            return data
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    private func deleteFromKeychain(key: Key) throws {
        let status = SecItemDelete(baseQuery(key: key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
}
