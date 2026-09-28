//
//  Phase3Tests.swift
//  iOS Agent Sandbox — ชุดทดสอบแกนกลางของเฟส 3
//
//  ทดสอบ "ของจริง" ของเฟส 3 ด้วยไฟล์ต้นฉบับของแอป:
//    • นโยบายสิทธิ์ (PrivilegePolicy): การเลือกโหมดรัน, ลำดับการหา shell, คำอธิบาย entitlements 5 คีย์
//    • ตัวสร้างไฟล์ .entitlements: ต้องเป็น plist ที่อ่านกลับได้และมีค่าตรงกับที่ออกแบบ
//    • ชั้นไฟล์ (FileSystemService): อ่าน/เขียน/ต่อท้าย/ลบ/ย้าย/ลิสต์ + ข้อความ error ภาษาไทย
//    • กฎหน่วยความจำ: อ่านไฟล์ใหญ่ต้องไม่โหลดทั้งไฟล์ (อ่านตามที่ขอเท่านั้น)
//    • ShellService: posix_spawn จริง, แยก stdout/stderr, รหัสออก, หมดเวลาแล้วฆ่าโปรเซส
//    • EntitlementProbe: สแกน entitlements จากไฟล์จริง (รวมกรณีคีย์ตกขอบก้อน)
//    • PrivilegeService: ตรวจสิทธิ์/เขียนไฟล์ entitlements/แคช
//    • ShellTool: ผลลัพธ์ต้องบอกว่า "รันในนามใคร"
//
//  ใช้ XCTest มาตรฐาน จึงรันได้ทั้ง Linux และ macOS (บน macOS คือโค้ดเส้นทางเดียวกับ iOS
//  เพราะ #if canImport(Darwin) ถูกคอมไพล์จริง)
//

import XCTest
@testable import OpenRouterCore

final class Phase3Tests: XCTestCase {

    // MARK: - ที่พักไฟล์ชั่วคราว

    private var scratchDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("phase3-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
        scratchDirectory = url
    }

    override func tearDownWithError() throws {
        if let scratchDirectory, FileManager.default.fileExists(atPath: scratchDirectory.path) {
            try? FileManager.default.removeItem(at: scratchDirectory)
        }
        try super.tearDownWithError()
    }

    private func scratchPath(_ name: String) -> String {
        scratchDirectory.appendingPathComponent(name).path
    }

    @discardableResult
    private func writeFixture(_ contents: String, to name: String) throws -> String {
        let path = scratchPath(name)
        try Data(contents.utf8).write(to: URL(fileURLWithPath: path))
        return path
    }

    // MARK: - 1) PrivilegePolicy: คีย์ entitlements

    func testEntitlementCatalogueHasTheFiveKeys() {
        let keys = PrivilegePolicy.entitlements.map { $0.key }
        XCTAssertEqual(PrivilegePolicy.entitlements.count, 5, "ต้องมี 5 คีย์ตามข้อกำหนดของเฟส 3")
        XCTAssertEqual(keys, [
            "platform-application",
            "com.apple.private.security.no-container",
            "com.apple.private.security.no-sandbox",
            "com.apple.private.persona-mgmt",
            "com.apple.private.security.container-required"
        ])
    }

    func testEntitlementExpectedValues() {
        let byKey = Dictionary(uniqueKeysWithValues: PrivilegePolicy.entitlements.map { ($0.key, $0) })

        XCTAssertEqual(byKey["platform-application"]?.expectedValue, true)
        XCTAssertEqual(byKey["com.apple.private.security.no-container"]?.expectedValue, true)
        XCTAssertEqual(byKey["com.apple.private.security.no-sandbox"]?.expectedValue, true)
        XCTAssertEqual(byKey["com.apple.private.persona-mgmt"]?.expectedValue, true)
        XCTAssertEqual(byKey["com.apple.private.security.container-required"]?.expectedValue, false)

        // ทุกคีย์ต้องมีคำอธิบายภาษาไทยที่พร้อมแสดงให้ผู้ใช้
        for explanation in PrivilegePolicy.entitlements {
            XCTAssertFalse(explanation.thaiName.isEmpty, "\(explanation.key): ต้องมีชื่อไทย")
            XCTAssertFalse(explanation.effect.isEmpty, "\(explanation.key): ต้องอธิบายผล")
            XCTAssertFalse(explanation.withoutIt.isEmpty, "\(explanation.key): ต้องอธิบายเมื่อไม่มีคีย์")
        }
    }

