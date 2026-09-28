//
//  Phase5Tests.swift
//  แบบทดสอบเฟส 5 (ไฟล์แนบ / หลายห้องสนทนา / ส่งออก)
//
//  ทดสอบ "ไฟล์ต้นฉบับของแอป" โดยตรง (คัดลอกมาพร้อมตรวจ sha256 ใน run-verification.sh)
//  ทุกอย่างในไฟล์นี้เป็น Foundation ล้วน จึงรันได้ทั้ง macOS และ Linux
//

import XCTest
@testable import OpenRouterCore

// MARK: - ชื่อไฟล์และชนิดไฟล์

final class AttachmentNamingTests: XCTestCase {

    func testSanitizeRemovesPathAndForbiddenCharacters() {
        XCTAssertEqual(AttachmentStore.sanitizeFileName("/var/mobile/Documents/my note.txt"), "my note.txt")
        XCTAssertEqual(AttachmentStore.sanitizeFileName("a:b*c?d\"e<f>g|h.txt"), "abcdefgh.txt")
        XCTAssertEqual(AttachmentStore.sanitizeFileName("   spaced   name.txt   "), "spaced name.txt")
    }

    func testSanitizeFallsBackForEmptyOrHiddenNames() {
        XCTAssertEqual(AttachmentStore.sanitizeFileName(""), "ไฟล์แนบ")
        XCTAssertEqual(AttachmentStore.sanitizeFileName(".."), "ไฟล์แนบ")
        XCTAssertEqual(AttachmentStore.sanitizeFileName(".hidden"), "ไฟล์.hidden")
    }

    func testSanitizeTrimsVeryLongNamesButKeepsExtension() {
        let long = String(repeating: "ก", count: 200) + ".txt"
        let result = AttachmentStore.sanitizeFileName(long)
        XCTAssertLessThanOrEqual(result.count, 90)
        XCTAssertTrue(result.hasSuffix(".txt"))
    }

    func testUniqueFileNameUsesTimestampAndAvoidsCollisions() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let first = AttachmentStore.uniqueFileName(original: "note.txt", date: date, existing: [])
        XCTAssertTrue(first.hasSuffix("-note.txt"), first)
        let second = AttachmentStore.uniqueFileName(original: "note.txt", date: date, existing: [first])
        XCTAssertNotEqual(first, second)
        XCTAssertTrue(second.contains("-note-1.txt"), second)
    }

    func testExtensionExtractionAndKindDetection() {
        XCTAssertEqual(AttachmentStore.extensionOf("photo.JPG"), "jpg")
        XCTAssertEqual(AttachmentStore.extensionOf("archive"), "")
        XCTAssertEqual(Attachment.kind(forExtension: "png"), .image)
        XCTAssertEqual(Attachment.kind(forExtension: "swift"), .text)
        XCTAssertEqual(Attachment.kind(forExtension: "zip"), .binary)
    }

    func testSizeTextIsHumanReadable() {
        XCTAssertEqual(Attachment.sizeText(for: 512), "512 ไบต์")
        XCTAssertEqual(Attachment.sizeText(for: 2_048), "2 KB")
        XCTAssertEqual(Attachment.sizeText(for: 3_145_728), "3.0 MB")
    }
}

// MARK: - คลังไฟล์แนบ (แตะดิสก์จริงในโฟลเดอร์ชั่วคราว)

final class AttachmentStoreTests: XCTestCase {

    private var root: String!

    override func setUpWithError() throws {
        root = NSTemporaryDirectory() + "attach-tests-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(atPath: root)
    }

    private func makeStore() -> AttachmentStore {
        AttachmentStore(rootPath: root + "/uploads")
    }

    func testImportDataWritesFileAndReportsMetadata() throws {
        let store = makeStore()
        let attachment = try store.importData(Data("สวัสดี".utf8), originalName: "hello.txt")
        XCTAssertEqual(attachment.originalName, "hello.txt")
        XCTAssertEqual(attachment.kind, .text)
        XCTAssertEqual(attachment.byteSize, Data("สวัสดี".utf8).count)
        XCTAssertTrue(FileManager.default.fileExists(atPath: attachment.path))
        XCTAssertTrue(attachment.isInlineText, "ไฟล์ข้อความเล็กต้องถูกฝังเนื้อหา")
        XCTAssertEqual(attachment.inlineText, "สวัสดี")
    }

