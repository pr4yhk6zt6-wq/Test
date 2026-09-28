//
//  EntitlementProbe.swift
//  iOS Agent Sandbox
//
//  สแกน "ข้อมูล entitlements" ที่ฝังอยู่ในไบนารีของแอปเอง (เฟส 3)
//  ใช้ยืนยันกับผู้ใช้ได้ว่าแอปที่ติดตั้งอยู่มีสิทธิ์ทั้ง 5 คีย์จริง
//  (ldid -S เขียน entitlements เป็น XML plist ไว้ในโค้ดซิกเนเจอร์ของไฟล์ Mach-O)
//
//  กฎหน่วยความจำ (RAM 2GB): อ่านทีละก้อน 256KB พร้อม overlap ไม่โหลดทั้งไฟล์
//  Foundation-only → รัน unit test/E2E ได้ทุกแพลตฟอร์ม
//

import Foundation

struct EntitlementScanResult: Equatable {

    /// path ของไบนารีที่สแกน (nil = ระบุไม่ได้)
    let binaryPath: String?
    /// อ่านไปทั้งหมดกี่ไบต์
    let scannedBytes: Int64
    /// ขนาดไฟล์ทั้งหมด (0 = อ่านไม่ได้)
    let fileSizeBytes: Int64
    /// คีย์ที่พบในไบนารี (เรียงตามลำดับที่ขอ)
    let foundKeys: [String]
    /// คีย์ที่ไม่พบ
    let missingKeys: [String]
    /// จำนวนครั้งที่เจอข้อความคีย์ทั้งหมด (นับรวมทุกคีย์)
    let totalMatches: Int
    /// คีย์ที่เจอ "ชื่อคีย์" ในไบนารี แต่ไม่เจอในรูป <key>...</key> (ข้อมูลวินิจฉัย ไม่ใช้อ้างว่ามีสิทธิ์)
    let looseMatchKeys: [String]
    /// true = สแกนไม่สำเร็จ เพราะไฟล์ใหญ่เกินเพดานความปลอดภัยของการสแกน
    let stoppedAtLimit: Bool
    /// ข้อผิดพลาดที่ทำให้อ่านไฟล์ไม่ได้ (nil = ปกติ)
    let readErrorText: String?

    var hasAllFive: Bool {
        missingKeys.isEmpty && !foundKeys.isEmpty
    }

    var summaryText: String {
        if let readErrorText {
            return "ตรวจ entitlements ในไบนารีไม่ได้: \(readErrorText)"
        }
        if stoppedAtLimit {
            return "สแกนได้ \(NetworkPolicy.formatBytes(scannedBytes)) แรกของไบนารี " +
                "(พบ \(foundKeys.count)/\(foundKeys.count + missingKeys.count) คีย์) — ไฟล์ใหญ่เกินเพดานการสแกน"
        }
        if foundKeys.isEmpty {
            var text = "ไม่พบข้อมูล entitlements ในไบนารี — ไบนารีนี้อาจถูกเซ็นด้วย codesign ad-hoc " +
                "หรือข้อมูลถูกตัดออกตอนติดตั้ง"
            if !looseMatchKeys.isEmpty {
                text += " (พบเพียงชื่อคีย์ \(looseMatchKeys.count) คีย์ในไบนารี แต่ไม่พบในรูป <key>…</key> ของ ldid)"
            }
            return text
        }
        if missingKeys.isEmpty {
            return "พบครบทั้ง \(foundKeys.count) คีย์ที่ต้องการในไบนารี ✓"
        }
        return "พบ \(foundKeys.count) คีย์ ขาด \(missingKeys.count) คีย์: \(missingKeys.joined(separator: ", "))"
    }
}

enum EntitlementProbe {

    /// เพดานการสแกนไบนารี (ไบนารีแอปทั่วไปประมาณ 1–10MB)
    static let scanLimitBytes: Int64 = 24 * 1024 * 1024
    static let chunkSize = 256 * 1024
    /// ไบต์ที่อ่านซ้ำระหว่างก้อน เพื่อให้เจอคีย์ที่ตกขอบพอดี
    static let overlapBytes = 512

    /// คีย์ทั้ง 5 ของโปรเจกต์นี้ (ใช้เป็นค่าเริ่มต้น)
    static var defaultKeys: [String] {
        PrivilegePolicy.entitlements.map { $0.key }
    }

    /// สแกนไบนารีของแอปที่กำลังรันอยู่
    static func scanRunningApp() -> EntitlementScanResult {
        let path = Bundle.main.executablePath
        guard let path, !path.isEmpty else {
            return EntitlementScanResult(binaryPath: nil,
                                         scannedBytes: 0,
                                         fileSizeBytes: 0,
                                         foundKeys: [],
                                         missingKeys: defaultKeys,
                                         totalMatches: 0,
                                         looseMatchKeys: [],
                                         stoppedAtLimit: false,
                                         readErrorText: "หา path ของไบนารีแอปไม่พบ")
        }
        return scan(path: path)
    }

    /// สแกนไฟล์ทีละก้อน (ใช้ได้กับไฟล์ใด ๆ เช่น .ipa ที่แตกแล้ว หรือเทสต์)
    static func scan(path: String, keys: [String] = EntitlementProbe.defaultKeys) -> EntitlementScanResult {
        let cleanKeys = keys.filter { !$0.isEmpty }
        guard !cleanKeys.isEmpty else {
            return EntitlementScanResult(binaryPath: path,
                                         scannedBytes: 0,
                                         fileSizeBytes: 0,
                                         foundKeys: [],
                                         missingKeys: [],
                                         totalMatches: 0,
                                         looseMatchKeys: [],
                                         stoppedAtLimit: false,
                                         readErrorText: "ไม่มีคีย์ให้สแกน")
        }

        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: path) else {
            return failure(path: path, keys: cleanKeys, message: "ไม่พบไฟล์ไบนารีที่ \(path)")
        }

