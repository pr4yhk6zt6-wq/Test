//
//  FileEditTools.swift
//  iOS Agent Sandbox
//
//  tools จัดการไฟล์ของเฟส 6: edit_file, move_file, copy_file, delete_file, create_directory
//
//  เป้าหมาย: ให้ Agent "แก้ไฟล์เดิมได้จริง" แบบประหยัดโทเคน (ค้นหา-แทนที่เฉพาะจุด)
//  แทนการเขียนทับทั้งไฟล์ด้วย write_file และจัดการโฟลเดอร์ได้ครบโดยไม่ต้องพึ่ง shell
//
//  ความปลอดภัย:
//  - ทุกการเขียน/ลบ/ย้าย ผ่านกฎเดียวกับ write_file: path ที่ต้องป้องกัน → ต้องอนุมัติก่อน
//  - การลบและการเขียนทับไฟล์ที่มีอยู่ = ต้องอนุมัติ (ระดับ elevated/destructive)
//  - edit_file ต้องเจอข้อความเป้าหมาย "ไม่ซ้ำ" ก่อนแก้ ถ้าซ้ำต้องสั่ง replace_all ชัดเจน
//
//  Foundation-only → รัน unit test/E2E ได้ทุกแพลตฟอร์ม (ไม่แตะ UIKit)
//

import Foundation

// MARK: - ตัวช่วยที่ใช้ร่วมกันในไฟล์นี้

enum FileOpSupport {

    /// เพดานขนาดไฟล์ที่ยอมให้แก้แบบแทนที่ข้อความ (ไบต์) — เครื่อง RAM 2GB อ่านทั้งไฟล์ได้ไม่มาก
    static let maximumEditableBytes = 512 * 1024

    /// ตัดข้อความยาวสำหรับแสดงตัวอย่างในหน้าอนุมัติ/ผลลัพธ์
    static func preview(_ text: String, limit: Int = 220) -> String {
        let flattened = text.replacingOccurrences(of: "\r\n", with: "\n")
        let single = flattened.replacingOccurrences(of: "\n", with: "⏎")
        if single.count <= limit { return single }
        return String(single.prefix(limit)) + "…"
    }

    /// ตัดข้อความของ argument สำหรับหน้าอนุมัติ (เผื่อข้อความที่มีอักขระขึ้นบรรทัดใหม่)
    static func fence(_ text: String, limit: Int = 160) -> String {
        let single = text.replacingOccurrences(of: "\n", with: "␊")
        if single.count <= limit { return single }
        return String(single.prefix(limit)) + "…"
    }

    /// ตรวจสิทธิ์เขียนแบบเดียวกับ write_file
    /// คืนข้อความอธิบายถ้าต้องขออนุมัติก่อน (nil = เขียนได้เลย)
    static func writeGate(path: String, context: ToolExecutionContext) -> String? {
        guard let reason = PathGuard.protectionReason(for: path, workspace: context.workspacePath),
              !context.isApproved else {
            return nil
        }
        return "ต้องขออนุมัติก่อนแก้ไฟล์นี้: \(reason)\n" +
            "ให้ผู้ใช้อนุมัติในแอปแล้วเรียก tool นี้อีกครั้ง (หรือทำงานใน \(PathGuard.displayPath(context.workspacePath, workspace: context.workspacePath)))"
    }
}

// MARK: - แก้ไฟล์แบบค้นหา-แทนที่

struct EditFileTool: AgentTool {

    let descriptor = ToolDescriptor(name: "edit_file",
                                    thaiLabel: "แก้ไฟล์ (ค้นหา-แทนที่)",
                                    summary: "แก้ไฟล์เดิมเฉพาะจุดด้วยการค้นหา-แทนที่ข้อความ (ประหยัดโทเคนกว่าเขียนทับทั้งไฟล์)",
                                    category: .fileSystem,
                                    alwaysRequiresApproval: false)

    /// เพดานจำนวนจุดที่แทนที่ได้ในการเรียกครั้งเดียว (กันการแก้พลาดเป็นวงกว้าง)
    static let maximumReplacements = 200

