//
//  HTMLTextExtractor.swift
//  iOS Agent Sandbox
//
//  แปลง HTML → ข้อความล้วน สำหรับ tool "fetch_webpage" และ "web_search"
//  - ตัด <script>, <style>, คอมเมนต์, และแท็กทั้งหมดออก
//  - เก็บขอบเขตบรรทัดจากแท็กบล็อก (<p>, <br>, <li>, <h1>…) เพื่อให้อ่านรู้เรื่อง
//  - ถอด HTML entity พื้นฐาน
//
//  เขียนเองแทนการใช้ NSAttributedString(html:) เพราะต้องรันได้บน Linux (unit test)
//  และต้องไม่โหลดภาพ/สไตล์เข้าหน่วยความจำบนเครื่อง RAM 2GB
//
//  Foundation-only → รัน unit test ได้ทุกแพลตฟอร์ม
//

import Foundation

// MARK: - ผลการดึงเนื้อหา

struct ExtractedPage: Equatable {
    let title: String?
    let text: String
}

// MARK: - ผลการค้นหาเว็บ

struct WebSearchResult: Equatable, Identifiable {
    let title: String
    let url: String
    let snippet: String

    var id: String { url }
}

// MARK: - ตัวดึงข้อความจาก HTML

enum HTMLTextExtractor {

    /// แท็กที่ถือว่าเป็น "แท็กบล็อก" → ใส่ขึ้นบรรทัดใหม่เมื่อปิด
    private static let blockTags: Set<String> = [
        "p", "div", "br", "li", "ul", "ol", "tr", "table", "section", "article", "header",
        "footer", "nav", "aside", "blockquote", "pre", "h1", "h2", "h3", "h4", "h5", "h6", "hr", "form"
    ]

    /// ดึงหัวเรื่อง + ข้อความจาก HTML
    static func extract(fromHTML html: String, maxCharacters: Int = ToolOutputLimiter.defaultMaxCharacters) -> ExtractedPage {
        let title = extractTitle(fromHTML: html)
        let text = plainText(fromHTML: html, maxCharacters: maxCharacters)
        return ExtractedPage(title: title, text: text)
    }

    /// ดึงเนื้อหา <title>
    static func extractTitle(fromHTML html: String) -> String? {
        guard let startRange = html.range(of: "<title", options: .caseInsensitive) else { return nil }
        guard let openEnd = html.range(of: ">", range: startRange.upperBound..<html.endIndex) else { return nil }
        guard let closeStart = html.range(of: "</title", options: .caseInsensitive, range: openEnd.upperBound..<html.endIndex) else {
            return nil
        }
        let raw = String(html[openEnd.upperBound..<closeStart.lowerBound])
        let decoded = decodeEntities(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        return decoded.isEmpty ? nil : decoded
    }

    /// ตัดแท็กทั้งหมดออก เหลือแต่ข้อความ
    static func plainText(fromHTML html: String, maxCharacters: Int = ToolOutputLimiter.defaultMaxCharacters) -> String {
        var output = ""
        var index = html.startIndex

        // กัน HTML ยาวเกินการประมวลผลในครั้งเดียว (หน้าเว็บหลาย MB บนเครื่อง RAM 2GB)
        let scanLimit = 2_000_000
        let scanEnd = html.index(html.startIndex,
                                 offsetBy: min(html.count, scanLimit),
                                 limitedBy: html.endIndex) ?? html.endIndex

        while index < scanEnd {
            guard let tagStart = html.range(of: "<", range: index..<scanEnd) else {
                output += String(html[index..<scanEnd])
                break
            }
            output += String(html[index..<tagStart.lowerBound])

            // คอมเมนต์
            if html[tagStart.lowerBound...].hasPrefix("<!--") {
                let afterOpen = html.index(tagStart.lowerBound, offsetBy: 4)
                if let end = html.range(of: "-->", range: afterOpen..<html.endIndex) {
                    index = end.upperBound
                    continue
                }
                index = html.endIndex
                continue
            }

            guard let tagEnd = html.range(of: ">", range: tagStart.upperBound..<html.endIndex) else {
                break
            }
            let tagBody = String(html[tagStart.upperBound..<tagEnd.lowerBound])
            let tagName = Self.tagName(fromTagBody: tagBody)

            // script/style/svg/noscript: ข้ามทั้งบล็อก
            if Self.skipTags.contains(tagName), !tagBody.hasPrefix("/") {
                let closeTag = "</\(tagName)"
                if let closeRange = html.range(of: closeTag, options: .caseInsensitive, range: tagEnd.upperBound..<html.endIndex),
                   let closeEnd = html.range(of: ">", range: closeRange.upperBound..<html.endIndex) {
                    index = closeEnd.upperBound
                    continue
                }
                index = html.endIndex
                continue
            }

            if Self.blockTags.contains(tagName) {
                output.append("\n")
            }

            index = tagEnd.upperBound
        }

        var text = decodeEntities(output)
        text = collapseWhitespace(text)

        if text.count > maxCharacters {
            text = String(text.prefix(maxCharacters)) +
                "\n\n… (ตัดทอนหน้าเว็บ: แสดง \(maxCharacters) ตัวอักษรแรก)"
        }
        return text
    }

    /// แท็กที่ไม่ต้องเอาเนื้อหาข้างในเลย
    private static let skipTags: Set<String> = ["script", "style", "svg", "noscript", "template", "head"]

    /// ดึงชื่อแท็กจากเนื้อในวงเล็บแหลม (<a href="x"> → "a")
    private static func tagName(fromTagBody body: String) -> String {
        var name = ""
        for character in body {
            if character == "/" && name.isEmpty {
                continue // ปิดแท็ก: ข้าม "/" ตัวแรก
            }
            if character.isLetter || character.isNumber || character == "-" {
                name.append(character)
            } else {
                break
            }
        }
        return name.lowercased()
    }

    /// ถอด HTML entity ที่พบบ่อย
    static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        let replacements: [(String, String)] = [
            ("&nbsp;", " "),
            ("&amp;", "&"),
            ("&lt;", "<"),
            ("&gt;", ">"),
            ("&quot;", "\""),
            ("&#39;", "'"),
            ("&apos;", "'"),
            ("&hellip;", "…"),
            ("&mdash;", "—"),
            ("&ndash;", "–"),
            ("&laquo;", "«"),
            ("&raquo;", "»"),
            ("&euro;", "€"),
            ("&pound;", "£"),
            ("&copy;", "©"),
            ("&middot;", "·"),
            ("&bull;", "•"),
            ("&rsquo;", "’"),
            ("&lsquo;", "‘"),
            ("&ldquo;", "“"),
            ("&rdquo;", "”")
        ]
        var result = text
        for (entity, value) in replacements {
            result = result.replacingOccurrences(of: entity, with: value)
        }
        // เลข entity แบบ &#8230; / &#x2026;
        result = decodeNumericEntities(result)
        return result
    }