        let rawAttributes = (try? fileManager.attributesOfItem(atPath: path)) ?? [:]
        let fileSize = (rawAttributes[.size] as? NSNumber)?.int64Value ?? 0
        guard let handle = FileHandle(forReadingAtPath: path) else {
            return failure(path: path, keys: cleanKeys, message: "เปิดไฟล์ไบนารีไม่ได้ (สิทธิ์ไม่พอ)")
        }
        defer { FileSystemService.closeQuietly(handle) }

        // ข้อความที่ใช้นับ — ใช้รูป <key>ชื่อคีย์</key> ก่อน ถ้าไม่พบจะนับชื่อคีย์เปล่า ๆ
        let needles = cleanKeys.map { ("<key>\($0)</key>", $0) }
        var counts: [String: Int] = [:]
        for key in cleanKeys { counts[key] = 0 }

        var scanned: Int64 = 0
        var carry = Data()
        var stoppedAtLimit = false
        var errorText: String?

        while scanned < scanLimitBytes {
            let remaining = scanLimitBytes - scanned
            let want = Int(min(Int64(chunkSize), remaining))
            let piece: Data
            do {
                guard let read = try handle.read(upToCount: want), !read.isEmpty else { break }
                piece = read
            } catch {
                errorText = error.localizedDescription
                break
            }

            var buffer = carry
            buffer.append(piece)
            let text = String(decoding: buffer, as: UTF8.self)

            for (needle, key) in needles {
                var searchRange = text.startIndex..<text.endIndex
                while let found = text.range(of: needle, range: searchRange) {
                    counts[key, default: 0] += 1
                    searchRange = found.upperBound..<text.endIndex
                }
            }

            scanned += Int64(piece.count)

            // เก็บท้ายก้อนไว้ต่อกับก้อนถัดไป เพื่อไม่ให้คีย์ที่ตกขอบหลุด
            if buffer.count > overlapBytes {
                carry = Data(buffer.suffix(overlapBytes))
            } else {
                carry = buffer
            }

            if piece.count < want { break }   // อ่านจนจบไฟล์แล้ว
        }

        if errorText == nil, scanned >= scanLimitBytes, fileSize > scanLimitBytes {
            stoppedAtLimit = true
        }

        // ตัดสินจากรูป <key>...</key> เท่านั้น (เป็นรูปแบบที่ ldid/codesign เขียนไว้จริง)
        var found: [String] = []
        var missing: [String] = []
        var loose: [String] = []
        for key in cleanKeys {
            if counts[key, default: 0] > 0 {
                found.append(key)
            } else {
                missing.append(key)
                if looseScanMatches(key, handle: handle, scannedBytes: scanned) {
                    loose.append(key)
                }
            }
        }

        let total = counts.values.reduce(0, +)
        return EntitlementScanResult(binaryPath: path,
                                     scannedBytes: scanned,
                                     fileSizeBytes: fileSize,
                                     foundKeys: found,
                                     missingKeys: missing,
                                     totalMatches: total,
                                     looseMatchKeys: loose,
                                     stoppedAtLimit: stoppedAtLimit,
                                     readErrorText: errorText)
    }

    /// สแกนข้อมูลในหน่วยความจำ (ใช้ในเทสต์ที่ไม่อยากเขียนไฟล์)
    static func scan(data: Data, keys: [String] = EntitlementProbe.defaultKeys) -> (found: [String], missing: [String]) {
        let text = String(decoding: data, as: UTF8.self)
        var found: [String] = []
        var missing: [String] = []
        for key in keys where !key.isEmpty {
            if text.range(of: "<key>\(key)</key>") != nil || text.range(of: key) != nil {
                found.append(key)
            } else {
                missing.append(key)
            }
        }
        return (found, missing)
    }

    // MARK: ตัวช่วยภายใน

    private static func looseScanMatches(_ needle: String, handle: FileHandle, scannedBytes: Int64) -> Bool {
        guard scannedBytes > 0, scannedBytes <= Int64(Int.max) else { return false }
        do {
            try handle.seek(toOffset: 0)
        } catch {
            return false
        }
        var carry = Data()
        var remaining = scannedBytes
        while remaining > 0 {
            let want = Int(min(Int64(chunkSize), remaining))
            guard let piece = try? handle.read(upToCount: want), !piece.isEmpty else { break }
            var buffer = carry
            buffer.append(piece)
            let text = String(decoding: buffer, as: UTF8.self)
            if text.range(of: needle) != nil {
                return true
            }
            carry = Data(buffer.suffix(overlapBytes))
            remaining -= Int64(piece.count)
        }
        return false
    }

    private static func failure(path: String, keys: [String], message: String) -> EntitlementScanResult {
        EntitlementScanResult(binaryPath: path,
                              scannedBytes: 0,
                              fileSizeBytes: 0,
                              foundKeys: [],
                              missingKeys: keys,
                              totalMatches: 0,
                              looseMatchKeys: [],
                              stoppedAtLimit: false,
                              readErrorText: message)
    }
}