    var definition: ToolDefinition {
        ToolDefinition(
            name: descriptor.name,
            description: "แก้ไฟล์ข้อความบนเครื่องโดยค้นหาข้อความเดิม (find) แล้วแทนที่ด้วยข้อความใหม่ (replace) " +
                "ใช้เมื่อต้องการแก้ไฟล์ที่มีอยู่แล้ว เช่น แก้โค้ด แก้ค่าใน config หรือแก้ข้อความ — ประหยัดกว่า write_file เพราะไม่ต้องส่งเนื้อหาทั้งไฟล์ " +
                "ถ้าข้อความที่ค้นพบซ้ำมากกว่า 1 จุด จะไม่แก้ให้ (กันแก้ผิดที่) จนกว่าจะตั้ง replace_all = true " +
                "ไฟล์ที่ใหญ่กว่า 512 KB ต้องใช้เครื่องมืออื่น (เช่น shell) แทน",
            parameters: .object([
                ("type", .string("object")),
                ("properties", .object([
                    ("path", .object([
                        ("type", .string("string")),
                        ("description", .string("path ของไฟล์ที่จะแก้ (absolute หรือสัมพัทธ์กับ workspace)"))
                    ])),
                    ("find", .object([
                        ("type", .string("string")),
                        ("description", .string("ข้อความเดิมที่ต้องการค้นหา (ต้องตรงทั้งข้อความ รวมช่องว่าง/ขึ้นบรรทัดใหม่)"))
                    ])),
                    ("replace", .object([
                        ("type", .string("string")),
                        ("description", .string("ข้อความใหม่ที่จะใส่แทน (ใส่ค่าว่างได้ = ลบข้อความนั้น)"))
                    ])),
                    ("replace_all", .object([
                        ("type", .string("boolean")),
                        ("description", .string("true = แทนที่ทุกจุดที่พบ (ค่าเริ่มต้น false = ต้องเจอไม่ซ้ำเท่านั้น)"))
                    ])),
                    ("expected_count", .object([
                        ("type", .string("integer")),
                        ("description", .string("จำนวนจุดที่คาดว่าจะแก้ (ถ้าไม่ตรงกับที่พบจริง จะไม่แก้ให้ — ใช้กันพลาด)"))
                    ]))
                ])),
                ("required", .array([.string("path"), .string("find"), .string("replace")]))
            ])
        )
    }

