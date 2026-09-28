//
//  PrivilegePolicy.swift
//  iOS Agent Sandbox
//
//  นโยบายเรื่อง "สิทธิ์" ของแอป (เฟส 3)
//  - เลือกโหมดการรันคำสั่ง: ผู้ใช้ปัจจุบัน หรือ root ผ่าน persona ของ TrollStore
//  - รวบรวม path ของ shell/PATH ที่ใช้จริงบนเครื่องที่ติดตั้งแบบต่าง ๆ
//  - อธิบาย entitlements ทั้ง 5 คีย์ที่ฝังในไบนารี (ใช้ทั้งในแอปและรายงานผล)
//
//  ไฟล์นี้เป็น Foundation-only และไม่เรียก API ของ Darwin เลย
//  (ตัวที่เรียกจริงคือ ShellService/PrivilegeService) จึงรัน unit test ได้ทุกแพลตฟอร์ม
//

import Foundation

// MARK: - โหมดการรันคำสั่ง

enum ShellLaunchMode: Equatable {
    /// รันในนามผู้ใช้เดียวกับแอป (uid 501 = mobile ในเครื่องทั่วไป)
    case currentUser
    /// รันในนาม root (uid 0) ด้วย persona ของ TrollStore
    case rootPersona

    var thaiName: String {
        switch self {
        case .currentUser: return "ผู้ใช้ปัจจุบัน"
        case .rootPersona: return "root (persona \(PrivilegePolicy.rootPersonaID))"
        }
    }

    var symbolName: String {
        switch self {
        case .currentUser: return "person"
        case .rootPersona: return "lock.open"
        }
    }
}

/// ผลการตัดสินใจว่าจะรันคำสั่งแบบไหน พร้อมเหตุผลภาษาไทย
struct LaunchModeDecision: Equatable {
    let mode: ShellLaunchMode
    /// เหตุผลสั้น ๆ (แสดงในผลลัพธ์ของ tool และในรายงานการทดสอบ)
    let reason: String
}

// MARK: - นโยบาย

enum PrivilegePolicy {

    /// หมายเลข persona ที่ TrollStore ใช้สลับไปรันเป็น root
    static let rootPersonaID: UInt32 = 99

    /// flag ของ posix_spawnattr_set_persona_np (ค่าคงที่ของ XNU: POSIX_SPAWN_PERSONA_FLAGS_OVERRIDE)
    static let personaFlagsOverride: UInt32 = 1

    /// ลำดับการหา shell (ตัวแรกที่มีจริงถูกใช้) — รองรับทั้ง rootless (/var/jb) และ rootful
    static let shellSearchPaths = [
        "/var/jb/bin/sh",       // rootless jailbreak (palera1n rootless / Dopamine)
        "/var/jb/usr/bin/sh",
        "/bin/sh",              // ทุก iOS (system shell)
        "/usr/bin/sh"
    ]

    /// PATH ที่ใส่ให้โปรเซสลูก — /var/jb/usr/bin มาก่อนเพื่อให้ใช้เครื่องมือของ jailbreak
    /// (เป็น superset ของ /var/jb/usr/bin:/usr/bin:/bin ที่จำเป็นขั้นต่ำ)
    static let shellPath = "/var/jb/usr/bin:/var/jb/bin:/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin"

    /// ตัวแปรสภาพแวดล้อมที่ใส่ให้ทุกคำสั่ง shell
    static func environment(uid: Int32, temporaryDirectory: String) -> [String] {
        [
            "PATH=\(shellPath)",
            "HOME=\(uid == 0 ? "/var/root" : "/var/mobile")",
            "TMPDIR=\(temporaryDirectory)",
            "LANG=C.UTF-8",
            "TERM=dumb",
            "LD_LIBRARY_PATH=/var/jb/usr/lib"
        ]
    }

