//
//  Phase2CoreTests.swift
//  iOS Agent Sandbox — ชุดทดสอบแกนกลางของเฟส 2
//
//  ทดสอบ "ตรรกะที่เสี่ยงที่สุด" ของเฟส 2 ด้วยไฟล์ต้นฉบับจริงของแอป:
//    • การอ่าน arguments ที่โมเดลส่งมา (ครบ/ผิดชนิด/ว่าง/ซ่อม JSON ได้)
//    • การตรวจ path (ยุบ .., ~, path ของระบบที่ต้องขออนุมัติ)
//    • การประเมินความเสี่ยงของคำสั่ง shell และการเขียนไฟล์
//    • การตัดทอนผลลัพธ์ที่ 10,000 ตัวอักษร
//    • การจับคู่ชื่อไฟล์แบบ glob
//    • การแปลง HTML → ข้อความ และการอ่านผลค้นหาของ DuckDuckGo
//    • นโยบายเครือข่าย (HTTPS, เปิด/ปิด internet, Wi-Fi เท่านั้น, เพดานขนาดไฟล์)
//    • การตัด context เมื่อบทสนทนายาวเกิน 80%
//
//  ใช้ XCTest มาตรฐาน (ไม่พึ่ง Xcode) จึงรันได้ทั้ง Linux และ macOS
//

import XCTest
@testable import OpenRouterCore

// MARK: - ToolArguments

final class Phase2ToolArgumentsTests: XCTestCase {

    func testRequireStringThrowsWhenMissing() {
        let args = ToolArguments([:])
        XCTAssertThrowsError(try args.string("path")) { error in
            guard case ToolArgumentError.missing(let key) = error else {
                return XCTFail("ควรเป็น missing แต่ได้ \(error)")
            }
            XCTAssertEqual(key, "path")
        }
    }

    func testRequireStringThrowsWhenEmptyAfterTrim() {
        let args = ToolArguments(["path": .string("   ")])
        XCTAssertThrowsError(try args.string("path")) { error in
            guard case ToolArgumentError.empty = error else {
                return XCTFail("ควรเป็น empty แต่ได้ \(error)")
            }
        }
    }

    func testOptionalStringReturnsNilForBlank() {
        let args = ToolArguments(["q": .string("  "), "p": .string(" x ")])
        XCTAssertNil(args.optionalString("q"))
        XCTAssertEqual(args.optionalString("p"), "x")
        XCTAssertNil(args.optionalString("ไม่มีคีย์นี้"))
    }

    func testIntInRangeClampsAndUsesDefault() {
        let args = ToolArguments(["a": .int(9_999), "b": .string("-5")])
        XCTAssertEqual(args.intInRange("a", default: 10, min: 1, max: 100), 100)
        XCTAssertEqual(args.intInRange("b", default: 10, min: 1, max: 100), 1)
        XCTAssertEqual(args.intInRange("missing", default: 42, min: 1, max: 100), 42)
    }

    func testBoolAcceptsStringAndDefault() {
        let args = ToolArguments(["t": .string("true"), "f": .string("false")])
        XCTAssertTrue(args.bool("t", default: false))
        XCTAssertFalse(args.bool("f", default: true))
        XCTAssertTrue(args.bool("ไม่มี", default: true))
    }

    func testStringDictionaryKeepsOnlyStrings() {
        let args = ToolArguments([
            "headers": .object(["A": .string("1"), "B": .int(2)])
        ])
        let headers = args.stringDictionary("headers")
        XCTAssertEqual(headers["A"], "1")
        XCTAssertEqual(headers["B"], "2") // ตัวเลขถูกแปลงเป็นข้อความ (โมเดลมักส่งแบบนี้)
        XCTAssertEqual(headers.count, 2)
    }