    func execute(arguments: [String: JSONValue], context: ToolExecutionContext) async -> ToolExecutionResult {
        let args = ToolArguments(arguments)

        let rawPath: String
        let find: String
        let replace: String
        do {
            rawPath = try args.string("path")
            find = try args.string("find")
            replace = try args.string("replace")
        } catch {
            return ToolResults.invalidArguments(error.localizedDescription)
        }

        guard !find.isEmpty else {
            return .failure(.invalidArguments, "ข้อความค้นหา (find) ต้องไม่ว่าง")
        }
        guard find != replace else {
            return .failure(.invalidArguments, "ข้อความใหม่เหมือนข้อความเดิม — ไม่มีอะไรต้องแก้")
        }

        let path = PathGuard.normalize(rawPath, workspace: context.workspacePath)
        let display = PathGuard.displayPath(path, workspace: context.workspacePath)
        let replaceAll = args.bool("replace_all", default: false)
        let expectedCount = args.optionalInt("expected_count")

        if let gate = FileOpSupport.writeGate(path: path, context: context) {
            return .failure(.blocked, gate)
        }

        guard FileSystemService.exists(path) else {
            return .failure(.notFound, "ไม่พบไฟล์: \(display)")
        }
        if FileSystemService.isDirectory(path) == true {
            return .failure(.invalidArguments, "\(display) เป็นโฟลเดอร์ — edit_file ใช้กับไฟล์ข้อความเท่านั้น")
        }

        let data: Data
        do {
            data = try FileSystemService.readAll(path, limitBytes: FileOpSupport.maximumEditableBytes)
        } catch {
            let mapped = ToolErrorMapper.describe(error, path: display)
            if mapped.kind == .tooLarge {
                return .failure(.tooLarge,
                                "ไฟล์ใหญ่เกิน \(NetworkPolicy.formatBytes(Int64(FileOpSupport.maximumEditableBytes))) — " +
                                "แก้ไฟล์นี้ด้วย write_file หรือคำสั่ง shell แทน")
            }
            return .failure(mapped.kind, mapped.message)
        }

        guard let original = String(data: data, encoding: .utf8) else {
            return .failure(.failed, "ไฟล์นี้ไม่ใช่ข้อความ UTF-8 — edit_file ใช้กับไฟล์ข้อความเท่านั้น")
        }

        let occurrences = EditFileSupport.occurrenceCount(of: find, in: original)
        guard occurrences > 0 else {
            return .failure(.notFound,
                            "ไม่พบข้อความที่ต้องการแทนที่ใน \(display)\n" +
                            "ข้อความที่ค้นหา: \(FileOpSupport.preview(find))\n" +
                            "คำแนะนำ: เปิดอ่านไฟล์ด้วย read_file เพื่อคัดลอกข้อความให้ตรงเป๊ะ (รวมช่องว่าง)")
        }

        if let expected = expectedCount, expected != occurrences {
            return .failure(.invalidArguments,
                            "พบข้อความตรงกัน \(occurrences) จุด แต่ระบุ expected_count = \(expected) — ไม่แก้ให้เพื่อความปลอดภัย")
        }

        if occurrences > 1, !replaceAll {
            return .failure(.invalidArguments,
                            "พบข้อความตรงกัน \(occurrences) จุด (ต้องมีบริบทมากกว่านี้)\n" +
                            "คำแนะนำ: ใส่ข้อความค้นหาให้ยาวขึ้น/มีบรรทัดรอบข้างเพื่อให้เจอจุดเดียว หรือตั้ง replace_all = true ถ้าตั้งใจแก้ทุกจุด")
        }

        if occurrences > EditFileTool.maximumReplacements {
            return .failure(.blocked,
                            "พบข้อความตรงกัน \(occurrences) จุด ซึ่งเกินเพดาน \(EditFileTool.maximumReplacements) จุดต่อครั้ง — แบ่งแก้เป็นหลายรอบ")
        }

        let updated = replaceAll
            ? original.replacingOccurrences(of: find, with: replace)
            : EditFileSupport.replacingFirstOccurrence(of: find, with: replace, in: original)

        guard updated != original else {
            return .failure(.failed, "ไม่มีอะไรเปลี่ยนแปลงหลังแทนที่ข้อความ")
        }

        do {
            let report = try FileSystemService.write(updated,
                                                     to: path,
                                                     append: false,
                                                     createDirectories: false,
                                                     maximumBytes: FileOpSupport.maximumEditableBytes)
            var message = "สำเร็จ: แก้ \(occurrences) จุดใน \(display)\n" +
                "ขนาดใหม่: \(NetworkPolicy.formatBytes(report.finalSizeBytes))"
            if let contextLine = EditFileSupport.changedLinePreview(before: original, after: updated) {
                message += "\nบรรทัดที่เปลี่ยน: \(contextLine)"
            }
            return .ok(message)
        } catch {
            let mapped = ToolErrorMapper.describe(error, path: display)
            return .failure(mapped.kind, mapped.message)
        }
    }

    func assessRisk(arguments: [String: JSONValue], workspace: String) -> RiskAssessment {
        let args = ToolArguments(arguments)
        guard let rawPath = args.optionalString("path") else { return .safe }
        let path = PathGuard.normalize(rawPath, workspace: workspace)

        var assessment = RiskyCommandDetector.assessWrite(path: path, workspace: workspace)
        if assessment.level == .normal, FileManager.default.fileExists(atPath: path) {
            assessment = RiskAssessment(level: .elevated,
                                        reasons: ["แก้ไฟล์ที่มีอยู่แล้ว (ค้นหา-แทนที่) — เนื้อหาในไฟล์จะเปลี่ยน"])
        }
        return assessment
    }

    func approvalDetail(arguments: [String: JSONValue]) async -> String? {
        let args = ToolArguments(arguments)
        guard let rawPath = args.optionalString("path"),
              let find = args.optionalString("find"),
              let replace = args.optionalString("replace") else { return nil }

        let replaceAll = args.bool("replace_all", default: false)
        return "ไฟล์: \(rawPath)\n" +
            "ค้นหา: \(FileOpSupport.fence(find))\n" +
            "แทนที่ด้วย: \(replace.isEmpty ? "(ลบข้อความนั้น)" : FileOpSupport.fence(replace))\n" +
            "ขอบเขต: \(replaceAll ? "ทุกจุดที่พบ" : "จุดเดียว (ต้องไม่ซ้ำ)")"
    }
}

