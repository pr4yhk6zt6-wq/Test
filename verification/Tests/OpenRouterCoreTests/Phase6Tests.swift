//
//  Phase6Tests.swift
//  iOS Agent Sandbox — ชุดทดสอบแกนกลางของเฟส 6
//
//  ทดสอบของจริงบนดิสก์ (ไม่ mock): edit_file / move_file / copy_file / delete_file /
//  create_directory / search_content รวมทั้งตรรกะภายในที่แยกไว้ให้ทดสอบตรง ๆ
//

import XCTest
@testable import OpenRouterCore

final class Phase6EditFileSupportTests: XCTestCase {

    func testOccurrenceCountCountsNonOverlappingMatches() {
        XCTAssertEqual(EditFileSupport.occurrenceCount(of: "ab", in: "ababab"), 3)
        XCTAssertEqual(EditFileSupport.occurrenceCount(of: "aa", in: "aaaa"), 2)   // ไม่ทับซ้อน
        XCTAssertEqual(EditFileSupport.occurrenceCount(of: "ไม่มี", in: "มีข้อความ"), 0)
        XCTAssertEqual(EditFileSupport.occurrenceCount(of: "", in: "อะไรก็ตาม"), 0)
    }

    func testOccurrenceCountHandlesThaiText() {
        let text = "สวัสดีครับ\nยินดีต้อนรับ\nสวัสดีอีกครั้ง"
        XCTAssertEqual(EditFileSupport.occurrenceCount(of: "สวัสดี", in: text), 2)
    }

    func testReplacingFirstOccurrenceKeepsTheRest() {
        let updated = EditFileSupport.replacingFirstOccurrence(of: "x", with: "Y", in: "x-x-x")
        XCTAssertEqual(updated, "Y-x-x")
    }

    func testReplacingFirstOccurrenceWithoutMatchReturnsOriginal() {
        XCTAssertEqual(EditFileSupport.replacingFirstOccurrence(of: "z", with: "Y", in: "abc"), "abc")
    }

    func testChangedLinePreviewPointsAtFirstChangedLine() {
        let before = "บรรทัดแรก\nบรรทัดที่สอง\nบรรทัดที่สาม"
        let after = "บรรทัดแรก\nบรรทัดที่แก้แล้ว\nบรรทัดที่สาม"
        let preview = EditFileSupport.changedLinePreview(before: before, after: after)
        XCTAssertEqual(preview, "บรรทัดที่ 2: บรรทัดที่แก้แล้ว")
    }

    func testChangedLinePreviewIsNilWhenNothingChanged() {
        XCTAssertNil(EditFileSupport.changedLinePreview(before: "เหมือนกัน", after: "เหมือนกัน"))
    }

    func testChangedLinePreviewTruncatesLongLines() {
        let long = String(repeating: "ก", count: 400)
        let preview = EditFileSupport.changedLinePreview(before: "เดิม", after: long, limit: 20)
        XCTAssertNotNil(preview)
        XCTAssertTrue(preview?.hasSuffix("…") == true)
        XCTAssertTrue((preview?.count ?? 0) < 60)
    }
}

final class Phase6ContentSearchSupportTests: XCTestCase {

    func testMakeRegexRejectsInvalidPattern() {
        XCTAssertThrowsError(try ContentSearchSupport.makeRegex(pattern: "([", caseSensitive: false))
    }

    func testMakeRegexIsCaseInsensitiveByDefault() throws {
        let regex = try ContentSearchSupport.makeRegex(pattern: "hello", caseSensitive: false)
        let text = "Hello โลก"
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        XCTAssertNotNil(regex.firstMatch(in: text, options: [], range: range))
    }

    func testMakeRegexHonoursCaseSensitiveFlag() throws {
        let regex = try ContentSearchSupport.makeRegex(pattern: "hello", caseSensitive: true)
        let text = "Hello"
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        XCTAssertNil(regex.firstMatch(in: text, options: [], range: range))
    }

