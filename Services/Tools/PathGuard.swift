//
//  PathGuard.swift
//  iOS Agent Sandbox
//
//  ตรวจและปรับ path ที่โมเดลส่งมาให้ปลอดภัยและคาดเดาได้
//  - ยุบ ".." และ "/" ซ้ำ ให้เหลือ path เดียวที่ชี้ปลายทางจริง
//  - path สัมพัทธ์ถูกตีความเป็น "สัมพัทธ์กับ workspace" (ไม่ใช่ CWD ของแอป)
//  - รู้ว่า path ใดเป็น "ของระบบ" (ต้องขออนุมัติก่อนเขียนทับ)
//
//  Foundation-only → รัน unit test ได้ทุกแพลตฟอร์ม
//

import Foundation

enum PathGuard {

    /// โฟลเดอร์ทำงานเริ่มต้นของ Agent (สร้างให้อัตโนมัติเมื่อ tool ตัวแรกเขียนไฟล์)
    static let defaultWorkspace = "/var/mobile/AgentWorkspace"

    /// path ที่ถือว่า "ของระบบ" — เขียนทับได้แต่ต้องให้ผู้ใช้อนุมัติก่อน
    private static let protectedRoots: [String] = [
        "/System",
        "/usr",
        "/bin",
        "/sbin",
        "/etc",
        "/dev",
        "/Applications",
        "/Library",
        "/cores",
        "/private/etc",
        "/private/preboot",
        "/private/var/db",
        "/private/var/jb/bin",
        "/private/var/jb/sbin",
        "/private/var/jb/usr",
        "/var/db",
        "/var/jb/bin",
        "/var/jb/sbin",
        "/var/jb/usr",
        "/var/stash",
        "/var/lib/dpkg"
    ]

    /// โฟลเดอร์บ้านของผู้ใช้บน iOS (โทรศัพท์ที่ผ่าน TrollStore/palera1n ใช้ /var/mobile)
    static var defaultHome: String {
        #if os(iOS)
        return "/var/mobile"
        #else
        // บน macOS/Linux (ใช้ตอนรัน unit test/E2E) ใช้โฟลเดอร์บ้านจริงของโปรเซส
        return NSHomeDirectory()
        #endif
    }

    // MARK: - ปรับ path

    /// ปรับ path ให้เป็น absolute + ยุบ `.`/`..`/`//` และตัด `/` ท้าย (ยกเว้น "/")
    ///
    /// - Parameters:
    ///   - raw: path ที่ได้จากโมเดลหรือผู้ใช้
    ///   - workspace: ใช้เป็นฐานเมื่อ path ไม่ขึ้นต้นด้วย "/" (ค่าเริ่มต้นคือโฟลเดอร์ Agent)
    ///   - home: ใช้แทน "~" (บน iOS = /var/mobile)
    static func normalize(_ raw: String,
                          workspace: String = PathGuard.defaultWorkspace,
                          home: String = PathGuard.defaultHome) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        // ลบเครื่องหมายคำพูดที่โมเดลมักติดมา (เช่น "'/var/mobile/a.txt'")
        if text.count >= 2,
           let first = text.first, let last = text.last,
           (first == "\"" && last == "\"") || (first == "'" && last == "'") {
            text = String(text.dropFirst().dropLast())
        }

        guard !text.isEmpty else { return workspace }

        // ขยาย ~
        if text == "~" {
            text = home
        } else if text.hasPrefix("~/") {
            text = home + String(text.dropFirst(1))
        }

        // path สัมพัทธ์ → ต่อกับ workspace
        if !text.hasPrefix("/") {
            text = workspace + "/" + text
        }

        // ยุบส่วนประกอบ
        var stack: [String] = []
        for component in text.split(separator: "/", omittingEmptySubsequences: true) {
            if component == "." {
                continue
            }
            if component == ".." {
                if !stack.isEmpty {
                    stack.removeLast()
                }
                continue
            }
            stack.append(String(component))
        }

