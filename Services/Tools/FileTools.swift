//
//  FileTools.swift
//  iOS Agent Sandbox
//
//  tools ฝั่งไฟล์ของเฟส 2: read_file, write_file, list_directory, search_files
//
//  เฟส 3: ทุกอย่างเรียกผ่าน FileSystemService (ชั้นเดียวกับที่ FileBrowserView จะใช้ในเฟส 4)
//  จึงได้ข้อความ error ภาษาไทยที่บอกสาเหตุจริง และกฎหน่วยความจำถูกบังคับใช้ที่ชั้นเดียว
//
//  กฎหน่วยความจำ (เครื่อง RAM 2GB): ห้ามโหลดไฟล์ทั้งไฟล์เข้าหน่วยความจำ
//  การอ่านจึงทำผ่าน FileHandle ทีละก้อน (64KB) และหยุดเมื่อได้ครบตามที่ขอ
//
//  Foundation-only → รัน unit test/E2E ได้ทุกแพลตฟอร์ม (ไม่แตะ UIKit)
//

import Foundation

// MARK: - อ่านไฟล์

struct ReadFileTool: AgentTool {

    let descriptor = ToolDescriptor(name: "read_file",
                                    thaiLabel: "อ่านไฟล์",
                                    summary: "อ่านเนื้อหาไฟล์ข้อความ (อ่านทีละก้อน ไม่โหลดทั้งไฟล์) รองรับการเลือกช่วงบรรทัด",
                                    category: .fileSystem,
                                    alwaysRequiresApproval: false)