    func testNormalizeExtensionsCleansSpacesAndDots() {
        let set = ContentSearchSupport.normalizeExtensions(" swift, .TXT , json ")
        XCTAssertEqual(set, Set(["swift", "txt", "json"]))
    }

    func testNormalizeExtensionsIgnoresSillyValues() {
        XCTAssertTrue(ContentSearchSupport.normalizeExtensions(nil).isEmpty)
        XCTAssertTrue(ContentSearchSupport.normalizeExtensions("").isEmpty)
        XCTAssertTrue(ContentSearchSupport.normalizeExtensions("abcdefghijklmnop").isEmpty)  // ยาวเกิน 12
    }

    func testMatchesExtensions() {
        XCTAssertTrue(ContentSearchSupport.matchesExtensions(fileName: "note.TXT", extensions: ["txt"]))
        XCTAssertFalse(ContentSearchSupport.matchesExtensions(fileName: "note.md", extensions: ["txt"]))
        XCTAssertTrue(ContentSearchSupport.matchesExtensions(fileName: "อะไรก็ได้", extensions: []))
    }

    func testMatchesReportsLineNumbersAndTruncates() throws {
        let regex = try ContentSearchSupport.makeRegex(pattern: "แก้ทีหลัง", caseSensitive: false)
        let longLine = "แก้ทีหลัง " + String(repeating: "x", count: 400)
        let lines: [(number: Int, text: String)] = [
            (1, "บรรทัดแรก"),
            (2, "มี แก้ทีหลัง อยู่ตรงนี้"),
            (3, longLine)
        ]
        let hits = ContentSearchSupport.matches(regex: regex, lines: lines, fileName: "a.txt", maximumLineCharacters: 40)
        XCTAssertEqual(hits.count, 2)
        XCTAssertEqual(hits[0].lineNumber, 2)
        XCTAssertEqual(hits[0].lineText, "มี แก้ทีหลัง อยู่ตรงนี้")
        XCTAssertEqual(hits[1].lineNumber, 3)
        XCTAssertTrue(hits[1].lineText.hasSuffix("…"))
    }

    func testReadSearchableLinesReturnsNilForBinary() throws {
        let directory = try Phase6TestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(atPath: directory) }

        let binaryPath = (directory as NSString).appendingPathComponent("bin.dat")
        var bytes = Data([0x50, 0x4B, 0x03, 0x04])
        bytes.append(0x00)   // ไบต์ 0 = ไบนารี
        bytes.append(contentsOf: [0x01, 0x02, 0x03])
        try bytes.write(to: URL(fileURLWithPath: binaryPath))

        XCTAssertNil(ContentSearchSupport.readSearchableLines(path: binaryPath, limitBytes: 4096))
    }

    func testReadSearchableLinesReadsUtf8Lines() throws {
        let directory = try Phase6TestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(atPath: directory) }

        let textPath = (directory as NSString).appendingPathComponent("note.txt")
        try "หนึ่ง\nสอง\nสาม".write(toFile: textPath, atomically: true, encoding: .utf8)

        let lines = try XCTUnwrap(ContentSearchSupport.readSearchableLines(path: textPath, limitBytes: 4096))
        XCTAssertEqual(lines.count, 3)
        XCTAssertEqual(lines[1].number, 2)
        XCTAssertEqual(lines[1].text, "สอง")
    }

    func testReadSearchableLinesReturnsNilWhenFileMissing() {
        XCTAssertNil(ContentSearchSupport.readSearchableLines(path: "/tmp/ไม่มีไฟล์นี้-\(UUID().uuidString)",
                                                              limitBytes: 1024))
    }
}

final class Phase6FileEditToolTests: XCTestCase {

    func testEditFileReplacesSingleOccurrence() async throws {
        let workspace = try Phase6TestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(atPath: workspace) }

