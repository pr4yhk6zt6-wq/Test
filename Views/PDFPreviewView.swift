//
//  PDFPreviewView.swift
//  iOS Agent Sandbox
//
//  แสดงไฟล์ PDF ด้วย PDFKit (เฟส 5) — PDFKit มีมาตั้งแต่ iOS 11 จึงปลอดภัยกับเป้าหมาย 15.0
//

#if canImport(UIKit)
import UIKit
#endif
import SwiftUI
import PDFKit

struct PDFPreviewView: UIViewRepresentable {

    let path: String

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = UIColor.secondarySystemBackground
        if let document = PDFDocument(url: URL(fileURLWithPath: path)) {
            view.document = document
        }
        return view
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        if uiView.document == nil, let document = PDFDocument(url: URL(fileURLWithPath: path)) {
            uiView.document = document
        }
    }
}