        let joined = "/" + stack.joined(separator: "/")
        return joined.isEmpty ? "/" : joined
    }

    /// path นี้อยู่ภายใน workspace หรือไม่ (ใช้ตัดสินว่าเป็นไฟล์ของผู้ใช้เอง)
    static func isWithinWorkspace(_ path: String, workspace: String = PathGuard.defaultWorkspace) -> Bool {
        let normalized = normalize(path, workspace: workspace)
        let root = normalize(workspace, workspace: workspace)
        return normalized == root || normalized.hasPrefix(root + "/")
    }

    // MARK: - path ของระบบ

    /// เหตุผลที่ path นี้ต้องขออนุมัติ (nil = เขียนได้ตามปกติ)
    static func protectionReason(for path: String,
                                 workspace: String = PathGuard.defaultWorkspace) -> String? {
        let normalized = normalize(path, workspace: workspace)

        for root in protectedRoots {
            if normalized == root || normalized.hasPrefix(root + "/") {
                return "อยู่ใน \(root) ซึ่งเป็นไดเรกทอรีของระบบ — แก้ผิดอาจทำให้เครื่องเปิดไม่ติด"
            }
        }

        // ไฟล์สำคัญระดับเครื่องที่อยู่นอกลิสต์ด้านบน
        let sensitiveFiles: Set<String> = [
            "/var/mobile/Library/Preferences/com.apple.springboard.plist",
            "/private/var/mobile/Library/Preferences/com.apple.springboard.plist"
        ]
        if sensitiveFiles.contains(normalized) {
            return "เป็นไฟล์ตั้งค่าของ SpringBoard — แก้ผิดแอปและหน้าจอหลักอาจมีปัญหา"
        }

        return nil
    }

    static func isProtected(_ path: String, workspace: String = PathGuard.defaultWorkspace) -> Bool {
        protectionReason(for: path, workspace: workspace) != nil
    }

    // MARK: - ชื่อไฟล์

    /// ทำชื่อไฟล์ที่ผู้ใช้/โมเดลส่งมาให้ปลอดภัย (ตัด / และอักขระควบคุมออก)
    static func sanitizedFileName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var cleaned = ""
        for scalar in trimmed.unicodeScalars {
            if scalar == "/" || scalar == "\\" || scalar == ":" || scalar.value < 0x20 {
                cleaned.append("_")
            } else {
                cleaned.unicodeScalars.append(scalar)
            }
        }
        if cleaned.isEmpty || cleaned == "." || cleaned == ".." {
            return "untitled"
        }
        if cleaned.count > 120 {
            cleaned = String(cleaned.prefix(120))
        }
        return cleaned
    }

    /// ชื่อไฟล์เริ่มต้นเมื่อผู้ใช้ไม่ได้ระบุ (ใช้กับ download_file)
    /// ต้องเป็น URL เต็มที่มี scheme + host เท่านั้น ไม่งั้นคืนชื่อกลาง ๆ
    static func suggestedFileName(fromURLString urlString: String) -> String {
        guard let url = URL(string: urlString),
              url.scheme != nil,
              let host = url.host, !host.isEmpty else {
            return "download.bin"
        }
        let last = url.lastPathComponent
        if last.isEmpty || last == "/" {
            return "download.bin"
        }
        return sanitizedFileName(last)
    }

    // MARK: - แสดงผล

    /// ย่อ path ให้สั้นลงสำหรับแสดงบนจอ 4.7 นิ้ว (ตัด prefix ของ workspace ออก)
    static func displayPath(_ path: String, workspace: String = PathGuard.defaultWorkspace) -> String {
        let normalized = normalize(path, workspace: workspace)
        if isWithinWorkspace(normalized, workspace: workspace) {
            let root = normalize(workspace, workspace: workspace)
            let suffix = normalized.dropFirst(root.count)
            let trimmed = suffix.hasPrefix("/") ? String(suffix.dropFirst()) : String(suffix)
            return trimmed.isEmpty ? "~" : "~/" + trimmed
        }
        return normalized
    }
}