    /// ตัดสินใจว่าจะพยายามรันเป็น root หรือไม่
    ///
    /// - Parameters:
    ///   - preferRoot: ผู้ใช้เปิดตัวเลือก "รันคำสั่งในนาม root ถ้าทำได้"
    ///   - canUsePersona: ตรวจพบฟังก์ชัน persona ในระบบปฏิบัติการนี้ (มาจาก PrivilegeService)
    ///   - currentUserID: uid ปัจจุบันของแอป (0 = เป็น root อยู่แล้ว)
    static func decideLaunchMode(preferRoot: Bool,
                                 canUsePersona: Bool,
                                 currentUserID: Int32) -> LaunchModeDecision {
        if currentUserID == 0 {
            return LaunchModeDecision(mode: .currentUser,
                                      reason: "แอปรันเป็น root อยู่แล้ว (uid 0) จึงไม่ต้องสลับ persona")
        }
        if !preferRoot {
            return LaunchModeDecision(mode: .currentUser,
                                      reason: "ปิดตัวเลือก \"รันคำสั่งในนาม root\" ไว้ (ตั้งค่า > Agent)")
        }
        if !canUsePersona {
            return LaunchModeDecision(mode: .currentUser,
                                      reason: "ไม่พบฟังก์ชัน posix_spawnattr_set_persona_np ของระบบ หรือแอปไม่ได้เซ็นด้วยสิทธิ์ persona-mgmt — จะรันในนามผู้ใช้ปัจจุบัน")
        }
        return LaunchModeDecision(mode: .rootPersona,
                                  reason: "จะลองรันในนาม root ด้วย persona \(rootPersonaID) (ต้องมีสิทธิ์ persona-mgmt)")
    }

    // MARK: การอธิบาย entitlements

    struct EntitlementExplanation: Equatable {
        /// คีย์ตามที่ปรากฏในไฟล์ .entitlements
        let key: String
        /// ชื่อสั้นภาษาไทยสำหรับแสดงบนหน้าจอ
        let thaiName: String
        /// เปิดอะไรให้แอป
        let effect: String
        /// ถ้าไม่มีคีย์นี้จะเป็นอย่างไร
        let withoutIt: String
        /// ค่าที่ไฟล์ entitlements ของโปรเจกต์นี้ตั้งไว้ (true/false)
        let expectedValue: Bool
    }

    /// คีย์ทั้ง 5 ที่โปรเจกต์นี้ใช้ (ตรงกับ Entitlements/iOSAgentSandbox.entitlements)
    static let entitlements: [EntitlementExplanation] = [
        EntitlementExplanation(
            key: "platform-application",
            thaiName: "แอปแพลตฟอร์ม",
            effect: "ทำให้ไบนารีถูกมองว่าเป็นแอปของแพลตฟอร์ม (แบบเดียวกับแอปของ Apple) จึงรันได้โดยไม่ต้องมี provisioning profile และไม่ติดข้อจำกัดของแอปที่ลงนามแบบผู้ใช้ทั่วไป — จำเป็นเมื่อติดตั้งผ่าน TrollStore",
            withoutIt: "TrollStore จะติดตั้งไม่ผ่าน หรือติดตั้งได้แต่เปิดไม่ขึ้น เพราะระบบไม่ยอมรับไบนารีที่ไม่มีข้อมูลการลงนามที่รู้จัก",
            expectedValue: true
        ),
        EntitlementExplanation(
            key: "com.apple.private.security.no-container",
            thaiName: "ไม่ใช้ data container",
            effect: "ปิดการใช้ data container ของแอป ทำให้แอปไม่ถูกจำกัดให้เห็นแค่โฟลเดอร์ของตัวเอง — อ่าน/เขียน /var/mobile/... และ path อื่นได้โดยตรง",
            withoutIt: "ทุก path จะถูกตัดให้ไปอยู่ใต้ /var/containers/Data/Application/<UUID>/ ของแอปเอง (อ่านไฟล์ของผู้ใช้ไม่ได้)",
            expectedValue: true
        ),
        EntitlementExplanation(
            key: "com.apple.private.security.no-sandbox",
            thaiName: "ปิด sandbox",
            effect: "ยกเลิก sandbox ของทั้งโปรเซส — เป็นคีย์สำคัญที่สุดสำหรับ FileSystemService และ ShellService เพราะถ้าไม่มีแม้จะเปิด /var/mobile ได้ก็ยังถูกปฏิเสธที่ระดับ kernel",
            withoutIt: "การอ่าน/เขียนไฟล์นอกโฟลเดอร์ของแอปจะล้มเหลวด้วยข้อความ \"Operation not permitted\"",
            expectedValue: true
        ),
        EntitlementExplanation(
            key: "com.apple.private.persona-mgmt",
            thaiName: "จัดการ persona",
            effect: "อนุญาตให้สลับ user persona ตอน spawn โปรเซส ทำให้รันคำสั่ง shell ในนาม root ได้ด้วย posix_spawnattr_set_persona_np (เส้นทางของ TrollStore)",
            withoutIt: "คำสั่ง shell จะรันในนามผู้ใช้ mobile (uid 501) เท่านั้น — ยูทิลิตี้ที่ต้องเป็น root จะทำไม่ได้",
            expectedValue: true
        ),
        EntitlementExplanation(
            key: "com.apple.private.security.container-required",
            thaiName: "ไม่บังคับ container",
            effect: "ระบุว่าแอปไม่บังคับให้ต้องมี container (คู่กับ no-container) ป้องกันระบบสร้าง container ให้เองแล้วดึง path กลับไปอยู่ใน /var/containers/...",
            withoutIt: "ระบบอาจบังคับสร้าง container และคืน path ใน /var/containers/ แทน /var/mobile ทำให้ Agent ทำงานกับไฟล์ผู้ใช้ไม่ได้",
            expectedValue: false
        )
    ]

