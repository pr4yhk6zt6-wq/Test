//
//  MultilineInputField.swift
//  iOS Agent Sandbox
//
//  ช่องพิมพ์หลายบรรทัดที่ "ขยายเองได้" บน iOS 15
//  หมายเหตุ: TextField(axis:) และ lineLimit(_:ClosedRange) เป็น API ของ iOS 16 จึงใช้ไม่ได้
//  ไฟล์นี้จึงห่อ UITextView ด้วย UIViewRepresentable และคำนวณความสูงเอง (สูงสุด maxHeight)
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct MultilineInputField: UIViewRepresentable {

    @Binding var text: String
    /// ความสูงที่คำนวณได้ (parent นำไปใช้กับ .frame(height:))
    @Binding var height: CGFloat
    let font: UIFont
    let minHeight: CGFloat
    let maxHeight: CGFloat
    var isEditable: Bool = true

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.font = font
        textView.backgroundColor = .clear
        textView.textColor = .label
        textView.isScrollEnabled = false
        textView.isEditable = isEditable
        textView.isSelectable = true
        textView.alwaysBounceVertical = false
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 5, bottom: 8, right: 5)
        textView.textContainer.lineFragmentPadding = 0
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.text = text
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        context.coordinator.parent = self
        if uiView.text != text {
            uiView.text = text
        }
        if uiView.font != font {
            uiView.font = font
        }
        uiView.isEditable = isEditable
        context.coordinator.recalculateHeight(for: uiView, notifyParent: true)
    }

    final class Coordinator: NSObject, UITextViewDelegate {

        var parent: MultilineInputField
        private var lastReportedHeight: CGFloat = 0

        init(_ parent: MultilineInputField) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
            recalculateHeight(for: textView, notifyParent: true)
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            recalculateHeight(for: textView, notifyParent: true)
        }

        /// คำนวณความสูงที่ต้องการ แล้วอัปเดต binding ให้ SwiftUI ปรับกรอบให้
        func recalculateHeight(for textView: UITextView, notifyParent: Bool) {
            let width = textView.bounds.width > 0 ? textView.bounds.width : UIScreen.main.bounds.width - 90
            let fittingSize = textView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
            let clamped = min(max(fittingSize.height, parent.minHeight), parent.maxHeight)
            textView.isScrollEnabled = fittingSize.height > parent.maxHeight

            guard notifyParent else { return }
            if abs(lastReportedHeight - clamped) > 0.5 {
                lastReportedHeight = clamped
                let newValue = clamped
                // หลีกเลี่ยงการแก้ state ระหว่างรอบอัปเดตวิว
                DispatchQueue.main.async {
                    if abs(self.parent.height - newValue) > 0.5 {
                        self.parent.height = newValue
                    }
                }
            }
        }
    }
}

#if canImport(UIKit)
enum InputFontProvider {
    /// ฟอนต์ช่องพิมพ์ที่รองรับ Dynamic Type และตัวคูณขนาดที่ผู้ใช้ตั้งไว้
    static func font(scale: Double) -> UIFont {
        let clamped = CGFloat(max(0.8, min(scale, 1.6)))
        let base = UIFont.systemFont(ofSize: 17 * clamped)
        return UIFontMetrics(forTextStyle: .body).scaledFont(for: base)
    }
}
#endif