    func testImportFileCopiesInsteadOfMoving() throws {
        let store = makeStore()
        let source = root + "/source.json"
        try Data("{\"a\":1}".utf8).write(to: URL(fileURLWithPath: source))
        let attachment = try store.importFile(at: URL(fileURLWithPath: source))
        XCTAssertTrue(FileManager.default.fileExists(atPath: attachment.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source), "ต้นฉบับต้องยังอยู่")
        XCTAssertEqual(attachment.kind, .text)
        XCTAssertNotEqual(attachment.path, source)
    }

    func testEmptyFileIsRejected() throws {
        let store = makeStore()
        XCTAssertThrowsError(try store.importData(Data(), originalName: "empty.txt")) { error in
            XCTAssertEqual(error as? AttachmentStoreError, .emptyFile)
        }
    }

    func testTooLargeFileIsRejectedWithThaiMessage() throws {
        let store = makeStore()
        let big = Data(repeating: 0x41, count: 4_096)
        XCTAssertThrowsError(try store.importData(big, originalName: "big.txt", maxBytes: 1_024)) { error in
            let message = (error as? AttachmentStoreError)?.errorDescription ?? ""
            XCTAssertTrue(message.contains("ใหญ่เกินเพดาน"), message)
        }
    }

    func testLargeTextFileIsNotInlined() throws {
        let store = makeStore()
        let text = String(repeating: "ก", count: 30_000)
        let attachment = try store.importData(Data(text.utf8), originalName: "big.md")
        XCTAssertFalse(attachment.isInlineText, "ไฟล์ใหญ่กว่า 20KB ต้องไม่ฝังเนื้อหา (กัน context บวม)")
        XCTAssertNil(attachment.inlineText)
    }

    func testDeleteRemovesFileButToleratesMissingFile() throws {
        let store = makeStore()
        let attachment = try store.importData(Data("x".utf8), originalName: "x.txt")
        try store.delete(attachment)
        XCTAssertFalse(FileManager.default.fileExists(atPath: attachment.path))
        XCTAssertNoThrow(try store.delete(attachment))
    }

    func testReadInlineTextRespectsLimit() throws {
        let store = makeStore()
        try store.ensureDirectory()
        let path = root + "/uploads/limit.txt"
        try Data(repeating: 0x41, count: 5_000).write(to: URL(fileURLWithPath: path))
        XCTAssertNotNil(store.readInlineText(path: path, limitBytes: 8_192))
        XCTAssertNil(store.readInlineText(path: path, limitBytes: 1_024))
    }
}

// MARK: - สร้างเนื้อหาข้อความที่มีไฟล์แนบ

final class AttachmentMessageBuilderTests: XCTestCase {

    private func textFile(name: String = "note.txt", content: String = "บรรทัดทดสอบ") -> Attachment {
        Attachment(fileName: "20260101-120000-\(name)",
                   originalName: name,
                   path: "/var/mobile/AgentWorkspace/uploads/\(name)",
                   byteSize: content.utf8.count,
                   kind: .text,
                   isInlineText: true,
                   inlineText: content)
    }

    private func imageFile(name: String = "photo.jpg") -> Attachment {
        Attachment(fileName: "20260101-120000-\(name)",
                   originalName: name,
                   path: "/var/mobile/AgentWorkspace/uploads/\(name)",
                   byteSize: 120_000,
                   kind: .image,
                   pixelWidth: 1024,
                   pixelHeight: 768)
    }

    func testTextBlockWithoutAttachmentsIsUnchanged() {
        XCTAssertEqual(AttachmentMessageBuilder.textBlock(text: "สวัสดี", attachments: []), "สวัสดี")
    }