// MARK: - ตรรกะการแทนที่ข้อความ (แยกออกมาให้ทดสอบได้ตรง ๆ)

enum EditFileSupport {

    /// นับจำนวนจุดที่ข้อความเป้าหมายปรากฏ (ไม่ทับซ้อนกัน)
    static func occurrenceCount(of needle: String, in haystack: String) -> Int {
        guard !needle.isEmpty else { return 0 }
        var count = 0
        var searchStart = haystack.startIndex
        while let range = haystack.range(of: needle, range: searchStart..<haystack.endIndex) {
            count += 1
            searchStart = range.upperBound
            if count > 10_000 { break }   // กันวนไม่จบบนไฟล์แปลก
        }
        return count
    }

    /// แทนที่เฉพาะจุดแรก
    static func replacingFirstOccurrence(of needle: String, with replacement: String, in haystack: String) -> String {
        guard let range = haystack.range(of: needle) else { return haystack }
        return haystack.replacingCharacters(in: range, with: replacement)
    }

    /// หาบรรทัดแรกที่เปลี่ยน เพื่อบอกโมเดล/ผู้ใช้ว่าแตะตรงไหน (ไม่ส่งทั้งไฟล์กลับ)
    static func changedLinePreview(before: String, after: String, limit: Int = 200) -> String? {
        let beforeLines = before.split(separator: "\n", omittingEmptySubsequences: false)
        let afterLines = after.split(separator: "\n", omittingEmptySubsequences: false)

        let shared = min(beforeLines.count, afterLines.count)
        var index = 0
        while index < shared, beforeLines[index] == afterLines[index] {
            index += 1
        }
        guard index < afterLines.count || index < beforeLines.count else { return nil }

        let lineNumber = min(index + 1, max(afterLines.count, 1))
        let lineText = index < afterLines.count ? String(afterLines[index]) : "(บรรทัดถูกลบ)"
        let trimmed = lineText.trimmingCharacters(in: .whitespaces)
        let shown = trimmed.count <= limit ? trimmed : String(trimmed.prefix(limit)) + "…"
        return "บรรทัดที่ \(lineNumber): \(shown)"
    }
}

// MARK: - ย้ายไฟล์

struct MoveFileTool: AgentTool {

    let descriptor = ToolDescriptor(name: "move_file",
                                    thaiLabel: "ย้าย/เปลี่ยนชื่อไฟล์",
                                    summary: "ย้ายหรือเปลี่ยนชื่อไฟล์/โฟลเดอร์ (ขออนุมัติเมื่อทับของเดิมหรือแตะไฟล์ระบบ)",
                                    category: .fileSystem,
                                    alwaysRequiresApproval: false)

    var definition: ToolDefinition {
        ToolDefinition(
            name: descriptor.name,
            description: "ย้ายไฟล์หรือโฟลเดอร์จาก source ไป destination (ใช้เปลี่ยนชื่อไฟล์ก็ได้) " +
                "ถ้าปลายทางมีอยู่แล้วจะไม่ทับให้ จนกว่าจะตั้ง overwrite = true (และผู้ใช้อนุมัติ)",
            parameters: .object([
                ("type", .string("object")),
                ("properties", .object([
                    ("source", .object([
                        ("type", .string("string")),
                        ("description", .string("path ต้นทาง (absolute หรือสัมพัทธ์กับ workspace)"))
                    ])),
                    ("destination", .object([
                        ("type", .string("string")),
                        ("description", .string("path ปลายทาง (รวมชื่อไฟล์ใหม่)"))
                    ])),
                    ("overwrite", .object([
                        ("type", .string("boolean")),
                        ("description", .string("true = ยอมเขียนทับถ้าปลายทางมีอยู่ (ต้องอนุมัติ)"))
                    ]))
                ])),
                ("required", .array([.string("source"), .string("destination")]))
            ])
        )
    }

