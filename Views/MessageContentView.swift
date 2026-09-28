//
//  MessageContentView.swift
//  iOS Agent Sandbox
//
//  แสดงเนื้อหาข้อความ: Markdown + code block แบบ monospace พร้อมปุ่มคัดลอก
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct MessageContentView: View {

    let markdown: String
    let textColor: Color
    let fontScale: Double

    @State private var copiedBlockID: UUID?

    init(markdown: String, textColor: Color = .primary, fontScale: Double = 1.0) {
        self.markdown = markdown
        self.textColor = textColor
        self.fontScale = fontScale
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(MarkdownRenderer.parse(markdown)) { block in
                switch block.kind {
                case .text(let text):
                    textView(text)
                case .code(let language, let code):
                    CodeBlockView(language: language,
                                  code: code,
                                  fontScale: fontScale,
                                  isCopied: copiedBlockID == block.id) {
                        copy(code)
                        copiedBlockID = block.id
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func textView(_ text: String) -> some View {
        let attributed = MarkdownRenderer.attributedText(from: text)
        return Text(attributed)
            .font(.system(size: 16 * fontScale))
            .foregroundColor(textColor)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func copy(_ value: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = value
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }
}

// MARK: - Code block

struct CodeBlockView: View {

    let language: String?
    let code: String
    let fontScale: Double
    let isCopied: Bool
    let onCopy: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(language?.uppercased() ?? "CODE")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.secondary)
                Text("\(MarkdownRenderer.lineCount(of: code)) บรรทัด")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer(minLength: 0)
                Button(action: onCopy) {
                    Label(isCopied ? "คัดลอกแล้ว" : "คัดลอก",
                          systemImage: isCopied ? "checkmark" : "doc.on.doc")
                        .font(.caption)
                        .labelStyle(.titleAndIcon)
                        .padding(.horizontal, 8)
                        .frame(minHeight: 32)
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
                .accessibilityLabel("คัดลอกโค้ด")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(UIColor.tertiarySystemBackground))

            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(size: 13 * fontScale, design: .monospaced))
                    .foregroundColor(.primary)
                    .textSelection(.enabled)
                    .padding(10)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(UIColor.secondarySystemBackground))
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color(UIColor.separator), lineWidth: 0.5)
        )
    }
}
