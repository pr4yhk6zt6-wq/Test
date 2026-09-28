//
//  AppRouter.swift
//  iOS Agent Sandbox
//
//  ตัวกลางนำทางระหว่างแท็บ (เฟส 5)
//  ใช้เมื่อผู้ใช้กด "ให้ Agent แก้ไฟล์นี้" จากหน้าดูไฟล์ หรือแตะคำสั่งด่วนในหน้าแชท
//

import Foundation

/// แท็บของแอป
enum RootTab: Int, Hashable {
    case chat = 0
    case files = 1
    case log = 2
    case settings = 3
}

@MainActor
final class AppRouter: ObservableObject {

    static let shared = AppRouter()

    /// แท็บที่กำลังแสดงอยู่
    @Published var selectedTab: RootTab = .chat

    /// ข้อความที่รอให้หน้าแชทส่งให้ Agent ทันที (nil = ไม่มี)
    @Published var pendingPrompt: String?

    /// ไฟล์ที่รอให้แชทแนบให้ Agent (ใช้กับ "ให้ Agent แก้ไฟล์นี้")
    @Published var pendingAttachmentPath: String?

    /// ห้องที่รอให้หน้าแชทเปิด (ใช้เมื่อผู้ใช้แตะการแจ้งเตือน หรือกด "เปิดห้องนี้" ในหน้างานของฉัน)
    @Published var pendingRoomID: UUID?

    /// สลับไปแท็บแชทและส่งคำสั่งให้ Agent
    func sendToAgent(_ prompt: String, attachmentPath: String? = nil) {
        pendingPrompt = prompt
        pendingAttachmentPath = attachmentPath
        selectedTab = .chat
    }

    /// สลับไปแท็บแชทและเปิดห้องที่ระบุ
    func openRoom(_ roomID: UUID) {
        pendingRoomID = roomID
        selectedTab = .chat
    }

    /// เรียกโดยหน้าแชทเมื่อเปิดห้องตามคำขอแล้ว
    func consumePendingRoom() {
        pendingRoomID = nil
    }

    /// เรียกโดยหน้าแชทเมื่อรับคำสั่งไปใช้แล้ว
    func consumePendingPrompt() -> (prompt: String, attachmentPath: String?)? {
        guard let prompt = pendingPrompt else { return nil }
        let attachmentPath = pendingAttachmentPath
        pendingPrompt = nil
        pendingAttachmentPath = nil
        return (prompt, attachmentPath)
    }
}
