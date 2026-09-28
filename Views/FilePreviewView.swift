//
//  FilePreviewView.swift
//  iOS Agent Sandbox
//
//  หน้าดูเนื้อหาไฟล์ (เฟส 4)
//  - ข้อความ: อ่านทีละก้อนผ่าน FileSystemService (ไม่โหลดทั้งไฟล์ — เครื่อง RAM 2GB)
//  - รูปภาพ: ย่อด้วย ImageIO ให้ด้านยาวสุด 1024px ก่อนแสดง (ประหยัดหน่วยความจำ)
//  - ไฟล์ไบนารี: แสดงตัวอย่าง hex แทน
//  - ข้อมูลไฟล์: ขนาด / วันที่ / สิทธิ์ / เจ้าของ / ปลายทาง symlink
//

import SwiftUI
import ImageIO
#if canImport(UIKit)
import UIKit
#endif

struct FilePreviewView: View {

    let path: String

    @Environment(\.presentationMode) private var presentationMode

    @State private var payload: PreviewPayload = .loading
    @State private var attributes: FileAttributes?
    @State private var shareText: ShareableText?
    @State private var notice: String?

    /// ขนาดสูงสุดที่อ่านมาแสดง (ไบต์) — พอสำหรับดูตัวอย่างบนจอเล็ก
    private static let previewReadBytes = 96 * 1024

    private enum PreviewPayload: Equatable {
        case loading
        case text(body: String, bytesRead: Int, totalBytes: Int64, hasMore: Bool)
        case image(data: Data)
        case hex(body: String, totalBytes: Int64)
        case failure(String)
    }

    var body: some View {
        NavigationView {
            List {
                infoSection
                contentSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle((path as NSString).lastPathComponent)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("ปิด") { presentationMode.wrappedValue.dismiss() }
                        .frame(minHeight: 44)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button {
                            copyPath()
                        } label: {
                            Label("คัดลอก path", systemImage: "doc.on.doc")
                        }

                        if let text = copyableText {
                            Button {
                                #if canImport(UIKit)
                                UIPasteboard.general.string = text
                                notice = "คัดลอกเนื้อหาแล้ว (\(text.count) ตัวอักษร)"
                                #endif
                            } label: {
                                Label("คัดลอกเนื้อหาที่แสดง", systemImage: "doc.on.clipboard")
                            }

                            Button {
                                shareText = ShareableText(text: text)
                            } label: {
                                Label("แชร์เนื้อหา", systemImage: "square.and.arrow.up")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("เมนูของไฟล์นี้")
                }
            }
        }
        .navigationViewStyle(.stack)
        .sheet(item: $shareText) { item in
            ShareSheet(items: [item.text])
        }
        .alert("เรียบร้อย", isPresented: isShowingNotice) {
            Button("ตกลง", role: .cancel) { notice = nil }
        } message: {
            Text(notice ?? "")
        }
        .task {
            await load()
        }
    }

    // MARK: - ข้อมูลไฟล์

    private var infoSection: some View {
        Section {
            infoRow(title: "path", value: path, monospaced: true)

            if let attributes {
                infoRow(title: "ชนิด", value: attributes.kindText)
                if !attributes.isDirectory {
                    infoRow(title: "ขนาด", value: NetworkPolicy.formatBytes(attributes.sizeBytes) +
                            " (\(attributes.sizeBytes) ไบต์)")
                }
                if let date = attributes.modificationDate {
                    infoRow(title: "แก้ไขล่าสุด", value: FileEntryFormatter.fullDateText(date))
                }
                if let date = attributes.creationDate {
                    infoRow(title: "สร้างเมื่อ", value: FileEntryFormatter.fullDateText(date))
                }
                if let permissions = attributes.permissionsText {
                    let owner = attributes.ownerID.map { " • เจ้าของ uid \($0)" } ?? ""
                    infoRow(title: "สิทธิ์", value: permissions + owner, monospaced: true)
                }
                if let target = attributes.linkTarget {
                    infoRow(title: "ลิงก์ไปยัง", value: target, monospaced: true)
                }
            } else {
                infoRow(title: "ข้อมูลไฟล์", value: "อ่านไม่ได้")
            }
        } header: {
            Text("ข้อมูลไฟล์")
        }
    }

    private func infoRow(title: String, value: String, monospaced: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(value)
                .font(monospaced ? .system(.footnote, design: .monospaced) : .footnote)
                .textSelection(.enabled)
        }
        .frame(minHeight: 44)
        .padding(.vertical, 2)
    }

    // MARK: - เนื้อหา

