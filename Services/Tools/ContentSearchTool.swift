//
//  ContentSearchTool.swift
//  iOS Agent Sandbox
//
//  tool ใหม่ของเฟส 6: search_content — ค้นหา "ข้อความในไฟล์" ด้วย regex พร้อมเลขบรรทัด
//
//  ต่างจาก search_files (เฟส 2) ที่ค้นจาก "ชื่อไฟล์" — ตัวนี้ค้นจาก "เนื้อหาข้างใน"
//  จึงใช้ตอบคำถามแบบ "ไฟล์ไหนมีคำนี้อยู่" ได้จริงบนเครื่องที่ไม่ติดตั้ง grep/ripgrep
//
//  กฎหน่วยความจำ (RAM 2GB): อ่านไฟล์ละไม่เกิน 128 KB และเดินสำรวจไม่เกินจำนวนไฟล์ที่กำหนด
//  Foundation-only (NSRegularExpression มีบน Linux/macOS) → ทดสอบได้ทุกแพลตฟอร์ม
//

import Foundation

struct SearchContentTool: AgentTool {

    let descriptor = ToolDescriptor(name: "search_content",
                                    thaiLabel: "ค้นหาข้อความในไฟล์",
                                    summary: "ค้นหาข้อความข้างในไฟล์ด้วย regex พร้อมเลขบรรทัดและชื่อไฟล์",
                                    category: .fileSystem,
                                    alwaysRequiresApproval: false)

    /// เพดานการอ่านต่อไฟล์ (ไบต์) — ไม่โหลดไฟล์ใหญ่เข้าหน่วยความจำ
    static let perFileReadBytes = 128 * 1024
    /// เพดานจำนวนไฟล์ที่เปิดอ่านต่อการเรียกหนึ่งครั้ง
    static let maximumFilesScanned = 2_000
    /// เพดานจำนวนรายการที่เดินสำรวจทั้งหมด
    static let maximumVisitedEntries = 20_000
    /// ความยาวสูงสุดของบรรทัดที่จะส่งกลับ
    static let maximumLineCharacters = 200

    var definition: ToolDefinition {
        ToolDefinition(
            name: descriptor.name,
            description: "ค้นหาข้อความภายในไฟล์ข้อความ (รองรับ regex) เริ่มจากโฟลเดอร์ที่ระบุ แล้วไล่ลงไปตามความลึก " +
                "คืนผลลัพธ์เป็น path:บรรทัดที่ N: ข้อความ — ใช้เมื่อต้องรู้ว่า 'ไฟล์ไหนมีข้อความ/โค้ดนี้' " +
                "ถ้าต้องการค้นจากชื่อไฟล์ ให้ใช้ search_files แทน",
            parameters: .object([
                ("type", .string("object")),
                ("properties", .object([
                    ("pattern", .object([
                        ("type", .string("string")),
                        ("description", .string("ข้อความหรือ regex ที่ต้องการค้นหา เช่น \"func login\" หรือ \"หมายเหตุ|แก้ทีหลัง\""))
                    ])),
                    ("path", .object([
                        ("type", .string("string")),
                        ("description", .string("โฟลเดอร์เริ่มต้นในการค้นหา (ค่าเริ่มต้น \(PathGuard.defaultWorkspace))"))
                    ])),
                    ("extensions", .object([
                        ("type", .string("string")),
                        ("description", .string("จำกัดชนิดไฟล์ เช่น swift,txt,json (คั่นด้วย , — ไม่ใส่ = ค้นทุกไฟล์ข้อความ)"))
                    ])),
                    ("max_results", .object([
                        ("type", .string("integer")),
                        ("description", .string("จำนวนผลลัพธ์สูงสุด (ค่าเริ่มต้น 40, สูงสุด 120)"))
                    ])),
                    ("max_depth", .object([
                        ("type", .string("integer")),
                        ("description", .string("ความลึกของโฟลเดอร์สูงสุด (ค่าเริ่มต้น 6, สูงสุด 12)"))
                    ])),
                    ("case_sensitive", .object([
                        ("type", .string("boolean")),
                        ("description", .string("true = แยกตัวพิมพ์เล็ก/ใหญ่ (ค่าเริ่มต้น false)"))
                    ]))
                ])),
                ("required", .array([.string("pattern")]))
            ])
        )
    }