    func testStringArrayAcceptsListAndNewlineText() {
        // ค่าที่ไม่ใช่ข้อความถูกแปลงเป็นข้อความ (โมเดลฟรีมักส่งตัวเลขปนมา) — ตั้งใจให้เป็นแบบนี้
        let listArgs = ToolArguments(["items": .array([.string("a"), .string(" b "), .int(3)])])
        XCTAssertEqual(listArgs.stringArray("items"), ["a", "b", "3"])

        let textArgs = ToolArguments(["items": .string("x\ny\n")])
        XCTAssertEqual(textArgs.stringArray("items"), ["x", "y"])
    }

    func testDisplayTextAndInlineSummary() {
        let args = ToolArguments(["path": .string("/var/mobile/a.txt"), "max_lines": .int(50)])
        XCTAssertTrue(args.displayText.contains("\"path\""))
        XCTAssertTrue(args.inlineSummary.contains("max_lines=50"))
        XCTAssertEqual(ToolArguments([:]).displayText, "{}")
        XCTAssertEqual(ToolArguments([:]).inlineSummary, "(ไม่มีพารามิเตอร์)")
    }

    func testParseToolCallRepairsTruncatedJSON() throws {
        // JSON ที่ถูกตัดกลางทางระหว่างสตรีม — ต้องถูกซ่อมก่อนอ่าน
        let call = ToolCall(id: "c1",
                            function: FunctionCall(name: "read_file",
                                                   arguments: "{\"path\":\"/var/mobile/a.txt\",\"max_lines\":"))
        let args = try ToolArguments.parse(call)
        XCTAssertEqual(try args.string("path"), "/var/mobile/a.txt")
        XCTAssertEqual(args.optionalInt("max_lines"), nil)
    }

    func testParseToolCallWithGarbageFallsBackToEmptyArguments() throws {
        // arguments ที่ไม่ใช่ JSON เลย: ตัวซ่อมจะคืน object ว่าง (ไม่โยน error)
        // แล้ว tool จะตอบกลับว่า "ไม่พบพารามิเตอร์ path" ซึ่งเป็นคำใบ้ที่โมเดลแก้เองได้
        let call = ToolCall(id: "c2",
                            function: FunctionCall(name: "read_file", arguments: "ขอโทษครับ ผมอ่านไฟล์ให้ไม่ได้"))
        let args = try ToolArguments.parse(call)
        XCTAssertTrue(args.isEmpty)
        XCTAssertThrowsError(try args.string("path"))
    }
}

// MARK: - PathGuard

final class Phase2PathGuardTests: XCTestCase {

    func testNormalizeRelativePathUsesWorkspace() {
        let path = PathGuard.normalize("notes/today.txt", workspace: "/var/mobile/AgentWorkspace")
        XCTAssertEqual(path, "/var/mobile/AgentWorkspace/notes/today.txt")
    }

    func testNormalizeCollapsesDotsAndDoubleSlashes() {
        XCTAssertEqual(PathGuard.normalize("/var//mobile/./Documents/../Documents/a.txt"),
                       "/var/mobile/Documents/a.txt")
        XCTAssertEqual(PathGuard.normalize("/var/mobile/../../etc/hosts"), "/etc/hosts")
        XCTAssertEqual(PathGuard.normalize("/var/mobile/work/", workspace: "/tmp"), "/var/mobile/work")
        XCTAssertEqual(PathGuard.normalize("/"), "/")
    }

    func testNormalizeExpandsTildeAndStripsQuotes() {
        XCTAssertEqual(PathGuard.normalize("~/Documents/x.txt", home: "/var/mobile"),
                       "/var/mobile/Documents/x.txt")
        XCTAssertEqual(PathGuard.normalize("~", home: "/var/mobile"), "/var/mobile")
        XCTAssertEqual(PathGuard.normalize("'/var/mobile/a b.txt'", workspace: "/tmp"),
                       "/var/mobile/a b.txt")
        XCTAssertEqual(PathGuard.normalize("", workspace: "/var/mobile/AgentWorkspace"),
                       "/var/mobile/AgentWorkspace")
    }