    func testEntitlementsPlistIsValidAndMatchesCatalogue() throws {
        let xml = PrivilegePolicy.entitlementsPlistXML(comment: "ทดสอบ")
        let data = Data(xml.utf8)

        let parsed = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        guard let dictionary = parsed as? [String: Any] else {
            return XCTFail("entitlements ที่สร้างต้องเป็น plist ชนิด dictionary")
        }

        XCTAssertEqual(dictionary.count, 5)
        XCTAssertEqual(dictionary["platform-application"] as? Bool, true)
        XCTAssertEqual(dictionary["com.apple.private.security.no-container"] as? Bool, true)
        XCTAssertEqual(dictionary["com.apple.private.security.no-sandbox"] as? Bool, true)
        XCTAssertEqual(dictionary["com.apple.private.persona-mgmt"] as? Bool, true)
        XCTAssertEqual(dictionary["com.apple.private.security.container-required"] as? Bool, false)
        XCTAssertTrue(xml.contains("<key>com.apple.private.security.no-sandbox</key>"))
    }

    // MARK: - 2) PrivilegePolicy: การเลือกโหมดรัน

    func testLaunchModeWhenRoot() {
        let decision = PrivilegePolicy.decideLaunchMode(preferRoot: true, canUsePersona: true, currentUserID: 0)
        XCTAssertEqual(decision.mode, .currentUser)
        XCTAssertTrue(decision.reason.contains("root"), decision.reason)
    }

    func testLaunchModeWhenUserDisabledRoot() {
        let decision = PrivilegePolicy.decideLaunchMode(preferRoot: false, canUsePersona: true, currentUserID: 501)
        XCTAssertEqual(decision.mode, .currentUser)
        XCTAssertTrue(decision.reason.contains("ปิดตัวเลือก"), decision.reason)
    }

    func testLaunchModeWhenPersonaUnavailable() {
        let decision = PrivilegePolicy.decideLaunchMode(preferRoot: true, canUsePersona: false, currentUserID: 501)
        XCTAssertEqual(decision.mode, .currentUser)
        XCTAssertTrue(decision.reason.contains("persona"), decision.reason)
    }

    func testLaunchModeRootPersonaWhenEverythingIsReady() {
        let decision = PrivilegePolicy.decideLaunchMode(preferRoot: true, canUsePersona: true, currentUserID: 501)
        XCTAssertEqual(decision.mode, .rootPersona)
        XCTAssertTrue(decision.reason.contains("\(PrivilegePolicy.rootPersonaID)"), decision.reason)
    }

    func testPersonaConstants() {
        XCTAssertEqual(PrivilegePolicy.rootPersonaID, 99)
        XCTAssertEqual(PrivilegePolicy.personaFlagsOverride, 1)
    }

    // MARK: - 3) PrivilegePolicy: shell และ environment

    func testShellSearchPathsPutRootlessJailbreakFirst() {
        XCTAssertEqual(PrivilegePolicy.shellSearchPaths.first, "/var/jb/bin/sh")
        XCTAssertTrue(PrivilegePolicy.shellSearchPaths.contains("/bin/sh"))
        XCTAssertEqual(PrivilegePolicy.shellSearchPaths.count, Set(PrivilegePolicy.shellSearchPaths).count,
                       "ต้องไม่มี path ซ้ำ")
    }

    func testShellPathContainsJailbreakBinaries() {
        XCTAssertTrue(PrivilegePolicy.shellPath.contains("/var/jb/usr/bin"))
        XCTAssertTrue(PrivilegePolicy.shellPath.contains("/usr/bin"))
        XCTAssertTrue(PrivilegePolicy.shellPath.contains("/bin"))
    }

