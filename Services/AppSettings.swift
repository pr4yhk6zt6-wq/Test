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
    /// ขอบเขต context ของโมเดล (ใช้ตัดบทสนทนาเมื่อใกล้เต็ม)
    static let contextLengthTokens = "settings.contextLengthTokens"
    /// โฟลเดอร์ทำงานของ Agent
    static let workspacePath = "settings.workspacePath"
}

/// ค่าเริ่มต้นของตัวเลือกที่เพิ่มในเฟส 2
enum AgentDefaults {
    static let requireApproval = true
    static let allowInternet = true
    static let wifiOnly = false
    static let maxDownloadMegabytes = 200
    static let contextLengthTokens = 32_768
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

    // MARK: - ตัวเลือกของ Agent (เฟส 2)

    /// ขออนุมัติก่อนรัน execute_shell และก่อนเขียนทับไฟล์สำคัญ (ค่าเริ่มต้น: เปิด)
    @Published var requireApproval: Bool {
        didSet { defaults.set(requireApproval, forKey: SettingsKeys.requireApproval) }
    }

    /// อนุญาตให้ Agent ใช้อินเทอร์เน็ต
    @Published var allowInternet: Bool {
        didSet { defaults.set(allowInternet, forKey: SettingsKeys.allowInternet) }
    }

    /// ใช้เฉพาะเมื่อเชื่อมต่อ Wi-Fi (กันการกินดาต้ามือถือ)
    @Published var wifiOnly: Bool {
        didSet { defaults.set(wifiOnly, forKey: SettingsKeys.wifiOnly) }
    }

    /// เพดานขนาดไฟล์ดาวน์โหลด (MB)
    @Published var maxDownloadMegabytes: Int {
        didSet { defaults.set(maxDownloadMegabytes, forKey: SettingsKeys.maxDownloadMegabytes) }
    }

    /// ขอบเขต context ของโมเดล (token) — ใช้ตัดบทสนทนาเมื่อใช้เกิน 80%
    @Published var contextLengthTokens: Int {
        didSet { defaults.set(contextLengthTokens, forKey: SettingsKeys.contextLengthTokens) }
    }

    /// โฟลเดอร์ทำงานเริ่มต้นของ Agent
    @Published var workspacePath: String {
        didSet { defaults.set(workspacePath, forKey: SettingsKeys.workspacePath) }
    }

    /// เพดานดาวน์โหลดเป็นไบต์ (อ่านจากค่าที่ตั้งไว้)
    var maxDownloadBytes: Int64 {
        NetworkPolicy.maxDownloadBytes(megabytes: maxDownloadMegabytes)
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

        // ค่าที่เพิ่มในเฟส 2 — ถ้ายังไม่เคยตั้ง ใช้ค่าเริ่มต้นที่ปลอดภัย
        self.requireApproval = defaults.object(forKey: SettingsKeys.requireApproval) as? Bool
            ?? AgentDefaults.requireApproval
        self.allowInternet = defaults.object(forKey: SettingsKeys.allowInternet) as? Bool
            ?? AgentDefaults.allowInternet
        self.wifiOnly = defaults.object(forKey: SettingsKeys.wifiOnly) as? Bool
            ?? AgentDefaults.wifiOnly
        let storedMegabytes = defaults.object(forKey: SettingsKeys.maxDownloadMegabytes) as? Int
            ?? AgentDefaults.maxDownloadMegabytes
        self.maxDownloadMegabytes = min(max(storedMegabytes, 10), 2_000)
        let storedContext = defaults.object(forKey: SettingsKeys.contextLengthTokens) as? Int
            ?? AgentDefaults.contextLengthTokens
        self.contextLengthTokens = min(max(storedContext, 4_096), 1_000_000)
        self.workspacePath = defaults.string(forKey: SettingsKeys.workspacePath) ?? PathGuard.defaultWorkspace

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
