//
//  ImagePickerRepresentable.swift
//  iOS Agent Sandbox
//
//  ตัวห่อ UIImagePickerController สำหรับถ่ายรูปด้วยกล้อง (เฟส 5)
//  ต้องมี NSCameraUsageDescription ใน Info.plist (มีแล้ว)
//  รูปที่ได้ถูกเขียนเป็นไฟล์ JPEG ในโฟลเดอร์ชั่วคราวก่อนคัดลอกเข้าโฟลเดอร์ทำงาน
//

import SwiftUI
import UIKit

struct ImagePickerRepresentable: UIViewControllerRepresentable {

    enum Source {
        case camera
        case photoLibrary

        var uiSourceType: UIImagePickerController.SourceType {
            switch self {
            case .camera: return .camera
            case .photoLibrary: return .photoLibrary
            }
        }
    }

    let source: Source
    let onPicked: ([(url: URL, name: String)]) -> Void
    let onCancel: () -> Void

    static var isCameraAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let controller = UIImagePickerController()
        controller.sourceType = source.uiSourceType
        controller.allowsEditing = false
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) { }

    func makeCoordinator() -> Coordinator {
        Coordinator(onPicked: onPicked, onCancel: onCancel)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {

        private let onPicked: ([(url: URL, name: String)]) -> Void
        private let onCancel: () -> Void

        init(onPicked: @escaping ([(url: URL, name: String)]) -> Void, onCancel: @escaping () -> Void) {
            self.onPicked = onPicked
            self.onCancel = onCancel
        }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            picker.dismiss(animated: true)

            guard let image = info[.originalImage] as? UIImage,
                  let data = image.jpegData(compressionQuality: 0.9) else {
                onCancel()
                return
            }

            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("camera-\(UUID().uuidString)", isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
                let url = directory.appendingPathComponent("camera-\(stamp).jpg")
                try data.write(to: url, options: .atomic)
                onPicked([(url: url, name: "camera-\(stamp).jpg")])
            } catch {
                onCancel()
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
            onCancel()
        }
    }
}
