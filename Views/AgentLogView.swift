//
//  AgentLogView.swift
//  iOS Agent Sandbox
//
//  บันทึกการทำงานของ Agent (เฟส 4)
//  แสดงทุกครั้งที่ Agent เรียก tool: ชื่อ tool, arguments, ผลลัพธ์, เวลา, ระยะเวลา, สถานะ
//  พร้อมคัดลอกรายการเดียว/ทั้งหมด และล้างบันทึก
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct AgentLogView: View {

    @ObservedObject private var store = AgentLogStore.shared

    @State private var keyword = ""
    @State private var showClearConfirm = false
    @State private var notice: String?

    var body: some View {
        List {
            if store.isEmpty {
                emptySection
            } else {
                searchSection
                summarySection
                entriesSection
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("บันทึก Agent")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        copyAll()
                    } label: {
                        Label("คัดลอกทั้งหมด", systemImage: "doc.on.doc")
                    }
                    .disabled(store.isEmpty)

                    Button(role: .destructive) {
                        showClearConfirm = true
                    } label: {
                        Label("ล้างบันทึก", systemImage: "trash")
                    }
                    .disabled(store.isEmpty)
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("เมนูบันทึก")
            }
        }
        .alert("ล้างบันทึกทั้งหมด?", isPresented: $showClearConfirm) {
            Button("ล้าง", role: .destructive) {
                store.clear()
                notice = "ล้างบันทึกแล้ว"
            }
            Button("ยกเลิก", role: .cancel) { }
        } message: {
            Text("บันทึกการเรียก tool ทั้ง \(store.count) รายการจะหายไป (ประวัติการสนทนาไม่ถูกลบ)")
        }
        .alert("เรียบร้อย", isPresented: isShowingNotice) {
            Button("ตกลง", role: .cancel) { notice = nil }
        } message: {
            Text(notice ?? "")
        }
    }

    // MARK: - สถานะว่าง

    private var emptySection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Label("ยังไม่มีบันทึก", systemImage: "list.bullet.rectangle")
                    .font(.headline)
                Text("เมื่อ Agent เรียก tool (อ่าน/เขียนไฟล์, รันคำสั่ง shell, เข้าอินเทอร์เน็ต) " +
                     "ทุกรายการจะถูกบันทึกไว้ที่นี่ พร้อม arguments, ผลลัพธ์, เวลา และระยะเวลา")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                Text("บันทึกเก็บในหน่วยความจำของแอป สูงสุด \(AgentLogStore.maximumEntries) รายการ ล่าสุดอยู่บนสุด")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .frame(minHeight: 44)
            .padding(.vertical, 2)
        }
    }

    // MARK: - ค้นหา + สรุป

    private var searchSection: some View {
        Section {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("ค้นหาในชื่อ tool / arguments / ผลลัพธ์", text: $keyword)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .frame(minHeight: 44)
                if !keyword.isEmpty {
                    Button {
                        keyword = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("ล้างคำค้นหา")
                }
            }
        }
    }

    private var summarySection: some View {
        Section {
            HStack {
                Label("ทั้งหมด \(store.count) รายการ", systemImage: "number")
                    .font(.footnote)
                Spacer(minLength: 8)
                Label("ผิดพลาด \(failureCount)", systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundColor(failureCount > 0 ? .orange : .secondary)
            }
            .frame(minHeight: 44)

            if !keyword.isEmpty {
                Text("กรองด้วยคำว่า \"\(keyword)\" เหลือ \(filteredEntries.count) รายการ")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var failureCount: Int {
        store.entries.filter { $0.isError }.count
    }

    private var filteredEntries: [AgentLogEntry] {
        let needle = keyword.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return store.entries }
        return store.entries.filter { entry in
            entry.toolName.lowercased().contains(needle) ||
            entry.thaiLabel.lowercased().contains(needle) ||
            entry.argumentsText.lowercased().contains(needle) ||
            entry.resultText.lowercased().contains(needle)
        }
    }

    // MARK: - รายการบันทึก

    private var entriesSection: some View {
        Section {
            if filteredEntries.isEmpty {
                Text("ไม่พบรายการที่ตรงกับคำค้นหา")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .frame(minHeight: 44)
            } else {
                ForEach(filteredEntries) { entry in
                    NavigationLink(destination: AgentLogDetailView(entry: entry)) {
                        row(entry)
                    }
                }
            }
        } header: {
            Text("รายการล่าสุดก่อน")
        } footer: {
            Text("แตะรายการเพื่อดู arguments และผลลัพธ์เต็ม")
        }
    }

    private func row(_ entry: AgentLogEntry) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: entry.symbolName)
                .font(.body)
                .foregroundColor(entry.isError ? .orange : .accentColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(entry.thaiLabel)
                        .font(.subheadline)
                        .lineLimit(1)

                    Text(entry.isError ? "ผิดพลาด" : "สำเร็จ")
                        .font(.caption2)
                        .foregroundColor(entry.isError ? .orange : .secondary)
                }

                Text(entry.argumentsText.isEmpty ? "(ไม่มี arguments)" : entry.argumentsText)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    Text(entry.timeText)
                    Text("•")
                    Text(entry.durationText)
                    if entry.wasTruncated {
                        Text("• ตัดข้อความ")
                    }
                }
                .font(.caption2)
                .foregroundColor(.secondary)
            }

            Spacer(minLength: 0)
        }
        .frame(minHeight: 44)
        .padding(.vertical, 2)
    }

    // MARK: - ตัวช่วย

    private var isShowingNotice: Binding<Bool> {
        Binding(get: { notice != nil },
                set: { newValue in
                    if !newValue { notice = nil }
                })
    }

    private func copyAll() {
        let text = store.allCopyText
        guard !text.isEmpty else { return }
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        notice = "คัดลอกบันทึกทั้งหมดแล้ว (\(store.count) รายการ • \(text.count) ตัวอักษร)"
        #endif
    }
}