    func testIsWithinWorkspace() {
        let workspace = "/var/mobile/AgentWorkspace"
        XCTAssertTrue(PathGuard.isWithinWorkspace(workspace, workspace: workspace))
        XCTAssertTrue(PathGuard.isWithinWorkspace("sub/dir/file.txt", workspace: workspace))
        XCTAssertFalse(PathGuard.isWithinWorkspace("/var/mobile/Documents/file.txt", workspace: workspace))
    }

    func testProtectedSystemPathsNeedApproval() {
        XCTAssertNotNil(PathGuard.protectionReason(for: "/System/Library/CoreServices/SystemVersion.plist"))
        XCTAssertNotNil(PathGuard.protectionReason(for: "/var/jb/usr/bin/apt"))
        XCTAssertNotNil(PathGuard.protectionReason(for: "/etc/hosts"))
        XCTAssertNotNil(PathGuard.protectionReason(for: "/usr/lib/dyld"))
        XCTAssertNil(PathGuard.protectionReason(for: "/var/mobile/Documents/report.txt"))
        XCTAssertNil(PathGuard.protectionReason(for: "/var/mobile/AgentWorkspace/notes.md"))
    }

    func testSanitizedFileNameRemovesDangerousCharacters() {
        XCTAssertEqual(PathGuard.sanitizedFileName("../../etc/passwd"), ".._.._etc_passwd")
        XCTAssertEqual(PathGuard.sanitizedFileName("  "), "untitled")
        XCTAssertEqual(PathGuard.sanitizedFileName(".."), "untitled")
        XCTAssertEqual(PathGuard.sanitizedFileName("report.txt"), "report.txt")
    }

    func testSuggestedFileNameFromURL() {
        XCTAssertEqual(PathGuard.suggestedFileName(fromURLString: "https://example.com/a/b/file.zip?v=1"),
                       "file.zip")
        XCTAssertEqual(PathGuard.suggestedFileName(fromURLString: "https://example.com/"), "download.bin")
        XCTAssertEqual(PathGuard.suggestedFileName(fromURLString: "ไม่ใช่ url"), "download.bin")
    }

    func testDisplayPathShortensWorkspace() {
        XCTAssertEqual(PathGuard.displayPath("/var/mobile/AgentWorkspace/a/b.txt",
                                             workspace: "/var/mobile/AgentWorkspace"), "~/a/b.txt")
        XCTAssertEqual(PathGuard.displayPath("/etc/hosts", workspace: "/var/mobile/AgentWorkspace"), "/etc/hosts")
    }
}

// MARK: - RiskyCommandDetector

final class Phase2RiskyCommandTests: XCTestCase {

    private let workspace = "/var/mobile/AgentWorkspace"

    func testReadOnlyCommandsAreSafe() {
        for command in ["ls -la /var/mobile", "cat /var/mobile/Documents/a.txt", "df -h",
                        "uname -a", "ps aux | grep SpringBoard", "echo สวัสดี"] {
            let result = RiskyCommandDetector.assess(shellCommand: command, workspace: workspace)
            XCTAssertEqual(result.level, .normal, "คำสั่งอ่านข้อมูลควรปลอดภัย: \(command) → \(result.reasons)")
        }
    }

    func testRmIsDestructive() {
        let result = RiskyCommandDetector.assess(shellCommand: "rm -rf /var/mobile/Documents/temp", workspace: workspace)
        XCTAssertEqual(result.level, .destructive)
        XCTAssertFalse(result.reasons.isEmpty)
    }

    func testRmOnSystemPathIsFlaggedAsSystemRisk() {
        let result = RiskyCommandDetector.assess(shellCommand: "rm /System/Library/x.plist", workspace: workspace)
        XCTAssertEqual(result.level, .destructive)
        XCTAssertTrue(result.reasons.contains { $0.contains("ระบบ") })
    }

    func testPermissionCommandsNeedApproval() {
        XCTAssertEqual(RiskyCommandDetector.assess(shellCommand: "chmod 777 /var/mobile/a.sh", workspace: workspace).level, .elevated)
        XCTAssertEqual(RiskyCommandDetector.assess(shellCommand: "chown mobile:mobile /var/mobile/a.sh", workspace: workspace).level, .elevated)
    }

