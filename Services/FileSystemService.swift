//
//  FileSystemService.swift
//  iOS Agent Sandbox
//
//  ชั้นกลางสำหรับเข้าถึงไฟล์ "ทุก path ที่แอปมีสิทธิ์" (เฟส 3)
//  ใช้ FileManager เป็นหลัก แต่ห่อด้วย:
//  - ข้อความ error ภาษาไทยที่บอกสาเหตุจริง (ไม่พบไฟล์ / ไม่มีสิทธิ์ / ปลายทางมีอยู่แล้ว)
//  - การอ่านแบบทีละก้อน (ChunkedFileReader) เพื่อไม่กิน RAM บนเครื่อง 2GB
//  - เมธอดครบชุดที่เฟส 4–5 ต้องใช้ (สร้าง/ลบ/ย้าย/คัดลอก/ลิงก์/พื้นที่ว่าง)
//
//  ไฟล์นี้เป็น Foundation-only → รัน unit test/E2E ได้ทุกแพลตฟอร์ม (ไม่แตะ UIKit)
//

import Foundation

// MARK: - ข้อผิดพลาดของไฟล์

enum FileSystemError: LocalizedError, Equatable {
    case notFound(String)
    case notADirectory(String)
    case isADirectory(String)
    case permissionDenied(String)
    case alreadyExists(String)
    case directoryNotEmpty(String)
    case tooLarge(path: String, size: Int64, limit: Int64)
    case cancelled
    case io(path: String, message: String)

    var errorDescription: String? {
        switch self {
        case .notFound(let path):
            return "ไม่พบไฟล์หรือโฟลเดอร์: \(path)"
        case .notADirectory(let path):
            return "path นี้ไม่ใช่โฟลเดอร์: \(path)"
        case .isADirectory(let path):
            return "path นี้เป็นโฟลเดอร์ ไม่ใช่ไฟล์: \(path)"
        case .permissionDenied(let path):
            return "ไม่มีสิทธิ์เข้าถึง \(path) — ถ้าเป็น path ของระบบ ต้องติดตั้งผ่าน TrollStore (entitlements no-sandbox) หรือรันเป็น root"
        case .alreadyExists(let path):
            return "ปลายทางมีอยู่แล้ว: \(path)"
        case .directoryNotEmpty(let path):
            return "โฟลเดอร์ไม่ว่าง: \(path) — ต้องใช้การลบแบบเรียกซ้ำ"
        case .tooLarge(let path, let size, let limit):
            return "ไฟล์ใหญ่เกินขอบเขต: \(path) (\(NetworkPolicy.formatBytes(size)) เกินเพดาน \(NetworkPolicy.formatBytes(limit)))"
        case .cancelled:
            return "งานถูกยกเลิก"
        case .io(let path, let message):
            return "ทำงานกับ \(path) ไม่สำเร็จ: \(message)"
        }
    }

    /// ชนิดข้อผิดพลาดในภาษาของ tools (ใช้กับ ToolExecutionResult)
    var toolErrorKind: ToolErrorKind {
        switch self {
        case .notFound, .notADirectory, .isADirectory: return .notFound
        case .permissionDenied: return .permissionDenied
        case .alreadyExists, .directoryNotEmpty: return .failed
        case .tooLarge: return .tooLarge
        case .cancelled: return .cancelled
        case .io: return .failed
        }
    }
}

// MARK: - ข้อมูลของไฟล์

struct FileAttributes: Equatable {
    let path: String
    let isDirectory: Bool
    let isSymbolicLink: Bool
    let sizeBytes: Int64
    let modificationDate: Date?
    let creationDate: Date?
    /// สิทธิ์แบบข้อความ เช่น "rw-r--r--" (nil ถ้าอ่านไม่ได้)
    let permissionsText: String?
    /// รหัสเจ้าของไฟล์ (nil ถ้าอ่านไม่ได้)
    let ownerID: Int?
    /// ปลายทางของ symlink (nil ถ้าไม่ใช่ symlink)
    let linkTarget: String?

