//
//  PrivilegeService.swift
//  iOS Agent Sandbox
//
//  ตรวจ "แอปนี้มีสิทธิ์แค่ไหน" ณ เวลาที่รันอยู่ (เฟส 3)
//  แล้วสรุปเป็นภาษาไทยที่ผู้ใช้เข้าใจได้ พร้อมวิธีแก้เมื่อยังได้สิทธิ์ไม่ครบ
//
//  สิ่งที่ตรวจ:
//  1) uid ปัจจุบัน (root หรือ mobile)
//  2) ชนิดการติดตั้ง (TrollStore / rootful / rootless)
//  3) shell ที่ใช้ได้จริงตามลำดับ /var/jb/bin/sh → /bin/sh
//  4) ฟังก์ชัน persona ของระบบ (ใช้รันคำสั่งเป็น root)
//  5) อ่าน/เขียน /var/mobile และโฟลเดอร์ทำงานได้จริงหรือไม่ (ทดสอบด้วยการอ่าน/เขียนจริง)
//  6) entitlements 5 คีย์ที่ฝังในไบนารี (สแกนไฟล์ไบนารี)
//
//  ไฟล์นี้ต้องคอมไพล์ได้ทั้ง Darwin และ Linux (ใช้ใน unit test/E2E)
//

import Foundation

struct PrivilegeChecklistItem: Equatable {
    let title: String
    let value: String
    let isOK: Bool
    let note: String?
}

struct PrivilegeReport: Equatable {

    let checkedAt: Date
    let userID: Int32
    let isRoot: Bool
    let bundlePath: String
    let installKind: PrivilegePolicy.InstallKind
    let shellPath: String?
    let personaAvailable: Bool
    let launchDecision: LaunchModeDecision
    let varMobileReadable: Bool
    let varMobileWritable: Bool
    let workspacePath: String
    let workspaceWritable: Bool
    let entitlements: EntitlementScanResult?
    let isRunningOnIOS: Bool

    /// สรุปสั้น ๆ สำหรับแสดงบนหัวข้อในหน้าตั้งค่า
    var summaryText: String {
        var parts: [String] = []
        parts.append(isRoot ? "ผู้ใช้: root" : "ผู้ใช้: \(userNameForUI)")
        parts.append("ติดตั้งแบบ: \(installKind.thaiName)")
        parts.append(varMobileReadable ? "/var/mobile: อ่านได้" : "/var/mobile: อ่านไม่ได้")
        return parts.joined(separator: " • ")
    }

    var userNameForUI: String {
        switch userID {
        case 0: return "root (uid 0)"
        case 501: return "mobile (uid 501)"
        default: return "uid \(userID)"
        }
    }

    /// true = สั่งรันคำสั่งเป็น root ได้จริงตอนนี้
    var canRunAsRootNow: Bool {
        if isRoot { return true }
        if case .rootPersona = launchDecision.mode { return personaAvailable }
        return false
    }

    /// พร้อมใช้งานเต็มรูปแบบ (อ่านไฟล์ทั้งเครื่องได้)
    var isFullyPrivileged: Bool {
        varMobileReadable && entitlements?.hasAllFive == true
    }