        let filePath = (workspace as NSString).appendingPathComponent("note.txt")
        try "alpha\nbeta\ngamma\n".write(toFile: filePath, atomically: true, encoding: .utf8)

        let result = await EditFileTool().execute(arguments: [
            "path": .string(filePath),
            "find": .string("beta"),
            "replace": .string("BETA-ใหม่")
        ], context: Phase6TestSupport.context(workspace: workspace))

        XCTAssertFalse(result.isError, result.text)
        let updated = try String(contentsOfFile: filePath, encoding: .utf8)
        XCTAssertEqual(updated, "alpha\nBETA-ใหม่\ngamma\n")
        XCTAssertTrue(result.text.contains("แก้ 1 จุด"))
    }

    func testEditFileRefusesWhenPatternIsAmbiguous() async throws {
        let workspace = try Phase6TestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(atPath: workspace) }

        let filePath = (workspace as NSString).appendingPathComponent("dup.txt")
        let original = "ซ้ำ\nซ้ำ\n"
        try original.write(toFile: filePath, atomically: true, encoding: .utf8)

        let result = await EditFileTool().execute(arguments: [
            "path": .string(filePath),
            "find": .string("ซ้ำ"),
            "replace": .string("ใหม่")
        ], context: Phase6TestSupport.context(workspace: workspace))

        XCTAssertTrue(result.isError)
        XCTAssertEqual(result.kind, .invalidArguments)
        XCTAssertEqual(try String(contentsOfFile: filePath, encoding: .utf8), original)   // ไม่ถูกแก้
    }

    func testEditFileReplaceAllWhenAskedExplicitly() async throws {
        let workspace = try Phase6TestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(atPath: workspace) }

        let filePath = (workspace as NSString).appendingPathComponent("dup.txt")
        try "ซ้ำ\nซ้ำ\n".write(toFile: filePath, atomically: true, encoding: .utf8)

        let result = await EditFileTool().execute(arguments: [
            "path": .string(filePath),
            "find": .string("ซ้ำ"),
            "replace": .string("ใหม่"),
            "replace_all": .bool(true)
        ], context: Phase6TestSupport.context(workspace: workspace))

        XCTAssertFalse(result.isError, result.text)
        XCTAssertEqual(try String(contentsOfFile: filePath, encoding: .utf8), "ใหม่\nใหม่\n")
    }

    func testEditFileRespectsExpectedCount() async throws {
        let workspace = try Phase6TestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(atPath: workspace) }

        let filePath = (workspace as NSString).appendingPathComponent("count.txt")
        try "a\nb\nc\n".write(toFile: filePath, atomically: true, encoding: .utf8)

        let result = await EditFileTool().execute(arguments: [
            "path": .string(filePath),
            "find": .string("a"),
            "replace": .string("A"),
            "expected_count": .int(2)
        ], context: Phase6TestSupport.context(workspace: workspace))

        XCTAssertTrue(result.isError)
        XCTAssertEqual(result.kind, .invalidArguments)
        XCTAssertEqual(try String(contentsOfFile: filePath, encoding: .utf8), "a\nb\nc\n")
    }

    func testEditFileReportsMissingPatternWithGuidance() async throws {
        let workspace = try Phase6TestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(atPath: workspace) }

        let filePath = (workspace as NSString).appendingPathComponent("note.txt")
        try "เนื้อหาเดิม".write(toFile: filePath, atomically: true, encoding: .utf8)

        let result = await EditFileTool().execute(arguments: [
            "path": .string(filePath),
            "find": .string("ไม่มีข้อความนี้"),
            "replace": .string("x")
        ], context: Phase6TestSupport.context(workspace: workspace))

        XCTAssertTrue(result.isError)
        XCTAssertEqual(result.kind, .notFound)
        XCTAssertTrue(result.text.contains("read_file"))
    }

    func testEditFileRejectsEmptySearchText() async throws {
        let workspace = try Phase6TestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(atPath: workspace) }

        let result = await EditFileTool().execute(arguments: [
            "path": .string((workspace as NSString).appendingPathComponent("x.txt")),
            "find": .string(""),
            "replace": .string("y")
        ], context: Phase6TestSupport.context(workspace: workspace))

        XCTAssertTrue(result.isError)
        XCTAssertEqual(result.kind, .invalidArguments)
    }

    func testEditFileReportsWrongArgumentTypes() async {
        let result = await EditFileTool().execute(arguments: ["path": .bool(true)],
                                                  context: Phase6TestSupport.context(workspace: "/tmp"))
        XCTAssertTrue(result.isError)
        XCTAssertEqual(result.kind, .invalidArguments)
    }

    func testEditFileAssessRiskElevatesExistingFile() throws {
        let workspace = try Phase6TestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(atPath: workspace) }

        let filePath = (workspace as NSString).appendingPathComponent("old.txt")
        try "เดิม".write(toFile: filePath, atomically: true, encoding: .utf8)

        let risk = EditFileTool().assessRisk(arguments: ["path": .string(filePath)], workspace: workspace)
        XCTAssertEqual(risk.level, .elevated)
        XCTAssertTrue(risk.needsApproval)
    }

    func testEditFileApprovalDetailShowsWhatWillChange() async throws {
        let detail = await EditFileTool().approvalDetail(arguments: [
            "path": .string("/tmp/a.txt"),
            "find": .string("ของเก่า"),
            "replace": .string("ของใหม่"),
            "replace_all": .bool(true)
        ])
        let text = try XCTUnwrap(detail)
        XCTAssertTrue(text.contains("ของเก่า"))
        XCTAssertTrue(text.contains("ของใหม่"))
        XCTAssertTrue(text.contains("ทุกจุด"))
    }
}

