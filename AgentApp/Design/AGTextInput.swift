//
//  AGTextInput.swift
//  AgentApp — ช่องพิมพ์หลายบรรทัด (ห่อ UITextView เพราะ iOS 15 ไม่มี TextField(axis:))
//

import SwiftUI
import UIKit

struct AGMultilineField: UIViewRepresentable {

    @Binding var text: String
    @Binding var height: CGFloat
    let font: UIFont
    let minHeight: CGFloat
    let maxHeight: CGFloat
    var isEditable: Bool = true
    var onFocusChange: ((Bool) -> Void)? = nil

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.delegate = context.coordinator
        view.isScrollEnabled = false
        view.backgroundColor = .clear
        view.textContainerInset = UIEdgeInsets(top: 6, left: 0, bottom: 6, right: 0)
        view.textContainer.lineFragmentPadding = 0
        view.font = font
        view.textColor = UIColor.label
        view.tintColor = UIColor(agHex: 0x2E4A8A)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        if view.text != text { view.text = text }
        view.font = font
        view.isEditable = isEditable
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, UITextViewDelegate {

        private let parent: AGMultilineField

        init(_ parent: AGMultilineField) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
            measure(textView)
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            parent.onFocusChange?(true)
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            parent.onFocusChange?(false)
        }

        private func measure(_ textView: UITextView) {
            let width = textView.bounds.width
            guard width > 0 else { return }
            let fitting = textView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
            let clamped = min(max(fitting.height, parent.minHeight), parent.maxHeight)
            if abs(clamped - parent.height) > 0.5 {
                parent.height = clamped
            }
        }
    }
}
