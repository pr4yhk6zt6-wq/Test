//
//  QuickPromptsView.swift
//  iOS Agent Sandbox
//
//  คำสั่งเริ่มต้นด่วน (เฟส 5) — แสดงเมื่อยังไม่มีข้อความในห้องนี้
//  แตะแล้วข้อความจะถูกใส่ในช่องพิมพ์ (ผู้ใช้ตรวจก่อนส่งได้)
//

#if canImport(UIKit)
import UIKit
#endif
import SwiftUI

struct QuickPromptsView: View {

    /// รายการคำสั่ง (ปรับตามสถานะสิทธิ์ของเครื่องได้)
    let prompts: [QuickPrompt]
    let onSelect: (QuickPrompt) -> Void

    struct QuickPrompt: Identifiable, Equatable {
        let id: String
        let title: String
        let detail: String
        let systemImage: String
        /// ข้อความที่จะถูกใส่ในช่องพิมพ์
        let text: String
    }

    static func defaultPrompts(workspacePath: String) -> [QuickPrompt] {
        [
            QuickPrompt(id: "explore",
                        title: "สำรวจเครื่องของฉัน",
                        detail: "ให้ Agent ดูว่ามีอะไรในเครื่องและสรุปให้ฟัง",
                        systemImage: "magnifyingglass",
                        text: "ช่วยสำรวจเครื่องนี้ให้หน่อย ว่ามีโฟลเดอร์อะไรบ้างใน /var/mobile และมีไฟล์อะไรที่ควรรู้"),
            QuickPrompt(id: "listworkspace",
                        title: "ดูไฟล์ในโฟลเดอร์ทำงาน",
                        detail: workspacePath,
                        systemImage: "folder",
                        text: "ช่วยเปิดดูว่าตอนนี้มีไฟล์อะไรอยู่ใน \(workspacePath) และสรุปให้ฟังทีละไฟล์"),
            QuickPrompt(id: "create",
                        title: "สร้างไฟล์ทดสอบ",
                        detail: "สร้างโฟลเดอร์ + ไฟล์ข้อความให้ดู",
                        systemImage: "doc.badge.plus",
                        text: "ช่วยสร้างโฟลเดอร์ชื่อ demo ให้ผม แล้วเขียนไฟล์ readme.txt ข้างในอธิบายว่าไฟล์นี้สร้างโดย Agent"),
            QuickPrompt(id: "search",
                        title: "ค้นหาไฟล์ในเครื่อง",
                        detail: "หาไฟล์ตามชื่อใน /var/mobile",
                        systemImage: "doc.text.magnifyingglass",
                        text: "ช่วยค้นหาไฟล์นามสกุล .plist ใน /var/mobile แล้วบอกว่าพบกี่ไฟล์และอยู่ที่ไหน"),
            QuickPrompt(id: "download",
                        title: "ดาวน์โหลดไฟล์จากอินเทอร์เน็ต",
                        detail: "ลองดาวน์โหลดไฟล์ตัวอย่าง",
                        systemImage: "arrow.down.circle",
                        text: "ช่วยดาวน์โหลด https://example.com เก็บไว้ในโฟลเดอร์ทำงาน แล้วบอกว่าได้ไฟล์อะไร"),
            QuickPrompt(id: "explain",
                        title: "อธิบายสิทธิ์ของแอป",
                        detail: "ดูว่าแอปเข้าถึงอะไรได้บ้าง",
                        systemImage: "lock.shield",
                        text: "ช่วยอธิบายให้ฟังหน่อยว่าแอปนี้เข้าถึงไฟล์ส่วนไหนของเครื่องได้บ้าง และถ้าอยากให้เข้าถึงได้ทั้งหมดต้องทำอะไร")
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("เริ่มจากตรงนี้ได้เลย")
                .font(.subheadline)
                .foregroundColor(.secondary)

            ForEach(prompts) { prompt in
                Button {
                    onSelect(prompt)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: prompt.systemImage)
                            .font(.system(size: 18))
                            .frame(width: 30)
                            .foregroundColor(.accentColor)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(prompt.title)
                                .font(.subheadline)
                                .foregroundColor(.primary)
                            Text(prompt.detail)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.up.left")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color(UIColor.secondarySystemBackground))
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 4)
    }
}
