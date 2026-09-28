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
    /// true = เพิ่งพบคีย์เก่าค้างในที่เก็บสำรองแล้วล้างทิ้ง (สาเหตุของบั๊ก 401 ที่ผู้ใช้เจอ)
    private(set) var purgedStaleFallback: Bool = false

    private let fallbackPrefix = "keychain.fallback."

    init(service: String = "com.example.iosagentsandbox", accessGroup: String? = nil) {
        self.service = service
        self.accessGroup = accessGroup
    }

    // MARK: - Public API

    /// บันทึกค่า (ถ้าค่าเป็น "" จะลบรายการทิ้ง)
    func set(_ value: String, for key: Key) throws {
        // ทำความสะอาดก่อนเก็บเสมอ: ตัดช่องว่าง/ขึ้นบรรทัดใหม่/อักขระล่องหนที่ติดมากับการคัดลอก
        // (คีย์ที่มี \n ต่อท้ายทำให้เซิร์ฟเวอร์ตอบ 401 "User not found.")
        let cleaned = APIKeySanitizer.sanitize(value).cleaned
        if cleaned.isEmpty {
            try remove(key)
            return
        }
        guard let data = cleaned.data(using: .utf8) else {
            throw KeychainError.dataConversionFailed
        }
        do {
            try writeToKeychain(data: data, key: key)
            // สำคัญ: ล้างค่าที่ค้างอยู่ในที่เก็บสำรอง ไม่งั้นคีย์เก่าจะถูกอ่านทับคีย์ใหม่เสมอ
            // (บั๊กที่ผู้ใช้เจอ: สร้างคีย์ใหม่แล้วยังได้ 401 "User not found.")
            let hadFallback = UserDefaults.standard.string(forKey: fallbackPrefix + key.rawValue) != nil
            UserDefaults.standard.removeObject(forKey: fallbackPrefix + key.rawValue)
            purgedStaleFallback = hadFallback
            isUsingFallback = false
            lastErrorMessage = nil
        } catch let error as KeychainError where error.isEntitlementRelated {
            // Keychain ใช้ไม่ได้ -> เก็บสำรองเพื่อให้แอปยังใช้งานได้ พร้อมเตือนใน UI
            UserDefaults.standard.set(cleaned, forKey: fallbackPrefix + key.rawValue)
            purgedStaleFallback = false
            isUsingFallback = true
            lastErrorMessage = error.localizedDescription
        }
    }

    /// อ่านค่า (nil = ยังไม่มีข้อมูล)
    ///
    /// ลำดับความสำคัญ: **Keychain ก่อนเสมอ** แล้วค่อยใช้ที่เก็บสำรองเฉพาะเมื่อ Keychain ใช้ไม่ได้
    /// (โค้ดเดิมอ่านสำรองก่อน ทำให้คีย์เก่าที่ค้างอยู่บดบังคีย์ใหม่ที่เพิ่งบันทึก → 401 ตลอดไป)
    func string(for key: Key) throws -> String? {
        var keychainValue: String?
        var keychainAvailable = true
        do {
            if let data = try readFromKeychain(key: key) {
                keychainValue = String(data: data, encoding: .utf8)
            }
        } catch let error as KeychainError where error.isEntitlementRelated {
            keychainAvailable = false
            lastErrorMessage = error.localizedDescription
        }

        let fallbackValue = UserDefaults.standard.string(forKey: fallbackPrefix + key.rawValue)
        let resolution = APIKeyStoragePolicy.resolve(keychainValue: keychainValue, fallbackValue: fallbackValue)

        if resolution.shouldPurgeFallback {
            UserDefaults.standard.removeObject(forKey: fallbackPrefix + key.rawValue)
            purgedStaleFallback = true
        } else if !resolution.isUsingFallback {
            purgedStaleFallback = false
        }

        isUsingFallback = resolution.isUsingFallback || !keychainAvailable
        if keychainAvailable && !resolution.isUsingFallback {
            lastErrorMessage = nil
        }
        return resolution.value
    }

    /// ลบค่าทั้งจาก Keychain และที่เก็บสำรอง
    func remove(_ key: Key) throws {
        UserDefaults.standard.removeObject(forKey: fallbackPrefix + key.rawValue)
        purgedStaleFallback = false
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

    /// ข้อมูลสรุปของคีย์ที่ใช้อยู่ — ไม่เปิดเผยคีย์เต็ม (ใช้แสดงในหน้าตั้งค่าเพื่อเทียบกับหน้าเว็บ)
    func diagnostics(for key: Key) -> KeyDiagnostics {
        let value = (try? string(for: key)) ?? nil
        return KeyDiagnostics(fingerprint: value.map { APIKeySanitizer.fingerprint($0) } ?? "(ยังไม่มีคีย์)",
                              hasValue: value?.isEmpty == false,
                              isOpenRouterFormat: value.map { APIKeySanitizer.looksLikeOpenRouterKey($0) } ?? false,
                              isUsingFallback: isUsingFallback,
                              purgedStaleFallback: purgedStaleFallback,
                              storageWarning: lastErrorMessage)
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

// MARK: - ข้อมูลสรุปคีย์ที่ใช้อยู่

struct KeyDiagnostics: Equatable {
    /// ข้อความระบุตัวคีย์ (เช่น sk-or-v1-ab…wxyz • 73 ตัวอักษร)
    let fingerprint: String
    let hasValue: Bool
    /// true = ขึ้นต้นด้วย sk-or- (รูปแบบคีย์ของ OpenRouter)
    let isOpenRouterFormat: Bool
    /// true = ค่ามาจากที่เก็บสำรองใน UserDefaults เพราะ Keychain ใช้ไม่ได้
    let isUsingFallback: Bool
    /// true = เพิ่งล้างคีย์เก่าที่ค้างในที่เก็บสำรองทิ้ง
    let purgedStaleFallback: Bool
    let storageWarning: String?

    var storageText: String {
        if isUsingFallback {
            return "ที่เก็บสำรอง (UserDefaults)"
        }
        return "Keychain ของเครื่อง"
    }
}