    var kindText: String {
        if isSymbolicLink {
            return "ลิงก์ → \(linkTarget ?? "?")"
        }
        return isDirectory ? "โฟลเดอร์" : "ไฟล์"
    }

    var sizeText: String {
        isDirectory ? "—" : NetworkPolicy.formatBytes(sizeBytes)
    }
}

/// รายการหนึ่งบรรทัดในโฟลเดอร์ (ใช้โดย FileBrowserTool และ FileBrowserView ในเฟส 4)
struct FileEntry: Equatable, Identifiable {
    let path: String
    let name: String
    let isDirectory: Bool
    let isSymbolicLink: Bool
    let sizeBytes: Int64
    let modificationDate: Date?

    var id: String { path }

    var isHidden: Bool {
        name.hasPrefix(".")
    }
}

struct WriteReport: Equatable {
    let path: String
    let bytesWritten: Int
    let didOverwriteExisting: Bool
    /// ขนาดไฟล์รวมหลังเขียน (ไบต์)
    let finalSizeBytes: Int64
}

// MARK: - บริการ

enum FileSystemService {

    /// ขนาดก้อนที่อ่านจากดิสก์ต่อครั้ง
    static let readChunkSize = 64 * 1024

    /// เพดานข้อมูลที่ยอมอ่านเข้าหน่วยความจำในครั้งเดียว
    static let maxReadBytes = ToolOutputLimiter.maxReadBytes

    // MARK: ตรวจสอบ

    static func exists(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }

    /// true/false = เป็นโฟลเดอร์หรือไม่, nil = ไม่มี path นี้
    static func isDirectory(_ path: String) -> Bool? {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
            return nil
        }
        return isDirectory.boolValue
    }

    /// รายละเอียดไฟล์ (โยน FileSystemError ที่มีข้อความไทยเมื่อล้มเหลว)
    static func attributes(of path: String) throws -> FileAttributes {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: path) else {
            throw FileSystemError.notFound(path)
        }

        let linkTarget = try? fileManager.destinationOfSymbolicLink(atPath: path) // ล้มเหลว = ไม่ใช่ symlink
        let isSymbolicLink = linkTarget != nil

        do {
            let raw = try fileManager.attributesOfItem(atPath: path)
            let type = raw[.type] as? FileAttributeType
            let isDirectory = type == .typeDirectory
            let size = (raw[.size] as? NSNumber)?.int64Value ?? 0
            let permissions = raw[.posixPermissions] as? NSNumber
            let owner = raw[.ownerAccountID] as? NSNumber

            return FileAttributes(path: path,
                                  isDirectory: isDirectory,
                                  isSymbolicLink: isSymbolicLink,
                                  sizeBytes: size,
                                  modificationDate: raw[.modificationDate] as? Date,
                                  creationDate: raw[.creationDate] as? Date,
                                  permissionsText: permissions.map { Self.permissionText($0.intValue) },
                                  ownerID: owner?.intValue,
                                  linkTarget: linkTarget)
        } catch {
            throw map(error, path: path)
        }
    }

    // MARK: อ่าน

    struct Prefix {
        let text: String
        let bytesRead: Int
        let totalBytes: Int64
        let isBinary: Bool
        /// true = ยังมีข้อมูลเหลือในไฟล์ที่ยังไม่ได้อ่าน
        let hasMore: Bool
    }

    /// อ่าน "ส่วนต้น" ของไฟล์ไม่เกิน maxBytes โดยไม่โหลดทั้งไฟล์
    static func readPrefix(_ path: String, maxBytes: Int = 96 * 1024) throws -> Prefix {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: path) else {
            throw FileSystemError.notFound(path)
        }
        guard isDirectory(path) != true else {
            throw FileSystemError.isADirectory(path)
        }

        let rawAttributes: [FileAttributeKey: Any]
        do {
            rawAttributes = try fileManager.attributesOfItem(atPath: path)
        } catch {
            throw map(error, path: path)
        }
        let totalBytes = (rawAttributes[.size] as? NSNumber)?.int64Value ?? 0

        guard let handle = FileHandle(forReadingAtPath: path) else {
            throw FileSystemError.permissionDenied(path)
        }
        defer { closeQuietly(handle) }

        var collected = Data()
        let ceiling = max(1, min(maxBytes, FileSystemService.maxReadBytes))
        do {
            while collected.count < ceiling {
                try Task.checkCancellation()
                let remaining = ceiling - collected.count
                let readSize = Swift.min(readChunkSize, remaining)
                guard let chunk = try handle.read(upToCount: readSize), !chunk.isEmpty else {
                    break
                }
                collected.append(chunk)
            }
        } catch is CancellationError {
            throw FileSystemError.cancelled
        } catch {
            throw FileSystemError.io(path: path, message: error.localizedDescription)
        }

        return Prefix(text: chunkDecode(collected),
                      bytesRead: collected.count,
                      totalBytes: totalBytes,
                      isBinary: looksBinary(collected),
                      hasMore: totalBytes > Int64(collected.count))
    }

    /// อ่านเฉพาะส่วนต้นไม่กี่ไบต์ (ใช้ทำตัวอย่าง hex หรือสแกนหัวไฟล์)
    static func readHead(_ path: String, maxBytes: Int = 256) throws -> Data {
        guard let handle = FileHandle(forReadingAtPath: path) else {
            throw FileSystemError.permissionDenied(path)
        }
        defer { closeQuietly(handle) }
        do {
            return try handle.read(upToCount: max(1, min(maxBytes, FileSystemService.maxReadBytes))) ?? Data()
        } catch {
            throw FileSystemError.io(path: path, message: error.localizedDescription)
        }
    }

    /// อ่านทั้งไฟล์ (ใช้กับไฟล์เล็กเท่านั้น — ปฏิเสธถ้าใหญ่เกินเพดาน)
    static func readAll(_ path: String, limitBytes: Int = 512 * 1024) throws -> Data {
        let attributes = try attributes(of: path)
        guard !attributes.isDirectory else {
            throw FileSystemError.isADirectory(path)
        }
        guard attributes.sizeBytes <= Int64(limitBytes) else {
            throw FileSystemError.tooLarge(path: path, size: attributes.sizeBytes, limit: Int64(limitBytes))
        }
        do {
            return try Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe)
        } catch {
            throw map(error, path: path)
        }
    }

    // MARK: เขียน

    @discardableResult
    static func write(_ content: String,
                      to path: String,
                      append: Bool = false,
                      createDirectories: Bool = true,
                      maximumBytes: Int = 512 * 1024) throws -> WriteReport {
        let data = Data(content.utf8)
        guard data.count <= maximumBytes else {
            throw FileSystemError.tooLarge(path: path, size: Int64(data.count), limit: Int64(maximumBytes))
        }

        let fileManager = FileManager.default
        let existedBefore = fileManager.fileExists(atPath: path)
        if existedBefore, isDirectory(path) == true {
            throw FileSystemError.isADirectory(path)
        }

        if createDirectories {
            let directory = (path as NSString).deletingLastPathComponent
            if !directory.isEmpty, !fileManager.fileExists(atPath: directory) {
                do {
                    try fileManager.createDirectory(atPath: directory,
                                                    withIntermediateDirectories: true,
                                                    attributes: nil)
                } catch {
                    throw map(error, path: directory)
                }
            }
        }

        do {
            if append, existedBefore {
                let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: path))
                defer { closeQuietly(handle) }
                _ = try handle.seekToEnd()
                try handle.write(contentsOf: data)
            } else {
                try data.write(to: URL(fileURLWithPath: path), options: .atomic)
            }
        } catch {
            throw map(error, path: path)
        }

        let finalSize = (try? attributes(of: path).sizeBytes) ?? Int64(data.count)
        return WriteReport(path: path,
                           bytesWritten: data.count,
                           didOverwriteExisting: existedBefore,
                           finalSizeBytes: finalSize)
    }

    // MARK: จัดการโฟลเดอร์

    /// รายการในโฟลเดอร์ (เรียงโฟลเดอร์ก่อน แล้วตามชื่อ)
    static func list(_ path: String,
                     includeHidden: Bool = false,
                     limit: Int = 500) throws -> (entries: [FileEntry], totalCount: Int, skippedHidden: Int) {
        guard let isDirectoryValue = isDirectory(path) else {
            throw FileSystemError.notFound(path)
        }
        guard isDirectoryValue else {
            throw FileSystemError.notADirectory(path)
        }

        let fileManager = FileManager.default
        let names: [String]
        do {
            names = try fileManager.contentsOfDirectory(atPath: path)
        } catch {
            throw map(error, path: path)
        }

        var entries: [FileEntry] = []
        var skippedHidden = 0

        for name in names.sorted(by: { $0.lowercased() < $1.lowercased() }) {
            if !includeHidden, name.hasPrefix(".") {
                skippedHidden += 1
                continue
            }
            let entryPath = (path as NSString).appendingPathComponent(name)
            let raw = (try? fileManager.attributesOfItem(atPath: entryPath)) ?? [:]
            let type = raw[.type] as? FileAttributeType
            entries.append(FileEntry(path: entryPath,
                                     name: name,
                                     isDirectory: type == .typeDirectory,
                                     isSymbolicLink: type == .typeSymbolicLink,
                                     sizeBytes: (raw[.size] as? NSNumber)?.int64Value ?? 0,
                                     modificationDate: raw[.modificationDate] as? Date))
        }

        entries.sort { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory {
                return lhs.isDirectory && !rhs.isDirectory
            }
            return lhs.name.lowercased() < rhs.name.lowercased()
        }

        return (Array(entries.prefix(limit)), entries.count, skippedHidden)
    }

    /// ชื่อไฟล์/โฟลเดอร์เท่านั้น (ใช้โดย search_files ที่ต้องเดินเองเพื่อคุมความลึก)
    static func directoryNames(_ path: String) throws -> [String] {
        do {
            return try FileManager.default.contentsOfDirectory(atPath: path)
        } catch {
            throw map(error, path: path)
        }
    }

    static func createDirectory(_ path: String, intermediate: Bool = true) throws {
        do {
            try FileManager.default.createDirectory(atPath: path,
                                                    withIntermediateDirectories: intermediate,
                                                    attributes: nil)
        } catch {
            throw map(error, path: path)
        }
    }

    // MARK: ลบ / ย้าย / คัดลอก

    static func remove(_ path: String, recursive: Bool = false) throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: path) else {
            throw FileSystemError.notFound(path)
        }
        if isDirectory(path) == true, !recursive {
            let children = (try? directoryNames(path)) ?? []
            if !children.isEmpty {
                throw FileSystemError.directoryNotEmpty(path)
            }
        }
        do {
            try fileManager.removeItem(atPath: path)
        } catch {
            throw map(error, path: path)
        }
    }

    static func move(_ source: String, to destination: String, overwrite: Bool = false) throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: source) else {
            throw FileSystemError.notFound(source)
        }
        if fileManager.fileExists(atPath: destination) {
            guard overwrite else {
                throw FileSystemError.alreadyExists(destination)
            }
            try remove(destination, recursive: true)
        }
        try ensureParentDirectory(of: destination)
        do {
            try fileManager.moveItem(atPath: source, toPath: destination)
        } catch {
            // ข้ามโวลุ่มไม่ได้ (เช่น /tmp → /var) → คัดลอกแล้วลบต้นทาง
            do {
                try fileManager.copyItem(atPath: source, toPath: destination)
                try fileManager.removeItem(atPath: source)
            } catch {
                throw map(error, path: source)
            }
        }
    }

    static func copy(_ source: String, to destination: String, overwrite: Bool = false) throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: source) else {
            throw FileSystemError.notFound(source)
        }
        if fileManager.fileExists(atPath: destination) {
            guard overwrite else {
                throw FileSystemError.alreadyExists(destination)
            }
            try remove(destination, recursive: true)
        }
        try ensureParentDirectory(of: destination)
        do {
            try fileManager.copyItem(atPath: source, toPath: destination)
        } catch {
            throw map(error, path: source)
        }
    }

    // MARK: ลิงก์และพื้นที่ว่าง

    /// ปลายทางจริงของ symlink (คืน path เดิมเมื่อไม่ใช่ symlink)
    static func resolveSymlink(_ path: String) -> String {
        let fileManager = FileManager.default
        if let target = try? fileManager.destinationOfSymbolicLink(atPath: path) {
            if target.hasPrefix("/") {
                return target
            }
            let parent = (path as NSString).deletingLastPathComponent
            return PathGuard.normalize(parent + "/" + target)
        }
        return path
    }

    /// พื้นที่ว่าง/ทั้งหมดของโวลุ่มที่ path นี้อยู่ (ไบต์) — nil ถ้าอ่านไม่ได้
    static func volumeSpace(at path: String) -> (free: Int64, total: Int64)? {
        let fileManager = FileManager.default
        guard let attributes = try? fileManager.attributesOfFileSystem(forPath: path) else {
            return nil
        }
        let free = (attributes[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
        let total = (attributes[.systemSize] as? NSNumber)?.int64Value ?? 0
        guard total > 0 else { return nil }
        return (free, total)
    }

    /// สร้างโฟลเดอร์แม่ให้ถ้ายังไม่มี
    static func ensureParentDirectory(of path: String) throws {
        let directory = (path as NSString).deletingLastPathComponent
        guard !directory.isEmpty, directory != "/" else { return }
        guard !FileManager.default.fileExists(atPath: directory) else { return }
        do {
            try FileManager.default.createDirectory(atPath: directory,
                                                    withIntermediateDirectories: true,
                                                    attributes: nil)
        } catch {
            throw map(error, path: directory)
        }
    }

    // MARK: ตัวช่วยภายใน

    static func closeQuietly(_ handle: FileHandle) {
        do {
            try handle.close()
        } catch {
            // ปิดไม่สำเร็จไม่กระทบผลลัพธ์ — ระบบจะเก็บคืนเองเมื่อ handle ถูกปล่อย
        }
    }

    /// แปลง NSError ของระบบเป็น FileSystemError ที่มีข้อความไทย
    static func map(_ error: Error, path: String) -> FileSystemError {
        if error is CancellationError {
            return .cancelled
        }
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain {
            switch nsError.code {
            case NSFileNoSuchFileError, NSFileReadNoSuchFileError:
                return .notFound(path)
            case NSFileReadNoPermissionError, NSFileWriteNoPermissionError:
                return .permissionDenied(path)
            case NSFileWriteFileExistsError:
                return .alreadyExists(path)
            case NSFileReadTooLargeError:
                return .tooLarge(path: path, size: 0, limit: Int64(FileSystemService.maxReadBytes))
            case NSFileWriteVolumeReadOnlyError:
                return .io(path: path, message: "โวลุ่มนี้เขียนไม่ได้ (อ่านอย่างเดียว)")
            default:
                break
            }
        }
        if nsError.domain == NSPOSIXErrorDomain {
            switch Int32(nsError.code) {
            case ENOENT:
                return .notFound(path)
            case EACCES, EPERM:
                return .permissionDenied(path)
            case EEXIST:
                return .alreadyExists(path)
            case ENOTEMPTY:
                return .directoryNotEmpty(path)
            case ENOTDIR:
                return .notADirectory(path)
            case EISDIR:
                return .isADirectory(path)
            default:
                break
            }
        }
        return .io(path: path, message: nsError.localizedDescription)
    }

    /// แปลงสิทธิ์ POSIX เป็นข้อความแบบที่ ls ใช้ (rwxr-xr-x)
    static func permissionText(_ permissions: Int) -> String {
        let bits: [(Int, Character)] = [
            (0o400, "r"), (0o200, "w"), (0o100, "x"),
            (0o040, "r"), (0o020, "w"), (0o010, "x"),
            (0o004, "r"), (0o002, "w"), (0o001, "x")
        ]
        var text = ""
        for (mask, symbol) in bits {
            text.append((permissions & mask) != 0 ? symbol : "-")
        }
        return text
    }

    /// เดาว่าเป็นไฟล์ไบนารีหรือไม่ (เจอไบต์ 0 ในส่วนต้น)
    static func looksBinary(_ data: Data) -> Bool {
        for byte in data.prefix(4096) where byte == 0 {
            return true
        }
        return false
    }

    /// ถอดรหัสข้อความ: UTF-8 → ตัดไบต์ท้ายที่ค้าง → ISO Latin-1 → lossy UTF-8
    static func chunkDecode(_ data: Data) -> String {
        if data.isEmpty { return "" }
        if let text = String(data: data, encoding: .utf8) { return text }
        if data.count > 4 {
            for drop in 1...3 {
                if let text = String(data: Data(data.dropLast(drop)), encoding: .utf8) {
                    return text
                }
            }
        }
        if let text = String(data: data, encoding: .isoLatin1) { return text }
        return String(decoding: data, as: UTF8.self)
    }

    /// ตัวอย่าง hex ของข้อมูล (ใช้กับไฟล์ไบนารี)
    static func hexPreview(_ data: Data, maxBytes: Int = 256) -> String {
        var lines: [String] = []
        var offset = 0
        var lineBytes: [UInt8] = []
        var ascii = ""

        for byte in data.prefix(maxBytes) {
            lineBytes.append(byte)
            ascii.append(byte >= 32 && byte < 127 ? Character(UnicodeScalar(byte)) : ".")
            if lineBytes.count == 16 {
                lines.append(String(format: "%08x  ", offset) + hexPart(lineBytes) + " |" + ascii + "|")
                offset += 16
                lineBytes.removeAll()
                ascii = ""
            }
        }
        if !lineBytes.isEmpty {
            lines.append(String(format: "%08x  ", offset) + hexPart(lineBytes) + " |" + ascii + "|")
        }
        return lines.joined(separator: "\n")
    }

    private static func hexPart(_ bytes: [UInt8]) -> String {
        var text = ""
        for (index, byte) in bytes.enumerated() {
            text += String(format: "%02x ", byte)
            if index == 7 { text += " " }
        }
        while text.count < 51 {
            text += " "
        }
        return text
    }
}

// MARK: - ตัวอ่านไฟล์แบบทีละก้อน (ใช้ร่วมกับเครื่องมือเครือข่าย)
//
// เดิมอยู่ใน FileTools.swift — ย้ายมาไว้ที่ชั้น FileSystemService เพื่อให้ทั้งแอปใช้ตัวเดียวกัน

enum ChunkedFileReader {

    static let chunkSize = FileSystemService.readChunkSize

    typealias Prefix = FileSystemService.Prefix

    /// อ่านส่วนต้นของไฟล์ (โยน FileSystemError ที่มีข้อความไทย)
    static func readPrefix(path: String, maxBytes: Int = 96 * 1024) throws -> Prefix {
        try FileSystemService.readPrefix(path, maxBytes: maxBytes)
    }

    static func readHead(path: String, maxBytes: Int = 256) throws -> Data {
        try FileSystemService.readHead(path, maxBytes: maxBytes)
    }

    static func looksBinary(_ data: Data) -> Bool {
        FileSystemService.looksBinary(data)
    }

    static func decode(_ data: Data) -> String {
        FileSystemService.chunkDecode(data)
    }

    static func hexPreview(_ data: Data, maxBytes: Int = 256) -> String {
        FileSystemService.hexPreview(data, maxBytes: maxBytes)
    }
}
