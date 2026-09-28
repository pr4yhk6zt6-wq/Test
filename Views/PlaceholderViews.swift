//
//  PlaceholderViews.swift
//  iOS Agent Sandbox
//
//  หน้าจอชั่วคราวสำหรับฟีเจอร์ที่จะทำในเฟสถัดไป
//  (ตั้งใจให้เห็นชัดว่าเป็นงานของเฟสไหน ไม่ใช่ TODO ที่ค้างในโค้ดทำงานจริง)
//

import SwiftUI

/// โครงของหน้าจอที่ยังไม่เปิดใช้งาน
private struct PhasePendingView: View {

    let title: String
    let systemImage: String
    let phase: String
    let detail: String
    let bullets: [String]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: systemImage)
                        .font(.title2)
                        .foregroundColor(.accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.headline)
                        Text(phase)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Text(detail)
                    .font(.footnote)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(bullets, id: \.self) { item in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "circle.dashed")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .padding(.top, 3)
                            Text(item)
                                .font(.footnote)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(UIColor.secondarySystemBackground))
                )

                Text("ตรวจสอบสิทธิ์ปัจจุบันได้ในแท็บ \"ตั้งค่า\" → สิทธิ์การเข้าถึงไฟล์")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(14)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// ไฟล์: เฟส 3 (FileSystemService) + เฟส 4 (FileBrowserView)
struct FileBrowserPlaceholderView: View {
    var body: some View {
        PhasePendingView(
            title: "ไฟล์",
            systemImage: "folder",
            phase: "จะเปิดใช้งานในเฟส 3–4",
            detail: "ตัวเรียกดูไฟล์ทั้งเครื่องจะเริ่มที่ /var/mobile และใช้ FileSystemService ที่ทำงานได้จริงหลังเซ็นแอปด้วย entitlements แบบ no-sandbox",
            bullets: [
                "เฟส 3: FileSystemService + ShellService (posix_spawn) + ไฟล์ .entitlements",
                "เฟส 4: FileBrowserView แตะเข้าโฟลเดอร์ แตะไฟล์เพื่อดูเนื้อหา",
                "เฟส 5: นำเข้าไฟล์ เปลี่ยนชื่อ ย้าย คัดลอก แชร์ ส่งให้ Agent และแก้ไขไฟล์ข้อความ"
            ]
        )
    }
}

/// บันทึกการทำงานของ Agent: เฟส 2 (AgentLogStore) + เฟส 4 (AgentLogView)
struct AgentLogPlaceholderView: View {
    var body: some View {
        PhasePendingView(
            title: "บันทึก Agent",
            systemImage: "list.bullet.rectangle",
            phase: "จะเปิดใช้งานในเฟส 2–4",
            detail: "ทุก tool call (ชื่อ, arguments, ผลลัพธ์, เวลา) จะถูกบันทึกไว้ที่นี่ พร้อมปุ่มคัดลอกและล้าง",
            bullets: [
                "เฟส 2: AgentEngine + tools (read_file, write_file, list_directory, execute_shell, search_files, http_request, download_file, web_search, fetch_webpage)",
                "เฟส 2: โหมดขออนุมัติก่อนรันคำสั่งเสี่ยง และตัวนับโทเคน/ลิมิต 20 รอบต่อคำสั่ง",
                "เฟส 4: หน้าจอบันทึกพร้อมปุ่มคัดลอก/ล้าง และการเก็บประวัติแชทเป็น JSON"
            ]
        )
    }
}
