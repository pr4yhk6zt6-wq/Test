//
//  APIKeyHandlingTests.swift
//  iOS Agent Sandbox — ชุดทดสอบ
//
//  ทดสอบ "การจัดการ API Key" ซึ่งเป็นสาเหตุของบั๊ก 401 (User not found.) ที่ผู้ใช้เจอบนเครื่อง:
//    • คีย์ที่วางมามีช่องว่าง/ขึ้นบรรทัดใหม่/อักขระล่องหนติดมา
//    • คีย์เก่าที่ค้างอยู่ในที่เก็บสำรองถูกอ่านทับคีย์ใหม่ที่เพิ่งบันทึก
//
//  ไฟล์นี้ทดสอบได้ทั้ง Linux และ macOS เพราะ APIKeySanitizer/APIKeyStoragePolicy เป็น Foundation ล้วน
//

import XCTest
@testable import OpenRouterCore

final class APIKeyHandlingTests: XCTestCase {

    // MARK: - ทำความสะอาดคีย์

    func testSanitizeRemovesTrailingNewline() {
        let result = APIKeySanitizer.sanitize("sk-or-v1-abc123\n")
        XCTAssertEqual(result.cleaned, "sk-or-v1-abc123")
        XCTAssertEqual(result.removedCharacters, 1)
        XCTAssertTrue(result.didChange)
    }

    func testSanitizeRemovesLeadingAndTrailingSpaces() {
        let result = APIKeySanitizer.sanitize("  sk-or-v1-abc123  ")
        XCTAssertEqual(result.cleaned, "sk-or-v1-abc123")
        XCTAssertEqual(result.removedCharacters, 4)
    }

    func testSanitizeRemovesZeroWidthSpaceInsideKey() {
        let result = APIKeySanitizer.sanitize("sk-or-v1-ab\u{200B}c123")
        XCTAssertEqual(result.cleaned, "sk-or-v1-abc123")
        XCTAssertEqual(result.removedCharacters, 1)
    }

    func testSanitizeRemovesNonBreakingSpaceAndBOM() {
        let result = APIKeySanitizer.sanitize("\u{FEFF}sk-or-v1-abc\u{00A0}123")
        XCTAssertEqual(result.cleaned, "sk-or-v1-abc123")
        XCTAssertEqual(result.removedCharacters, 2)
    }

    func testSanitizeRemovesWrappingDoubleQuotes() {
        let result = APIKeySanitizer.sanitize("\"sk-or-v1-abc123\"")
        XCTAssertEqual(result.cleaned, "sk-or-v1-abc123")
        XCTAssertTrue(result.hadWrappingQuotes)
        XCTAssertTrue(result.didChange)
    }

    func testSanitizeRemovesWrappingSmartQuotes() {
        let result = APIKeySanitizer.sanitize("“sk-or-v1-abc123”")
        XCTAssertEqual(result.cleaned, "sk-or-v1-abc123")
        XCTAssertTrue(result.hadWrappingQuotes)
    }

    func testSanitizeKeepsSingleQuoteInsideKey() {
        // เครื่องหมายคำพูดที่ไม่ได้ครอบทั้งคีย์ต้องไม่ถูกตัด
        let result = APIKeySanitizer.sanitize("sk-or-v1-ab'c")
        XCTAssertEqual(result.cleaned, "sk-or-v1-ab'c")
        XCTAssertFalse(result.hadWrappingQuotes)
    }

    func testSanitizeLeavesCleanKeyUntouched() {
        let key = "sk-or-v1-0123456789abcdef"
        let result = APIKeySanitizer.sanitize(key)
        XCTAssertEqual(result.cleaned, key)
        XCTAssertFalse(result.didChange)
        XCTAssertNil(result.changeDescription)
    }

    func testChangeDescriptionMentionsWhatWasFixed() {
        let result = APIKeySanitizer.sanitize("  \"sk-or-v1-abc\"\n")
        let description = result.changeDescription
        XCTAssertNotNil(description)
        XCTAssertTrue(description?.contains("ช่องว่าง") ?? false, "ควรบอกว่าตัดช่องว่าง: \(description ?? "-")")
        XCTAssertTrue(description?.contains("เครื่องหมายคำพูด") ?? false, "ควรบอกว่าตัดเครื่องหมายคำพูด: \(description ?? "-")")
    }

    // MARK: - ตรวจรูปแบบคีย์

    func testLooksLikeOpenRouterKeyAcceptsOpenRouterFormat() {
        XCTAssertTrue(APIKeySanitizer.looksLikeOpenRouterKey("sk-or-v1-abcdef123456"))
    }

    func testLooksLikeOpenRouterKeyRejectsOpenAIFormat() {
        XCTAssertFalse(APIKeySanitizer.looksLikeOpenRouterKey("sk-proj-abcdef123456"))
    }

    func testLooksLikeOpenRouterKeyRejectsEmptyString() {
        XCTAssertFalse(APIKeySanitizer.looksLikeOpenRouterKey("   "))
    }

    func testValidateReturnsNilForNormalKey() {
        XCTAssertNil(APIKeySanitizer.validate("sk-or-v1-abcdefghijklmnop1234"))
    }

    func testValidateWarnsWhenPrefixMissing() {
        let warning = APIKeySanitizer.validate("abc123def456ghi789")
        XCTAssertNotNil(warning)
        XCTAssertTrue(warning?.contains("sk-or-") ?? false, "ควรบอกเรื่องคำขึ้นต้น: \(warning ?? "-")")
    }

    func testValidateWarnsWhenKeyTooShort() {
        let warning = APIKeySanitizer.validate("sk-or-v1-abc")
        XCTAssertNotNil(warning)
        XCTAssertTrue(warning?.contains("สั้น") ?? false, "ควรบอกว่าคีย์สั้นผิดปกติ: \(warning ?? "-")")
    }