final class Phase6FileOperationToolTests: XCTestCase {

    func testCreateDirectoryCreatesNestedFolders() async throws {
        let workspace = try Phase6TestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(atPath: workspace) }

        let target = (workspace as NSString).appendingPathComponent("a/b/c")
        let result = await CreateDirectoryTool().execute(arguments: ["path": .string(target)],
                                                         context: Phase6TestSupport.context(workspace: workspace))
        XCTAssertFalse(result.isError, result.text)
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: target, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
    }

    func testCreateDirectoryRefusesWhenAFileHasThatName() async throws {
        let workspace = try Phase6TestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(atPath: workspace) }

        let filePath = (workspace as NSString).appendingPathComponent("already.txt")
        try "x".write(toFile: filePath, atomically: true, encoding: .utf8)

        let result = await CreateDirectoryTool().execute(arguments: ["path": .string(filePath)],
                                                         context: Phase6TestSupport.context(workspace: workspace))
        XCTAssertTrue(result.isError)
        XCTAssertEqual(result.kind, .invalidArguments)
    }

    func testCopyFileThenMoveFile() async throws {
        let workspace = try Phase6TestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(atPath: workspace) }

        let source = (workspace as NSString).appendingPathComponent("source.txt")
        let copy = (workspace as NSString).appendingPathComponent("copy.txt")
        let moved = (workspace as NSString).appendingPathComponent("moved.txt")
        try "ข้อมูลสำคัญ".write(toFile: source, atomically: true, encoding: .utf8)

        let copyResult = await CopyFileTool().execute(arguments: [
            "source": .string(source), "destination": .string(copy)
        ], context: Phase6TestSupport.context(workspace: workspace))
        XCTAssertFalse(copyResult.isError, copyResult.text)
        XCTAssertEqual(try String(contentsOfFile: copy, encoding: .utf8), "ข้อมูลสำคัญ")
        XCTAssertTrue(FileManager.default.fileExists(atPath: source))   // ต้นฉบับยังอยู่

        let moveResult = await MoveFileTool().execute(arguments: [
            "source": .string(copy), "destination": .string(moved)
        ], context: Phase6TestSupport.context(workspace: workspace))
        XCTAssertFalse(moveResult.isError, moveResult.text)
        XCTAssertTrue(FileManager.default.fileExists(atPath: moved))
        XCTAssertFalse(FileManager.default.fileExists(atPath: copy))
    }

    func testCopyFileRefusesToOverwriteWithoutFlag() async throws {
        let workspace = try Phase6TestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(atPath: workspace) }

        let source = (workspace as NSString).appendingPathComponent("a.txt")
        let destination = (workspace as NSString).appendingPathComponent("b.txt")
        try "ใหม่".write(toFile: source, atomically: true, encoding: .utf8)
        try "ของเดิม".write(toFile: destination, atomically: true, encoding: .utf8)

        let result = await CopyFileTool().execute(arguments: [
            "source": .string(source), "destination": .string(destination)
        ], context: Phase6TestSupport.context(workspace: workspace))

        XCTAssertTrue(result.isError)
        XCTAssertEqual(try String(contentsOfFile: destination, encoding: .utf8), "ของเดิม")
    }

    func testDeleteFileRequiresApproval() async throws {
        let workspace = try Phase6TestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(atPath: workspace) }

        let filePath = (workspace as NSString).appendingPathComponent("ลบฉัน.txt")
        try "x".write(toFile: filePath, atomically: true, encoding: .utf8)

        let denied = await DeleteFileTool().execute(arguments: ["path": .string(filePath)],
                                                    context: Phase6TestSupport.context(workspace: workspace, approved: false))
        XCTAssertTrue(denied.isError)
        XCTAssertEqual(denied.kind, .blocked)
        XCTAssertTrue(FileManager.default.fileExists(atPath: filePath))   // ยังอยู่

        let allowed = await DeleteFileTool().execute(arguments: ["path": .string(filePath)],
                                                     context: Phase6TestSupport.context(workspace: workspace, approved: true))
        XCTAssertFalse(allowed.isError, allowed.text)
        XCTAssertFalse(FileManager.default.fileExists(atPath: filePath))
    }

    func testDeleteDirectoryWithoutRecursiveIsRejected() async throws {
        let workspace = try Phase6TestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(atPath: workspace) }

        let folder = (workspace as NSString).appendingPathComponent("โฟลเดอร์")
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        try "x".write(toFile: (folder as NSString).appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)

        let result = await DeleteFileTool().execute(arguments: ["path": .string(folder)],
                                                    context: Phase6TestSupport.context(workspace: workspace, approved: true))
        XCTAssertTrue(result.isError)
        XCTAssertEqual(result.kind, .invalidArguments)
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder))

        let recursive = await DeleteFileTool().execute(arguments: [
            "path": .string(folder), "recursive": .bool(true)
        ], context: Phase6TestSupport.context(workspace: workspace, approved: true))
        XCTAssertFalse(recursive.isError, recursive.text)
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder))
    }

    func testDeleteFileRiskIsAlwaysDestructive() {
        let risk = DeleteFileTool().assessRisk(arguments: ["path": .string("/tmp/x.txt")], workspace: "/tmp")
        XCTAssertEqual(risk.level, .destructive)
        XCTAssertTrue(risk.needsApproval)
    }

    func testMoveFileRiskElevatesWhenDestinationExists() throws {
        let workspace = try Phase6TestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(atPath: workspace) }

        let destination = (workspace as NSString).appendingPathComponent("มีอยู่.txt")
        try "x".write(toFile: destination, atomically: true, encoding: .utf8)

        let risk = MoveFileTool().assessRisk(arguments: [
            "source": .string((workspace as NSString).appendingPathComponent("อะไร.txt")),
            "destination": .string(destination)
        ], workspace: workspace)
        XCTAssertEqual(risk.level, .elevated)
    }
}