    func execute(arguments: [String: JSONValue], context: ToolExecutionContext) async -> ToolExecutionResult {
        let args = ToolArguments(arguments)
        let rawSource: String
        let rawDestination: String
        do {
            rawSource = try args.string("source")
            rawDestination = try args.string("destination")
        } catch {
            return ToolResults.invalidArguments(error.localizedDescription)
        }

        let source = PathGuard.normalize(rawSource, workspace: context.workspacePath)
        let destination = PathGuard.normalize(rawDestination, workspace: context.workspacePath)
        let sourceDisplay = PathGuard.displayPath(source, workspace: context.workspacePath)
        let destinationDisplay = PathGuard.displayPath(destination, workspace: context.workspacePath)
        let overwrite = args.bool("overwrite", default: false)

        guard FileSystemService.exists(source) else {
            return .failure(.notFound, "ไม่พบต้นทาง: \(sourceDisplay)")
        }
        if let gate = FileOpSupport.writeGate(path: source, context: context) {
            return .failure(.blocked, gate)
        }

        let destinationExists = FileSystemService.exists(destination)
        if destinationExists, !overwrite {
            return .failure(.invalidArguments,
                            "ปลายทางมีอยู่แล้ว: \(destinationDisplay)\n" +
                            "ถ้าต้องการเขียนทับจริง ให้ตั้ง overwrite = true (ผู้ใช้จะถูกขออนุมัติ)")
        }
        if destinationExists {
            if let gate = FileOpSupport.writeGate(path: destination, context: context) {
                return .failure(.blocked, gate)
            }
            // การเขียนทับไฟล์/โฟลเดอร์เดิมคือความเสี่ยงระดับกลาง → ต้องอนุมัติเสมอเมื่อโหมดอนุมัติเปิด
            if !context.isApproved {
                return .failure(.blocked,
                                "ต้องขออนุมัติก่อนเขียนทับ \(destinationDisplay) — ให้ผู้ใช้อนุมัติแล้วเรียก tool นี้อีกครั้ง")
            }
        }

        do {
            try FileSystemService.move(source, to: destination, overwrite: overwrite)
            return .short("สำเร็จ: ย้าย \(sourceDisplay) → \(destinationDisplay)")
        } catch {
            let mapped = ToolErrorMapper.describe(error, path: destinationDisplay)
            return .failure(mapped.kind, mapped.message)
        }
    }

    func assessRisk(arguments: [String: JSONValue], workspace: String) -> RiskAssessment {
        let args = ToolArguments(arguments)
        guard let rawDestination = args.optionalString("destination"),
              let rawSource = args.optionalString("source") else { return .safe }
        let destination = PathGuard.normalize(rawDestination, workspace: workspace)
        let source = PathGuard.normalize(rawSource, workspace: workspace)

        var assessment = RiskyCommandDetector.assessWrite(path: destination, workspace: workspace)
        if assessment.level == .normal, FileManager.default.fileExists(atPath: destination) {
            assessment = RiskAssessment(level: .elevated,
                                        reasons: ["ปลายทางมีอยู่แล้ว — การย้ายจะเขียนทับข้อมูลเดิม"])
        }
        if assessment.level == .normal, !PathGuard.isWithinWorkspace(source, workspace: workspace) {
            assessment = RiskAssessment(level: .elevated,
                                        reasons: ["ย้ายไฟล์ที่อยู่นอกโฟลเดอร์ทำงาน"])
        }
        return assessment
    }

    func approvalDetail(arguments: [String: JSONValue]) async -> String? {
        let args = ToolArguments(arguments)
        guard let source = args.optionalString("source"),
              let destination = args.optionalString("destination") else { return nil }
        let overwrite = args.bool("overwrite", default: false)
        return "จาก: \(source)\nไป: \(destination)\n" +
            (overwrite ? "อนุญาตให้เขียนทับปลายทางที่มีอยู่" : "ไม่เขียนทับ (ถ้าปลายทางมีอยู่จะยกเลิก)")
    }
}

// MARK: - คัดลอกไฟล์

struct CopyFileTool: AgentTool {