    var checklist: [PrivilegeChecklistItem] {
        [
            PrivilegeChecklistItem(
                title: "ผู้ใช้ที่แอปรันอยู่",
                value: userNameForUI,
                isOK: true,
                note: isRoot ? "รันเป็น root อยู่แล้ว ไม่ต้องสลับ persona" : "แอปผู้ใช้ทั่วไป — ถ้าต้องการ root ให้ติดตั้งผ่าน TrollStore"
            ),
            PrivilegeChecklistItem(
                title: "อ่าน /var/mobile",
                value: varMobileReadable ? "ได้" : "ไม่ได้",
                isOK: varMobileReadable,
                note: varMobileReadable ? "เข้าถึงไฟล์ของผู้ใช้ได้ตามที่ออกแบบไว้" : "ยังถูกจำกัดสิทธิ์ — ติดตั้งผ่าน TrollStore หรือ palera1n"
            ),
            PrivilegeChecklistItem(
                title: "เขียน /var/mobile",
                value: varMobileWritable ? "ได้" : "ไม่ได้ (อ่านอย่างเดียว)",
                isOK: varMobileWritable,
                note: varMobileWritable ? nil : "คำสั่งที่เขียนไฟล์ใน /var/mobile จะล้มเหลว"
            ),
            PrivilegeChecklistItem(
                title: "โฟลเดอร์ทำงานของ Agent",
                value: workspacePath + (workspaceWritable ? " (เขียนได้)" : " (เขียนไม่ได้)"),
                isOK: workspaceWritable,
                note: workspaceWritable ? nil : "เปลี่ยน path ในช่อง \"โฟลเดอร์ทำงาน\" ด้านบน"
            ),
            PrivilegeChecklistItem(
                title: "shell ที่ใช้",
                value: shellPath ?? "ไม่พบ shell",
                isOK: shellPath != nil,
                note: shellPath == nil ? "ลองติดตั้งผู้ช่วย jailbreak ให้มี /bin/sh หรือปรับ path ในโค้ด" : nil
            ),
            PrivilegeChecklistItem(
                title: "รันคำสั่งเป็น root (persona)",
                value: canRunAsRootNow ? "ทำได้" : (personaAvailable ? "ปิดไว้ในตั้งค่า" : "ระบบไม่รองรับ/ไม่ได้รับสิทธิ์"),
                isOK: canRunAsRootNow,
                note: personaAvailable
                    ? "ต้องมีคีย์ com.apple.private.persona-mgmt ใน entitlements และรันบน TrollStore"
                    : "ไม่พบฟังก์ชัน posix_spawnattr_set_persona_np ของระบบ — คำสั่งจะรันในนามผู้ใช้ปัจจุบัน"
            ),
            PrivilegeChecklistItem(
                title: "entitlements ในไบนารี",
                value: entitlements.map { "\($0.foundKeys.count)/\($0.foundKeys.count + $0.missingKeys.count) คีย์" } ?? "ยังไม่ได้ตรวจ",
                isOK: entitlements?.hasAllFive ?? false,
                note: entitlements?.summaryText
            ),
            PrivilegeChecklistItem(
                title: "แพลตฟอร์มที่กำลังรัน",
                value: isRunningOnIOS ? "iOS (อุปกรณ์จริง)" : "ไม่ใช่ iOS (เครื่องพัฒนา/ซิมูเลเตอร์)",
                isOK: true,
                note: isRunningOnIOS ? nil : "ผลการตรวจ path ของระบบจะไม่ตรงกับบน iPhone"
            )
        ]
    }

    /// รายการที่ยังไม่ผ่าน พร้อมคำแนะนำแก้ไข
    var pendingAdvice: [String] {
        var advice: [String] = []
        if isRunningOnIOS, !varMobileReadable {
            advice.append("ติดตั้ง .ipa นี้ผ่าน TrollStore (หรือ palera1n) เพื่อให้ได้สิทธิ์อ่านไฟล์ทั้งเครื่อง")
        }
        if isRunningOnIOS, varMobileReadable, !varMobileWritable {
            advice.append("อ่านได้แต่เขียนไม่ได้ — ตรวจว่าติดตั้งแบบติดตั้งผู้ใช้ (sideload) อยู่หรือไม่ แล้วเปลี่ยนไปใช้ TrollStore")
        }
        if !workspaceWritable {
            advice.append("เปลี่ยน \"โฟลเดอร์ทำงาน\" ในตั้งค่าเป็น path ที่เขียนได้ เช่น /var/mobile/AgentWorkspace")
        }
        if shellPath == nil {
            advice.append("ไม่พบ shell ที่ใช้ได้ — เครื่องรุ่นเก่าควรมี /bin/sh; ถ้าใช้ jailbreak แบบ rootless ให้ตรวจว่ามี /var/jb/bin/sh")
        }
        if let entitlements, !entitlements.hasAllFive, isRunningOnIOS {
            advice.append("ไบนารีขาด entitlements บางคีย์ — ติดตั้ง .ipa ที่เซ็นด้วย ldid (บิลด์จาก GitHub Actions ของโปรเจกต์นี้) อีกครั้ง")
        }
        if isRunningOnIOS, !personaAvailable {
            advice.append("ฟังก์ชัน persona ไม่พร้อม — คำสั่ง shell จะรันในนามผู้ใช้ปัจจุบัน (ยังใช้งานได้ แต่แก้ไฟล์ของระบบไม่ได้)")
        }
        if advice.isEmpty {
            advice.append("สิทธิ์ครบถ้วนตามที่โปรเจกต์นี้ออกแบบไว้ — Agent อ่าน/เขียนไฟล์ทั้งเครื่องและรันคำสั่งได้ตามปกติ")
        }
        return advice
    }