final class Phase6SearchContentToolTests: XCTestCase {

    func testSearchContentFindsTextWithLineNumbers() async throws {
        let workspace = try Phase6TestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(atPath: workspace) }

        let filePath = (workspace as NSString).appendingPathComponent("code.swift")
        try "// บรรทัดแรก\nfunc login() {}\n// หมายเหตุ: แก้ทีหลัง\n".write(toFile: filePath, atomically: true, encoding: .utf8)

        let result = await SearchContentTool().execute(arguments: [
            "pattern": .string("หมายเหตุ|login"),
            "path": .string(workspace)
        ], context: Phase6TestSupport.context(workspace: workspace))

        XCTAssertFalse(result.isError, result.text)
        XCTAssertTrue(result.text.contains("code.swift:2"), result.text)
        XCTAssertTrue(result.text.contains("code.swift:3"), result.text)
    }

    func testSearchContentHonoursExtensionFilter() async throws {
        let workspace = try Phase6TestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(atPath: workspace) }

        try "คำค้น".write(toFile: (workspace as NSString).appendingPathComponent("a.md"),
                        atomically: true, encoding: .utf8)
        try "คำค้น".write(toFile: (workspace as NSString).appendingPathComponent("b.swift"),
                        atomically: true, encoding: .utf8)

        let result = await SearchContentTool().execute(arguments: [
            "pattern": .string("คำค้น"),
            "path": .string(workspace),
            "extensions": .string("swift")
        ], context: Phase6TestSupport.context(workspace: workspace))

        XCTAssertFalse(result.isError, result.text)
        XCTAssertTrue(result.text.contains("b.swift"), result.text)
        XCTAssertFalse(result.text.contains("a.md"), result.text)
    }

    func testSearchContentReportsWhenNothingFound() async throws {
        let workspace = try Phase6TestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(atPath: workspace) }

        try "มีแค่ข้อความนี้".write(toFile: (workspace as NSString).appendingPathComponent("a.txt"),
                                  atomically: true, encoding: .utf8)

        let result = await SearchContentTool().execute(arguments: [
            "pattern": .string("ไม่มีทางเจอ"),
            "path": .string(workspace)
        ], context: Phase6TestSupport.context(workspace: workspace))

        XCTAssertFalse(result.isError)
        XCTAssertTrue(result.text.contains("ไม่พบข้อความ"))
    }

    func testSearchContentRejectsBrokenRegex() async {
        let result = await SearchContentTool().execute(arguments: ["pattern": .string("([")],
                                                       context: Phase6TestSupport.context(workspace: "/tmp"))
        XCTAssertTrue(result.isError)
        XCTAssertEqual(result.kind, .invalidArguments)
    }

    func testSearchContentReportsMissingFolder() async {
        let result = await SearchContentTool().execute(arguments: [
            "pattern": .string("x"),
            "path": .string("/tmp/ไม่มีโฟลเดอร์นี้-\(UUID().uuidString)")
        ], context: Phase6TestSupport.context(workspace: "/tmp"))
        XCTAssertTrue(result.isError)
        XCTAssertEqual(result.kind, .notFound)
    }
}

