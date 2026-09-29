//
//  AGFilesScreen.swift
//  AgentApp — แท็บ "ไฟล์" (พอร์ตจาก phase3: ทางลัด · รายการไฟล์ · เปิดดู · ส่งต่อให้ Agent)
//
//  หลักการ: ทุกการกระทำที่แตะไฟล์ของผู้ใช้ต้องมีการยืนยัน และการลบต้องบอกตรง ๆ ว่ากู้คืนไม่ได้
//  การแก้ไฟล์ที่มากับมือให้ทำผ่าน Agent เพื่อให้มีการสำรองไฟล์ก่อนแก้ (ย้อนกลับได้)
//

import SwiftUI
import UIKit

struct AGFilesScreen: View {

    let path: String

    @EnvironmentObject private var settings: AppSettings
    @ObservedObject private var router: AppRouter = .shared
    @AppStorage(SettingsKeys.chatFontScale) private var fontScale: Double = 1

    @State private var entries: [FileEntry] = []
    @State private var totalCount: Int = 0
    @State private var isLoading: Bool = true
    @State private var errorMessage: String?
    @State private var previewBox: PreviewBox?
    @State private var renameBox: RenameBox?
    @State private var newFolderName: String = ""
    @State private var showNewFolder: Bool = false
    @State private var confirmDelete: FileEntry?
    @State private var notice: String?

    init(path: String = "") {
        self.path = path.isEmpty ? PathGuard.defaultWorkspace : path
    }