    /// ค่าที่คาดหวังจากคีย์หนึ่ง (true/false) ในรูปแบบข้อความ plist
    static func plistValueLine(for explanation: EntitlementExplanation) -> String {
        explanation.expectedValue ? "<true/>" : "<false/>"
    }

    /// สร้างเนื้อหาไฟล์ .entitlements (XML plist) ทั้ง 5 คีย์
    ///
    /// ใช้คู่กับคำสั่ง:  ldid -S<ไฟล์นี้> <ไบนารีของแอป>
    /// ผู้ใช้กดบันทึกจากหน้า "คำอธิบาย entitlements" ในแอปได้เลย
    static func entitlementsPlistXML(comment: String? = nil) -> String {
        var lines: [String] = []
        lines.append("<?xml version=\"1.0\" encoding=\"UTF-8\"?>")
        lines.append("<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">")
        if let comment, !comment.isEmpty {
            lines.append("<!-- \(comment) -->")
        }
        lines.append("<plist version=\"1.0\">")
        lines.append("<dict>")
        for explanation in entitlements {
            lines.append("\t<key>\(explanation.key)</key>")
            lines.append("\t\(plistValueLine(for: explanation))")
        }
        lines.append("</dict>")
        lines.append("</plist>")
        return lines.joined(separator: "\n") + "\n"
    }

    /// ข้อความตรวจสอบแบบ <key>...</key> สำหรับค้นหาในไบนารี
    static func entitlementKeyNeedles(_ explanation: EntitlementExplanation) -> [String] {
        ["<key>\(explanation.key)</key>", explanation.key]
    }

    // MARK: ชนิดการติดตั้ง

    enum InstallKind: Equatable {
        case trollStoreOrPermasigned
        case rootfulJailbreak
        case rootlessJailbreak
        case unknown(String)

        var thaiName: String {
            switch self {
            case .trollStoreOrPermasigned: return "TrollStore / permasigned"
            case .rootfulJailbreak: return "เจลเบรคแบบ rootful (/Applications)"
            case .rootlessJailbreak: return "เจลเบรคแบบ rootless (/var/jb)"
            case .unknown: return "ไม่ทราบ"
            }
        }

        var advice: String {
            switch self {
            case .trollStoreOrPermasigned:
                return "ควรอ่าน/เขียนไฟล์ทั้งเครื่องได้เต็มที่ และรันคำสั่งเป็น root ได้ผ่าน persona"
            case .rootfulJailbreak:
                return "รันเป็น root อยู่แล้ว — ถ้าอ่าน /var/mobile ไม่ได้ ให้ตรวจว่าเซ็นไบนารีด้วย ldid แล้วหรือยัง"
            case .rootlessJailbreak:
                return "เครื่องมือของ jailbreak อยู่ใต้ /var/jb — ตรวจว่ามี /var/jb/bin/sh และ /var/jb/usr/bin"
            case .unknown:
                return "ตรวจชนิดการติดตั้งไม่ได้ — ดูผลการเข้าถึงไฟล์ด้านล่างเป็นหลัก"
            }
        }
    }

    /// เดาชนิดการติดตั้งจาก path ของ bundle ที่แอปรันอยู่
    static func installKind(bundlePath: String) -> InstallKind {
        let path = bundlePath
        if path.hasPrefix("/var/containers/Bundle/Application")
            || path.hasPrefix("/private/var/containers/Bundle/Application") {
            return .trollStoreOrPermasigned
        }
        if path.hasPrefix("/Applications") {
            return .rootfulJailbreak
        }
        if path.hasPrefix("/var/jb") || path.hasPrefix("/private/preboot") {
            return .rootlessJailbreak
        }
        return .unknown(path.isEmpty ? "ไม่ทราบ path ของ bundle" : path)
    }
}
