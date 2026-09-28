//
//  AppSettings.swift
//  iOS Agent Sandbox
//
//  ค่าตั้งต้นของแอป
//  - API Key เก็บใน Keychain (ดู KeychainHelper)
//  - ค่าอื่น ๆ เก็บใน UserDefaults
//
//  หมายเหตุ: คลาสนี้ถูกแก้ไขจาก UI (main thread) เท่านั้น
//  ส่วน service ที่ทำงานเบื้องหลังอ่านค่าจาก UserDefaults โดยตรงผ่าน SettingsKeys
//

import Foundation

/// คีย์ที่ใช้ร่วมกันระหว่าง UI และ service (service อ่านจาก UserDefaults ตรง ๆ
/// เพื่อไม่ต้องพึ่ง main thread)
enum SettingsKeys {
    static let modelID = "settings.modelID"
    static let allowInternet = "settings.allowInternet"
    static let wifiOnly = "settings.wifiOnly"
    static let requireApproval = "settings.requireApproval"
    static let maxDownloadMegabytes = "settings.maxDownloadMegabytes"
    static let chatFontScale = "settings.chatFontScale"
    static let appearance = "settings.appearance"
    static let hasCompletedOnboarding = "settings.hasCompletedOnboarding"
}

final class AppSettings: ObservableObject {

    static let shared = AppSettings()

    // MARK: - สถานะของ API Key

    enum APIKeyState {
        case missing
        case inKeychain
        case inFallback
    }

    // MARK: - ค่าที่ผูกกับ UI

    /// Model ID รูปแบบ provider/model เช่น "deepseek/deepseek-chat-v3-0324:free"
    @Published var modelID: String {
        didSet {
            defaults.set(modelID, forKey: SettingsKeys.modelID)
        }
    }

    @Published private(set) var apiKeyState: APIKeyState = .missing

    /// ข้อความ error ล่าสุดจาก Keychain (ถ้ามี)
    private(set) var storageWarning: String?

    private let defaults: UserDefaults
    private let keychain: KeychainHelper

    init(defaults: UserDefaults = .standard, keychain: KeychainHelper = .shared) {
        self.defaults = defaults
        self.keychain = keychain
        self.modelID = defaults.string(forKey: SettingsKeys.modelID) ?? ""
        refreshAPIKeyState()
    }

    // MARK: - API Key

    @discardableResult
    func refreshAPIKeyState() -> APIKeyState {
        if let stored = try? keychain.string(for: .openRouterAPIKey), !stored.isEmpty {
            if keychain.isUsingFallback {
                apiKeyState = .inFallback
            } else {
                apiKeyState = .inKeychain
            }
        } else {
            apiKeyState = .missing
        }
        storageWarning = keychain.lastErrorMessage
        return apiKeyState
    }

    func saveAPIKey(_ value: String) throws {
        try keychain.set(value, for: .openRouterAPIKey)
        refreshAPIKeyState()
    }

    func deleteAPIKey() throws {
        try keychain.remove(.openRouterAPIKey)
        refreshAPIKeyState()
    }

    var apiKeyStateText: String {
        switch apiKeyState {
        case .missing:
            return "ยังไม่มี API Key"
        case .inKeychain:
            return "เก็บใน Keychain ของเครื่องแล้ว"
        case .inFallback:
            return "เก็บแบบสำรองใน UserDefaults (ไม่เข้ารหัส)"
        }
    }

    var hasAPIKey: Bool {
        apiKeyState != .missing
    }

    /// โมเดลปัจจุบัน (อ่านจาก UserDefaults โดยตรง — ใช้ได้จากทุกเธรด)
    static var currentModelID: String {
        UserDefaults.standard.string(forKey: SettingsKeys.modelID) ?? ""
    }
}