    /// ข้อความสั้นสำหรับใส่ใน System Prompt ให้ Agent รู้ว่าตัวเองมีสิทธิ์แค่ไหน
    var promptContext: String {
        var lines: [String] = []
        lines.append("สิทธิ์ของแอปบนเครื่องนี้: \(summaryText)")
        lines.append("shell: \(shellPath ?? "ไม่พบ")")
        lines.append(canRunAsRootNow
                     ? "รันคำสั่งเป็น root ได้ (execute_shell จะลองสลับ persona ให้เอง)"
                     : "รันคำสั่งในนามผู้ใช้ปัจจุบัน (ยังไม่ใช่ root) — ถ้าคำสั่งต้องเป็น root ให้แจ้งผู้ใช้ว่าต้องติดตั้งผ่าน TrollStore")
        if isRunningOnIOS, !varMobileReadable {
            lines.append("อ่าน /var/mobile ไม่ได้ — ให้แจ้งผู้ใช้เรื่องสิทธิ์ก่อนพยายามอ่านไฟล์นอกโฟลเดอร์ของแอป")
        }
        if let entitlements, !entitlements.hasAllFive {
            lines.append("entitlements ที่ฝังในไบนารีไม่ครบ: \(entitlements.summaryText)")
        }
        return lines.joined(separator: "\n")
    }
}

enum PrivilegeService {

    /// ตรวจสถานะสิทธิ์ทั้งหมด ณ ตอนนี้ (เรียกจากหน้าตั้งค่า/ตอนเปิดแอป)
    static func probe(workspacePath: String, preferRootShell: Bool) -> PrivilegeReport {
        let userID = ShellService.currentUserID
        let bundlePath = Bundle.main.bundlePath
        let installKind = PrivilegePolicy.installKind(bundlePath: bundlePath)
        let shellPath = ShellService.shared.resolveShellPath()
        let personaAvailable = ShellService.personaSymbolsAvailable
        let launchDecision = PrivilegePolicy.decideLaunchMode(preferRoot: preferRootShell,
                                                              canUsePersona: personaAvailable,
                                                              currentUserID: userID)

        let varMobileReadable = isReadable("/var/mobile")
        let varMobileWritable = isWritable("/var/mobile")
        let workspaceWritable = ensureWorkspace(workspacePath) && isWritable(workspacePath)
        let entitlements = EntitlementProbe.scanRunningApp()

        return PrivilegeReport(checkedAt: Date(),
                               userID: userID,
                               isRoot: userID == 0,
                               bundlePath: bundlePath,
                               installKind: installKind,
                               shellPath: shellPath,
                               personaAvailable: personaAvailable,
                               launchDecision: launchDecision,
                               varMobileReadable: varMobileReadable,
                               varMobileWritable: varMobileWritable,
                               workspacePath: workspacePath,
                               workspaceWritable: workspaceWritable,
                               entitlements: entitlements,
                               isRunningOnIOS: isRunningOnIOS())
    }