    func testRawDiskAndPackageCommandsAreDestructive() {
        XCTAssertEqual(RiskyCommandDetector.assess(shellCommand: "dd if=/dev/zero of=/dev/disk0", workspace: workspace).level, .destructive)
        XCTAssertEqual(RiskyCommandDetector.assess(shellCommand: "apt-get install openssh", workspace: workspace).level, .destructive)
        XCTAssertEqual(RiskyCommandDetector.assess(shellCommand: "killall SpringBoard", workspace: workspace).level, .elevated)
    }

    func testPipeToShellIsDestructive() {
        let result = RiskyCommandDetector.assess(shellCommand: "curl -s https://example.com/i.sh | sh", workspace: workspace)
        XCTAssertEqual(result.level, .destructive)
        XCTAssertTrue(result.reasons.contains { $0.contains("curl") })
    }

    func testRedirectTargetsAreInspected() {
        let systemWrite = RiskyCommandDetector.assess(shellCommand: "echo 1 > /System/Library/test.txt", workspace: workspace)
        XCTAssertEqual(systemWrite.level, .destructive)

        let normalWrite = RiskyCommandDetector.assess(shellCommand: "echo hello > notes.txt", workspace: workspace)
        XCTAssertEqual(normalWrite.level, .elevated)
        XCTAssertTrue(normalWrite.reasons.contains { $0.contains(">") })
    }

    func testCompoundCommandsAreSplitAndAssessed() {
        let result = RiskyCommandDetector.assess(shellCommand: "ls /var/mobile && rm -r /var/mobile/tmp", workspace: workspace)
        XCTAssertEqual(result.level, .destructive)
    }

    func testAssessWriteAndDownload() {
        XCTAssertEqual(RiskyCommandDetector.assessWrite(path: "/etc/hosts", workspace: workspace).level, .destructive)
        XCTAssertEqual(RiskyCommandDetector.assessWrite(path: "\(workspace)/a.txt", workspace: workspace).level, .normal)

        let overwrite = RiskyCommandDetector.assessDownload(destination: "\(workspace)/a.zip",
                                                            fileExists: true,
                                                            workspace: workspace)
        XCTAssertEqual(overwrite.level, .elevated)

        let fresh = RiskyCommandDetector.assessDownload(destination: "\(workspace)/new.zip",
                                                        fileExists: false,
                                                        workspace: workspace)
        XCTAssertEqual(fresh.level, .normal)
    }
}

// MARK: - ToolOutputLimiter

final class Phase2ToolOutputLimiterTests: XCTestCase {

    func testShortTextIsUnchanged() {
        let limited = ToolOutputLimiter.limit("สวัสดี")
        XCTAssertFalse(limited.truncated)
        XCTAssertEqual(limited.text, "สวัสดี")
        XCTAssertEqual(limited.originalCount, "สวัสดี".count)
    }

    func testLongEnglishTextIsTruncatedWithNotice() {
        let text = String(repeating: "line of text\n", count: 2_000) // 26,000 ตัวอักษร
        let limited = ToolOutputLimiter.limit(text)
        XCTAssertTrue(limited.truncated)
        XCTAssertLessThan(limited.text.count, 10_400)
        XCTAssertTrue(limited.text.contains("ตัดทอนผลลัพธ์"))
        XCTAssertTrue(limited.text.contains("\(limited.originalCount) ตัวอักษร"))
    }

    func testThaiTextCountsByCharacters() {
        let text = String(repeating: "ก", count: 25_000)
        let limited = ToolOutputLimiter.limit(text)
        XCTAssertTrue(limited.truncated)
        XCTAssertEqual(limited.originalCount, 25_000)
        // ตัวอักษรไทย 1 ตัว = 1 ตัวอักษร (ไม่ใช่ 3 ไบต์) จึงต้องเหลือประมาณ 10,000 ตัว
        XCTAssertGreaterThan(limited.text.count, 9_900)
    }

