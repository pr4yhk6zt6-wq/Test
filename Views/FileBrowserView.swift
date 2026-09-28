//
//  FileBrowserView.swift
//  iOS Agent Sandbox
//
//  เบราว์เซอร์ไฟล์ของแอป (เฟส 4)
//  - เริ่มที่ /var/mobile แล้วแตะเข้าโฟลเดอร์ไปเรื่อย ๆ (push navigation ปกติ)
//  - แตะไฟล์ → ดูเนื้อหา (ข้อความ / รูป / hex) ที่ FilePreviewView
//  - ใช้ FileSystemService ตัวเดียวกับที่ Agent ใช้ → สิทธิ์และข้อความ error ตรงกัน
//  - รองรับ Dynamic Type และปุ่ม ≥44pt (จอ 4.7 นิ้ว)
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct FileBrowserView: View {

    /// โฟลเดอร์ที่กำลังเปิดอยู่
    let path: String

    @State private var entries: [FileEntry] = []
    @State private var totalCount = 0
    @State private var skippedHidden = 0
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showHidden = false
    @State private var previewRequest: FilePreviewRequest?
    @State private var notice: String?

    /// path เริ่มต้นตามข้อกำหนดของเฟส 4
    static let defaultStartPath = "/var/mobile"

    /// ทางลัดไปยัง path ที่ใช้บ่อย (แสดงเป็นแถวท้ายรายการ จึงกดเข้าได้จริง)
    static let shortcuts: [(title: String, path: String)] = [
        ("โฟลเดอร์ผู้ใช้", "/var/mobile"),
        ("Documents ของผู้ใช้", "/var/mobile/Documents"),
        ("Downloads ของผู้ใช้", "/var/mobile/Downloads"),
        ("โฟลเดอร์ทำงานของ Agent", PathGuard.defaultWorkspace),
        ("jailbreak rootless", "/var/jb"),
        ("แอปที่ติดตั้ง", "/Applications"),
        ("Library ของระบบ", "/Library"),
        ("รากของระบบ", "/")
    ]

    var body: some View {
        List {
            pathHeader

            if let errorMessage {
                errorSection(message: errorMessage)
            } else if isLoading {
                loadingRow
            } else if entries.isEmpty {
                Text("โฟลเดอร์ว่าง")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .frame(minHeight: 44)
            } else {
                entriesSection
            }

            shortcutsSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle(folderTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        load()
                    } label: {
                        Label("อ่านใหม่", systemImage: "arrow.clockwise")
                    }

                    Toggle(isOn: $showHidden) {
                        Label("แสดงไฟล์ที่ซ่อน", systemImage: "eye")
                    }

                    Divider()

                    Button {
                        copyPath()
                    } label: {
                        Label("คัดลอก path นี้", systemImage: "doc.on.doc")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("เมนูของโฟลเดอร์นี้")
            }
        }
        .sheet(item: $previewRequest) { request in
            FilePreviewView(path: request.path)
        }
        .alert("คัดลอก path แล้ว", isPresented: isShowingNotice) {
            Button("ตกลง", role: .cancel) { notice = nil }
        } message: {
            Text(notice ?? "")
        }
        .onAppear(perform: load)
        .refreshable { load() }
        .onChange(of: showHidden) { _ in
            load()
        }
    }

    // MARK: - ส่วนหัว: path ปัจจุบัน + ปุ่มขึ้นโฟลเดอร์แม่

    private var pathHeader: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text(path)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)

                if !isLoading, errorMessage == nil {
                    Text(summaryText)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .frame(minHeight: 32)
            .padding(.vertical, 2)

            if let parent = parentPath {
                NavigationLink(destination: FileBrowserView(path: parent)) {
                    Label("ขึ้นไปโฟลเดอร์แม่", systemImage: "arrow.up.left")
                        .frame(minHeight: 44)
                }
            }
        } header: {
            Text("ตำแหน่งปัจจุบัน")
        }
    }

    private var summaryText: String {
        var parts: [String] = []
        let folders = entries.filter { $0.isDirectory }.count
        parts.append("\(folders) โฟลเดอร์ • \(entries.count - folders) ไฟล์")
        if skippedHidden > 0 {
            parts.append("ซ่อนไฟล์ที่ขึ้นต้นด้วย . อยู่ \(skippedHidden) รายการ")
        }
        if totalCount > entries.count {
            parts.append("แสดง \(entries.count) จาก \(totalCount) รายการ")
        }
        return parts.joined(separator: " • ")
    }

    private var loadingRow: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text("กำลังอ่านโฟลเดอร์…")
                .font(.footnote)
                .foregroundColor(.secondary)
        }
        .frame(minHeight: 44)
    }

    // MARK: - รายการไฟล์

    private var entriesSection: some View {
        Section {
            ForEach(entries) { entry in
                if entry.isDirectory {
                    NavigationLink(destination: FileBrowserView(path: entry.path)) {
                        entryRow(entry)
                    }
                } else {
                    Button {
                        previewRequest = FilePreviewRequest(path: entry.path)
                    } label: {
                        entryRow(entry)
                    }
                    .buttonStyle(.plain)
                }
            }
        } header: {
            Text("เนื้อหาในโฟลเดอร์")
        } footer: {
            Text("แตะโฟลเดอร์เพื่อเข้าไป • แตะไฟล์เพื่อดูเนื้อหา (ข้อความ/รูป/hex) • " +
                 "หน้าจอนี้กับ Agent ใช้สิทธิ์เดียวกัน ถ้าอ่านไม่ได้จะขึ้นเหตุผลให้ทราบ")
        }
    }

    private func entryRow(_ entry: FileEntry) -> some View {
        HStack(spacing: 10) {
            Image(systemName: iconName(for: entry))
                .font(.body)
                .foregroundColor(entry.isDirectory ? .accentColor : .secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .font(.body)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    if !entry.isDirectory {
                        Text(NetworkPolicy.formatBytes(entry.sizeBytes))
                    }
                    if let date = entry.modificationDate {
                        Text(FileEntryFormatter.dateText(date))
                    }
                    if entry.isSymbolicLink {
                        Text("ลิงก์")
                            .foregroundColor(.orange)
                    }
                }
                .font(.caption2)
                .foregroundColor(.secondary)
            }

            Spacer(minLength: 0)

            if entry.isDirectory {
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    // MARK: - ทางลัด

    private var shortcutsSection: some View {
        Section {
            ForEach(FileBrowserView.shortcuts, id: \.path) { shortcut in
                NavigationLink(destination: FileBrowserView(path: shortcut.path)) {
                    HStack {
                        Text(shortcut.title)
                            .font(.footnote)
                        Spacer(minLength: 8)
                        Text(shortcut.path)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.head)
                    }
                    .frame(minHeight: 44)
                }
            }
        } header: {
            Text("ไปยัง path ที่ใช้บ่อย")
        }
    }

    // MARK: - แถบแจ้งเมื่ออ่านโฟลเดอร์ไม่ได้

    private func errorSection(message: String) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(message)
                        .font(.footnote)
                }
                .frame(minHeight: 44)

                if message.contains("ไม่มีสิทธิ์") {
                    Text("path ของระบบต้องอาศัยสิทธิ์ no-sandbox — ติดตั้งแอปผ่าน TrollStore หรือเจลเบรคด้วย palera1n " +
                         "แล้วดูผลตรวจได้ที่ ตั้งค่า → สิทธิ์ของแอป")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Button {
                    load()
                } label: {
                    Label("ลองอ่านใหม่", systemImage: "arrow.clockwise")
                        .frame(minHeight: 44)
                }
            }
        } header: {
            Text("อ่านโฟลเดอร์ไม่สำเร็จ")
        }
    }

    // MARK: - ตัวช่วย

    private func iconName(for entry: FileEntry) -> String {
        if entry.isSymbolicLink {
            return "arrow.turn.up.right"
        }
        if entry.isDirectory {
            return "folder"
        }
        switch (entry.name as NSString).pathExtension.lowercased() {
        case "png", "jpg", "jpeg", "gif", "heic", "webp", "bmp", "tiff":
            return "photo"
        case "plist", "json", "xml", "entitlements":
            return "curlybraces"
        case "sh", "bash", "zsh":
            return "terminal"
        case "log", "txt", "md", "swift", "py", "js", "css", "html":
            return "doc.text"
        case "db", "sqlite", "sqlite3":
            return "cylinder.split.1x2"
        case "zip", "ipa", "tar", "gz", "7z":
            return "archivebox"
        case "mp3", "m4a", "wav", "aac":
            return "waveform"
        case "mp4", "mov", "m4v":
            return "film"
        case "pdf":
            return "doc.richtext"
        default:
            return "doc"
        }
    }

    private var folderTitle: String {
        let name = (path as NSString).lastPathComponent
        return name.isEmpty ? path : name
    }

    private var parentPath: String? {
        guard path != "/" else { return nil }
        let parent = (path as NSString).deletingLastPathComponent
        return parent.isEmpty || parent == path ? "/" : parent
    }

    /// ใช้บอก SwiftUI ว่าให้แสดง alert (ผูกกับ notice)
    private var isShowingNotice: Binding<Bool> {
        Binding(get: { notice != nil },
                set: { newValue in
                    if !newValue { notice = nil }
                })
    }

    private func load() {
        isLoading = true
        errorMessage = nil
        do {
            let listing = try FileSystemService.list(path, includeHidden: showHidden, limit: 500)
            entries = listing.entries
            totalCount = listing.totalCount
            skippedHidden = listing.skippedHidden
        } catch {
            entries = []
            totalCount = 0
            skippedHidden = 0
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func copyPath() {
        #if canImport(UIKit)
        UIPasteboard.general.string = path
        notice = path
        #endif
    }
}

/// คำขอเปิดดูไฟล์ (ใช้กับ `.sheet(item:)`)
private struct FilePreviewRequest: Identifiable {
    let id = UUID()
    let path: String
}

/// ตัวช่วยจัดรูปแบบวันที่ของไฟล์ (ใช้ร่วมกับ FilePreviewView)
enum FileEntryFormatter {

    private static let shortFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "th_TH")
        formatter.dateFormat = "d MMM yy HH:mm"
        return formatter
    }()

    static func dateText(_ date: Date) -> String {
        shortFormatter.string(from: date)
    }

    static func fullDateText(_ date: Date) -> String {
        let full = DateFormatter()
        full.locale = Locale(identifier: "th_TH")
        full.dateFormat = "d MMMM yyyy HH:mm:ss"
        return full.string(from: date)
    }
}