    // MARK: แคช (การสแกนไบนารีมีค่าใช้จ่าย จึงไม่ทำทุกครั้งที่ส่งข้อความ)

    private static let cacheLock = NSLock()
    private static var cache: (report: PrivilegeReport, key: String, at: Date)?

    /// อายุของผลตรวจที่ยอมให้ใช้ซ้ำ (วินาที)
    static let cacheLifetime: TimeInterval = 120

    /// ผลตรวจแบบใช้ซ้ำได้ (คำนวณใหม่เมื่อพ้นอายุ หรือเมื่อค่าตั้งเปลี่ยน)
    static func cachedReport(workspacePath: String, preferRootShell: Bool) -> PrivilegeReport {
        let key = "\(workspacePath)|\(preferRootShell)"

        cacheLock.lock()
        if let cache, cache.key == key, Date().timeIntervalSince(cache.at) < cacheLifetime {
            cacheLock.unlock()
            return cache.report
        }
        cacheLock.unlock()

        let report = probe(workspacePath: workspacePath, preferRootShell: preferRootShell)

        cacheLock.lock()
        cache = (report, key, Date())
        cacheLock.unlock()

        return report
    }

    /// ข้อความสำหรับ System Prompt (ใช้แคช)
    static func cachedPromptContext(workspacePath: String, preferRootShell: Bool) -> String {
        cachedReport(workspacePath: workspacePath, preferRootShell: preferRootShell).promptContext
    }

    /// ล้างแคช (เรียกเมื่อผู้ใช้เปลี่ยนค่าตั้งหรือกดตรวจใหม่)
    static func invalidateCache() {
        cacheLock.lock()
        cache = nil
        cacheLock.unlock()
    }

    /// เขียนไฟล์ .entitlements (สำหรับ ldid) ลงในโฟลเดอร์ที่กำหนด
    static func writeEntitlementsFile(to directory: String,
                                      fileName: String = "iOSAgentSandbox.entitlements") throws -> WriteReport {
        let path = (directory as NSString).appendingPathComponent(fileName)
        let comment = "สร้างโดยแอป iOS Agent Sandbox — ใช้กับ: ldid -S<ไฟล์นี้> <ไบนารี>"
        return try FileSystemService.write(PrivilegePolicy.entitlementsPlistXML(comment: comment),
                                          to: path,
                                          append: false,
                                          createDirectories: true,
                                          maximumBytes: 16 * 1024)
    }

    // MARK: ตัวช่วย

    /// ตรวจว่าแอปรันบน iOS จริง (ไม่ใช่เครื่อง dev/ซิมูเลเตอร์/CI)
    static func isRunningOnIOS() -> Bool {
        #if os(iOS)
        return true
        #else
        return false
        #endif
    }

    /// อ่านโฟลเดอร์ได้หรือไม่ (ทดลองอ่านจริง)
    static func isReadable(_ path: String) -> Bool {
        guard FileSystemService.isDirectory(path) == true else { return false }
        do {
            _ = try FileManager.default.contentsOfDirectory(atPath: path)
            return true
        } catch {
            return false
        }
    }

    /// เขียนไฟล์ชั่วคราวในโฟลเดอร์นั้นได้หรือไม่ แล้วลบทิ้ง (ทดลองเขียนจริง)
    static func isWritable(_ path: String) -> Bool {
        guard FileSystemService.isDirectory(path) == true else { return false }
        let probePath = (path as NSString).appendingPathComponent(".iosagent-writecheck-\(UUID().uuidString)")
        do {
            try Data("ok".utf8).write(to: URL(fileURLWithPath: probePath), options: .atomic)
        } catch {
            return false
        }
        try? FileManager.default.removeItem(atPath: probePath)
        return true
    }

    /// สร้างโฟลเดอร์ทำงานให้ถ้ายังไม่มี (คืน false = สร้างไม่ได้)
    static func ensureWorkspace(_ path: String) -> Bool {
        if FileSystemService.isDirectory(path) == true { return true }
        return (try? FileSystemService.createDirectory(path)) != nil
    }
}