    func testZeroLimitProducesEmptyText() {
        let limited = ToolOutputLimiter.limit("ข้อความ", maxCharacters: 0)
        XCTAssertTrue(limited.truncated)
        XCTAssertEqual(limited.text, "")
    }
}

// MARK: - GlobMatcher

final class Phase2GlobMatcherTests: XCTestCase {

    func testStarMatchesAnySuffix() {
        XCTAssertTrue(GlobMatcher.matches("*.txt", "notes.txt"))
        XCTAssertTrue(GlobMatcher.matches("*.TXT", "notes.txt"))       // ไม่แยกตัวพิมพ์โดยค่าเริ่มต้น
        XCTAssertFalse(GlobMatcher.matches("*.txt", "notes.txt.bak"))
        XCTAssertTrue(GlobMatcher.matches("config*", "config.plist"))
        XCTAssertTrue(GlobMatcher.matches("*", "อะไรก็ได้"))
    }

    func testQuestionMarkMatchesSingleCharacter() {
        XCTAssertTrue(GlobMatcher.matches("a?c", "abc"))
        XCTAssertFalse(GlobMatcher.matches("a?c", "ac"))
        XCTAssertTrue(GlobMatcher.matches("log-??.txt", "log-15.txt"))
    }

    func testCaseSensitiveMode() {
        XCTAssertFalse(GlobMatcher.matches("*.TXT", "notes.txt", caseSensitive: true))
        XCTAssertTrue(GlobMatcher.matches("*.txt", "notes.txt", caseSensitive: true))
    }

    func testMatchesAnyAndSplitPatterns() {
        XCTAssertTrue(GlobMatcher.matchesAny(["*.jpg", "*.png"], "photo.png"))
        XCTAssertFalse(GlobMatcher.matchesAny(["*.jpg", "*.png"], "photo.gif"))

        XCTAssertEqual(GlobMatcher.splitPatterns("*.txt, *.md  *.json"), ["*.txt", "*.md", "*.json"])
        XCTAssertTrue(GlobMatcher.isValidPattern("*.txt"))
        XCTAssertFalse(GlobMatcher.isValidPattern("   "))
        XCTAssertFalse(GlobMatcher.isValidPattern(String(repeating: "a", count: 201)))
    }
}

// MARK: - HTMLTextExtractor / DuckDuckGoParser

final class Phase2HTMLTests: XCTestCase {

    func testTagsAreStrippedAndTextKept() {
        let html = "<html><body><h1>หัวข้อ</h1><p>ย่อหน้าหนึ่ง</p><p>ย่อหน้าที่สอง</p></body></html>"
        let text = HTMLTextExtractor.plainText(fromHTML: html)
        XCTAssertTrue(text.contains("หัวข้อ"))
        XCTAssertTrue(text.contains("ย่อหน้าหนึ่ง"))
        XCTAssertFalse(text.contains("<p>"))
    }

    func testScriptAndStyleContentIsRemoved() {
        let html = """
        <div>ก่อนสคริปต์</div>
        <script>var secret = "ลบไฟล์ทั้งหมด";</script>
        <style>.x { color: red; }</style>
        <div>หลังสคริปต์</div>
        """
        let text = HTMLTextExtractor.plainText(fromHTML: html)
        XCTAssertTrue(text.contains("ก่อนสคริปต์"))
        XCTAssertTrue(text.contains("หลังสคริปต์"))
        XCTAssertFalse(text.contains("secret"))
        XCTAssertFalse(text.contains("color: red"))
    }

    func testCommentsAreRemoved() {
        let text = HTMLTextExtractor.plainText(fromHTML: "a<!-- ซ่อนอยู่ -->b")
        XCTAssertEqual(text, "ab")
    }

    func testEntitiesAreDecoded() {
        let text = HTMLTextExtractor.plainText(fromHTML: "<p>A &amp; B &lt;tag&gt; &#39;quote&#39; &#x2026;</p>")
        XCTAssertTrue(text.contains("A & B"))
        XCTAssertTrue(text.contains("<tag>"))
        XCTAssertTrue(text.contains("'quote'"))
        XCTAssertTrue(text.contains("…"))
    }

