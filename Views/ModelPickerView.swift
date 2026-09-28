//
//  ModelPickerView.swift
//  iOS Agent Sandbox
//
//  เลือกโมเดลจาก GET /models (ไม่บังคับ – ผู้ใช้พิมพ์ Model ID เองได้)
//  ใช้ List + searchable (iOS 15) และปุ่มกรอง "เฉพาะโมเดลฟรี/รองรับ tools"
//

import SwiftUI

struct ModelPickerView: View {

    let models: [OpenRouterModel]
    /// ปิดด้วยปุ่มยกเลิก (ไม่เลือกอะไร)
    let onCancel: () -> Void
    /// เลือกโมเดลแล้ว
    let onSelect: (OpenRouterModel) -> Void

    @State private var searchText: String = ""
    @State private var showFreeOnly: Bool = true
    @State private var showToolsOnly: Bool = true
    @State private var showVisionOnly: Bool = false

    private var filteredModels: [OpenRouterModel] {
        var result = models
        if showFreeOnly { result = result.filter { $0.isFree } }
        if showToolsOnly { result = result.filter { $0.supportsTools } }
        if showVisionOnly { result = result.filter { $0.supportsVision } }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return result }
        return result.filter { model in
            model.id.lowercased().contains(query)
                || model.displayName.lowercased().contains(query)
                || (model.description ?? "").lowercased().contains(query)
        }
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                filterBar
                List {
                    Section {
                        if filteredModels.isEmpty {
                            Text("ไม่พบโมเดลที่ตรงกับเงื่อนไข ลองปิดตัวกรองด้านบนหรือล้างคำค้นหา")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                                .padding(.vertical, 8)
                        }
                        ForEach(filteredModels) { model in
                            Button {
                                onSelect(model)
                            } label: {
                                modelRow(model)
                            }
                            .buttonStyle(.plain)
                        }
                    } footer: {
                        Text("พบ \(filteredModels.count) จากทั้งหมด \(models.count) โมเดล • ไม่ต้องมี API Key ก็ดูรายการได้ แต่ต้องมี API Key จึงจะโหลดสำเร็จ")
                    }
                }
                .listStyle(.plain)
            }
            .navigationTitle("เลือกโมเดล")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "ค้นหาชื่อโมเดล")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("ยกเลิก") { onCancel() }
                }
            }
        }
        .navigationViewStyle(.stack)
        .dynamicTypeSize(.small ... .accessibility2)
    }

    private var filterBar: some View {
        HStack(spacing: 8) {
            toggleChip(title: "ฟรี", isOn: $showFreeOnly)
            toggleChip(title: "ใช้ tools ได้", isOn: $showToolsOnly)
            toggleChip(title: "รับรูปได้", isOn: $showVisionOnly)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(UIColor.secondarySystemBackground))
    }

    private func toggleChip(title: String, isOn: Binding<Bool>) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            Text(title)
                .font(.caption.weight(isOn.wrappedValue ? .semibold : .regular))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(minHeight: 32)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isOn.wrappedValue ? Color.accentColor.opacity(0.20) : Color(UIColor.tertiarySystemBackground))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(isOn.wrappedValue ? Color.accentColor : Color.clear, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("ตัวกรอง \(title)")
        .accessibilityValue(isOn.wrappedValue ? "เปิด" : "ปิด")
    }

    private func modelRow(_ model: OpenRouterModel) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(model.displayName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                if model.isFree {
                    Text("ฟรี")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.18))
                        .cornerRadius(6)
                }
            }
            Text(model.id)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
                .lineLimit(2)
            HStack(spacing: 8) {
                label(model.contextLabel)
                if model.supportsTools { label("tools") }
                if model.supportsVision { label("vision") }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .foregroundColor(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color(UIColor.tertiarySystemBackground))
            .cornerRadius(6)
    }
}