    /// ถอด entity แบบตัวเลข (ทั้งฐานสิบและฐานสิบหก) โดยไม่ใช้ regex
    private static func decodeNumericEntities(_ text: String) -> String {
        guard text.contains("&#") else { return text }
        var output = ""
        let characters = Array(text)
        var index = 0
        while index < characters.count {
            if characters[index] == "&", index + 2 < characters.count, characters[index + 1] == "#" {
                var cursor = index + 2
                var isHex = false
                if cursor < characters.count, characters[cursor] == "x" || characters[cursor] == "X" {
                    isHex = true
                    cursor += 1
                }
                var digits = ""
                while cursor < characters.count, characters[cursor] != ";", digits.count < 8 {
                    digits.append(characters[cursor])
                    cursor += 1
                }
                if cursor < characters.count, characters[cursor] == ";", !digits.isEmpty {
                    let radix = isHex ? 16 : 10
                    if let value = UInt32(digits, radix: radix), let scalar = Unicode.Scalar(value) {
                        output.unicodeScalars.append(scalar)
                        index = cursor + 1
                        continue
                    }
                }
            }
            output.append(characters[index])
            index += 1
        }
        return output
    }

    /// ยุบช่องว่างซ้ำและบรรทัดว่างเกิน
    static func collapseWhitespace(_ text: String) -> String {
        var lines: [String] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let collapsed = line.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\r" })
                .joined(separator: " ")
            lines.append(collapsed)
        }

        var result: [String] = []
        var previousWasEmpty = false
        for line in lines {
            let isEmpty = line.isEmpty
            if isEmpty && previousWasEmpty { continue }
            result.append(line)
            previousWasEmpty = isEmpty
        }
        return result.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - อ่านผลการค้นหาของ DuckDuckGo (หน้า HTML ไม่ต้องใช้ API Key)

enum DuckDuckGoParser {

    /// อ่านผลลัพธ์จากหน้า html.duckduckgo.com/html
    static func parse(html: String, limit: Int = 8) -> [WebSearchResult] {
        var results: [WebSearchResult] = []
        var pendingTitle: String?
        var pendingURL: String?

        // เดินผ่านแท็ก <a ...> ทีละตัว แล้วดูว่าคลาสเป็นผลการค้นหาหรือคำอธิบาย
        for anchor in anchors(inHTML: html) {
            let classes = anchor.classAttribute
            let content = anchor.innerText

            if classes.contains("result__a") {
                // เริ่มผลลัพธ์ใหม่
                if let title = pendingTitle, let url = pendingURL, !title.isEmpty {
                    results.append(WebSearchResult(title: title, url: url, snippet: ""))
                    if results.count >= limit { return results }
                }
                pendingTitle = content
                pendingURL = resolveRedirect(anchor.href)
            } else if classes.contains("result__snippet") {
                if let title = pendingTitle, let url = pendingURL, !title.isEmpty {
                    results.append(WebSearchResult(title: title, url: url, snippet: content))
                    pendingTitle = nil
                    pendingURL = nil
                    if results.count >= limit { return results }
                }
            }
        }

        if let title = pendingTitle, let url = pendingURL, !title.isEmpty, results.count < limit {
            results.append(WebSearchResult(title: title, url: url, snippet: ""))
        }

        return results
    }

