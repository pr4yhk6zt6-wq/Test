//
//  MarkdownRenderer.swift
//  iOS Agent Sandbox
//
//  แปลงข้อความ Markdown เป็นบล็อกที่แสดงผลได้
//  - ข้อความปกติ → AttributedString(markdown:) (iOS 15)
//  - code block (```lang) → แสดง monospace พร้อมปุ่มคัดลอก
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif

struct MarkdownBlock: Identifiable {
    enum Kind {
        case text(String)
        case code(language: String?, code: String)
    }

    let id: UUID
    let kind: Kind

    init(kind: Kind) {
        self.id = UUID()
        self.kind = kind
    }
}

enum MarkdownRenderer {

    /// ตัดข้อความ Markdown ออกเป็นบล็อกข้อความ / บล็อกโค้ด
    static func parse(_ markdown: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var textBuffer: [String] = []
        var codeBuffer: [String] = []
        var codeLanguage: String?
        var insideCodeBlock = false

        func flushText() {
            let text = textBuffer.joined(separator: "\n").trimmingCharacters(in: .newlines)
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                blocks.append(MarkdownBlock(kind: .text(text)))
            }
            textBuffer.removeAll(keepingCapacity: true)
        }

        func flushCode() {
            var code = codeBuffer.joined(separator: "\n")
            if code.hasSuffix("\n") { code.removeLast() }
            if !code.isEmpty {
                blocks.append(MarkdownBlock(kind: .code(language: codeLanguage, code: code)))
            }
            codeBuffer.removeAll(keepingCapacity: true)
            codeLanguage = nil
        }

        for rawLine in markdown.components(separatedBy: "\n") {
            let trimmedLine = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmedLine.hasPrefix("```") {
                if insideCodeBlock {
                    flushCode()
                    insideCodeBlock = false
                } else {
                    flushText()
                    let language = trimmedLine.dropFirst(3).trimmingCharacters(in: .whitespaces)
                    codeLanguage = language.isEmpty ? nil : language
                    insideCodeBlock = true
                }
                continue
            }
            if insideCodeBlock {
                codeBuffer.append(rawLine)
            } else {
                textBuffer.append(rawLine)
            }
        }

        if insideCodeBlock {
            // code block ที่ไม่ได้ปิด (streaming ยังไม่จบ) – แสดงเท่าที่มีก่อน
            flushCode()
        }
        flushText()

        if blocks.isEmpty && !markdown.isEmpty {
            blocks.append(MarkdownBlock(kind: .text(markdown)))
        }
        return blocks
    }

    /// แปลง Markdown เป็น AttributedString (รองรับ **ตัวหนา**, *เอียง*, `โค้ด`)
    /// ถ้า parse ไม่สำเร็จจะคืนข้อความธรรมดา
    /// หมายเหตุ: ไม่รับพารามิเตอร์ Font ที่นี่ เพื่อไม่ให้ไฟล์นี้ต้อง import SwiftUI
    /// (การปรับขนาด/ฟอนต์ทำที่ MessageContentView ซึ่งเป็นชั้น SwiftUI)
    static func attributedText(from markdown: String) -> AttributedString {
        var options = AttributedString.MarkdownParsingOptions()
        options.interpretedSyntax = .inlineOnlyPreservingWhitespace
        options.allowsExtendedAttributes = false

        if let parsed = try? AttributedString(markdown: markdown, options: options) {
            return parsed
        }
        return AttributedString(markdown)
    }

    /// จำนวนบรรทัดของโค้ด (ใช้แสดงในหัวข้อ code block)
    static func lineCount(of text: String) -> Int {
        if text.isEmpty { return 0 }
        return text.components(separatedBy: "\n").count
    }
}