    let descriptor = ToolDescriptor(name: "copy_file",
                                    thaiLabel: "คัดลอกไฟล์",
                                    summary: "คัดลอกไฟล์/โฟลเดอร์ไปที่ใหม่ (ขออนุมัติเมื่อทับของเดิม)",
                                    category: .fileSystem,
                                    alwaysRequiresApproval: false)

    var definition: ToolDefinition {
        ToolDefinition(
            name: descriptor.name,
            description: "คัดลอกไฟล์หรือโฟลเดอร์ (ต้นฉบับยังอยู่) — ใช้สำหรับสำรองไฟล์ก่อนแก้ หรือทำสำเนาไว้ทดลอง " +
                "ถ้าปลายทางมีอยู่แล้วจะไม่ทับให้จนกว่าจะตั้ง overwrite = true",
            parameters: .object([
                ("type", .string("object")),
                ("properties", .object([
                    ("source", .object([
                        ("type", .string("string")),
                        ("description", .string("path ต้นทาง"))
                    ])),
                    ("destination", .object([
                        ("type", .string("string")),
                        ("description", .string("path ปลายทาง (รวมชื่อไฟล์)"))
                    ])),
                    ("overwrite", .object([
                        ("type", .string("boolean")),
                        ("description", .string("true = ยอมเขียนทับถ้าปลายทางมีอยู่ (ต้องอนุมัติ)"))
                    ]))
                ])),
                ("required", .array([.string("source"), .string("destination")]))
            ])
        )
    }

    func execute(arguments: [String: JSONValue], context: ToolExecutionContext) async -> ToolExecutionResult {
        let args = ToolArguments(arguments)
        let rawSource: String
        let rawDestination: String
        do {
            rawSource = try args.string("source")
            rawDestination = try args.string("destination")
        } catch {
            return ToolResults.invalidArguments(error.localizedDescription)
        }

        let source = PathGuard.normalize(rawSource, workspace: context.workspacePath)
        let destination = PathGuard.normalize(rawDestination, workspace: context.workspacePath)
        let sourceDisplay = PathGuard.displayPath(source, workspace: context.workspacePath)
        let destinationDisplay = PathGuard.displayPath(destination, workspace: context.workspacePath)
        let overwrite = args.bool("overwrite", default: false)

        guard FileSystemService.exists(source) else {
            return .failure(.notFound, "ไม่พบต้นทาง: \(sourceDisplay)")
        }

        let destinationExists = FileSystemService.exists(destination)
        if destinationExists, !overwrite {
            return .failure(.invalidArguments,
                            "ปลายทางมีอยู่แล้ว: \(destinationDisplay) — ตั้ง overwrite = true ถ้าต้องการเขียนทับ")
        }
        if destinationExists {
            if let gate = FileOpSupport.writeGate(path: destination, context: context) {
                return .failure(.blocked, gate)
            }
            // คัดลอกทับไฟล์เดิม = เขียนทับข้อมูล → ต้องอนุมัติเสมอเมื่อโหมดอนุมัติเปิด
            if !context.isApproved {
                return .failure(.blocked,
                                "ต้องขออนุมัติก่อนเขียนทับ \(destinationDisplay) — ให้ผู้ใช้อนุมัติแล้วเรียก tool นี้อีกครั้ง")
            }
        }

        do {
            try FileSystemService.copy(source, to: destination, overwrite: overwrite)
            return .short("สำเร็จ: คัดลอก \(sourceDisplay) → \(destinationDisplay)")
        } catch {
            let mapped = ToolErrorMapper.describe(error, path: destinationDisplay)
            return .failure(mapped.kind, mapped.message)
        }
    }

    func assessRisk(arguments: [String: JSONValue], workspace: String) -> RiskAssessment {
        let args = ToolArguments(arguments)
        guard let rawDestination = args.optionalString("destination") else { return .safe }
        let destination = PathGuard.normalize(rawDestination, workspace: workspace)

        var assessment = RiskyCommandDetector.assessWrite(path: destination, workspace: workspace)
        if assessment.level == .normal, FileManager.default.fileExists(atPath: destination) {
            assessment = RiskAssessment(level: .elevated,
                                        reasons: ["ปลายทางมีอยู่แล้ว — การคัดลอกจะเขียนทับข้อมูลเดิม"])
        }
        return assessment
    }