    /// แปลงลิงก์ของ DuckDuckGo (/l/?uddg=<encoded>) ให้เป็น URL จริง
    ///
    /// ใช้การค้นหา "uddg=" ในสตริงโดยตรง (แทนการพึ่ง URLComponents)
    /// เพราะ URLComponents ล้มเหลวได้เมื่อลิงก์มีอักขระที่ไม่ใช่ ASCII และพฤติกรรมต่างกันในแต่ละแพลตฟอร์ม
    static func resolveRedirect(_ href: String) -> String {
        var value = href.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("//") {
            value = "https:" + value
        }
        guard value.lowercased().contains("uddg=") else {
            return value
        }

        guard let range = value.range(of: "uddg=") else { return value }
        var encoded = String(value[range.upperBound...])
        if let end = encoded.firstIndex(where: { $0 == "&" || $0 == "#" }) {
            encoded = String(encoded[encoded.startIndex..<end])
        }
        let decoded = encoded.removingPercentEncoding ?? encoded
        let cleaned = HTMLTextExtractor.decodeEntities(decoded).trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? value : cleaned
    }

    // MARK: ตัวช่วยแยกแท็ก <a>

    private struct Anchor {
        let href: String
        let classAttribute: String
        let innerText: String
    }

    private static func anchors(inHTML html: String) -> [Anchor] {
        var list: [Anchor] = []
        var searchStart = html.startIndex

        while let openRange = html.range(of: "<a ", options: .caseInsensitive, range: searchStart..<html.endIndex) {
            guard let openEnd = html.range(of: ">", range: openRange.upperBound..<html.endIndex) else { break }
            let attributes = String(html[openRange.upperBound..<openEnd.lowerBound])

            guard let closeRange = html.range(of: "</a", options: .caseInsensitive, range: openEnd.upperBound..<html.endIndex) else { break }
            let inner = String(html[openEnd.upperBound..<closeRange.lowerBound])

            let href = attributeValue(named: "href", in: attributes) ?? ""
            let classValue = attributeValue(named: "class", in: attributes) ?? ""
            let text = HTMLTextExtractor.collapseWhitespace(
                HTMLTextExtractor.decodeEntities(HTMLTextExtractor.plainText(fromHTML: inner))
            )

            list.append(Anchor(href: href, classAttribute: classValue, innerText: text))
            if list.count > 400 { break }
            searchStart = closeRange.upperBound
        }

        return list
    }

    /// อ่านค่าของ attribute จากข้อความในแท็ก (รองรับทั้ง " และ ')
    private static func attributeValue(named name: String, in attributes: String) -> String? {
        var searchStart = attributes.startIndex
        while let range = attributes.range(of: name, options: .caseInsensitive, range: searchStart..<attributes.endIndex) {
            // ต้องเป็นชื่อ attribute เต็ม (ตัวถัดไปต้องเป็น = หรือช่องว่าง)
            let afterName = range.upperBound
            if afterName < attributes.endIndex {
                let next = attributes[afterName]
                if next == "=" || next == " " {
                    var cursor = afterName
                    while cursor < attributes.endIndex, attributes[cursor] == " " {
                        cursor = attributes.index(after: cursor)
                    }
                    if cursor < attributes.endIndex, attributes[cursor] == "=" {
                        cursor = attributes.index(after: cursor)
                        while cursor < attributes.endIndex, attributes[cursor] == " " {
                            cursor = attributes.index(after: cursor)
                        }
                        if cursor < attributes.endIndex {
                            let quote = attributes[cursor]
                            if quote == "\"" || quote == "'" {
                                let valueStart = attributes.index(after: cursor)
                                if let valueEnd = attributes[valueStart...].firstIndex(of: quote) {
                                    return String(attributes[valueStart..<valueEnd])
                                }
                            } else {
                                var value = ""
                                var scan = cursor
                                while scan < attributes.endIndex, attributes[scan] != " " {
                                    value.append(attributes[scan])
                                    scan = attributes.index(after: scan)
                                }
                                if !value.isEmpty { return value }
                            }
                        }
                    }
                }
            }
            searchStart = range.upperBound
        }
        return nil
    }
}
