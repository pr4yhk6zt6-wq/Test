//
//  SystemAccessChecker.swift
//  iOS Agent Sandbox
//
//  ตรวจสิทธิ์การเข้าถึงระบบไฟล์ตอนเปิดแอป
//  ถ้าอ่าน /var/mobile ไม่ได้ แปลว่าแอปยังถูก sandbox อยู่
//  (ต้องติดตั้งผ่าน TrollStore หรือเจลเบรคด้วย palera1n)
//

import Foundation
import Darwin

struct SystemAccessReport {
    let isRoot: Bool
    let isVarMobileReadable: Bool
    let isVarContainersReadable: Bool
    let isPrivateVarReadable: Bool
    let isVarJailbreakReadable: Bool
    let jailbreakMarkers: [String]
    let checkedAt: Date

    /// ต้องแจ้งเตือนให้ผู้ใช้รู้ว่ายังไม่ได้รับสิทธิ์เข้าถึงไฟล์ทั้งเครื่อง
    var needsJailbreakNotice: Bool {
        !isVarMobileReadable
    }

    var privilegeText: String {
        isRoot ? "root" : "mobile (ไม่ใช่ root)"
    }

    /// ข้อความบรรทัดเดียวสรุปสถานะ
    var summaryMessage: String {
        var parts: [String] = []
        parts.append("สิทธิ์: \(privilegeText)")
        parts.append(isVarMobileReadable ? "/var/mobile: อ่านได้" : "/var/mobile: อ่านไม่ได้")
        parts.append(isVarContainersReadable ? "/var/containers: อ่านได้" : "/var/containers: อ่านไม่ได้")
        return parts.joined(separator: " • ")
    }
}

enum SystemAccessChecker {

    /// path ที่ตรวจว่าอ่านได้หรือไม่
    static let probePaths: [String] = [
        "/var/mobile",
        "/var/containers",
        "/private/var",
        "/var/jb"
    ]

    /// ร่องรอยการติดตั้งแบบปลดล็อก/TrollStore (ใช้เพื่อแสดงข้อมูลเท่านั้น)
    static let jailbreakMarkerPaths: [String] = [
        "/var/jb",
        "/Applications/TrollStore.app",
        "/private/var/mobile/Library/Preferences/com.opa334.trollstore.plist",
        "/Applications/Cydia.app",
        "/Applications/Sileo.app",
        "/private/var/lib/dpkg",
        "/bin/bash"
    ]

    static func check() -> SystemAccessReport {
        let fileManager = FileManager.default

        func isReadable(_ path: String) -> Bool {
            fileManager.isReadableFile(atPath: path)
        }

        func exists(_ path: String) -> Bool {
            fileManager.fileExists(atPath: path)
        }

        let markers = jailbreakMarkerPaths.filter { exists($0) }

        return SystemAccessReport(
            isRoot: getuid() == 0,
            isVarMobileReadable: isReadable("/var/mobile"),
            isVarContainersReadable: isReadable("/var/containers"),
            isPrivateVarReadable: isReadable("/private/var"),
            isVarJailbreakReadable: isReadable("/var/jb"),
            jailbreakMarkers: markers,
            checkedAt: Date()
        )
    }

    /// path ของ shell ที่ควรลองใช้ (ตรวจละเอียดใน ShellService เฟส 3)
    static func candidateShellPaths() -> [String] {
        ["/var/jb/bin/sh", "/bin/sh"]
    }

    /// รายชื่อ path ที่แอปควรเข้าถึงได้ ถ้าได้รับ entitlements ครบ
    static func expectedAccessiblePaths() -> [String] {
        ["/var/mobile", "/var/containers", "/private/var", "/var/jb", "/Applications"]
    }
}