    func execute(arguments: [String: JSONValue], context: ToolExecutionContext) async -> ToolExecutionResult {
        let args = ToolArguments(arguments)

        let pattern: String
        do {
            pattern = try args.string("pattern")
        } catch {
            return ToolResults.invalidArguments(error.localizedDescription)
        }

        guard !pattern.isEmpty, pattern.count <= 200 else {
            return .failure(.invalidArguments, "รูปแบบการค้นหาต้องยาว 1–200 ตัวอักษร")
        }

        let caseSensitive = args.bool("case_sensitive", default: false)
        let regex: NSRegularExpression
        do {
            regex = try ContentSearchSupport.makeRegex(pattern: pattern, caseSensitive: caseSensitive)
        } catch {
            return .failure(.invalidArguments,
                            "รูปแบบ regex ไม่ถูกต้อง: \(pattern)\n" +
                            "ถ้าต้องการค้นข้อความธรรมดา ให้หลีกอักขระพิเศษ เช่น \\\\( \\\\) \\\\. \\\\[ \\\\]")
        }

        let rawPath = args.optionalString("path") ?? context.workspacePath
        let root = PathGuard.normalize(rawPath, workspace: context.workspacePath)
        let rootDisplay = PathGuard.displayPath(root, workspace: context.workspacePath)

        guard FileSystemService.isDirectory(root) == true else {
            return .failure(.notFound, "ไม่พบโฟลเดอร์เริ่มต้น: \(rootDisplay)")
        }

        let maxResults = args.intInRange("max_results", default: 40, min: 1, max: 120)
        let maxDepth = args.intInRange("max_depth", default: 6, min: 1, max: 12)
        let extensions = ContentSearchSupport.normalizeExtensions(args.optionalString("extensions"))

        var results: [String] = []
        var visited = 0
        var filesScanned = 0
        var hitVisitLimit = false
        var hitFileLimit = false
        var queue: [(path: String, depth: Int)] = [(root, 0)]

        while !queue.isEmpty {
            if Task.isCancelled {
                return .failure(.cancelled, "การค้นหาถูกยกเลิก")
            }
            let current = queue.removeFirst()
            if current.depth > maxDepth { continue }

            let listing: (entries: [FileEntry], totalCount: Int, skippedHidden: Int)
            do {
                listing = try FileSystemService.list(current.path, includeHidden: false, limit: 400)
            } catch {
                continue   // ข้ามโฟลเดอร์ที่อ่านไม่ได้ (เช่น โฟลเดอร์ของแอปอื่น)
            }

            for entry in listing.entries {
                if Task.isCancelled {
                    return .failure(.cancelled, "การค้นหาถูกยกเลิก")
                }
                visited += 1
                if visited > SearchContentTool.maximumVisitedEntries {
                    hitVisitLimit = true
                    break
                }

                if entry.isDirectory {
                    if current.depth < maxDepth {
                        queue.append((entry.path, current.depth + 1))
                    }
                    continue
                }

                if entry.isSymbolicLink { continue }
                if !ContentSearchSupport.matchesExtensions(fileName: entry.name, extensions: extensions) { continue }
                if entry.sizeBytes > Int64(SearchContentTool.perFileReadBytes) { continue }

                filesScanned += 1
                if filesScanned > SearchContentTool.maximumFilesScanned {
                    hitFileLimit = true
                    break
                }

                guard let lines = ContentSearchSupport.readSearchableLines(path: entry.path,
                                                                           limitBytes: SearchContentTool.perFileReadBytes) else {
                    continue
                }

                let displayPath = PathGuard.displayPath(entry.path, workspace: context.workspacePath)
                for hit in ContentSearchSupport.matches(regex: regex,
                                                        lines: lines,
                                                        fileName: entry.name,
                                                        maximumLineCharacters: SearchContentTool.maximumLineCharacters) {
                    results.append("\(displayPath):\(hit.lineNumber): \(hit.lineText)")
                    if results.count >= maxResults { break }
                }
                if results.count >= maxResults { break }
            }

            if results.count >= maxResults || hitVisitLimit || hitFileLimit { break }
        }

        if results.isEmpty {
            var message = "ไม่พบข้อความที่ค้นใน \(rootDisplay)"
            if !extensions.isEmpty {
                message += " (จำกัดชนิดไฟล์: \(extensions.sorted().joined(separator: ", ")))"
            }
            message += "\nคำแนะนำ: ลองลดความเฉพาะเจาะจงของคำค้น หรือใช้ search_files เพื่อหาชื่อไฟล์ก่อน"
            return .short(message)
        }

        var summary = "พบ \(results.count) จุดใน \(rootDisplay)"
        if results.count >= maxResults {
            summary += " (ถึงเพดานผลลัพธ์แล้ว — อาจมีมากกว่านี้)"
        }
        summary += "\n\n" + results.joined(separator: "\n")

        if hitVisitLimit || hitFileLimit {
            summary += "\n\n(หยุดสแกนเพราะถึงเพดานจำนวนไฟล์ — ถ้าต้องการละเอียดขึ้น ให้ระบุ path หรือ extensions ให้แคบลง)"
        }
        return .ok(summary)
    }
}

