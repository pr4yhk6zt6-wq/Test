//
//  AttachmentPickerSheet.swift
//  iOS Agent Sandbox
//
//  หน้าต่าง "+" สำหรับแนบไฟล์ (เฟส 5)
//  เลือกได้ 4 ทาง: รูปภาพ (หลายรูป) • ไฟล์ (หลายไฟล์) • ถ่ายรูป • วางจากคลิปบอร์ด
//  ทุกทางจบที่ AttachmentStore ซึ่งคัดลอกไฟล์เข้า /var/mobile/AgentWorkspace/uploads
//

import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct AttachmentPickerSheet: View {

    /// เพดานขนาดต่อไฟล์ (ไบต์) — ส่งมาจากเพดานดาวน์โหลดในหน้าตั้งค่า
    let maxBytes: Int
    /// จำนวนรูปสูงสุดต่อครั้ง
    var photoSelectionLimit: Int = 6

    let onImported: ([Attachment]) -> Void
    /// ข้อความจากคลิปบอร์ด (ใส่ลงช่องพิมพ์ให้เลย)
    let onPasteText: (String) -> Void
    let onMessage: (String) -> Void

    @Environment(\.presentationMode) private var presentationMode
    @State private var activePicker: ActivePicker?
    @State private var isImporting = false

    private enum ActivePicker: Identifiable {
        case photos
        case documents
        case camera

        var id: Int {
            switch self {
            case .photos: return 0
            case .documents: return 1
            case .camera: return 2
            }
        }
    }

    private var store: AttachmentStore {
        AttachmentStore(rootPath: AppSettings.shared.uploadsPath)
    }

    var body: some View {
        NavigationView {
            List {
                Section(header: Text("แนบไฟล์ให้ Agent")) {
                    pickerRow(title: "รูปภาพ",
                              subtitle: "เลือกได้หลายรูปจากคลังภาพ (ย่อขนาดก่อนส่งอัตโนมัติ)",
                              systemImage: "photo.on.rectangle.angled") {
                        activePicker = .photos
                    }

                    pickerRow(title: "ไฟล์",
                              subtitle: "เลือกไฟล์ได้หลายไฟล์จากแอปไฟล์",
                              systemImage: "folder") {
                        activePicker = .documents
                    }

                    if ImagePickerRepresentable.isCameraAvailable {
                        pickerRow(title: "ถ่ายรูป",
                                  subtitle: "เปิดกล้องแล้วแนบรูปที่ถ่ายทันที",
                                  systemImage: "camera") {
                            activePicker = .camera
                        }
                    }

                    pickerRow(title: "วางจากคลิปบอร์ด",
                              subtitle: "รูปจะถูกแนบเป็นไฟล์ • ข้อความจะถูกใส่ในช่องพิมพ์",
                              systemImage: "doc.on.clipboard") {
                        pasteFromClipboard()
                    }
                }

                Section(header: Text("ข้อจำกัด")) {
                    Text("• ไฟล์แนบถูกคัดลอกเข้า \(AppSettings.shared.uploadsPath)")
                    Text("• ขนาดสูงสุดต่อไฟล์: \(Attachment.sizeText(for: maxBytes))")
                    Text("• ไฟล์ข้อความเล็กกว่า 20 KB จะถูกฝังเนื้อหาไปกับข้อความให้อัตโนมัติ")
                    Text("• รูปจะถูกย่อให้ด้านยาวไม่เกิน 1024 px ก่อนส่งให้โมเดล")
                }
                .font(.caption)
                .foregroundColor(.secondary)

                if isImporting {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("กำลังคัดลอกไฟล์…")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .listStyle(GroupedListStyle())
            .navigationTitle("แนบไฟล์")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("ปิด") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
        .sheet(item: $activePicker) { picker in
            pickerSheet(for: picker)
        }
    }

    private func pickerRow(title: String,
                           subtitle: String,
                           systemImage: String,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 20))
                    .frame(width: 32)
                    .foregroundColor(.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundColor(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 4)
        }
        .disabled(isImporting)
    }

    @ViewBuilder
    private func pickerSheet(for picker: ActivePicker) -> some View {
        switch picker {
        case .photos:
            PHPickerRepresentable(selectionLimit: photoSelectionLimit,
                                  onPicked: { files in
                                      activePicker = nil
                                      importFiles(files)
                                  },
                                  onCancel: { activePicker = nil })
        case .documents:
            DocumentPickerRepresentable(allowsMultipleSelection: true,
                                        onPicked: { files in
                                            activePicker = nil
                                            importFiles(files)
                                        },
                                        onCancel: { activePicker = nil })
        case .camera:
            ImagePickerRepresentable(source: .camera,
                                     onPicked: { files in
                                         activePicker = nil
                                         importFiles(files)
                                     },
                                     onCancel: { activePicker = nil })
        }
    }

    // MARK: - นำเข้าไฟล์

    private func importFiles(_ files: [(url: URL, name: String)]) {
        guard !files.isEmpty else { return }
        isImporting = true

        let store = self.store
        let maxBytes = self.maxBytes
        DispatchQueue.global(qos: .userInitiated).async {
            var imported: [Attachment] = []
            var errors: [String] = []
            for file in files {
                do {
                    imported.append(try store.importFile(at: file.url, originalName: file.name, maxBytes: maxBytes))
                } catch {
                    errors.append("\(file.name): \(error.localizedDescription)")
                }
                // ลบไฟล์ชั่วคราวที่ตัวเลือกสร้างให้ (หลังคัดลอกแล้ว)
                try? FileManager.default.removeItem(at: file.url.deletingLastPathComponent())
            }

            DispatchQueue.main.async {
                isImporting = false
                if !imported.isEmpty {
                    onImported(imported)
                }
                if !errors.isEmpty {
                    onMessage("แนบไฟล์ไม่สำเร็จ \(errors.count) ไฟล์: " + errors.joined(separator: " | "))
                }
                if !imported.isEmpty {
                    presentationMode.wrappedValue.dismiss()
                }
            }
        }
    }

    private func pasteFromClipboard() {
        let pasteboard = UIPasteboard.general
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")

        if let image = pasteboard.image, let data = image.jpegData(compressionQuality: 0.9) {
            do {
                let attachment = try store.importData(data, originalName: "clipboard-\(stamp).jpg")
                onImported([attachment])
                presentationMode.wrappedValue.dismiss()
            } catch {
                onMessage(error.localizedDescription)
            }
            return
        }

        if let text = pasteboard.string, !text.isEmpty {
            onPasteText(text)
            presentationMode.wrappedValue.dismiss()
            return
        }

        onMessage("คลิปบอร์ดว่าง — คัดลอกรูปหรือข้อความก่อนแล้วลองใหม่")
    }
}