    func testEnvironmentDiffersBetweenRootAndUser() {
        let asRoot = PrivilegePolicy.environment(uid: 0, temporaryDirectory: "/tmp/x")
        let asUser = PrivilegePolicy.environment(uid: 501, temporaryDirectory: "/tmp/x")

        XCTAssertTrue(asRoot.contains("HOME=/var/root"))
        XCTAssertTrue(asUser.contains("HOME=/var/mobile"))
        XCTAssertTrue(asRoot.allSatisfy { $0.contains("=") })
        XCTAssertTrue(asRoot.contains("TMPDIR=/tmp/x"))
        XCTAssertTrue(asRoot.contains { $0.hasPrefix("PATH=") && $0.contains("/var/jb/usr/bin") })
    }

    func testInstallKindDetection() {
        XCTAssertEqual(PrivilegePolicy.installKind(bundlePath: "/var/containers/Bundle/Application/AB/App.app"),
                       .trollStoreOrPermasigned)
        XCTAssertEqual(PrivilegePolicy.installKind(bundlePath: "/Applications/App.app"), .rootfulJailbreak)
        XCTAssertEqual(PrivilegePolicy.installKind(bundlePath: "/var/jb/Applications/App.app"), .rootlessJailbreak)
        if case .unknown = PrivilegePolicy.installKind(bundlePath: "/Users/dev/build/App.app") {
            // ถูกต้อง
        } else {
            XCTFail("path ที่ไม่รู้จักต้องได้ .unknown")
        }
    }

    // MARK: - 4) FileSystemService: อ่าน/เขียน

    func testWriteThenReadPrefix() throws {
        let path = scratchPath("note.txt")
        let report = try FileSystemService.write("สวัสดี agent\nบรรทัดสอง", to: path)

        XCTAssertEqual(report.bytesWritten, Data("สวัสดี agent\nบรรทัดสอง".utf8).count)
        XCTAssertFalse(report.didOverwriteExisting)
        XCTAssertEqual(report.finalSizeBytes, Int64(report.bytesWritten))

        let prefix = try FileSystemService.readPrefix(path)
        XCTAssertTrue(prefix.text.contains("สวัสดี agent"))
        XCTAssertTrue(prefix.text.contains("บรรทัดสอง"))
        XCTAssertFalse(prefix.isBinary)
        XCTAssertFalse(prefix.hasMore)
        XCTAssertEqual(prefix.bytesRead, report.bytesWritten)
    }

    func testWriteAppendAndOverwrite() throws {
        let path = scratchPath("log.txt")
        try FileSystemService.write("เส้นแรก\n", to: path)
        let appended = try FileSystemService.write("เส้นที่สอง\n", to: path, append: true)

        XCTAssertTrue(appended.didOverwriteExisting)
        XCTAssertEqual(try FileSystemService.readPrefix(path).text, "เส้นแรก\nเส้นที่สอง\n")

        let overwritten = try FileSystemService.write("เขียนใหม่", to: path)
        XCTAssertTrue(overwritten.didOverwriteExisting)
        XCTAssertEqual(try FileSystemService.readPrefix(path).text, "เขียนใหม่")
    }

    func testWriteCreatesIntermediateDirectories() throws {
        let path = scratchDirectory.appendingPathComponent("a/b/c/deep.txt").path
        XCTAssertFalse(FileSystemService.exists(path))
        try FileSystemService.write("ลึก", to: path)
        XCTAssertTrue(FileSystemService.exists(path))
        XCTAssertEqual(try FileSystemService.readPrefix(path).text, "ลึก")
    }

