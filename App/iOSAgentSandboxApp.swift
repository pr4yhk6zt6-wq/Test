//
//  iOSAgentSandboxApp.swift
//  iOS Agent Sandbox
//
//  จุดเริ่มต้นของแอป (iOS 15.0 deployment target)
//  ห้ามใช้ API ของ iOS 16+ (NavigationStack / NavigationSplitView ฯลฯ)
//

import SwiftUI

@main
struct IOSAgentSandboxApp: App {

    @StateObject private var settings = AppSettings.shared
    @StateObject private var usage = TokenUsageTracker.shared

    init() {
        // หมายเหตุสำหรับการรันบนเครื่องจริง (TrollStore/palera1n):
        // ไม่ตั้งค่าใด ๆ ที่ต้องใช้ API ของ iOS 16+
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(settings)
                .environmentObject(usage)
                .onAppear(perform: handleLaunchChecks)
        }
    }

    /// ตรวจสิทธิ์การเข้าถึงระบบตั้งแต่เปิดแอป (ผลจริงแสดงในแชทและหน้าตั้งค่า)
    private func handleLaunchChecks() {
        let report = SystemAccessChecker.check()
        if report.needsJailbreakNotice {
            print("[iOSAgentSandbox] แอปถูก sandbox: อ่าน /var/mobile ไม่ได้ → ต้องติดตั้งผ่าน TrollStore (entitlements no-sandbox) หรือเจลเบรคด้วย palera1n")
        } else {
            print("[iOSAgentSandbox] เข้าถึง /var/mobile ได้ (สิทธิ์: \(report.privilegeText))")
        }
    }
}