    func testTitleExtraction() {
        let html = "<html><head><title>  หน้าทดสอบ &amp; อื่น ๆ  </title></head><body>x</body></html>"
        XCTAssertEqual(HTMLTextExtractor.extractTitle(fromHTML: html), "หน้าทดสอบ & อื่น ๆ")
        XCTAssertNil(HTMLTextExtractor.extractTitle(fromHTML: "<html><body>ไม่มีหัวเรื่อง</body></html>"))
    }

    func testMaxCharactersLimitAndNotice() {
        let html = "<p>" + String(repeating: "abc ", count: 5_000) + "</p>"
        let page = HTMLTextExtractor.extract(fromHTML: html, maxCharacters: 500)
        XCTAssertLessThanOrEqual(page.text.count, 600)
        XCTAssertTrue(page.text.contains("ตัดทอนหน้าเว็บ"))
    }

    func testDuckDuckGoParsing() {
        let html = """
        <div class="result">
          <a rel="nofollow" class="result__a" href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fexample.com%2Fone&amp;rut=abc">ผลที่หนึ่ง</a>
          <a class="result__snippet" href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fexample.com%2Fone">คำอธิบายของผลที่หนึ่ง</a>
        </div>
        <div class="result">
          <a class="result__a" href="https://example.com/two">ผลที่สอง</a>
          <a class="result__snippet" href="https://example.com/two">คำอธิบายของผลที่สอง</a>
        </div>
        """
        let results = DuckDuckGoParser.parse(html: html, limit: 8)
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0].title, "ผลที่หนึ่ง")
        XCTAssertEqual(results[0].url, "https://example.com/one")
        XCTAssertEqual(results[0].snippet, "คำอธิบายของผลที่หนึ่ง")
        XCTAssertEqual(results[1].url, "https://example.com/two")
    }

    func testDuckDuckGoRedirectResolution() {
        XCTAssertEqual(DuckDuckGoParser.resolveRedirect("//duckduckgo.com/l/?uddg=https%3A%2F%2F蘋果.com%2Fa&rut=x"),
                       "https://蘋果.com/a")
        XCTAssertEqual(DuckDuckGoParser.resolveRedirect("https://example.com/plain"), "https://example.com/plain")
        XCTAssertEqual(DuckDuckGoParser.resolveRedirect("ไม่ใช่ลิงก์"), "ไม่ใช่ลิงก์")
    }

    func testDuckDuckGoEmptyPage() {
        XCTAssertTrue(DuckDuckGoParser.parse(html: "<html><body>ไม่มีผลลัพธ์</body></html>").isEmpty)
    }
}

// MARK: - NetworkPolicy

final class Phase2NetworkPolicyTests: XCTestCase {

    func testHTTPSIsAllowed() {
        XCTAssertNil(NetworkPolicy.validate(urlString: "https://openrouter.ai/api/v1/models",
                                            allowInternet: true, wifiOnly: false, isWiFiConnected: false))
    }

    func testPlainHTTPIsBlockedExceptLocalhost() {
        XCTAssertEqual(NetworkPolicy.validate(urlString: "http://example.com/x",
                                              allowInternet: true, wifiOnly: false, isWiFiConnected: false),
                       .insecureScheme("http"))
        XCTAssertNil(NetworkPolicy.validate(urlString: "http://localhost:8080/health",
                                            allowInternet: true, wifiOnly: false, isWiFiConnected: false))
        XCTAssertNil(NetworkPolicy.validate(urlString: "http://127.0.0.1:9000/x",
                                            allowInternet: true, wifiOnly: false, isWiFiConnected: false))
    }

    func testUnsupportedSchemeAndInvalidURL() {
        XCTAssertEqual(NetworkPolicy.validate(urlString: "file:///var/mobile/a.txt",
                                              allowInternet: true, wifiOnly: false, isWiFiConnected: false),
                       .unsupportedScheme("file"))
        XCTAssertEqual(NetworkPolicy.validate(urlString: "ไม่ใช่ url",
                                              allowInternet: true, wifiOnly: false, isWiFiConnected: false),
                       .invalidURL("ไม่ใช่ url"))
        XCTAssertEqual(NetworkPolicy.validate(urlString: "",
                                              allowInternet: true, wifiOnly: false, isWiFiConnected: false),
                       .invalidURL(""))
    }