    func approvalDetail(arguments: [String: JSONValue]) async -> String? {
        let args = ToolArguments(arguments)
        guard let source = args.optionalString("source"),
              let destination = args.optionalString("destination") else { return nil }
        return "จาก: \(source)\nไป: \(destination)"
    }
}

// MARK: - ลบไฟล์/โฟลเดอร์

struct DeleteFileTool: AgentTool {

    let descriptor = ToolDescriptor(name: "delete_file",
                                    thaiLabel: "ลบไฟล์/โฟลเดอร์",
                                    summary: "ลบไฟล์หรือโฟลเดอร์ (ต้องอนุมัติทุกครั้งเมื่อโหมดอนุมัติเปิด)",
                                    category: .fileSystem,
                                    alwaysRequiresApproval: true)

    var definition: ToolDefinition {
        ToolDefinition(
            name: descriptor.name,
            description: "ลบไฟล์หรือโฟลเดอร์บนเครื่อง (ลบแล้วกู้คืนไม่ได้) " +
                "ต้องให้ผู้ใช้อนุมัติก่อนเสมอ — ถ้าเป็นโฟลเดอร์ที่มีข้อมูลข้างใน ต้องตั้ง recursive = true อย่างชัดเจน " +
                "คำแนะนำ: ก่อนลบให้บอกผู้ใช้ว่าจะลบอะไร และถ้าเป็นไฟล์สำคัญควรคัดลอกสำรองด้วย copy_file ก่อน",
            parameters: .object([
                ("type", .string("object")),
                ("properties", .object([
                    ("path", .object([
                        ("type", .string("string")),
                        ("description", .string("path ของไฟล์/โฟลเดอร์ที่จะลบ"))
                    ])),
                    ("recursive", .object([
                        ("type", .string("boolean")),
                        ("description", .string("true = ลบทั้งโฟลเดอร์รวมเนื้อหาข้างใน (ค่าเริ่มต้น false)"))
                    ]))
                ])),
                ("required", .array([.string("path")]))
            ])
        )
    }

    func execute(arguments: [String: JSONValue], context: ToolExecutionContext) async -> ToolExecutionResult {
        let args = ToolArguments(arguments)
        let rawPath: String
        do {
            rawPath = try args.string("path")
        } catch {
            return ToolResults.invalidArguments(error.localizedDescription)
        }

        let path = PathGuard.normalize(rawPath, workspace: context.workspacePath)
        let display = PathGuard.displayPath(path, workspace: context.workspacePath)
        let recursive = args.bool("recursive", default: false)

        guard FileSystemService.exists(path) else {
            return .failure(.notFound, "ไม่พบสิ่งที่ต้องการลบ: \(display)")
        }

        // ลบต้องมีอนุมัติเสมอ (ไม่ว่าจะอยู่ในโฟลเดอร์ทำงานหรือไม่)
        if !context.isApproved {
            let reason = PathGuard.protectionReason(for: path, workspace: context.workspacePath)
                ?? "การลบไฟล์ไม่สามารถย้อนกลับได้"
            return .failure(.blocked,
                            "ต้องขออนุมัติก่อนลบ: \(reason)\nให้ผู้ใช้อนุมัติแล้วเรียก tool นี้อีกครั้ง")
        }

        let isDirectory = FileSystemService.isDirectory(path) == true
        if isDirectory, !recursive {
            let childCount = (try? FileSystemService.list(path, includeHidden: true, limit: 5).totalCount) ?? 0
            return .failure(.invalidArguments,
                            "\(display) เป็นโฟลเดอร์ (มีรายการข้างในอย่างน้อย \(childCount) รายการ) — " +
                            "ถ้าต้องการลบทั้งโฟลเดอร์ ให้ตั้ง recursive = true")
        }

        do {
            try FileSystemService.remove(path, recursive: recursive)
            return .short("สำเร็จ: ลบ \(display)\(isDirectory ? " (ทั้งโฟลเดอร์)" : "")")
        } catch {
            let mapped = ToolErrorMapper.describe(error, path: display)
            return .failure(mapped.kind, mapped.message)
        }
    }

