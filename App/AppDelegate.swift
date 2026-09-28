//
//  AppDelegate.swift
//  iOS Agent Sandbox — ดีไซน์ v2 (เฟส 5 ส่วนที่ 6)
//
//  ตัวแทนแอปขนาดเล็ก ทำหน้าที่ผูก "การแจ้งเตือน" ของระบบเข้ากับ AgentNotifier
//  (SwiftUI ไม่มีที่ให้ตั้ง UNUserNotificationCenter.delegate โดยตรงบน iOS 15)
//
//  หมายเหตุ: ไม่มีการขอสิทธิ์ใด ๆ ที่นี่ — สิทธิ์การแจ้งเตือนจะขอเฉพาะเมื่อผู้ใช้
//  เปิดสวิตช์ในหน้าตั้งค่าเท่านั้น (ตามกติกาความปลอดภัยของโปรเจกต์)
//

import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // ตั้ง delegate ของการแจ้งเตือน และอ่านสถานะปัจจุบัน (ไม่ขอสิทธิ์)
        _ = AgentNotifier.shared
        AgentNotifier.shared.refreshAuthorizationStatus()
        return true
    }
}
