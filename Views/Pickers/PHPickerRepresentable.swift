//
//  PHPickerRepresentable.swift
//  iOS Agent Sandbox
//
//  ตัวห่อ PHPickerViewController (iOS 14+) สำหรับเลือกรูปหลายรูป (เฟส 5)
//  ใช้ loadFileRepresentation เพื่อให้ได้ "ไฟล์" ไม่ใช่ UIImage ก้อนใหญ่ในหน่วยความจำ
//  แล้วคัดลอกเข้าโฟลเดอร์ทำงานด้วย AttachmentStore
//

import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct PHPickerRepresentable: UIViewControllerRepresentable {

    /// จำนวนรูปสูงสุดที่เลือกได้
    let selectionLimit: Int
    /// เรียกเมื่อผู้ใช้เลือกเสร็จ (ส่ง URL ของไฟล์ชั่วคราว + ชื่อไฟล์)
    let onPicked: ([(url: URL, name: String)]) -> Void
    /// เรียกเมื่อผู้ใช้ยกเลิก
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration()
        configuration.filter = .images
        configuration.selectionLimit = max(1, selectionLimit)
        let controller = PHPickerViewController(configuration: configuration)
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) { }

    func makeCoordinator() -> Coordinator {
        Coordinator(onPicked: onPicked, onCancel: onCancel)
    }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {

        private let onPicked: ([(url: URL, name: String)]) -> Void
        private let onCancel: () -> Void

        init(onPicked: @escaping ([(url: URL, name: String)]) -> Void, onCancel: @escaping () -> Void) {
            self.onPicked = onPicked
            self.onCancel = onCancel
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard !results.isEmpty else {
                onCancel()
                return
            }

            let group = DispatchGroup()
            let lock = NSLock()
            var files: [(url: URL, name: String)] = []

            let temporaryDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("picker-\(UUID().uuidString)", isDirectory: true)
            try? FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)

            for (index, result) in results.enumerated() {
                let provider = result.itemProvider
                let typeIdentifier = provider.registeredTypeIdentifiers.first(where: { identifier in
                    UTType(identifier)?.conforms(to: .image) == true
                }) ?? UTType.image.identifier

                let suggestedName = provider.suggestedName ?? "photo"
                group.enter()
                provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { url, _ in
                    defer { group.leave() }
                    guard let url = url else { return }
                    let extensionName = url.pathExtension.isEmpty ? "jpg" : url.pathExtension
                    let fileName = "\(suggestedName)-\(index + 1).\(extensionName)"
                    let destination = temporaryDirectory.appendingPathComponent(fileName)
                    do {
                        if FileManager.default.fileExists(atPath: destination.path) {
                            try FileManager.default.removeItem(at: destination)
                        }
                        try FileManager.default.copyItem(at: url, to: destination)
                        lock.lock()
                        files.append((url: destination, name: fileName))
                        lock.unlock()
                    } catch {
                        // ข้ามรูปที่คัดลอกไม่ได้ — รูปอื่นยังใช้งานได้
                    }
                }
            }

            group.notify(queue: .main) {
                if files.isEmpty {
                    self.onCancel()
                } else {
                    self.onPicked(files.sorted { $0.name < $1.name })
                }
            }
        }
    }
}
