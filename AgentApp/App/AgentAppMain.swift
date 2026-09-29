//
//  AgentAppMain.swift
//  AgentApp — แอปหลักที่สร้างจากแบบ (ดีไซน์ v2)
//
//  แนวคิด: หน้าจอทุกจุดเขียนขึ้นใหม่จากแบบโดยตรง (โทเคน + คอมโพเนนต์ในโฟลเดอร์ Design)
//  ส่วน "สมอง" ของแอป (การคุยกับ OpenRouter, เครื่องมือ, ประวัติ, การอนุมัติ) ใช้ตัวที่ผ่าน
//  การทดสอบแล้วใน Services/ และ Models/ — ไม่เขียนใหม่เพื่อไม่ให้ความปลอดภัยถดถอย
//
//  เป้าหมาย: iPhone 7 / iOS 15.0 (ไม่ใช้ API ของ iOS 16+)
//

import SwiftUI
import UIKit

@main
struct AgentAppMain: App {

    /// ตัวแทนแอป (ใช้ตั้งค่า delegate ของการแจ้งเตือนเท่านั้น — ไม่ขอสิทธิ์ใด ๆ ที่นี่)
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var router = AppRouter.shared

    @AppStorage(SettingsKeys.appearance) private var appearanceRaw: String = AppAppearance.system.rawValue
    @AppStorage(SettingsKeys.hasCompletedOnboarding) private var hasCompletedOnboarding: Bool = false

    @State private var showOnboarding: Bool = false

    var body: some Scene {
        WindowGroup {
            AGShell()
                .environmentObject(settings)
                .preferredColorScheme(AppAppearance(rawValue: appearanceRaw)?.colorScheme)
                .onAppear {
                    AgentNotifier.shared.refreshAuthorizationStatus()
                    reportSystemAccess()
#if DEBUG
                    if AGPreview.isActive {
                        switch AGPreview.screen {
                        case "tasks", "tasks-history":
                            AGPreview.seedTasks()
                            PendingMessageQueue.shared.enqueue(text: "พิมพ์ไว้ระหว่าง Agent ทำงาน — ช่วยเพิ่มกราฟเปรียบเทียบให้ด้วย", roomID: nil)
                            router.selectedTab = .log
                        case "files":
                            AGPreview.prepareWorkspace()
                            router.selectedTab = .files
                        case "settings":
                            router.selectedTab = .settings
                        default:
                            break
                        }
                        return
                    }
#endif
                    if !hasCompletedOnboarding { showOnboarding = true }
                }
                .fullScreenCover(isPresented: $showOnboarding) {
                    AGOnboardingScreen {
                        hasCompletedOnboarding = true
                        showOnboarding = false
                    }
                    .environmentObject(settings)
                }
        }
    }
}

extension AgentAppMain {

    /// ตรวจสิทธิ์การเข้าถึงระบบตั้งแต่เปิดแอป (ผลจริงใช้แสดงในหน้าแชทและหน้าตั้งค่า)
    private func reportSystemAccess() {
        let report = SystemAccessChecker.check()
        if report.needsJailbreakNotice {
            print("[AgentApp] แอปถูก sandbox: อ่าน /var/mobile ไม่ได้ → ต้องติดตั้งผ่าน TrollStore (entitlements no-sandbox) หรือเจลเบรคด้วย palera1n")
        } else {
            print("[AgentApp] เข้าถึง /var/mobile ได้ (สิทธิ์: \(report.privilegeText))")
        }
    }
}

/// โครงหลักของแอป: เนื้อหาของแท็บ + แถบแท็บล่างที่วาดเอง (ตามแบบ)
struct AGShell: View {

    @ObservedObject private var router: AppRouter = .shared
    @AppStorage(SettingsKeys.chatFontScale) private var fontScale: Double = 1

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch router.selectedTab {
                case .chat:
                    NavigationView { AGChatScreen() }
                        .navigationViewStyle(.stack)
                case .files:
                    NavigationView { AGFilesScreen() }
                        .navigationViewStyle(.stack)
                case .log:
                    NavigationView { AGTasksScreen() }
                        .navigationViewStyle(.stack)
                case .settings:
                    NavigationView { AGSettingsScreen() }
                        .navigationViewStyle(.stack)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            AGTabBar(selection: Binding(
                get: { router.selectedTab.rawValue },
                set: { router.selectedTab = RootTab(rawValue: $0) ?? .chat }
            ), scale: fontScale)
        }
        .background(AGColor.bg)
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }
}