    // MARK: - รหัสอ้างอิงคีย์ (fingerprint)

    func testFingerprintShowsPrefixSuffixAndLength() {
        let key = "sk-or-v1-0123456789abcdefghij"
        let fingerprint = APIKeySanitizer.fingerprint(key)
        XCTAssertTrue(fingerprint.hasPrefix("sk-or-v1-01"), fingerprint)
        XCTAssertTrue(fingerprint.contains("…"), fingerprint)
        XCTAssertTrue(fingerprint.contains("\(key.count) ตัวอักษร"), fingerprint)
    }

    func testFingerprintForShortKeyStillHidesMiddle() {
        let fingerprint = APIKeySanitizer.fingerprint("sk-or-abc")
        XCTAssertTrue(fingerprint.contains("…"), fingerprint)
        XCTAssertFalse(fingerprint.contains("sk-or-abc"), "ต้องไม่แสดงคีย์เต็ม")
    }

    func testFingerprintForMissingKey() {
        XCTAssertEqual(APIKeySanitizer.fingerprint(""), "(ยังไม่มีคีย์)")
        XCTAssertEqual(APIKeySanitizer.fingerprint("   \n"), "(ยังไม่มีคีย์)")
    }

    // MARK: - กติกาเลือกคีย์ (ต้นเหตุบั๊ก 401)

    func testPolicyUsesKeychainWhenOnlyKeychainHasValue() {
        let resolution = APIKeyStoragePolicy.resolve(keychainValue: "sk-or-v1-new", fallbackValue: nil)
        XCTAssertEqual(resolution.value, "sk-or-v1-new")
        XCTAssertFalse(resolution.isUsingFallback)
        XCTAssertFalse(resolution.shouldPurgeFallback)
    }

    func testPolicyPrefersKeychainAndPurgesStaleFallback() {
        // บั๊กจริง: Keychain มีคีย์ใหม่ แต่ที่เก็บสำรองยังมีคีย์เก่าค้าง → ต้องใช้คีย์ใหม่และสั่งล้างสำรอง
        let resolution = APIKeyStoragePolicy.resolve(keychainValue: "sk-or-v1-new",
                                                     fallbackValue: "sk-or-v1-old-revoked")
        XCTAssertEqual(resolution.value, "sk-or-v1-new")
        XCTAssertFalse(resolution.isUsingFallback)
        XCTAssertTrue(resolution.shouldPurgeFallback, "ต้องสั่งล้างคีย์เก่าที่ค้างในที่เก็บสำรอง")
    }

    func testPolicyDoesNotPurgeWhenBothValuesMatch() {
        let resolution = APIKeyStoragePolicy.resolve(keychainValue: "sk-or-v1-same",
                                                     fallbackValue: "sk-or-v1-same")
        XCTAssertEqual(resolution.value, "sk-or-v1-same")
        XCTAssertFalse(resolution.shouldPurgeFallback)
    }

    func testPolicyUsesFallbackWhenKeychainIsEmpty() {
        let resolution = APIKeyStoragePolicy.resolve(keychainValue: nil, fallbackValue: "sk-or-v1-fallback")
        XCTAssertEqual(resolution.value, "sk-or-v1-fallback")
        XCTAssertTrue(resolution.isUsingFallback)
        XCTAssertFalse(resolution.shouldPurgeFallback)
    }

    func testPolicyReturnsNothingWhenBothStoresAreEmpty() {
        let resolution = APIKeyStoragePolicy.resolve(keychainValue: "   ", fallbackValue: "\n")
        XCTAssertNil(resolution.value)
        XCTAssertFalse(resolution.isUsingFallback)
        XCTAssertFalse(resolution.shouldPurgeFallback)
    }

    func testPolicyComparesValuesAfterCleaning() {
        // ค่าเดียวกันแต่ฝั่งหนึ่งมีช่องว่างติดมา → ไม่ต้องล้างสำรอง
        let resolution = APIKeyStoragePolicy.resolve(keychainValue: "sk-or-v1-same",
                                                     fallbackValue: " sk-or-v1-same\n")
        XCTAssertEqual(resolution.value, "sk-or-v1-same")
        XCTAssertFalse(resolution.shouldPurgeFallback)
    }

    func testPolicyCleansValueItReturns() {
        let resolution = APIKeyStoragePolicy.resolve(keychainValue: "sk-or-v1-new\u{200B}\n", fallbackValue: nil)
        XCTAssertEqual(resolution.value, "sk-or-v1-new")
    }

    func testPolicyStaleFallbackScenarioEndsUpWithNewKey() {
        // จำลองลำดับที่เกิดจริง: เก็บคีย์เก่าแบบสำรอง → ภายหลังบันทึกคีย์ใหม่ลง Keychain สำเร็จ
        let first = APIKeyStoragePolicy.resolve(keychainValue: nil, fallbackValue: "sk-or-v1-old")
        XCTAssertEqual(first.value, "sk-or-v1-old")

        let afterNewKeySaved = APIKeyStoragePolicy.resolve(keychainValue: "sk-or-v1-new", fallbackValue: "sk-or-v1-old")
        XCTAssertEqual(afterNewKeySaved.value, "sk-or-v1-new", "หลังบันทึกคีย์ใหม่ ต้องไม่ใช้คีย์เก่าอีก")
        XCTAssertTrue(afterNewKeySaved.shouldPurgeFallback)

        let afterPurge = APIKeyStoragePolicy.resolve(keychainValue: "sk-or-v1-new", fallbackValue: nil)
        XCTAssertEqual(afterPurge.value, "sk-or-v1-new")
        XCTAssertFalse(afterPurge.shouldPurgeFallback)
    }
}