    func testTextBlockListsPathsAndInlinesSmallTextFiles() {
        let block = AttachmentMessageBuilder.textBlock(text: "ช่วยอ่านไฟล์นี้",
                                                       attachments: [textFile(), imageFile()])
        XCTAssertTrue(block.contains("[ไฟล์แนบจากผู้ใช้]"))
        XCTAssertTrue(block.contains("note.txt"))
        XCTAssertTrue(block.contains("/var/mobile/AgentWorkspace/uploads/photo.jpg"))
        XCTAssertTrue(block.contains("[เนื้อหาไฟล์ข้อความที่ฝังมาให้]"))
        XCTAssertTrue(block.contains("บรรทัดทดสอบ"))
        XCTAssertTrue(block.contains("```txt"))
    }

    func testContentStaysStringWhenImagesAreNotSent() throws {
        let content = AttachmentMessageBuilder.content(text: "ดูไฟล์",
                                                       attachments: [imageFile()],
                                                       imageDataURLs: [],
                                                       includeImages: false)
        guard case .string(let text) = content else {
            return XCTFail("ต้องเป็นข้อความล้วนเมื่อไม่ส่งรูป")
        }
        XCTAssertTrue(text.contains("photo.jpg"))
    }

    func testContentBecomesPartsArrayWithImageURLWhenVisionIsOn() throws {
        let dataURL = AttachmentMessageBuilder.dataURL(mimeType: "image/jpeg", base64: "QUJD")
        let content = AttachmentMessageBuilder.content(text: "รูปนี้คืออะไร",
                                                       attachments: [imageFile()],
                                                       imageDataURLs: [dataURL],
                                                       includeImages: true)
        guard case .array(let parts) = content else {
            return XCTFail("ต้องเป็น array ของ parts เมื่อส่งรูป")
        }
        XCTAssertEqual(parts.count, 2)
        XCTAssertEqual(parts[0]["type"]?.stringValue, "text")
        XCTAssertEqual(parts[1]["type"]?.stringValue, "image_url")
        XCTAssertEqual(parts[1]["image_url"]?["url"]?.stringValue, dataURL)
    }

    func testImageAttachmentsFilterOnlyImages() {
        let images = AttachmentMessageBuilder.imageAttachments(in: [textFile(), imageFile(), imageFile(name: "b.png")])
        XCTAssertEqual(images.count, 2)
        XCTAssertTrue(images.allSatisfy { $0.isImage })
    }

    func testNoVisionWarningMentionsModelAndSuggestion() {
        let warning = AttachmentMessageBuilder.noVisionWarning(modelID: "deepseek/deepseek-v3:free", imageCount: 2)
        XCTAssertTrue(warning.contains("deepseek/deepseek-v3:free"))
        XCTAssertTrue(warning.contains("gpt-4o") || warning.contains("gemini"))
    }
}

// MARK: - ประเมินว่าโมเดลรับรูปได้

final class VisionSupportTests: XCTestCase {

    func testKnownVisionModelsAreDetected() {
        for model in ["openai/gpt-4o", "openai/gpt-4o-mini", "anthropic/claude-3.5-sonnet",
                      "google/gemini-2.0-flash-exp:free", "qwen/qwen2.5-vl-72b-instruct",
                      "qwen/qwen3-vl-235b", "meta-llama/llama-3.2-11b-vision-instruct",
                      "mistralai/pixtral-12b", "x-ai/grok-2-vision-1212"] {
            XCTAssertTrue(VisionSupport.markerDecision(modelID: model), model)
        }
    }

    func testTextOnlyModelsAreNotDetectedAsVision() {
        for model in ["deepseek/deepseek-v3.1:free", "cohere/north-mini-code:free",
                      "qwen/qwen3-coder:free", "meta-llama/llama-3.3-70b-instruct",
                      "nousresearch/hermes-3-llama-3.1-405b", "codestral/codestral-2501"] {
            XCTAssertFalse(VisionSupport.markerDecision(modelID: model), model)
        }
    }