    func testInternetSwitchBlocksEverything() {
        XCTAssertEqual(NetworkPolicy.validate(urlString: "https://example.com",
                                              allowInternet: false, wifiOnly: false, isWiFiConnected: true),
                       .internetDisabled)
    }

    func testWiFiOnlyBlocksCellular() {
        XCTAssertEqual(NetworkPolicy.validate(urlString: "https://example.com",
                                              allowInternet: true, wifiOnly: true, isWiFiConnected: false),
                       .wifiRequired)
        XCTAssertNil(NetworkPolicy.validate(urlString: "https://example.com",
                                            allowInternet: true, wifiOnly: true, isWiFiConnected: true))
    }

    func testDownloadSizeLimit() {
        let limit = NetworkPolicy.maxDownloadBytes(megabytes: 200)
        XCTAssertEqual(limit, 200 * 1024 * 1024)
        XCTAssertNil(NetworkPolicy.validateDownload(sizeBytes: 150 * 1024 * 1024, limitBytes: limit))
        XCTAssertEqual(NetworkPolicy.validateDownload(sizeBytes: 300 * 1024 * 1024, limitBytes: limit),
                       .fileTooLarge(bytes: 300 * 1024 * 1024, limit: limit))
        XCTAssertNil(NetworkPolicy.validateDownload(sizeBytes: nil, limitBytes: limit))
    }

    func testMaxDownloadBytesIsClamped() {
        XCTAssertEqual(NetworkPolicy.maxDownloadBytes(megabytes: 0), 1024 * 1024)
        XCTAssertEqual(NetworkPolicy.maxDownloadBytes(megabytes: 99_999), 8 * 1024 * 1024 * 1024)
    }

    func testByteFormatting() {
        XCTAssertEqual(NetworkPolicy.formatBytes(512), "512 ไบต์")
        XCTAssertEqual(NetworkPolicy.formatBytes(2_048), "2.0 KB")
        XCTAssertEqual(NetworkPolicy.formatBytes(5 * 1024 * 1024), "5.0 MB")
        XCTAssertEqual(NetworkPolicy.formatBytes(3 * 1024 * 1024 * 1024), "3.0 GB")
    }

    func testContentTypeHeuristics() {
        XCTAssertTrue(NetworkPolicy.isLikelyText(contentType: "text/html; charset=utf-8"))
        XCTAssertTrue(NetworkPolicy.isLikelyText(contentType: "application/json"))
        XCTAssertTrue(NetworkPolicy.isLikelyText(contentType: nil))
        XCTAssertFalse(NetworkPolicy.isLikelyText(contentType: "image/png"))
        XCTAssertFalse(NetworkPolicy.isLikelyText(contentType: "application/octet-stream"))
    }
}

// MARK: - ContextTrimmer

final class Phase2ContextTrimmerTests: XCTestCase {

    private func makeToolMessage(toolName: String, characters: Int) -> ChatMessage {
        ChatMessage.toolResult(String(repeating: "ข", count: characters),
                               toolCallID: "call-\(toolName)",
                               name: toolName)
    }

    func testTokenEstimateIsPositive() {
        XCTAssertEqual(ContextTrimmer.estimateTokens(""), 0)
        XCTAssertGreaterThan(ContextTrimmer.estimateTokens("สวัสดีครับ"), 0)
        XCTAssertGreaterThan(ContextTrimmer.estimateTokens(String(repeating: "a", count: 300)),
                             ContextTrimmer.estimateTokens("a"))
    }