    func assessRisk(arguments: [String: JSONValue], workspace: String) -> RiskAssessment {
        let args = ToolArguments(arguments)
        guard let rawPath = args.optionalString("path") else {
            return RiskAssessment(level: .destructive, reasons: ["การลบไฟล์"])
        }
        let path = PathGuard.normalize(rawPath, workspace: workspace)
        var reasons = ["การลบไฟล์/โฟลเดอร์ — กู้คืนไม่ได้"]
        if let extra = PathGuard.protectionReason(for: path, workspace: workspace) {
            reasons.append(extra)
        }
        return RiskAssessment(level: .destructive, reasons: reasons)
    }

    func approvalDetail(arguments: [String: JSONValue]) async -> String? {
        let args = ToolArguments(arguments)
        guard let path = args.optionalString("path") else { return nil }
        let recursive = args.bool("recursive", default: false)
        return "จะลบ: \(path)\n" +
            (recursive ? "รวมเนื้อหาทั้งหมดในโฟลเดอร์ (recursive)" : "เฉพาะไฟล์/โฟลเดอร์ว่างเท่านั้น")
    }
}

// MARK: - สร้างโฟลเดอร์

struct CreateDirectoryTool: AgentTool {

    let descriptor = ToolDescriptor(name: "create_directory",
                                    thaiLabel: "สร้างโฟลเดอร์",
                                    summary: "สร้างโฟลเดอร์ใหม่ (สร้างโฟลเดอร์ย่อยให้อัตโนมัติได้)",
                                    category: .fileSystem,
                                    alwaysRequiresApproval: false)

    var definition: ToolDefinition {
        ToolDefinition(
            name: descriptor.name,
            description: "สร้างโฟลเดอร์ใหม่บนเครื่อง (ค่าเริ่มต้นสร้างโฟลเดอร์ย่อยที่ขาดให้ด้วย) " +
                "ใช้เตรียมที่จัดเก็บก่อนเขียนไฟล์หรือดาวน์โหลด",
            parameters: .object([
                ("type", .string("object")),
                ("properties", .object([
                    ("path", .object([
                        ("type", .string("string")),
                        ("description", .string("path ของโฟลเดอร์ที่จะสร้าง"))
                    ])),
                    ("intermediate", .object([
                        ("type", .string("boolean")),
                        ("description", .string("true = สร้างโฟลเดอร์แม่ที่ยังไม่มีให้ด้วย (ค่าเริ่มต้น true)"))
                    ]))
                ])),
                ("required", .array([.string("path")]))
            ])
        )
    }

    func execute(arguments: [String: JSONValue], context: ToolExecutionContext) async -> ToolExecutionResult {
        let args = ToolArguments(arguments)
        let rawPath: String
        do {
            rawPath = try args.string("path")
        } catch {
            return ToolResults.invalidArguments(error.localizedDescription)
        }

        let path = PathGuard.normalize(rawPath, workspace: context.workspacePath)
        let display = PathGuard.displayPath(path, workspace: context.workspacePath)

        if FileSystemService.exists(path) {
            return FileSystemService.isDirectory(path) == true
                ? .short("โฟลเดอร์นี้มีอยู่แล้ว: \(display)")
                : .failure(.invalidArguments, "มีไฟล์ชื่อนี้อยู่แล้ว (ไม่ใช่โฟลเดอร์): \(display)")
        }

        if let gate = FileOpSupport.writeGate(path: path, context: context) {
            return .failure(.blocked, gate)
        }

        do {
            try FileSystemService.createDirectory(path, intermediate: args.bool("intermediate", default: true))
            return .short("สำเร็จ: สร้างโฟลเดอร์ \(display)")
        } catch {
            let mapped = ToolErrorMapper.describe(error, path: display)
            return .failure(mapped.kind, mapped.message)
        }
    }

    func assessRisk(arguments: [String: JSONValue], workspace: String) -> RiskAssessment {
        let args = ToolArguments(arguments)
        guard let rawPath = args.optionalString("path") else { return .safe }
        let path = PathGuard.normalize(rawPath, workspace: workspace)
        return RiskyCommandDetector.assessWrite(path: path, workspace: workspace)
    }
}
