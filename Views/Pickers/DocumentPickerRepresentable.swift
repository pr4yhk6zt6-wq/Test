//
//  DocumentPickerRepresentable.swift
//  iOS Agent Sandbox
//
//  ตัวห่อ UIDocumentPickerViewController (ใช้ asCopy: true) สำหรับเลือกไฟล์หลายไฟล์ (เฟส 5)
//  asCopy: true ทำให้ได้ไฟล์ชั่วคราวที่เป็นของแอป จึงคัดลอกเข้าโฟลเดอร์ทำงานได้ทันที
//

import SwiftUI
import UniformTypeIdentifiers

struct DocumentPickerRepresentable: UIViewControllerRepresentable {

    let allowsMultipleSelection: Bool
    let onPicked: ([(url: URL, name: String)]) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let controller = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.item],
                                                        asCopy: true)
        controller.allowsMultipleSelection = allowsMultipleSelection
        controller.shouldShowFileExtensions = true
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) { }

    func makeCoordinator() -> Coordinator {
        Coordinator(onPicked: onPicked, onCancel: onCancel)
    }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {

        private let onPicked: ([(url: URL, name: String)]) -> Void
        private let onCancel: () -> Void

        init(onPicked: @escaping ([(url: URL, name: String)]) -> Void, onCancel: @escaping () -> Void) {
            self.onPicked = onPicked
            self.onCancel = onCancel
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard !urls.isEmpty else {
                onCancel()
                return
            }
            onPicked(urls.map { (url: $0, name: $0.lastPathComponent) })
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onCancel()
        }
    }
}
