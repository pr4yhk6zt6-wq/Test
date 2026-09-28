//
//  FileEditorView.swift
//  iOS Agent Sandbox
//
//  แก้ไขไฟล์ข้อความในแอป (เฟส 5)
//  - นับบรรทัด + ค้นหาในเนื้อหา (ไฮไลต์จำนวนที่พบและเลื่อนไปยังผลลัพธ์)
//  - บันทึกผ่าน FileSystemService (มีเพดานขนาด + เขียนแบบ atomic)
//  - ปุ่ม "ให้ Agent แก้ไฟล์นี้" ส่งคำสั่งไปยังแท็บแชทพร้อมแนบไฟล์
//

#if canImport(UIKit)
import UIKit
#endif
import SwiftUI

struct FileEditorView: View {

    let path: String
    /// เรียกเมื่อบันทึกสำเร็จ (ให้หน้ารายละเอียดไฟล์โหลดใหม่)
    var onSaved: (() -> Void)?

    @Environment(\.presentationMode) private var presentationMode
    @EnvironmentObject private var settings: AppSettings

    @State private var text: String = ""
    @State private var originalText: String = ""
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var message: String?
    @State private var messageIsError = false
    @State private var searchText: String = ""
    @State private var matchIndex: Int = 0

    /// เพดานการแก้ไขในแอป (ไบต์) — ใหญ่กว่านี้ให้ Agent แก้ผ่าน tool
    private let maximumEditableBytes = 200 * 1024

    private var lineCount: Int {
        text.isEmpty ? 0 : text.components(separatedBy: "\n").count
    }

    private var matchCount: Int {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return 0 }
        return text.components(separatedBy: query).count - 1
    }

    private var isDirty: Bool {
        text != originalText
    }

    var body: some View {
        VStack(spacing: 0) {
            infoBar
            searchBar
            Divider()

            if isLoading {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("กำลังโหลดไฟล์…")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                TextEditor(text: $text)
                    .font(.system(.footnote, design: .monospaced))
                    .disableAutocorrection(true)
                    .autocapitalization(.none)
                    .padding(.horizontal, 4)
            }

            if let message = message {
                Text(message)
                    .font(.caption)
                    .foregroundColor(messageIsError ? .red : .secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(UIColor.tertiarySystemBackground))
            }
        }
        .navigationTitle((path as NSString).lastPathComponent)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(isSaving ? "กำลังบันทึก…" : "บันทึก") {
                    save()
                }
                .disabled(isSaving || isLoading || !isDirty)
            }
            ToolbarItem(placement: .bottomBar) {
                Button {
                    sendToAgent()
                } label: {
                    Label("ให้ Agent แก้ไฟล์นี้", systemImage: "sparkles")
                }
                .frame(minHeight: 44)
            }
        }
        .onAppear(perform: load)
    }

    private var infoBar: some View {
        HStack(spacing: 10) {
            Label("\(lineCount) บรรทัด", systemImage: "text.alignleft")
            Label("\(text.count) ตัวอักษร", systemImage: "character")
            if isDirty {
                Label("ยังไม่บันทึก", systemImage: "pencil.circle")
                    .foregroundColor(.orange)
            }
            Spacer(minLength: 0)
        }
        .font(.caption2)
        .foregroundColor(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            TextField("ค้นหาในไฟล์", text: $searchText)
                .textFieldStyle(PlainTextFieldStyle())
                .autocapitalization(.none)
                .disableAutocorrection(true)
            if !searchText.isEmpty {
                Text(matchCount == 0 ? "ไม่พบ" : "พบ \(matchCount) แห่ง")
                    .font(.caption2)
                    .foregroundColor(matchCount == 0 ? .red : .secondary)
            }
            if matchCount > 0 {
                Button {
                    matchIndex = (matchIndex + 1) % matchCount
                } label: {
                    Image(systemName: "arrow.down.circle")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("ไปยังผลลัพธ์ถัดไป")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(minHeight: 40)
    }

    // MARK: - โหลด/บันทึก

    private func load() {
        isLoading = true
        let path = self.path
        let limit = maximumEditableBytes
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let prefix = try FileSystemService.readPrefix(path, maxBytes: limit)
                DispatchQueue.main.async {
                    if prefix.isBinary {
                        message = "ไฟล์นี้เป็นไฟล์ไบนารี — แก้ไขเป็นข้อความไม่ได้"
                        messageIsError = true
                    } else if prefix.hasMore {
                        message = "ไฟล์ใหญ่กว่า \(Attachment.sizeText(for: limit)) — แสดงเฉพาะส่วนต้น ควรให้ Agent แก้ผ่าน tool"
                        messageIsError = false
                        text = prefix.text
                        originalText = prefix.text
                    } else {
                        text = prefix.text
                        originalText = prefix.text
                    }
                    isLoading = false
                }
            } catch {
                DispatchQueue.main.async {
                    message = error.localizedDescription
                    messageIsError = true
                    isLoading = false
                }
            }
        }
    }

    private func save() {
        isSaving = true
        let content = text
        let path = self.path
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let report = try FileSystemService.write(content, to: path)
                DispatchQueue.main.async {
                    isSaving = false
                    originalText = content
                    message = "บันทึกแล้ว \(report.bytesWritten) ไบต์ → \(report.path)"
                    messageIsError = false
                    onSaved?()
                }
            } catch {
                DispatchQueue.main.async {
                    isSaving = false
                    message = "บันทึกไม่สำเร็จ: \(error.localizedDescription)"
                    messageIsError = true
                }
            }
        }
    }

    private func sendToAgent() {
        let fileName = (path as NSString).lastPathComponent
        let prompt = "ช่วยตรวจและแก้ไขไฟล์นี้ให้ผม: \(path)\n(ไฟล์ \(fileName) — ผมเปิดแก้ในแอปอยู่)"
        AppRouter.shared.sendToAgent(prompt, attachmentPath: path)
        presentationMode.wrappedValue.dismiss()
    }
}