    func testOverrideWins() {
        XCTAssertTrue(VisionSupport.supportsImages(modelID: "deepseek/deepseek-v3", override: .always))
        XCTAssertFalse(VisionSupport.supportsImages(modelID: "openai/gpt-4o", override: .never))
        XCTAssertTrue(VisionSupport.supportsImages(modelID: "openai/gpt-4o", override: .automatic))
        XCTAssertTrue(VisionSupport.explanation(modelID: "openai/gpt-4o", override: .automatic).contains("รับรูป"))
        XCTAssertTrue(VisionSupport.explanation(modelID: "", override: .automatic).contains("ยังไม่ได้เลือก"))
    }
}

// MARK: - หลายห้องสนทนา

final class ChatRoomStoreTests: XCTestCase {

    private var root: String!
    private var store: ChatRoomStore!

    override func setUpWithError() throws {
        root = NSTemporaryDirectory() + "rooms-tests-\(UUID().uuidString)"
        store = ChatRoomStore(directoryPath: root)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(atPath: root)
    }

    func testCreateSaveLoadRooms() throws {
        let room = try store.createRoom(name: "งานแรก")
        var rooms = store.loadRooms()
        rooms.append(room)
        try store.saveRooms(rooms)

        let loaded = store.loadRooms()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.name, "งานแรก")
        XCTAssertEqual(loaded.first?.id, room.id)
    }

    func testDefaultRoomNameUsesCounter() throws {
        let room = try store.createRoom(existingCount: 2)
        XCTAssertEqual(room.name, "แชทใหม่ 3")
    }

    func testMessagesRoundTripWithAttachments() throws {
        let room = try store.createRoom(name: "มีไฟล์แนบ")
        let attachment = Attachment(fileName: "a.txt", originalName: "a.txt",
                                    path: "/tmp/a.txt", byteSize: 10, kind: .text)
        let messages = [ChatMessage.user("ดูไฟล์นี้", attachments: [attachment],
                                         visionImageDataURLs: ["data:image/jpeg;base64,QUJD"]),
                        ChatMessage.assistant("ได้ครับ")]
        try store.saveMessages(messages, roomID: room.id)

        let loaded = store.loadMessages(roomID: room.id)
        XCTAssertEqual(loaded.count, 2)
        XCTAssertEqual(loaded.first?.attachments?.first?.originalName, "a.txt")
        XCTAssertEqual(loaded.last?.text, "ได้ครับ")
    }

    func testVisionDataURLsAreNotPersisted() throws {
        // รูป base64 ต้องไม่ถูกบันทึกลงไฟล์ประวัติ (กันไฟล์บวม + RAM เกิน)
        let message = ChatMessage.user("รูป", attachments: [],
                                       visionImageDataURLs: ["data:image/jpeg;base64,QUJD"])
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode([message])
        let json = String(data: data, encoding: .utf8) ?? ""
        XCTAssertFalse(json.contains("visionImageDataURLs"))
        XCTAssertFalse(json.contains("QUJD"))
    }

    func testPreviewTextPrefersToolLabel() {
        let tool = ChatMessage.toolResult("ผลลัพธ์ยาว", toolCallID: "c1", name: "read_file", thaiLabel: "อ่านไฟล์")
        XCTAssertTrue(ChatRoomStore.previewText(of: [tool]).contains("อ่านไฟล์"))
        let long = ChatMessage.user(String(repeating: "ก", count: 120))
        XCTAssertLessThanOrEqual(ChatRoomStore.previewText(of: [long]).count, 61)
    }

    func testMarkdownExportContainsAllRoles() {
        let messages = [ChatMessage.user("คำถาม"),
                        ChatMessage.assistant("คำตอบ"),
                        ChatMessage.toolResult("ผลลัพธ์", toolCallID: "c1", name: "read_file", thaiLabel: "อ่านไฟล์")]
        let markdown = ChatRoomStore.markdownExport(roomName: "ห้องทดสอบ", messages: messages)
        XCTAssertTrue(markdown.contains("# ห้องทดสอบ"))
        XCTAssertTrue(markdown.contains("## ผู้ใช้"))
        XCTAssertTrue(markdown.contains("## ผู้ช่วย"))
        XCTAssertTrue(markdown.contains("tool: อ่านไฟล์"))
        XCTAssertTrue(markdown.contains("ผลลัพธ์"))
    }

    func testJSONExportIsDecodable() throws {
        let messages = [ChatMessage.user("สวัสดี"), ChatMessage.assistant("ครับ")]
        let data = try ChatRoomStore.jsonExport(roomName: "ห้อง", messages: messages)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let export = try decoder.decode(ChatExport.self, from: data)
        XCTAssertEqual(export.roomName, "ห้อง")
        XCTAssertEqual(export.messageCount, 2)
        XCTAssertEqual(export.messages.count, 2)
    }

    func testMigrationMovesLegacyHistoryIntoFirstRoom() throws {
        let legacy = [ChatMessage.user("ข้อความเก่า"), ChatMessage.assistant("คำตอบเก่า")]
        let result = try store.migrateLegacyHistoryIfNeeded(legacyMessages: legacy)
        XCTAssertEqual(result.rooms.count, 1)
        XCTAssertEqual(result.rooms.first?.name, "แชทเดิม")
        XCTAssertEqual(result.migrated.count, 2)
        XCTAssertEqual(store.loadMessages(roomID: result.rooms[0].id).count, 2)

        // เรียกซ้ำต้องไม่สร้างห้องใหม่
        let again = try store.migrateLegacyHistoryIfNeeded(legacyMessages: legacy)
        XCTAssertEqual(again.rooms.count, 1)
        XCTAssertTrue(again.migrated.isEmpty)
    }

    func testSafeExportNameReplacesSeparators() {
        XCTAssertEqual(ChatRoomStore.safeExportName("งาน/วันจันทร์: เช้า"), "งาน-วันจันทร์- เช้า")
        XCTAssertEqual(ChatRoomStore.safeExportName("   "), "chat")
    }
}

