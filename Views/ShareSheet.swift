//
//  ShareSheet.swift
//  iOS Agent Sandbox
//
//  Wrapper ของ UIActivityViewController สำหรับใช้ใน SwiftUI (iOS 15)
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
        // ไม่ต้องอัปเดต
    }
}

/// ตัวห่อข้อความสำหรับ `.sheet(item:)`
struct ShareableText: Identifiable {
    let id = UUID()
    let text: String
}