    func testTrimTriggerAtEightyPercent() {
        XCTAssertFalse(ContextTrimmer.shouldTrim(estimatedTokens: 7_000, contextLengthTokens: 10_000))
        XCTAssertTrue(ContextTrimmer.shouldTrim(estimatedTokens: 8_500, contextLengthTokens: 10_000))
        XCTAssertFalse(ContextTrimmer.shouldTrim(estimatedTokens: 9_000, contextLengthTokens: 0))
    }

    func testSmallConversationIsUntouched() {
        let messages: [ChatMessage] = [
            .system("system prompt"),
            .user("สวัสดี"),
            .assistant("สวัสดีครับ มีอะไรให้ช่วยไหม")
        ]
        let result = ContextTrimmer.trim(messages, contextLengthTokens: 100_000)
        XCTAssertFalse(result.didTrim)
        XCTAssertEqual(result.messages.count, 3)
        XCTAssertNil(result.noticeText)
    }

    func testOldestToolResultsAreDroppedFirst() {
        var messages: [ChatMessage] = [.system("system prompt")]
        for index in 0..<6 {
            let call = ToolCall(id: "call-\(index)",
                                function: FunctionCall(name: "read_file", arguments: "{\"path\":\"/a\(index)\"}"))
            messages.append(ChatMessage(role: .assistant, text: "", toolCalls: [call]))
            messages.append(makeToolMessage(toolName: "read_file", characters: 6_000))
        }
        messages.append(.user("คำถามล่าสุด"))

        let result = ContextTrimmer.trim(messages, contextLengthTokens: 6_000, keepRecentCount: 2)

        XCTAssertTrue(result.didTrim)
        XCTAssertGreaterThan(result.droppedToolResults, 0)
        XCTAssertLessThan(result.estimatedTokensAfter, result.estimatedTokensBefore)
        XCTAssertTrue(result.messages.contains { $0.text.contains("ถูกตัดออกเพราะบทสนทนายาวเกินขอบเขต") })
        // system prompt และข้อความล่าสุดต้องอยู่ครบ
        XCTAssertTrue(result.messages.contains { $0.role == .system })
        XCTAssertEqual(result.messages.last?.text, "คำถามล่าสุด")
        XCTAssertNotNil(result.noticeText)
    }

    func testAssistantWithToolCallsStaysPairedWithItsToolResult() {
        var messages: [ChatMessage] = [.system("system prompt")]
        for index in 0..<5 {
            let call = ToolCall(id: "call-\(index)",
                                function: FunctionCall(name: "execute_shell", arguments: "{\"command\":\"ls\"}"))
            messages.append(ChatMessage(role: .assistant, text: "", toolCalls: [call]))
            messages.append(ChatMessage.toolResult(String(repeating: "x", count: 5_000),
                                                   toolCallID: "call-\(index)",
                                                   name: "execute_shell"))
        }

        let result = ContextTrimmer.trim(messages, contextLengthTokens: 6_000, keepRecentCount: 2)

        // ทุก tool message ต้องมี assistant ที่ประกาศ tool_call_id นั้นอยู่ด้วยเสมอ (ไม่งั้น API จะปฏิเสธ)
        let declaredIDs = Set(result.messages.flatMap { ($0.toolCalls ?? []).map { $0.id } })
        let toolResultIDs = result.messages.filter { $0.role == .tool }.compactMap { $0.toolCallID }
        for id in toolResultIDs {
            XCTAssertTrue(declaredIDs.contains(id), "พบ tool message ที่ไม่มี assistant คู่กัน: \(id)")
        }
        XCTAssertTrue(result.messages.contains { $0.role == .system })
    }

    func testContextLengthZeroDoesNothing() {
        let messages: [ChatMessage] = [.system("s"), .user(String(repeating: "a", count: 10_000))]
        let result = ContextTrimmer.trim(messages, contextLengthTokens: 0)
        XCTAssertFalse(result.didTrim)
        XCTAssertEqual(result.messages.count, 2)
    }

    func testPlaceholderTextMentionsToolName() {
        let text = ContextTrimmer.placeholderText(for: "web_search")
        XCTAssertTrue(text.contains("web_search"))
        XCTAssertTrue(text.contains("ตัดออก"))
    }
}
