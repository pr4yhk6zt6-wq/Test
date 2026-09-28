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

    @AppStorage(SettingsKeys.appearance) private var appearanceRawValue: String = AppAppearance.system.rawValue

    private var preferredScheme: ColorScheme? {
        AppAppearance(rawValue: appearanceRawValue)?.colorScheme
    }

    var body: some View {
        TabView {
            NavigationView {
                ChatView()
            }
            .navigationViewStyle(.stack)
            .tabItem {
                Label("แชท", systemImage: "bubble.left.and.bubble.right")
            }

            NavigationView {
                FileBrowserView(path: FileBrowserView.defaultStartPath)
            }
            .navigationViewStyle(.stack)
            .tabItem {
                Label("ไฟล์", systemImage: "folder")
            }

            NavigationView {
                AgentLogView()
            }
            .navigationViewStyle(.stack)
            .tabItem {
                Label("บันทึก", systemImage: "list.bullet.rectangle")
            }

            NavigationView {
                SettingsView()
            }
            .navigationViewStyle(.stack)
            .tabItem {
                Label("ตั้งค่า", systemImage: "gearshape")
            }
        }
        .preferredColorScheme(preferredScheme)
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