    /// กฎ RAM: อ่านไฟล์ 3MB โดยขอแค่ 4KB ต้องได้ไม่เกิน 4KB (ไม่โหลดทั้งไฟล์)
    func testReadPrefixDoesNotLoadWholeLargeFile() throws {
        let path = scratchPath("large.bin")
        let block = Data(repeating: 0x41, count: 64 * 1024)   // 64KB ของ 'A'
        FileManager.default.createFile(atPath: path, contents: nil, attributes: nil)

        let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: path))
        for _ in 0..<48 {                                    // 48 × 64KB = 3MB
            try handle.write(contentsOf: block)
        }
        FileSystemService.closeQuietly(handle)

        let prefix = try FileSystemService.readPrefix(path, maxBytes: 4096)
        XCTAssertEqual(prefix.bytesRead, 4096)
        XCTAssertEqual(prefix.text.count, 4096)
        XCTAssertTrue(prefix.hasMore)
        XCTAssertEqual(prefix.totalBytes, 3 * 1024 * 1024)
        XCTAssertLessThanOrEqual(FileSystemService.maxReadBytes, 512 * 1024,
                                 "เพดานการอ่านครั้งเดียวต้องเล็กพอสำหรับเครื่อง RAM 2GB")
    }

    func testReadAllRespectsLimit() throws {
        let path = try writeFixture("0123456789", to: "small.txt")

        let data = try FileSystemService.readAll(path, limitBytes: 1024)
        XCTAssertEqual(data.count, 10)

        XCTAssertThrowsError(try FileSystemService.readAll(path, limitBytes: 4)) { error in
            guard let fileError = error as? FileSystemError else {
                return XCTFail("ต้องเป็น FileSystemError, ได้: \(error)")
            }
            if case .tooLarge = fileError { } else {
                XCTFail("ต้องเป็น .tooLarge, ได้: \(fileError)")
            }
        }
    }

    // MARK: - 5) FileSystemService: ข้อมูลไฟล์/ลิสต์/ลบ/ย้าย

    func testAttributesAndPermissionsText() throws {
        let path = try writeFixture("hello", to: "info.txt")
        let attributes = try FileSystemService.attributes(of: path)

        XCTAssertFalse(attributes.isDirectory)
        XCTAssertFalse(attributes.isSymbolicLink)
        XCTAssertEqual(attributes.sizeBytes, 5)
        XCTAssertEqual(attributes.kindText, "ไฟล์")
        XCTAssertEqual(attributes.sizeText, NetworkPolicy.formatBytes(5))
        XCTAssertNotNil(attributes.modificationDate)
        if let permissions = attributes.permissionsText {
            XCTAssertEqual(permissions.count, 9)
        } else {
            XCTFail("ควรอ่านสิทธิ์ของไฟล์ได้บนแพลตฟอร์มนี้")
        }
    }

    func testPermissionTextFormatting() {
        XCTAssertEqual(FileSystemService.permissionText(0o644), "rw-r--r--")
        XCTAssertEqual(FileSystemService.permissionText(0o755), "rwxr-xr-x")
        XCTAssertEqual(FileSystemService.permissionText(0o000), "---------")
    }

    func testAttributesOfMissingPathThrowsThaiError() {
        let missing = scratchPath("ไม่มีอยู่จริง.txt")
        XCTAssertThrowsError(try FileSystemService.attributes(of: missing)) { error in
            guard let fileError = error as? FileSystemError else {
                return XCTFail("ต้องเป็น FileSystemError")
            }
            XCTAssertEqual(fileError.toolErrorKind, .notFound)
            XCTAssertTrue(fileError.localizedDescription.contains("ไม่พบไฟล์หรือโฟลเดอร์"), fileError.localizedDescription)
        }
    }

    func testListSortsDirectoriesFirstAndReportsHidden() throws {
        try FileSystemService.createDirectory(scratchPath("zeta-dir"))
        try FileSystemService.createDirectory(scratchPath("alpha-dir"))
        try writeFixture("1", to: "beta.txt")
        try writeFixture("2", to: ".hidden")

        let listing = try FileSystemService.list(scratchDirectory.path)
        let names = listing.entries.map { $0.name }

        XCTAssertEqual(names.first, "alpha-dir", "โฟลเดอร์ต้องมาก่อนและเรียงตามชื่อ")
        XCTAssertEqual(names.dropFirst().first, "zeta-dir")
        XCTAssertEqual(listing.skippedHidden, 1)
        XCTAssertFalse(names.contains(".hidden"))
        XCTAssertEqual(listing.totalCount, 3, "totalCount นับเฉพาะรายการที่ไม่ถูกซ่อน (2 โฟลเดอร์ + 1 ไฟล์)")

        let withHidden = try FileSystemService.list(scratchDirectory.path, includeHidden: true)
        XCTAssertTrue(withHidden.entries.contains { $0.name == ".hidden" })
    }

    func testListRespectsLimit() throws {
        for index in 0..<6 {
            try writeFixture("x", to: String(format: "file-%02d.txt", index))
        }
        let listing = try FileSystemService.list(scratchDirectory.path, limit: 3)
        XCTAssertEqual(listing.entries.count, 3)
        XCTAssertEqual(listing.totalCount, 6)
    }

    func testListRejectsNonDirectory() throws {
        let path = try writeFixture("x", to: "plain.txt")
        XCTAssertThrowsError(try FileSystemService.list(path)) { error in
            guard let fileError = error as? FileSystemError else {
                return XCTFail("ต้องเป็น FileSystemError")
            }
            XCTAssertEqual(fileError, .notADirectory(path))
        }
    }

    func testRemoveRefusesNonEmptyDirectoryWithoutRecursive() throws {
        let directory = scratchPath("with-child")
        try FileSystemService.createDirectory(directory)
        try writeFixture("x", to: "with-child/child.txt")

        XCTAssertThrowsError(try FileSystemService.remove(directory)) { error in
            guard let fileError = error as? FileSystemError else {
                return XCTFail("ต้องเป็น FileSystemError")
            }
            XCTAssertEqual(fileError.toolErrorKind, .failed)
            XCTAssertTrue(fileError.localizedDescription.contains("ไม่ว่าง"), fileError.localizedDescription)
        }

        try FileSystemService.remove(directory, recursive: true)
        XCTAssertFalse(FileSystemService.exists(directory))
    }

    func testMoveAndCopyBehaviour() throws {
        let source = try writeFixture("ต้นทาง", to: "move-me.txt")
        let destination = scratchPath("moved/renamed.txt")

        try FileSystemService.move(source, to: destination)
        XCTAssertFalse(FileSystemService.exists(source))
        XCTAssertEqual(try FileSystemService.readPrefix(destination).text, "ต้นทาง")

        // ย้ายทับโดยไม่อนุญาต → ต้องได้ alreadyExists
        let second = try writeFixture("อีกไฟล์", to: "second.txt")
        XCTAssertThrowsError(try FileSystemService.move(second, to: destination)) { error in
            guard let fileError = error as? FileSystemError else {
                return XCTFail("ต้องเป็น FileSystemError")
            }
            XCTAssertEqual(fileError.toolErrorKind, .failed)
            XCTAssertTrue(fileError.localizedDescription.contains("มีอยู่แล้ว"), fileError.localizedDescription)
        }

        try FileSystemService.move(second, to: destination, overwrite: true)
        XCTAssertEqual(try FileSystemService.readPrefix(destination).text, "อีกไฟล์")

        // คัดลอกไม่ทับต้นทาง
        let copyTarget = scratchPath("copied.txt")
        try FileSystemService.copy(destination, to: copyTarget)
        XCTAssertTrue(FileSystemService.exists(destination))
        XCTAssertEqual(try FileSystemService.readPrefix(copyTarget).text, "อีกไฟล์")
    }

    func testVolumeSpaceLookup() {
        let space = FileSystemService.volumeSpace(at: scratchDirectory.path)
        XCTAssertNotNil(space, "ควรอ่านพื้นที่ว่างของโวลุ่มได้")
        if let space {
            XCTAssertGreaterThan(space.total, 0)
            XCTAssertLessThanOrEqual(space.free, space.total)
        }
    }

    // MARK: - 6) ตัวช่วยเข้ารหัส/แสดงไฟล์

    func testBinaryDetectionAndChunkDecoding() {
        XCTAssertTrue(FileSystemService.looksBinary(Data([0x50, 0x4B, 0x00, 0x01])))
        XCTAssertFalse(FileSystemService.looksBinary(Data("ข้อความธรรมดา".utf8)))

        XCTAssertEqual(FileSystemService.chunkDecode(Data("ภาษาไทย".utf8)), "ภาษาไทย")

        // ไบต์สุดท้ายถูกตัดกลางตัวอักษร → ต้องไม่เหลืออักขระแทนค่า (U+FFFD)
        let truncated = Data(Array("ไทย".utf8).dropLast(1))
        let decoded = FileSystemService.chunkDecode(truncated)
        XCTAssertFalse(decoded.unicodeScalars.contains { $0.value == 0xFFFD },
                       "ต้องตัดไบต์ที่ค้างออก ไม่ทิ้งอักขระเพี้ยน")
    }

    func testHexPreviewLayout() {
        let preview = FileSystemService.hexPreview(Data("AB".utf8), maxBytes: 16)
        XCTAssertTrue(preview.hasPrefix("00000000  "), preview)
        XCTAssertTrue(preview.contains("41 42"), preview)
        XCTAssertTrue(preview.contains("|AB"), preview)
    }

    func testFileSystemErrorMessagesAreThai() {
        XCTAssertTrue(FileSystemError.permissionDenied("/var/mobile/x").localizedDescription.contains("ไม่มีสิทธิ์"))
        XCTAssertTrue(FileSystemError.isADirectory("/tmp").localizedDescription.contains("เป็นโฟลเดอร์"))
        XCTAssertEqual(FileSystemError.cancelled.toolErrorKind, .cancelled)
        XCTAssertEqual(FileSystemError.permissionDenied("/x").toolErrorKind, .permissionDenied)

        let cocoa = NSError(domain: NSPOSIXErrorDomain, code: Int(EACCES), userInfo: nil)
        let mapped = FileSystemService.map(cocoa, path: "/var/mobile/x")
        XCTAssertEqual(mapped, .permissionDenied("/var/mobile/x"))
    }

    func testChunkedFileReaderAliasDelegates() throws {
        let path = try writeFixture("แถวข้อมูล\n", to: "alias.txt")
        let prefix = try ChunkedFileReader.readPrefix(path: path)
        XCTAssertEqual(prefix.text, "แถวข้อมูล\n")
        XCTAssertEqual(ChunkedFileReader.decode(Data("ไทย".utf8)), "ไทย")
        XCTAssertFalse(ChunkedFileReader.looksBinary(Data("ไทย".utf8)))
        XCTAssertEqual(ChunkedFileReader.chunkSize, 64 * 1024)
    }

    // MARK: - 7) ShellService: รันคำสั่งจริงด้วย posix_spawn

    func testShellRunsCommandAndCapturesStdout() async throws {
        let result = try await ShellService.shared.run(command: "echo ตรวจสอบ-shell-ok",
                                                       timeout: 15,
                                                       preferRoot: false)

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("ตรวจสอบ-shell-ok"), result.stdout)
        XCTAssertTrue(result.stderr.isEmpty, result.stderr)
        XCTAssertFalse(result.timedOut)
        XCTAssertFalse(result.wasCancelled)
        XCTAssertNotNil(result.shellPath)
        XCTAssertEqual(result.launchMode, .currentUser)
        XCTAssertFalse(result.launchReason.isEmpty)
        XCTAssertNil(result.privilegeWarning)
        XCTAssertLessThan(result.duration, 15)
    }

    func testShellCapturesStderrAndExitCode() async throws {
        let result = try await ShellService.shared.run(command: "echo ปัญหา >&2; exit 3", timeout: 15)

        XCTAssertEqual(result.exitCode, 3)
        XCTAssertTrue(result.stderr.contains("ปัญหา"), result.stderr)
        XCTAssertFalse(result.timedOut)
    }

    func testShellWorkingDirectory() async throws {
        let result = try await ShellService.shared.run(command: "pwd", timeout: 15, workingDirectory: "/tmp")
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("/tmp"), result.stdout)
    }

    func testShellHonoursPreferRootFlagOnThisPlatform() async throws {
        // บน Linux/macOS ไม่มีฟังก์ชัน persona ของ XNU → ต้องถอยไปรันแบบผู้ใช้ปัจจุบัน และบอกเหตุผล
        let result = try await ShellService.shared.run(command: "echo persona-check", timeout: 15, preferRoot: true)

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.launchMode, .currentUser)
        XCTAssertFalse(result.launchReason.isEmpty)
    }

    func testShellTimeoutKillsLongCommand() async throws {
        let started = Date()
        let result = try await ShellService.shared.run(command: "sleep 6", timeout: 1)
        let elapsed = Date().timeIntervalSince(started)

        XCTAssertTrue(result.timedOut, "คำสั่งที่ค้างต้องถูกรายงานว่าหมดเวลา")
        XCTAssertLessThan(elapsed, 5, "ต้องฆ่าโปรเซสทันทีเมื่อหมดเวลา (ใช้เวลา \(elapsed) วินาที)")
    }

    func testShellRejectsEmptyCommand() async {
        do {
            _ = try await ShellService.shared.run(command: "   ")
            XCTFail("คำสั่งว่างต้องไม่ถูกรัน")
        } catch {
            XCTAssertTrue(error is ShellError)
        }
    }

    // MARK: - 8) ShellTool: ผลลัพธ์ต้องบอกโหมดการรัน (เฟส 3)

    func testShellToolReportsLaunchModeInOutput() async {
        let context = ToolExecutionContext(workspacePath: scratchDirectory.path,
                                          allowInternet: false,
                                          wifiOnly: false,
                                          isWiFiConnected: false,
                                          maxDownloadBytes: 1_000_000,
                                          isApproved: true,
                                          runShellAsRoot: false)

        let result = await ExecuteShellTool().execute(arguments: ["command": .string("echo tool-phase3")], context: context)
        XCTAssertFalse(result.isError, result.text)
        XCTAssertTrue(result.text.contains("รันในนาม:"), result.text)
        XCTAssertTrue(result.text.contains("exit code: 0"), result.text)
        XCTAssertTrue(result.text.contains("tool-phase3"), result.text)
    }

    // MARK: - 9) EntitlementProbe

    func testEntitlementProbeFindsKeysInPlantedFile() throws {
        let xml = PrivilegePolicy.entitlementsPlistXML(comment: "โพรบ")
        let path = try writeFixture(xml, to: "planted-entitlements.txt")

        let scan = EntitlementProbe.scan(path: path)
        XCTAssertEqual(scan.missingKeys, [])
        XCTAssertTrue(scan.hasAllFive)
        XCTAssertEqual(scan.foundKeys.count, 5)
        XCTAssertGreaterThan(scan.totalMatches, 0)
        XCTAssertNil(scan.readErrorText)
        XCTAssertTrue(scan.summaryText.contains("พบครบทั้ง 5 คีย์"), scan.summaryText)
    }

    func testEntitlementProbeReportsMissingKeys() throws {
        // ไฟล์ที่มีแค่ 2 คีย์จาก 5
        let partial = """
        <plist version="1.0"><dict>
        <key>platform-application</key>
        <true/>
        <key>com.apple.private.security.no-sandbox</key>
        <true/>
        </dict></plist>
        """
        let path = try writeFixture(partial, to: "partial-entitlements.txt")
        let scan = EntitlementProbe.scan(path: path)

        XCTAssertEqual(scan.foundKeys, ["platform-application", "com.apple.private.security.no-sandbox"])
        XCTAssertEqual(scan.missingKeys.count, 3)
        XCTAssertFalse(scan.hasAllFive)
    }

    /// คีย์ที่ตกขอบก้อนอ่าน (ข้ามขอบ chunk) ต้องยังเจอ — ทดสอบ overlap ของตัวสแกน
    func testEntitlementProbeFindsKeyAcrossChunkBoundary() throws {
        let key = "com.apple.private.security.no-container"
        let padding = String(repeating: "x", count: EntitlementProbe.chunkSize - 10)
        let content = padding + "<key>\(key)</key><true/>" +
            String(repeating: "y", count: 1024)
        let path = try writeFixture(content, to: "boundary.txt")

        let scan = EntitlementProbe.scan(path: path, keys: [key])
        XCTAssertEqual(scan.foundKeys, [key], "ต้องเจอคีย์ที่พาดขอบก้อน: \(scan.summaryText)")
        XCTAssertTrue(scan.missingKeys.isEmpty)
    }

    func testEntitlementProbeHandlesMissingFile() {
        let scan = EntitlementProbe.scan(path: scratchPath("ไม่มีไฟล์นี้"))
        XCTAssertNotNil(scan.readErrorText)
        XCTAssertEqual(scan.missingKeys.count, 5)
        XCTAssertFalse(scan.hasAllFive)
    }

    func testEntitlementProbeScansDataInMemory() {
        let xml = PrivilegePolicy.entitlementsPlistXML()
        let result = EntitlementProbe.scan(data: Data(xml.utf8))
        XCTAssertEqual(result.found.count, 5)
        XCTAssertTrue(result.missing.isEmpty)
    }

    // MARK: - 10) PrivilegeService

    func testWritabilityProbe() throws {
        XCTAssertTrue(PrivilegeService.isWritable(scratchDirectory.path))
        XCTAssertFalse(PrivilegeService.isWritable(scratchPath("ไม่มีโฟลเดอร์นี้")))
        XCTAssertTrue(PrivilegeService.isReadable(scratchDirectory.path))
        XCTAssertFalse(PrivilegeService.isReadable(scratchPath("ไม่มีโฟลเดอร์นี้")))

        // ต้องไม่ทิ้งไฟล์ทดสอบไว้ในเครื่อง
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: scratchDirectory.path)
            .filter { $0.hasPrefix(".iosagent-writecheck-") }
        XCTAssertTrue(leftovers.isEmpty, "ไฟล์ทดสอบการเขียนต้องถูกลบ: \(leftovers)")
    }

    func testEnsureWorkspaceCreatesDirectory() throws {
        let path = scratchPath("workspace-ใหม่")
        XCTAssertFalse(FileSystemService.exists(path))
        XCTAssertTrue(PrivilegeService.ensureWorkspace(path))
        XCTAssertTrue(FileSystemService.isDirectory(path) == true)
        XCTAssertTrue(PrivilegeService.ensureWorkspace(path), "เรียกซ้ำต้องได้ true")
    }

    func testProbeProducesReportAndAdvice() {
        let report = PrivilegeService.probe(workspacePath: scratchDirectory.path, preferRootShell: true)

        XCTAssertEqual(report.checklist.count, 8)
        XCTAssertFalse(report.summaryText.isEmpty)
        XCTAssertFalse(report.promptContext.isEmpty)
        XCTAssertTrue(report.promptContext.contains("สิทธิ์ของแอป"), report.promptContext)
        XCTAssertTrue(report.workspaceWritable, "โฟลเดอร์ชั่วคราวต้องเขียนได้")
        XCTAssertFalse(report.pendingAdvice.isEmpty, "ต้องมีคำแนะนำอย่างน้อยหนึ่งข้อเสมอ")
        XCTAssertNotNil(report.entitlements, "ต้องสแกน entitlements ของไบนารีที่กำลังรัน")
    }

    func testWriteEntitlementsFileProducesReadablePlist() throws {
        let report = try PrivilegeService.writeEntitlementsFile(to: scratchDirectory.path)

        XCTAssertTrue(FileSystemService.exists(report.path))
        XCTAssertTrue(report.path.hasSuffix("iOSAgentSandbox.entitlements"))

        let data = try FileSystemService.readAll(report.path, limitBytes: 64 * 1024)
        let parsed = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        let dictionary = parsed as? [String: Any]
        XCTAssertEqual(dictionary?.count, 5)
        XCTAssertEqual(dictionary?["com.apple.private.security.container-required"] as? Bool, false)
    }

    func testPrivilegeCacheReusesThenRefreshes() {
        PrivilegeService.invalidateCache()
        let first = PrivilegeService.cachedReport(workspacePath: scratchDirectory.path, preferRootShell: true)
        let second = PrivilegeService.cachedReport(workspacePath: scratchDirectory.path, preferRootShell: true)
        XCTAssertEqual(first.checkedAt, second.checkedAt, "ภายในอายุแคชต้องได้ผลเดิม")

        let other = PrivilegeService.cachedReport(workspacePath: scratchDirectory.path, preferRootShell: false)
        XCTAssertEqual(other.launchDecision.mode, .currentUser)

        PrivilegeService.invalidateCache()
        let third = PrivilegeService.cachedReport(workspacePath: scratchDirectory.path, preferRootShell: true)
        XCTAssertNotEqual(third.checkedAt, first.checkedAt, "ล้างแคชแล้วต้องตรวจใหม่")
    }

    func testRunningOnIOSFlagMatchesPlatform() {
        #if os(iOS)
        XCTAssertTrue(PrivilegeService.isRunningOnIOS())
        #else
        XCTAssertFalse(PrivilegeService.isRunningOnIOS())
        #endif
    }
}