// MARK: - หน้ารายละเอียดรายการเดียว

struct AgentLogDetailView: View {

    let entry: AgentLogEntry

    @State private var shareText: ShareableText?
    @State private var notice: String?

    var body: some View {
        List {
            Section {
                infoRow("เวลา", entry.timeText)
                infoRow("ระยะเวลา", entry.durationText)
                infoRow("สถานะ", entry.statusText)
                infoRow("tool (API)", entry.toolName)
                infoRow("หมวด", entry.category.thaiName)
                if entry.wasTruncated {
                    infoRow("หมายเหตุ", "ผลลัพธ์ถูกตัดตามเพดานของ tool")
                }
            } header: {
                Text("ข้อมูลการเรียก")
            }

            Section {
                Text(entry.argumentsText.isEmpty ? "(ไม่มี arguments)" : entry.argumentsText)
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } header: {
                Text("Arguments ที่โมเดลส่งมา")
            }

            Section {
                Text(entry.resultText.isEmpty ? "(ไม่มีผลลัพธ์)" : entry.resultText)
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } header: {
                Text("ผลลัพธ์ที่ Agent ได้รับ")
            }

            Section {
                Button {
                    #if canImport(UIKit)
                    UIPasteboard.general.string = entry.copyText
                    notice = "คัดลอกรายการนี้แล้ว"
                    #endif
                } label: {
                    Label("คัดลอกรายการนี้", systemImage: "doc.on.doc")
                        .frame(minHeight: 44)
                }

                Button {
                    shareText = ShareableText(text: entry.copyText)
                } label: {
                    Label("แชร์รายการนี้", systemImage: "square.and.arrow.up")
                        .frame(minHeight: 44)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(entry.thaiLabel)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $shareText) { item in
            ShareSheet(items: [item.text])
        }
        .alert("เรียบร้อย", isPresented: isShowingNotice) {
            Button("ตกลง", role: .cancel) { notice = nil }
        } message: {
            Text(notice ?? "")
        }
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .font(.footnote)
                .multilineTextAlignment(.trailing)
        }
        .frame(minHeight: 44)
    }

    private var isShowingNotice: Binding<Bool> {
        Binding(get: { notice != nil },
                set: { newValue in
                    if !newValue { notice = nil }
                })
    }
}