    /// รากของแท็บไฟล์ = โฟลเดอร์ทำงานที่ตั้งไว้ (ไม่ผูกกับค่าคงที่ เพื่อให้ผู้ใช้เปลี่ยนโฟลเดอร์ได้)
    private var isRoot: Bool {
        let workspace = settings.workspacePath.isEmpty ? PathGuard.defaultWorkspace : settings.workspacePath
        return path == workspace
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AGMetric.s4) {
                header

                if let notice = notice { noticeRow(notice) }

                if isLoading {
                    VStack(alignment: .leading, spacing: AGMetric.s2) {
                        Text("กำลังอ่านรายการไฟล์…")
                            .font(AGFont.font(AGFont.sub, scale: fontScale))
                            .foregroundColor(AGColor.t2)
                        AGSkeleton(lines: 4, scale: fontScale)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("กำลังอ่านรายการไฟล์"))
                } else if let errorMessage = errorMessage {
                    AGBanner(tone: .error,
                             title: "เปิดโฟลเดอร์นี้ไม่ได้",
                             message: "\(errorMessage)\n\nลองกด \"ลองใหม่\" หรือย้อนกลับไปโฟลเดอร์ก่อนหน้า",
                             scale: fontScale)
                    AGButton(title: "ลองใหม่", icon: "arrow.clockwise", kind: .primary, scale: fontScale) { load() }
                } else if entries.isEmpty {
                    emptyState
                } else {
                    fileList
                }
            }
            .padding(.horizontal, AGMetric.screenPadding)
            .padding(.vertical, AGMetric.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(AGColor.bg)
        .navigationTitle(isRoot ? "ไฟล์ในเครื่อง" : (path as NSString).lastPathComponent)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button(action: { newFolderName = ""; showNewFolder = true }) {
                        Label("สร้างโฟลเดอร์ใหม่", systemImage: "folder.badge.plus")
                    }
                    Button(action: {
                        router.sendToAgent("ช่วยจัดระเบียบไฟล์ในโฟลเดอร์นี้ให้เป็นหมวดหมู่ โดยอธิบายก่อนว่าจะย้ายอะไรไปไหน")
                    }) {
                        Label("ให้ Agent ช่วยจัดระเบียบโฟลเดอร์นี้", systemImage: "wand.and.stars")
                    }
                    Button(action: copyPath) {
                        Label("คัดลอกพาธ", systemImage: "doc.on.doc")
                    }
                    if !isRoot {
                        Button(action: {
                            settings.workspacePath = path
                            notice = "ตั้งโฟลเดอร์ทำงานเป็น \(path) แล้ว"
                        }) {
                            Label("ตั้งเป็นโฟลเดอร์ทำงานของ Agent", systemImage: "pin")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(AGFont.font(AGFont.head, weight: .semibold, scale: fontScale))
                        .foregroundColor(AGColor.t1)
                }
                .accessibilityLabel(Text("ตัวเลือกของโฟลเดอร์นี้"))
            }
        }
        .sheet(item: $previewBox) { box in
            AGFilePreviewSheet(path: box.path, fontScale: fontScale, onGiveToAgent: {
                previewBox = nil
                router.sendToAgent("ช่วยแก้ไฟล์นี้ให้หน่อย: \(box.path)", attachmentPath: box.path)
            })
        }
        .sheet(isPresented: $showNewFolder) { newFolderSheet }
        .sheet(item: $renameBox) { box in
            renameSheet(box)
        }
        .alert(item: $confirmDelete) { entry in
            Alert(title: Text("ลบ \"\(entry.name)\"?"),
                  message: Text("การลบกู้คืนไม่ได้บนเครื่องนี้ — ถ้าต้องการย้อนกลับได้ ให้บอก Agent ให้จัดการไฟล์แทน เพราะระบบจะสำรองไฟล์ไว้ก่อน"),
                  primaryButton: .destructive(Text("ลบเลย")) { performDelete(entry) },
                  secondaryButton: .cancel(Text("ยกเลิก")))
        }
        .onAppear(perform: load)
    }

    // MARK: - หัวหน้า

    private var header: some View {
        AGCard(padding: AGMetric.s4) {
            VStack(alignment: .leading, spacing: AGMetric.s2) {
                Text(isRoot ? "โฟลเดอร์ทำงานของ Agent" : (path as NSString).lastPathComponent)
                    .font(AGFont.font(AGFont.sub, weight: .semibold, scale: fontScale))
                    .foregroundColor(AGColor.t1)
                Text(path)
                    .font(AGFont.mono(AGFont.micro, scale: fontScale))
                    .foregroundColor(AGColor.t2)
                    .lineLimit(2)
                    .truncationMode(.middle)
                HStack(spacing: AGMetric.s2) {
                    AGChip(text: "\(totalCount) รายการ", tone: .neutral, scale: fontScale)
                    if let space = FileSystemService.volumeSpace(at: path) {
                        AGChip(text: "ว่าง \(AGFormat.bytes(Int(space.free)))", tone: .neutral, scale: fontScale)
                    }
                }
                if isRoot {
                    Text("Agent เห็นเฉพาะโฟลเดอร์นี้และโฟลเดอร์ที่คุณอนุญาตเป็นรายครั้ง — ทุกครั้งที่มีการแก้ไฟล์ ระบบจะสำรองไฟล์เดิมไว้ให้ย้อนกลับได้ 10 นาที")
                        .font(AGFont.font(AGFont.micro, scale: fontScale))
                        .foregroundColor(AGColor.t2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func noticeRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: AGMetric.s2) {
            Image(systemName: "info.circle.fill")
                .font(AGFont.font(AGFont.micro, scale: fontScale))
                .foregroundColor(AGColor.accentInk)
                .accessibilityHidden(true)
            Text(text)
                .font(AGFont.font(AGFont.cap, scale: fontScale))
                .foregroundColor(AGColor.t2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(action: { notice = nil }) {
                Image(systemName: "xmark")
                    .font(AGFont.font(AGFont.micro, weight: .semibold, scale: fontScale))
                    .foregroundColor(AGColor.t3)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(AGPressableStyle())
            .accessibilityLabel(Text("ปิดข้อความแจ้ง"))
        }
        .padding(AGMetric.s3)
        .background(RoundedRectangle(cornerRadius: AGMetric.rSM, style: .continuous).fill(AGColor.surface2))
    }

    private var emptyState: some View {
        AGCard(padding: AGMetric.s4) {
            VStack(alignment: .leading, spacing: AGMetric.s2) {
                Text("โฟลเดอร์นี้ว่าง")
                    .font(AGFont.font(AGFont.sub, weight: .semibold, scale: fontScale))
                    .foregroundColor(AGColor.t1)
                Text("ยังไม่มีไฟล์ในโฟลเดอร์นี้ — บอก Agent ให้สร้างไฟล์ให้ได้ เช่น \"สร้างไฟล์สรุป.md ในโฟลเดอร์ทำงาน\"")
                    .font(AGFont.font(AGFont.cap, scale: fontScale))
                    .foregroundColor(AGColor.t2)
                    .fixedSize(horizontal: false, vertical: true)
                AGButton(title: "ให้ Agent สร้างไฟล์ให้", icon: "wand.and.stars", kind: .primary, scale: fontScale) {
                    router.sendToAgent("ช่วยสร้างไฟล์สรุป.md ในโฟลเดอร์ทำงาน พร้อมหัวข้อตัวอย่าง 3 ข้อ")
                }
            }
        }
    }

    private var fileList: some View {
        VStack(alignment: .leading, spacing: AGMetric.s2) {
            if isRoot { shortcuts }

            AGSectionTitle(text: "ในโฟลเดอร์นี้", scale: fontScale)
            AGCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        if index > 0 {
                            Rectangle().fill(AGColor.border).frame(height: 1).padding(.leading, 52)
                        }
                        row(for: entry)
                    }
                }
            }
            if totalCount > entries.count {
                Text("แสดง \(entries.count) จาก \(totalCount) รายการ (จำกัดเพื่อไม่ให้หน้าจอหนักเกินไป)")
                    .font(AGFont.font(AGFont.micro, scale: fontScale))
                    .foregroundColor(AGColor.t3)
            }
        }
    }

    private var shortcuts: some View {
        VStack(alignment: .leading, spacing: AGMetric.s2) {
            AGSectionTitle(text: "ทางลัด", scale: fontScale)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AGMetric.s2) {
                    ForEach(["/var/mobile/Documents", "/var/mobile/Downloads", "/var/jb"], id: \.self) { item in
                        AGQuickChip(text: (item as NSString).lastPathComponent, scale: fontScale) {
                            settings.workspacePath = item
                            notice = "ตั้งโฟลเดอร์ทำงานเป็น \(item) แล้ว — Agent จะเห็นโฟลเดอร์นี้ในการทำงานครั้งถัดไป"
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    @ViewBuilder
    private func row(for entry: FileEntry) -> some View {
        if entry.isDirectory {
            NavigationLink(destination: AGFilesScreen(path: entry.path)) {
                AGRow(icon: "folder.fill",
                      title: entry.name,
                      subtitle: detailLine(entry),
                      showsChevron: true,
                      scale: fontScale,
                      action: nil)
            }
            .buttonStyle(AGPressableStyle())
        } else {
            AGCard(padding: 0) {
                AGRow(icon: icon(for: entry),
                      title: entry.name,
                      subtitle: detailLine(entry),
                      showsChevron: false,
                      scale: fontScale) { previewBox = PreviewBox(entry.path) }
                    .contextMenu {
                        Button(action: { previewBox = PreviewBox(entry.path) }) {
                            Label("เปิดดู", systemImage: "doc.text.magnifyingglass")
                        }
                        Button(action: {
                            router.sendToAgent("ช่วยแก้ไฟล์นี้ให้หน่อย: \(entry.path)", attachmentPath: entry.path)
                        }) {
                            Label("ให้ Agent แก้ไฟล์นี้", systemImage: "wand.and.stars")
                        }
                        Button(action: {
                            router.sendToAgent("ช่วยอธิบายว่าไฟล์นี้มีอะไร: \(entry.path)")
                        }) {
                            Label("ให้ Agent อธิบายไฟล์นี้", systemImage: "text.magnifyingglass")
                        }
                        Button(action: { renameBox = RenameBox(entry: entry, newName: entry.name) }) {
                            Label("เปลี่ยนชื่อ", systemImage: "pencil")
                        }
                        Button(action: { confirmDelete = entry }) {
                            Label("ลบไฟล์นี้", systemImage: "trash")
                        }
                    }
            }
        }
    }

    private func detailLine(_ entry: FileEntry) -> String {
        var parts: [String] = []
        if entry.isDirectory {
            parts.append("โฟลเดอร์")
        } else {
            parts.append(AGFormat.bytes(Int(entry.sizeBytes)))
        }
        if let date = entry.modificationDate {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "th_TH")
            formatter.dateFormat = "d MMM HH:mm"
            parts.append(formatter.string(from: date))
        }
        if entry.isSymbolicLink { parts.append("ลิงก์") }
        return parts.joined(separator: " · ")
    }

    private func icon(for entry: FileEntry) -> String {
        let ext = (entry.name as NSString).pathExtension.lowercased()
        switch ext {
        case "md", "txt": return "doc.text"
        case "json", "yml", "yaml", "xml": return "curlybraces"
        case "swift", "py", "js", "sh": return "chevron.left.forwardslash.chevron.right"
        case "png", "jpg", "jpeg", "heic", "gif": return "photo"
        case "zip", "tar", "gz": return "archivebox"
        case "ipa", "deb": return "shippingbox"
        default: return "doc"
        }
    }

    // MARK: - การทำงานกับไฟล์

    private func load() {
        isLoading = true
        errorMessage = nil
        do {
            let listing = try FileSystemService.list(path, includeHidden: false, limit: 200)
            entries = listing.entries.sorted { lhs, rhs in
                if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
            totalCount = listing.totalCount
        } catch {
            entries = []
            totalCount = 0
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func copyPath() {
        UIPasteboard.general.string = path
        AGHaptic.light()
        notice = "คัดลอกพาธแล้ว: \(path)"
    }

    private func performDelete(_ entry: FileEntry) {
        do {
            try FileSystemService.remove(entry.path, recursive: entry.isDirectory)
            AGHaptic.success()
            notice = "ลบ \"\(entry.name)\" แล้ว"
            load()
        } catch {
            AGHaptic.warning()
            notice = "ลบไม่สำเร็จ: \(error.localizedDescription)"
        }
    }

    private var newFolderSheet: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AGMetric.s3) {
                Text("สร้างโฟลเดอร์ใหม่ใน \(path)")
                    .font(AGFont.font(AGFont.sub, scale: fontScale))
                    .foregroundColor(AGColor.t2)
                    .fixedSize(horizontal: false, vertical: true)
                TextField("ชื่อโฟลเดอร์", text: $newFolderName)
                    .font(AGFont.font(AGFont.body, scale: fontScale))
                    .padding(.horizontal, AGMetric.s3)
                    .frame(minHeight: AGMetric.touch)
                    .background(RoundedRectangle(cornerRadius: AGMetric.rSM, style: .continuous).fill(AGColor.surface2))
                AGButton(title: "สร้าง", icon: "folder.badge.plus", kind: .primary, scale: fontScale) {
                    let name = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !name.isEmpty else { return }
                    do {
                        try FileSystemService.createDirectory((path as NSString).appendingPathComponent(name))
                        AGHaptic.success()
                        showNewFolder = false
                        notice = "สร้างโฟลเดอร์ \"\(name)\" แล้ว"
                        load()
                    } catch {
                        AGHaptic.warning()
                        notice = "สร้างโฟลเดอร์ไม่สำเร็จ: \(error.localizedDescription)"
                        showNewFolder = false
                    }
                }
            }
            .padding(.horizontal, AGMetric.screenPadding)
            .padding(.vertical, AGMetric.s3)
        }
        .frame(maxHeight: 300)
    }

    private func renameSheet(_ box: RenameBox) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AGMetric.s3) {
                Text("ของเดิม: \(box.entry.name)")
                    .font(AGFont.font(AGFont.sub, scale: fontScale))
                    .foregroundColor(AGColor.t2)
                    .fixedSize(horizontal: false, vertical: true)
                TextField("ชื่อใหม่", text: Binding(
                    get: { renameBox?.newName ?? "" },
                    set: { renameBox?.newName = $0 }))
                    .font(AGFont.font(AGFont.body, scale: fontScale))
                    .padding(.horizontal, AGMetric.s3)
                    .frame(minHeight: AGMetric.touch)
                    .background(RoundedRectangle(cornerRadius: AGMetric.rSM, style: .continuous).fill(AGColor.surface2))
                AGButton(title: "เปลี่ยนชื่อ", icon: "pencil", kind: .primary, scale: fontScale) {
                    if let current = renameBox {
                        performRename(current)
                        renameBox = nil
                    }
                }
                AGButton(title: "ยกเลิก", kind: .secondary, scale: fontScale) { renameBox = nil }
            }
            .padding(.horizontal, AGMetric.screenPadding)
            .padding(.vertical, AGMetric.s3)
        }
        .frame(maxHeight: 320)
    }

    private func performRename(_ box: RenameBox) {
        let target = (path as NSString).appendingPathComponent(box.newName)
        guard box.newName != box.entry.name else { return }
        do {
            try FileSystemService.move(box.entry.path, to: target, overwrite: false)
            AGHaptic.success()
            notice = "เปลี่ยนชื่อเป็น \"\(box.newName)\" แล้ว"
            load()
        } catch {
            AGHaptic.warning()
            notice = "เปลี่ยนชื่อไม่สำเร็จ: \(error.localizedDescription)"
        }
    }

    struct PreviewBox: Identifiable {
        let path: String
        var id: String { path }
        init(_ path: String) { self.path = path }
    }

    struct RenameBox: Identifiable {
        let entry: FileEntry
        var newName: String
        var id: String { entry.path }
    }
}
