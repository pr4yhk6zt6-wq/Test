//
//  RootTabView.swift
//  iOS Agent Sandbox
//
//  แท็บหลักของแอป (ทั้ง 4 แท็บทำงานจริงแล้วในเฟส 4)
//  แชท (AgentEngine + อนุมัติทีละครั้ง) • ไฟล์ (เริ่มที่ /var/mobile) • บันทึก tool • ตั้งค่า
//

import SwiftUI

struct RootTabView: View {

    @EnvironmentObject private var settings: AppSettings
    @ObservedObject private var router = AppRouter.shared

    @AppStorage(SettingsKeys.appearance) private var appearanceRawValue: String = AppAppearance.system.rawValue
    @AppStorage(SettingsKeys.hasCompletedOnboarding) private var hasCompletedOnboarding: Bool = false
    @State private var showOnboarding: Bool = false

    private var preferredScheme: ColorScheme? {
        AppAppearance(rawValue: appearanceRawValue)?.colorScheme
    }

    var body: some View {
        TabView(selection: $router.selectedTab) {
            NavigationView {
                Group {
                    if settings.useNewChatUI {
                        ChatScreenNew()
                    } else {
                        ChatView()
                    }
                }
            }
            .navigationViewStyle(.stack)
            .tabItem {
                Label("แชท", systemImage: "bubble.left.and.bubble.right")
            }
            .tag(RootTab.chat)

            NavigationView {
                FileBrowserView(path: FileBrowserView.defaultStartPath)
            }
            .navigationViewStyle(.stack)
            .tabItem {
                Label("ไฟล์", systemImage: "folder")
            }
            .tag(RootTab.files)

            NavigationView {
                MyTasksScreen()
            }
            .navigationViewStyle(.stack)
            .tabItem {
                Label("งานของฉัน", systemImage: "square.stack.3d.up")
            }
            .tag(RootTab.log)

            NavigationView {
                SettingsView()
            }
            .navigationViewStyle(.stack)
            .tabItem {
                Label("ตั้งค่า", systemImage: "gearshape")
            }
            .tag(RootTab.settings)
        }
        .preferredColorScheme(preferredScheme)
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView(onFinish: {
                hasCompletedOnboarding = true
                showOnboarding = false
            })
            .environmentObject(settings)
        }
        .onAppear {
            // เฟส 5: แนะนำการใช้งาน 3 หน้าเมื่อเปิดแอปครั้งแรก
            if !hasCompletedOnboarding {
                showOnboarding = true
            }
        }
    }
}

/// ธีมของแอป (ผูกกับ SettingsKeys.appearance)
enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "ตามระบบ"
        case .light: return "สว่าง"
        case .dark: return "มืด"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}