    var definition: ToolDefinition {
        ToolDefinition(
            name: descriptor.name,
            description: "อ่านเนื้อหาของไฟล์ข้อความบนเครื่อง อ่านได้ทุก path ที่แอปมีสิทธิ์ (เช่น /var/mobile, /var/jb) " +
                "อ่านทีละก้อนเพื่อประหยัดหน่วยความจำ จึงได้เฉพาะส่วนต้นของไฟล์ใหญ่ — ใช้ start_line/max_lines เพื่อเลื่อนดูช่วงถัดไป " +
                "ถ้าไฟล์เป็นไบนารีจะได้ข้อมูลขนาดและตัวอย่าง hex แทนข้อความ",
            parameters: .object([
                ("type", .string("object")),
                ("properties", .object([
                    ("path", .object([
                        ("type", .string("string")),
                        ("description", .string("path ของไฟล์ (absolute หรือสัมพัทธ์กับ workspace)"))
                    ])),
                    ("start_line", .object([
                        ("type", .string("integer")),
                        ("description", .string("เริ่มอ่านที่บรรทัดนี้ (เริ่มนับที่ 1) ค่าเริ่มต้น 1"))
                    ])),
                    ("max_lines", .object([
                        ("type", .string("integer")),
                        ("description", .string("อ่านสูงสุดกี่บรรทัด (ค่าเริ่มต้น 400, สูงสุด 2000)"))
                    ])),
                    ("max_characters", .object([
                        ("type", .string("integer")),
                        ("description", .string("จำกัดจำนวนตัวอักษรที่จะส่งกลับ (สูงสุด 10000)"))
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
        let startLine = max(1, args.intInRange("start_line", default: 1, min: 1, max: 5_000_000))
        let maxLines = args.intInRange("max_lines", default: 400, min: 1, max: 2000)
        let maxCharacters = args.intInRange("max_characters",
                                           default: ToolOutputLimiter.defaultMaxCharacters,
                                           min: 200,
                                           max: ToolOutputLimiter.defaultMaxCharacters)

        do {
            let prefix = try ChunkedFileReader.readPrefix(path: path)

            if prefix.isBinary {
                let head = (try? ChunkedFileReader.readHead(path: path, maxBytes: 256)) ?? Data()
                let hex = ChunkedFileReader.hexPreview(head, maxBytes: 256)
                let header = "ไฟล์ไบนารี: \(PathGuard.displayPath(path, workspace: context.workspacePath))\n" +
                    "ขนาด: \(NetworkPolicy.formatBytes(prefix.totalBytes))\n" +
                    "ไม่แสดงเป็นข้อความ — ตัวอย่าง hex 256 ไบต์แรก:\n"
                return .ok(header + (hex.isEmpty ? "(อ่านตัวอย่างไม่สำเร็จ)" : hex))
            }

            let lines = prefix.text.split(separator: "\n", omittingEmptySubsequences: false)
            let totalLinesRead = lines.count
            let fromIndex = min(startLine - 1, lines.count)
            let toIndex = min(fromIndex + maxLines, lines.count)
            let selected = lines[fromIndex..<toIndex]

            var body = selected.enumerated().map { offset, line in
                "\(fromIndex + offset + 1)\t\(line)"
            }.joined(separator: "\n")

            if body.count > maxCharacters {
                body = String(body.prefix(maxCharacters))
            }

            var header = "ไฟล์: \(PathGuard.displayPath(path, workspace: context.workspacePath))\n" +
                "ขนาด: \(NetworkPolicy.formatBytes(prefix.totalBytes)) • บรรทัดที่อ่านได้ในก้อนนี้: \(totalLinesRead)"
            if startLine > 1 || toIndex < totalLinesRead {
                header += " • แสดงบรรทัด \(fromIndex + 1)–\(toIndex)"
            }
            if prefix.hasMore {
                header += "\n(ยังมีข้อมูลเหลือในไฟล์ — เพิ่ม start_line เพื่ออ่านช่วงถัดไป)"
            }

            let text = body.isEmpty ? "\(header)\n(ไม่มีเนื้อหาในช่วงบรรทัดที่ขอ)" : "\(header)\n\n\(body)"
            return .ok(text)
        } catch {
            let mapped = ToolErrorMapper.describe(error, path: PathGuard.displayPath(path, workspace: context.workspacePath))
            return .failure(mapped.kind, mapped.message)
        }
    }
}

// MARK: - เขียนไฟล์

struct WriteFileTool: AgentTool {

    let descriptor = ToolDescriptor(name: "write_file",
                                    thaiLabel: "เขียนไฟล์",
                                    summary: "สร้างหรือเขียนทับไฟล์ข้อความ (สร้างโฟลเดอร์ให้อัตโนมัติ) และเขียนต่อท้ายได้",
                                    category: .fileSystem,
                                    alwaysRequiresApproval: false)

    /// ขนาดเนื้อหาสูงสุดต่อการเขียนหนึ่งครั้ง (กันการส่งข้อมูลก้อนใหญ่ผิดพลาด)
    static let maximumContentBytes = 512 * 1024

    var definition: ToolDefinition {
        ToolDefinition(
            name: descriptor.name,
            description: "สร้างหรือเขียนทับไฟล์บนเครื่อง เขียนได้ทุก path ที่แอปมีสิทธิ์ ถ้าโฟลเดอร์ปลายทางไม่มีจะสร้างให้ " +
                "ใส่ append=true เพื่อต่อท้ายไฟล์เดิม ระบบจะขออนุมัติก่อนถ้าเขียนทับไฟล์ของระบบหรือไฟล์ที่มีอยู่แล้ว",
            parameters: .object([
                ("type", .string("object")),
                ("properties", .object([
                    ("path", .object([
                        ("type", .string("string")),
                        ("description", .string("path ปลายทางของไฟล์"))
                    ])),
                    ("content", .object([
                        ("type", .string("string")),
                        ("description", .string("เนื้อหาที่จะเขียน"))
                    ])),
                    ("append", .object([
                        ("type", .string("boolean")),
                        ("description", .string("true = ต่อท้ายไฟล์เดิม (ค่าเริ่มต้น false = เขียนทับ)"))
                    ])),
                    ("create_directories", .object([
                        ("type", .string("boolean")),
                        ("description", .string("true = สร้างโฟลเดอร์ที่ขาดให้ (ค่าเริ่มต้น true)"))
                    ]))
                ])),
                ("required", .array([.string("path"), .string("content")]))
            ])
        )
    }

    func execute(arguments: [String: JSONValue], context: ToolExecutionContext) async -> ToolExecutionResult {
        let args = ToolArguments(arguments)

        let rawPath: String
        let content: String
        do {
            rawPath = try args.string("path")
            content = try args.string("content")
        } catch {
            return ToolResults.invalidArguments(error.localizedDescription)
        }

        let path = PathGuard.normalize(rawPath, workspace: context.workspacePath)
        let append = args.bool("append", default: false)
        let createDirectories = args.bool("create_directories", default: true)

        if let reason = PathGuard.protectionReason(for: path, workspace: context.workspacePath), !context.isApproved {
            return .failure(.blocked,
                            "ต้องขออนุมัติก่อนเขียนไฟล์นี้: \(reason)\n" +
                            "ให้ผู้ใช้อนุมัติในแอปแล้วเรียก tool นี้อีกครั้ง (หรือเปลี่ยนไปเขียนใน \(PathGuard.displayPath(context.workspacePath, workspace: context.workspacePath)))")
        }


        // สำเนาสำรองก่อนลงมือเขียน — ทำให้ปุ่ม "ย้อนกลับ" ในไทม์ไลน์ทำงานได้จริง
        // (ไฟล์ใหม่ = ไม่มีเวอร์ชันก่อนหน้า แต่ยังย้อนกลับได้ด้วยการลบไฟล์ที่เพิ่งสร้าง)
        WorkspaceBackup.shared.keep(path: path,
                                    kind: FileSystemService.exists(path) ? .overwrite : .created)

        do {
            // เขียนผ่าน FileSystemService เพื่อให้ได้ข้อความ error ภาษาไทยและเพดานขนาดที่เดียวกันทั้งแอป
            let report = try FileSystemService.write(content,
                                                     to: path,
                                                     append: append,
                                                     createDirectories: createDirectories,
                                                     maximumBytes: WriteFileTool.maximumContentBytes)
            let mode = (append && report.didOverwriteExisting)
                ? "ต่อท้าย"
                : (report.didOverwriteExisting ? "เขียนทับ" : "สร้างใหม่")

            return .short("สำเร็จ: \(mode)ไฟล์ \(PathGuard.displayPath(path, workspace: context.workspacePath)) " +
                "(\(NetworkPolicy.formatBytes(report.finalSizeBytes)) • เขียนไป \(report.bytesWritten) ไบต์)")
        } catch {
            let mapped = ToolErrorMapper.describe(error, path: PathGuard.displayPath(path, workspace: context.workspacePath))
            return .failure(mapped.kind, mapped.message)
        }
    }

    func assessRisk(arguments: [String: JSONValue], workspace: String) -> RiskAssessment {
        let args = ToolArguments(arguments)
        guard let rawPath = args.optionalString("path") else { return .safe }
        let path = PathGuard.normalize(rawPath, workspace: workspace)

        var assessment = RiskyCommandDetector.assessWrite(path: path, workspace: workspace)

        // เขียนทับไฟล์ที่มีอยู่แล้ว = เสี่ยงระดับกลาง (ต้องอนุมัติ แต่ไม่ต้องกลัวเท่าเขียนทับไฟล์ระบบ)
        let append = args.bool("append", default: false)
        if !append, FileManager.default.fileExists(atPath: path), assessment.level == .normal {
            assessment = RiskAssessment(level: .elevated,
                                        reasons: ["ไฟล์ปลายทางมีอยู่แล้ว — การเขียนจะทับข้อมูลเดิม"])
        }
        return assessment
    }
}

// MARK: - แสดงรายการโฟลเดอร์

struct ListDirectoryTool: AgentTool {

    let descriptor = ToolDescriptor(name: "list_directory",
                                    thaiLabel: "ดูรายการโฟลเดอร์",
                                    summary: "แสดงรายชื่อไฟล์/โฟลเดอร์ พร้อมขนาดและวันที่แก้ไข (จำกัดจำนวนรายการ)",
                                    category: .fileSystem,
                                    alwaysRequiresApproval: false)

    var definition: ToolDefinition {
        ToolDefinition(
            name: descriptor.name,
            description: "แสดงรายการไฟล์และโฟลเดอร์ใน path ที่ระบุ (ค่าเริ่มต้นคือโฟลเดอร์ทำงานของ Agent) " +
                "บอกขนาดไฟล์ วันที่แก้ไข และตัวอักษร / ต่อท้ายชื่อโฟลเดอร์ ใช้เมื่อต้องสำรวจไฟล์บนเครื่องก่อนตัดสินใจทำอย่างอื่น",
            parameters: .object([
                ("type", .string("object")),
                ("properties", .object([
                    ("path", .object([
                        ("type", .string("string")),
                        ("description", .string("path ของโฟลเดอร์ที่ต้องการดู (ค่าเริ่มต้น \(PathGuard.defaultWorkspace))"))
                    ])),
                    ("max_entries", .object([
                        ("type", .string("integer")),
                        ("description", .string("จำนวนรายการสูงสุด (ค่าเริ่มต้น 200, สูงสุด 1000)"))
                    ])),
                    ("show_hidden", .object([
                        ("type", .string("boolean")),
                        ("description", .string("true = แสดงไฟล์ที่ขึ้นต้นด้วย . (ค่าเริ่มต้น false)"))
                    ]))
                ])),
                ("required", .array([]))
            ])
        )
    }

    func execute(arguments: [String: JSONValue], context: ToolExecutionContext) async -> ToolExecutionResult {
        let args = ToolArguments(arguments)
        let rawPath = args.optionalString("path") ?? context.workspacePath
        let path = PathGuard.normalize(rawPath, workspace: context.workspacePath)
        let maxEntries = args.intInRange("max_entries", default: 200, min: 1, max: 1000)
        let showHidden = args.bool("show_hidden", default: false)

        guard FileSystemService.isDirectory(path) != nil else {
            return .failure(.notFound, "ไม่พบโฟลเดอร์: \(PathGuard.displayPath(path, workspace: context.workspacePath))" +
                            (PathGuard.isProtected(path, workspace: context.workspacePath)
                             ? "\n(path นี้เป็นของระบบ — ถ้าอ่านไม่ได้ ให้ตรวจว่าแอปติดตั้งผ่าน TrollStore/palera1n แล้ว)"
                             : ""))
        }

        do {
            // อ่านรายการผ่าน FileSystemService (ชั้นเดียวกับ FileBrowserView ในเฟส 4)
            let listing = try FileSystemService.list(path, includeHidden: showHidden, limit: maxEntries)

            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "th_TH")
            formatter.dateFormat = "yyyy-MM-dd HH:mm"

            var lines: [String] = []
            for entry in listing.entries {
                let kind = entry.isSymbolicLink ? "LINK " : (entry.isDirectory ? "DIR " : "FILE")
                var sizeText = entry.isDirectory ? "        " : NetworkPolicy.formatBytes(entry.sizeBytes)
                while sizeText.count < 8 {
                    sizeText = " " + sizeText
                }
                let dateText = entry.modificationDate.map { formatter.string(from: $0) } ?? "—"
                lines.append("\(kind) \(sizeText)  \(dateText)  \(entry.name)\(entry.isDirectory ? "/" : "")")
            }

            let directoryCount = listing.entries.filter { $0.isDirectory }.count
            let fileCount = listing.entries.count - directoryCount

            var header = "โฟลเดอร์: \(PathGuard.displayPath(path, workspace: context.workspacePath))\n" +
                "แสดง \(directoryCount) โฟลเดอร์, \(fileCount) ไฟล์"
            if listing.skippedHidden > 0 {
                header += " (ซ่อนไฟล์ที่ขึ้นต้นด้วย . อยู่ \(listing.skippedHidden) รายการ)"
            }
            if listing.totalCount > listing.entries.count {
                header += "\nแสดงเฉพาะ \(listing.entries.count) รายการแรกจาก \(listing.totalCount) รายการที่ตรงเงื่อนไข"
            }

            if listing.entries.isEmpty {
                return .ok("\(header)\n\n(โฟลเดอร์ว่าง)")
            }
            return .ok("\(header)\n\n" + lines.joined(separator: "\n"))
        } catch {
            let mapped = ToolErrorMapper.describe(error, path: PathGuard.displayPath(path, workspace: context.workspacePath))
            return .failure(mapped.kind, mapped.message)
        }
    }
}

// MARK: - ค้นหาไฟล์

struct SearchFilesTool: AgentTool {

    let descriptor = ToolDescriptor(name: "search_files",
                                    thaiLabel: "ค้นหาไฟล์",
                                    summary: "ค้นหาไฟล์ตามรูปแบบชื่อ (glob เช่น *.txt, *.plist, config*) ภายในโฟลเดอร์ที่กำหนด",
                                    category: .fileSystem,
                                    alwaysRequiresApproval: false)

    /// เพดานจำนวนรายการที่เดินสำรวจ (กันการไล่ทั้งเครื่องซึ่งใช้เวลานานบน iPhone 7)
    static let maximumVisitedEntries = 50_000

    var definition: ToolDefinition {
        ToolDefinition(
            name: descriptor.name,
            description: "ค้นหาไฟล์บนเครื่องตามรูปแบบชื่อไฟล์ (glob) เริ่มจากโฟลเดอร์ที่ระบุ ไล่ลงไปตามระดับความลึกที่กำหนด " +
                "ตัวอย่าง pattern: *.txt, *.plist, Photo*, *.log ใช้เมื่อต้องหาไฟล์ที่ต้องการโดยยังไม่รู้ path เต็ม",
            parameters: .object([
                ("type", .string("object")),
                ("properties", .object([
                    ("path", .object([
                        ("type", .string("string")),
                        ("description", .string("โฟลเดอร์เริ่มต้นในการค้นหา (ค่าเริ่มต้น \(PathGuard.defaultWorkspace))"))
                    ])),
                    ("pattern", .object([
                        ("type", .string("string")),
                        ("description", .string("รูปแบบชื่อไฟล์ เช่น *.txt หรือ config* (คั่นหลายรูปแบบด้วย , ได้)"))
                    ])),
                    ("max_results", .object([
                        ("type", .string("integer")),
                        ("description", .string("จำนวนผลลัพธ์สูงสุด (ค่าเริ่มต้น 50, สูงสุด 200)"))
                    ])),
                    ("max_depth", .object([
                        ("type", .string("integer")),
                        ("description", .string("ความลึกของโฟลเดอร์สูงสุด (ค่าเริ่มต้น 6, สูงสุด 12)"))
                    ])),
                    ("include_directories", .object([
                        ("type", .string("boolean")),
                        ("description", .string("true = ให้โฟลเดอร์ที่ชื่อตรงกับ pattern อยู่ในผลลัพธ์ด้วย (ค่าเริ่มต้น false)"))
                    ]))
                ])),
                ("required", .array([.string("pattern")]))
            ])
        )
    }

    func execute(arguments: [String: JSONValue], context: ToolExecutionContext) async -> ToolExecutionResult {
        let args = ToolArguments(arguments)

        let rawPattern: String
        do {
            rawPattern = try args.string("pattern")
        } catch {
            return ToolResults.invalidArguments(error.localizedDescription)
        }

        let patterns = GlobMatcher.splitPatterns(rawPattern)
        guard !patterns.isEmpty, patterns.allSatisfy({ GlobMatcher.isValidPattern($0) }) else {
            return .failure(.invalidArguments, "รูปแบบการค้นหาไม่ถูกต้อง (ต้องยาว 1–200 ตัวอักษร): \(rawPattern)")
        }

        let rawPath = args.optionalString("path") ?? context.workspacePath
        let root = PathGuard.normalize(rawPath, workspace: context.workspacePath)
        let maxResults = args.intInRange("max_results", default: 50, min: 1, max: 200)
        let maxDepth = args.intInRange("max_depth", default: 6, min: 1, max: 12)
        let includeDirectories = args.bool("include_directories", default: false)

        guard FileSystemService.isDirectory(root) == true else {
            return .failure(.notFound, "ไม่พบโฟลเดอร์เริ่มต้น: \(PathGuard.displayPath(root, workspace: context.workspacePath))")
        }

        var matches: [String] = []
        var visited = 0
        var hitVisitLimit = false
        var queue: [(path: String, depth: Int)] = [(root, 0)]

        while !queue.isEmpty {
            if Task.isCancelled {
                return .failure(.cancelled, "การค้นหาถูกยกเลิก")
            }
            let current = queue.removeFirst()
            if current.depth > maxDepth { continue }

            let names: [String]
            do {
                names = try FileSystemService.directoryNames(current.path)
            } catch {
                continue // โฟลเดอร์ที่อ่านไม่ได้ (สิทธิ์ไม่พอ) ข้ามไป ไม่ทำให้ทั้งการค้นหาล้ม
            }

            for entry in names {
                visited += 1
                if visited > SearchFilesTool.maximumVisitedEntries {
                    hitVisitLimit = true
                    break
                }
                let entryPath = (current.path as NSString).appendingPathComponent(entry)
                let entryIsDirectory = FileSystemService.isDirectory(entryPath) ?? false

                if entryIsDirectory {
                    if includeDirectories, GlobMatcher.matchesAny(patterns, entry) {
                        matches.append(entryPath + "/")
                        if matches.count >= maxResults { break }
                    }
                    if current.depth + 1 <= maxDepth {
                        queue.append((entryPath, current.depth + 1))
                    }
                } else if GlobMatcher.matchesAny(patterns, entry) {
                    matches.append(entryPath)
                    if matches.count >= maxResults { break }
                }
            }
            if matches.count >= maxResults || hitVisitLimit { break }
        }

        var header = "ค้นหาใน \(PathGuard.displayPath(root, workspace: context.workspacePath)) ด้วยรูปแบบ \(patterns.joined(separator: ", "))\n" +
            "พบ \(matches.count) รายการ (สำรวจ \(visited) รายการ, ความลึกสูงสุด \(maxDepth))"
        if hitVisitLimit {
            header += "\nหยุดเพราะสำรวจครบเพดาน \(SearchFilesTool.maximumVisitedEntries) รายการ — ลดขอบเขต path หรือความลึกแล้วลองใหม่"
        }
        if matches.isEmpty {
            return .ok("\(header)\n\n(ไม่พบไฟล์ที่ตรงกับรูปแบบ)")
        }
        return .ok("\(header)\n\n" + matches.map { PathGuard.displayPath($0, workspace: context.workspacePath) }.joined(separator: "\n"))
    }
}