// MARK: - ตัวช่วยสำหรับเทสต์ (สร้างโฟลเดอร์ชั่วคราว + บริบทของ tool)

enum Phase6TestSupport {

    static func makeTempDirectory() throws -> String {
        let path = NSTemporaryDirectory() + "phase6-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        return path
    }

    static func context(workspace: String, approved: Bool = true) -> ToolExecutionContext {
        ToolExecutionContext(workspacePath: workspace,
                             allowInternet: false,
                             wifiOnly: false,
                             isWiFiConnected: false,
                             maxDownloadBytes: 200 * 1024 * 1024,
                             isApproved: approved)
    }
}

final class Phase6ChatSearchTests: XCTestCase {

    func testSnippetCentersAroundQueryAndMarksTruncation() {
        let text = String(repeating: "ก", count: 100) + "คำค้น" + String(repeating: "ข", count: 100)
        let snippet = ChatSearchIndex.snippet(in: text, around: "คำค้น", context: 10)
        let value = snippet ?? ""
        XCTAssertTrue(value.contains("คำค้น"))
        XCTAssertTrue(value.hasPrefix("…"))
        XCTAssertTrue(value.hasSuffix("…"))
        XCTAssertTrue(value.count < 40)
    }

    func testSnippetIsNilWhenQueryIsAbsent() {
        XCTAssertNil(ChatSearchIndex.snippet(in: "ข้อความทั่วไป", around: "ไม่มีคำนี้"))
    }