    @ViewBuilder
    private var contentSection: some View {
        switch payload {
        case .loading:
            Section {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("กำลังอ่านไฟล์…")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                .frame(minHeight: 44)
            }

        case .text(let body, let bytesRead, let totalBytes, let hasMore):
            Section {
                ScrollView(.vertical) {
                    Text(body.isEmpty ? "(ไฟล์ว่าง)" : body)
                        .font(.system(.footnote, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                }
                .frame(maxHeight: 380)
            } header: {
                Text("เนื้อหา (ข้อความ)")
            } footer: {
                Text(hasMore
                     ? "แสดง \(NetworkPolicy.formatBytes(Int64(bytesRead))) แรกจากทั้งหมด \(NetworkPolicy.formatBytes(totalBytes)) — ไฟล์ใหญ่กว่านี้จะไม่ถูกโหลดทั้งหมดเพื่อประหยัดหน่วยความจำ"
                     : "อ่านครบทั้งไฟล์ (\(NetworkPolicy.formatBytes(totalBytes)))")
            }

        case .image(let data):
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    #if canImport(UIKit)
                    if let image = UIImage(data: data) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity)
                            .background(Color(UIColor.secondarySystemBackground))
                            .cornerRadius(8)
                            .accessibilityLabel("ตัวอย่างรูปภาพ")
                    } else {
                        Text("แสดงรูปไม่ได้ (ไฟล์อาจเสียหรือเป็นรูปแบบที่ระบบไม่รองรับ)")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                    #else
                    Text("เครื่องนี้ไม่รองรับการแสดงรูป")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    #endif
                }
                .frame(minHeight: 44)
            } header: {
                Text("ตัวอย่างรูปภาพ")
            } footer: {
                Text("ย่อขนาดให้ด้านยาวสุดไม่เกิน 1024px ก่อนแสดง เพื่อไม่ให้กินหน่วยความจำเกินจำเป็น")
            }

        case .hex(let body, let totalBytes):
            Section {
                ScrollView([.horizontal, .vertical]) {
                    Text(body.isEmpty ? "(อ่านตัวอย่างไม่สำเร็จ)" : body)
                        .font(.system(.caption2, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(.vertical, 4)
                }
                .frame(maxHeight: 320)
            } header: {
                Text("ตัวอย่าง hex (512 ไบต์แรก)")
            } footer: {
                Text("ไฟล์นี้เป็นข้อมูลไบนารี ขนาดรวม \(NetworkPolicy.formatBytes(totalBytes)) จึงแสดงเป็น hex แทนข้อความ")
            }

        case .failure(let message):
            Section {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(message)
                            .font(.footnote)
                        Text("ถ้าไฟล์อยู่ใน path ของระบบ ต้องมีสิทธิ์ no-sandbox (ติดตั้งผ่าน TrollStore/palera1n)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(minHeight: 44)

                Button {
                    Task { await load() }
                } label: {
                    Label("ลองอ่านใหม่", systemImage: "arrow.clockwise")
                        .frame(minHeight: 44)
                }
            } header: {
                Text("อ่านไฟล์ไม่สำเร็จ")
            }
        }
    }

    // MARK: - ตัวช่วย

    private var copyableText: String? {
        switch payload {
        case .text(let body, _, _, _):
            return body
        case .hex(let body, _):
            return body
        default:
            return nil
        }
    }

    private var isShowingNotice: Binding<Bool> {
        Binding(get: { notice != nil },
                set: { newValue in
                    if !newValue { notice = nil }
                })
    }

    private func copyPath() {
        #if canImport(UIKit)
        UIPasteboard.general.string = path
        notice = path
        #endif
    }

    private func load() async {
        let targetPath = path
        let readLimit = FilePreviewView.previewReadBytes

        let result = await Task.detached(priority: .userInitiated) { () -> (PreviewPayload, FileAttributes?) in
            let attributes = try? FileSystemService.attributes(of: targetPath)

            if FilePreviewLoader.isImage(targetPath),
               let thumbnail = FilePreviewLoader.makeThumbnailData(path: targetPath) {
                return (.image(data: thumbnail), attributes)
            }

            do {
                let prefix = try FileSystemService.readPrefix(targetPath, maxBytes: readLimit)
                if prefix.isBinary {
                    let head = (try? FileSystemService.readHead(targetPath, maxBytes: 512)) ?? Data()
                    return (.hex(body: FileSystemService.hexPreview(head, maxBytes: 512),
                                 totalBytes: prefix.totalBytes), attributes)
                }
                return (.text(body: prefix.text,
                              bytesRead: prefix.bytesRead,
                              totalBytes: prefix.totalBytes,
                              hasMore: prefix.hasMore), attributes)
            } catch {
                return (.failure(error.localizedDescription), attributes)
            }
        }.value

        payload = result.0
        attributes = result.1
    }
}

// MARK: - ตัวอ่านตัวอย่างไฟล์ (แยกออกมาเพื่อไม่ผูกกับ SwiftUI actor)

enum FilePreviewLoader {

    static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "heic", "heif", "webp", "bmp", "tiff", "tif"]

    static func isImage(_ path: String) -> Bool {
        imageExtensions.contains((path as NSString).pathExtension.lowercased())
    }

    /// สร้างข้อมูลรูปย่อ (JPEG) ด้วย ImageIO — ไม่ถอดรหัสทั้งรูปสำหรับไฟล์ใหญ่
    static func makeThumbnailData(path: String, maxPixelSize: Int = 1024) -> Data? {
        let url = URL(fileURLWithPath: path)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        #if canImport(UIKit)
        return UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.7)
        #else
        return nil
        #endif
    }
}