// MARK: - ตรรกะการค้นหา (แยกออกมาให้ทดสอบได้โดยไม่ต้องแตะดิสก์)

enum ContentSearchSupport {

    struct LineHit: Equatable {
        let lineNumber: Int
        let lineText: String
    }

    /// สร้าง regex โดยค่าเริ่มต้นไม่แยกตัวพิมพ์เล็ก/ใหญ่
    static func makeRegex(pattern: String, caseSensitive: Bool) throws -> NSRegularExpression {
        var options: NSRegularExpression.Options = [.dotMatchesLineSeparators]
        if !caseSensitive {
            options.insert(.caseInsensitive)
        }
        return try NSRegularExpression(pattern: pattern, options: options)
    }

    /// แปลง "swift, txt" → ["swift", "txt"] (ตัวพิมพ์เล็ก, ตัดค่าว่าง)
    static func normalizeExtensions(_ raw: String?) -> Set<String> {
        guard let raw = raw, !raw.isEmpty else { return [] }
        let parts = raw
            .replacingOccurrences(of: " ", with: "")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased() }
            .filter { !$0.isEmpty && $0.count <= 12 }
        return Set(parts)
    }

    /// true = ไฟล์นี้ควรถูกค้น (ไม่มีตัวกรอง = ใช้ได้ทุกไฟล์)
    static func matchesExtensions(fileName: String, extensions: Set<String>) -> Bool {
        guard !extensions.isEmpty else { return true }
        let ext = (fileName as NSString).pathExtension.lowercased()
        return extensions.contains(ext)
    }

    /// อ่านไฟล์แบบจำกัดขนาด แล้วคืนบรรทัดสำหรับค้นหา (nil = อ่านไม่ได้/ไม่ใช่ข้อความ)
    static func readSearchableLines(path: String, limitBytes: Int) -> [(number: Int, text: String)]? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }

        let data: Data
        do {
            data = try handle.read(upToCount: limitBytes) ?? Data()
        } catch {
            return nil
        }
        guard !data.isEmpty else { return [] }

        // ตรวจไบนารีแบบเร็ว: ถ้ามีไบต์ 0 อยู่ในช่วงต้น ถือว่าไม่ใช่ข้อความ
        if data.prefix(2048).contains(0) { return nil }
        guard let text = String(data: data, encoding: .utf8) else { return nil }

        var lines: [(Int, String)] = []
        var number = 1
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            lines.append((number, String(line)))
            number += 1
            if number > 20_000 { break }
        }
        return lines
    }

    /// หาเฉพาะบรรทัดที่ตรง regex (ไม่คืนทั้งไฟล์)
    static func matches(regex: NSRegularExpression,
                        lines: [(number: Int, text: String)],
                        fileName: String,
                        maximumLineCharacters: Int) -> [LineHit] {
        var hits: [LineHit] = []
        for line in lines {
            let text = line.text
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            guard regex.firstMatch(in: text, options: [], range: range) != nil else { continue }

            let trimmed = text.trimmingCharacters(in: .whitespaces)
            let shown = trimmed.count <= maximumLineCharacters
                ? trimmed
                : String(trimmed.prefix(maximumLineCharacters)) + "…"
            hits.append(LineHit(lineNumber: line.number, lineText: shown))
            if hits.count >= 50 { break }   // กันไฟล์เดียวที่มีผลลัพธ์พรืด
        }
        return hits
    }
}