    func testSnippetIgnoresCaseAndFlattensNewlines() {
        let snippet = ChatSearchIndex.snippet(in: "บรรทัดแรก\nมี HELLO อยู่", around: "hello")
        let value = snippet ?? ""
        XCTAssertTrue(value.contains("HELLO"))
        XCTAssertFalse(value.contains("\n"))
    }

    func testSearchRequiresMinimumLength() {
        let room = ChatRoom(id: UUID(), name: "ห้องทดสอบ", createdAt: Date(), updatedAt: Date(),
                            messageCount: 1, preview: "")
        let hits = ChatSearchIndex.search(query: "ก", rooms: [room], messagesForRoom: { _ in
            [ChatMessage.user("กขคง")]
        })
        XCTAssertTrue(hits.isEmpty)
    }

    func testSearchFindsMatchesAcrossRoomsNewestFirst() {
        let older = ChatRoom(id: UUID(), name: "ห้องเก่า", createdAt: Date().addingTimeInterval(-600),
                             updatedAt: Date().addingTimeInterval(-600), messageCount: 1, preview: "")
        let newer = ChatRoom(id: UUID(), name: "ห้องใหม่", createdAt: Date(), updatedAt: Date(),
                             messageCount: 1, preview: "")

        let store: [UUID: [ChatMessage]] = [
            older.id: [ChatMessage.user("มีคำว่า เป้าหมาย อยู่ในห้องเก่า")],
            newer.id: [ChatMessage.assistant("ห้องใหม่ก็มี เป้าหมาย เหมือนกัน")]
        ]

        let hits = ChatSearchIndex.search(query: "เป้าหมาย", rooms: [older, newer],
                                          messagesForRoom: { store[$0] ?? [] })
        XCTAssertEqual(hits.count, 2)
        XCTAssertEqual(hits[0].roomName, "ห้องใหม่")     // ใหม่ก่อน
        XCTAssertEqual(hits[0].roleLabel, "ผู้ช่วย")
        XCTAssertEqual(hits[1].roomName, "ห้องเก่า")
        XCTAssertEqual(hits[1].roleLabel, "ผู้ใช้")
    }

    func testSearchRespectsLimit() {
        let room = ChatRoom(id: UUID(), name: "ห้อง", createdAt: Date(), updatedAt: Date(),
                            messageCount: 10, preview: "")
        let messages = (0..<10).map { ChatMessage.user("ข้อความที่ \($0) มีคำค้นซ้ำ") }
        let hits = ChatSearchIndex.search(query: "คำค้น", rooms: [room], messagesForRoom: { _ in messages }, limit: 3)
        XCTAssertEqual(hits.count, 3)
    }

    func testSearchSkipsEmptyTexts() {
        let room = ChatRoom(id: UUID(), name: "ห้อง", createdAt: Date(), updatedAt: Date(),
                            messageCount: 2, preview: "")
        let hits = ChatSearchIndex.search(query: "อะไรก็ได้", rooms: [room], messagesForRoom: { _ in
            [ChatMessage.assistant(""), ChatMessage.user("มีคำว่า อะไรก็ได้ อยู่")]
        })
        XCTAssertEqual(hits.count, 1)
    }
}