// MARK: - payload ของข้อความที่มีไฟล์แนบ

final class ChatMessageAttachmentPayloadTests: XCTestCase {

    func testPayloadWithImageDataURLsBecomesPartsArray() throws {
        let attachment = Attachment(fileName: "p.jpg", originalName: "p.jpg", path: "/tmp/p.jpg",
                                    byteSize: 1_000, kind: .image)
        let message = ChatMessage.user("รูปนี้คืออะไร",
                                       attachments: [attachment],
                                       visionImageDataURLs: ["data:image/jpeg;base64,QUJD"])
        let data = try JSONEncoder().encode(message.payload())
        let json = try XCTUnwrap(JSONValue.decode(fromJSONString: String(data: data, encoding: .utf8) ?? ""))
        guard case .array(let parts)? = json["content"] else {
            return XCTFail("ต้องเป็น array เมื่อส่งรูป")
        }
        XCTAssertEqual(parts.count, 2)
        XCTAssertEqual(parts[0]["type"]?.stringValue, "text")
        XCTAssertEqual(parts[1]["type"]?.stringValue, "image_url")
    }

    func testPayloadWithoutVisionKeepsPathInText() throws {
        let attachment = Attachment(fileName: "p.jpg", originalName: "p.jpg",
                                    path: "/var/mobile/AgentWorkspace/uploads/p.jpg",
                                    byteSize: 1_000, kind: .image)
        let message = ChatMessage.user("ช่วยเปิดไฟล์นี้", attachments: [attachment], visionImageDataURLs: [])
        let data = try JSONEncoder().encode(message.payload())
        let json = try XCTUnwrap(JSONValue.decode(fromJSONString: String(data: data, encoding: .utf8) ?? ""))
        let content = try XCTUnwrap(json["content"]?.stringValue)
        XCTAssertTrue(content.contains("uploads/p.jpg"))
        XCTAssertTrue(content.contains("ช่วยเปิดไฟล์นี้"))
    }

    func testPlainUserMessageIsUnaffected() throws {
        let message = ChatMessage.user("สวัสดี")
        let data = try JSONEncoder().encode(message.payload())
        let json = try XCTUnwrap(JSONValue.decode(fromJSONString: String(data: data, encoding: .utf8) ?? ""))
        XCTAssertEqual(json["content"]?.stringValue, "สวัสดี")
        XCTAssertNil(json["attachments"])
    }
}
