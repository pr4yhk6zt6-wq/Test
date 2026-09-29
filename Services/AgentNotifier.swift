//
//  AgentNotifier.swift
//  iOS Agent Sandbox — ดีไซน์ v2 (เฟส 5 ส่วนที่ 6)
//
//  การแจ้งเตือนในเครื่อง (local notifications) ตามข้อจำกัดจริงของ iOS 15 / iPhone 7
//  - เปิดใช้เฉพาะเมื่อ "ผู้ใช้เปิดสวิตช์เอง" ในหน้าตั้งค่า จึงจะขออนุญาตจาก iOS
//  - ไม่มีปุ่มอนุมัติบนแจ้งเตือน (ต้องเปิดแอปเพื่อดูบริบทให้ครบก่อนตัดสินใจ)
//  - เนื้อหาแจ้งเตือนไม่ใส่ข้อมูลอ่อนไหว และไม่บอกเส้นทางไฟล์แบบละเอียด
//  - แตะแจ้งเตือนแล้วเปิดเข้าห้องที่ถูกต้องทันที
//

import Foundation
import Combine
import UserNotifications

final class AgentNotifier: NSObject, ObservableObject, UNUserNotificationCenterDelegate {

    static let shared = AgentNotifier()

    enum Kind: String {
        /// งานจบแล้ว (มีคำตอบให้อ่าน)
        case finished
        /// รอคำตอบจากผู้ใช้
        case needsAnswer
        /// ขั้นตอนล้มเหลว
        case failed
        /// เริ่มทำงานตามที่ผู้ใช้สั่งไว้ (ใช้เมื่อมีการตั้งเวลาในอนาคต)
        case started

        var title: String {
            switch self {
            case .finished: return "งานเสร็จแล้ว"
            case .needsAnswer: return "Agent รอคำตอบจากคุณ"
            case .failed: return "มีขั้นตอนที่ไม่สำเร็จ"
            case .started: return "Agent เริ่มทำงานแล้ว"
            }
        }

        func body(detail: String?) -> String {
            guard let detail = detail, !detail.isEmpty else {
                switch self {
                case .finished: return "เปิดแอปเพื่อดูผลลัพธ์และไทม์ไลน์ทั้งหมด"
                case .needsAnswer: return "มีเรื่องที่ต้องให้คุณตัดสินใจก่อนทำงานต่อ"
                case .failed: return "เปิดแอปเพื่อดูสาเหตุและลองใหม่"
                case .started: return "เปิดแอปเพื่อติดตามความคืบหน้า"
                }
            }
            return detail
        }
    }

    @Published private(set) var isEnabled: Bool
    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    private let center = UNUserNotificationCenter.current()
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.isEnabled = defaults.bool(forKey: SettingsKeys.agentNotifications)
        super.init()
        center.delegate = self
        refreshAuthorizationStatus()
    }

    // MARK: - สถานะ

    /// ข้อความอธิบายสถานะปัจจุบัน (ใช้ในหน้าตั้งค่าและหน้างานของฉัน)
    var statusExplanation: String {
        if !isEnabled {
            return "การแจ้งเตือนยังปิดอยู่ — เปิดได้ที่ ตั้งค่า → การแจ้งเตือน"
        }
        switch authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return "เปิดอยู่: จะแจ้งเมื่องานเสร็จ ต้องรอคำตอบ หรือมีขั้นที่ล้มเหลว"
        case .denied:
            return "คุณปิดการแจ้งเตือนของแอปนี้ใน iOS — เปิดได้ที่ ตั้งค่าเครื่อง → การแจ้งเตือน → iOS Agent Sandbox"
        case .notDetermined:
            return "เปิดไว้แล้ว แต่ยังรอการยืนยันจาก iOS (จะถามเมื่อบันทึกครั้งแรก)"
        @unknown default:
            return "ไม่ทราบสถานะการแจ้งเตือน"
        }
    }

    var canDeliver: Bool {
        guard isEnabled else { return false }
        switch authorizationStatus {
        case .authorized, .provisional: return true
        default: return false
        }
    }

    func refreshAuthorizationStatus() {
        center.getNotificationSettings { [weak self] settings in
            DispatchQueue.main.async {
                self?.authorizationStatus = settings.authorizationStatus
            }
        }
    }

    /// เรียกจากหน้าตั้งค่าเท่านั้น (ผู้ใช้กดเปิดเอง) — ขออนุญาตจาก iOS เฉพาะตอนนั้น
    func setEnabled(_ enabled: Bool, completion: ((Bool) -> Void)? = nil) {
        defaults.set(enabled, forKey: SettingsKeys.agentNotifications)
        DispatchQueue.main.async { self.isEnabled = enabled }

        guard enabled else {
            completion?(true)
            return
        }
        center.requestAuthorization(options: [.alert, .sound]) { [weak self] granted, _ in
            DispatchQueue.main.async {
                self?.refreshAuthorizationStatus()
                completion?(granted)
            }
        }
    }

    // MARK: - ส่งแจ้งเตือน

    func notify(kind: Kind, roomID: UUID?, detail: String?) {
        guard isEnabled else { return }

        let content = UNMutableNotificationContent()
        content.title = kind.title
        content.body = kind.body(detail: detail)
        content.sound = .default
        var userInfo: [String: Any] = ["kind": kind.rawValue]
        if let roomID = roomID {
            userInfo["roomID"] = roomID.uuidString
        }
        content.userInfo = userInfo

        let request = UNNotificationRequest(identifier: UUID().uuidString,
                                            content: content,
                                            trigger: nil)
        center.add(request, withCompletionHandler: nil)
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// ตอนแอปเปิดอยู่: ไม่ต้องเด้งซ้ำ เพราะในแอปมีแบนเนอร์ของตัวเองอยู่แล้ว
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([])
    }

    /// แตะแจ้งเตือน: เปิดแอปเข้าห้องที่ถูกต้อง
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        let roomID = (info["roomID"] as? String).flatMap { UUID(uuidString: $0) }
        Task { @MainActor in
            if let roomID = roomID {
                AppRouter.shared.openRoom(roomID)
            } else {
                AppRouter.shared.selectedTab = .chat
            }
        }
        completionHandler()
    }
}
