//
//  ChatSearchView.swift
//  iOS Agent Sandbox
//
//  ชีตค้นข้อความย้อนหลังทุกห้อง (เฟส 6)
//  - พิมพ์แล้วเห็นผลทันที (ค้นจากข้อความที่โหลดไว้ ไม่แตะดิสก์ถี่ ๆ)
//  - แตะผลลัพธ์ → สลับไปห้องนั้นแล้วปิดชีต
//  - รองรับ Dynamic Type และปุ่ม ≥44pt
//

import SwiftUI

struct ChatSearchView: View {

    /// ฟังก์ชันค้น (ส่งคำค้นเข้าไป รับผลลัพธ์กลับ) — ให้ ViewModel เป็นคนถือข้อมูล
    let search: (String) -> [ChatSearchHit]
    /// แตะผลลัพธ์แล้วทำอะไร (สลับห้อง)
    let onSelect: (ChatSearchHit) -> Void

    @Environment(\.presentationMode) private var presentationMode

    @State private var query: String = ""
    @State private var hits: [ChatSearchHit] = []

    var body: some View {
        NavigationView {
            List {
                if query.trimmingCharacters(in: .whitespacesAndNewlines).count < ChatSearchIndex.minimumQueryLength {
                    Section {
                        Text("พิมพ์อย่างน้อย \(ChatSearchIndex.minimumQueryLength) ตัวอักษรเพื่อค้นข้อความในทุกห้องสนทนา")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                } else if hits.isEmpty {
                    Section {
                        Text("ไม่พบข้อความที่ตรงกับ “\(query)”")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                } else {
                    Section {
                        ForEach(hits) { hit in
                            Button {
                                onSelect(hit)
                                presentationMode.wrappedValue.dismiss()
                            } label: {
                                hitRow(hit)
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        Text("พบ \(hits.count) ข้อความ")
                    } footer: {
                        Text("เรียงจากใหม่ไปเก่า • แตะเพื่อข้ามไปห้องสนทนานั้น")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("ค้นหาในแชท")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("ปิด") { presentationMode.wrappedValue.dismiss() }
                        .frame(minHeight: 44)
                }
            }
        }
        .navigationViewStyle(.stack)
        .onChange(of: query) { newValue in
            hits = search(newValue)
        }
    }

    private func hitRow(_ hit: ChatSearchHit) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "bubble.left")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(hit.roomName)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text(ChatSearchView.timeText(hit.date))
                    .font(.caption2.monospacedDigit())
                    .foregroundColor(.secondary)
            }

            Text(hit.snippet)
                .font(.footnote)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            Text(hit.roleLabel)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    private static func timeText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "th_TH")
        formatter.dateFormat = "d MMM HH:mm"
        return formatter.string(from: date)
    }
}
