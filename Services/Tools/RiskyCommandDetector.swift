//
//  RiskyCommandDetector.swift
//  iOS Agent Sandbox
//
//  ประเมินว่า "คำสั่ง shell" หรือ "path ที่จะเขียนทับ" อันตรายแค่ไหน
//  ใช้สองที่: (1) ตัดสินใจว่าต้องเด้งหน้าขออนุมัติหรือไม่ (2) แสดงสี/เหตุผลบนการ์ด
//
//  หลักการ: ไม่พยายามเป็น shell parser จริง (ทำได้แต่เปราะ) แต่จับ "รูปแบบที่พังเครื่องได้จริง"
//  บน iOS: rm/mv/dd/chmod/chown/launchctl/killall + การเขียนทับ path ของระบบ
//
//  Foundation-only → รัน unit test ได้ทุกแพลตฟอร์ม
//

import Foundation

// MARK: - ระดับความเสี่ยง

enum RiskLevel: Int, Comparable, Codable, Equatable {
    /// ปลอดภัย/อ่านข้อมูลล้วน — ตั้งใจไม่ใช้ชื่อ "none" เพราะจะชนกับ Optional.none ของ Swift
    /// (ทำให้ `optionalValue == .none` เทียบพลาดได้) — บทเรียนจากการทดสอบ E2E
    case normal = 0
    case elevated = 1
    case destructive = 2

    static func < (lhs: RiskLevel, rhs: RiskLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var thaiName: String {
        switch self {
        case .normal: return "ปกติ"
        case .elevated: return "ควรระวัง"
        case .destructive: return "เสี่ยงสูง"
        }
    }
}

// MARK: - ผลการประเมิน

struct RiskAssessment: Equatable {
    let level: RiskLevel
    let reasons: [String]

    static let safe = RiskAssessment(level: .normal, reasons: [])

    /// ต้องให้ผู้ใช้อนุมัติหรือไม่ (เมื่อโหมดอนุมัติเปิดอยู่)
    var needsApproval: Bool {
        level != .normal
    }

    var summaryText: String {
        if reasons.isEmpty { return "ไม่พบความเสี่ยง" }
        return reasons.joined(separator: " • ")
    }
}

// MARK: - ตัวประเมิน

enum RiskyCommandDetector {

    /// คำสั่งที่ถือว่าเสี่ยงเมื่อถูกเรียกผ่าน shell
    private struct Rule {
        let token: String
        let level: RiskLevel
        let reason: String
    }

    private static let rules: [Rule] = [
        Rule(token: "rm", level: .destructive, reason: "คำสั่งลบไฟล์ (rm) — ลบแล้วกู้คืนไม่ได้บน iPhone ที่ยังไม่เจลเบรคเต็มรูปแบบ"),
        Rule(token: "shred", level: .destructive, reason: "คำสั่งลบแบบเขียนทับข้อมูล (shred)"),
        Rule(token: "mv", level: .elevated, reason: "คำสั่งย้าย/เขียนทับไฟล์ (mv) — ปลายทางเดิมจะถูกแทนที่"),
        Rule(token: "dd", level: .destructive, reason: "คำสั่งเขียนระดับดิบลงอุปกรณ์ (dd) — เขียนผิดตำแหน่งทำข้อมูลเสียหายได้"),
        Rule(token: "mkfs", level: .destructive, reason: "คำสั่งสร้างระบบไฟล์ใหม่ (mkfs) — ล้างข้อมูลทั้งพาร์ทิชัน"),
        Rule(token: "chmod", level: .elevated, reason: "คำสั่งเปลี่ยนสิทธิ์ไฟล์ (chmod) — ตั้งสิทธิ์ผิดแอปอาจเปิดไม่ได้"),
        Rule(token: "chown", level: .elevated, reason: "คำสั่งเปลี่ยนเจ้าของไฟล์ (chown)"),
        Rule(token: "chflags", level: .elevated, reason: "คำสั่งเปลี่ยนแฟล็กไฟล์ของ macOS/iOS (chflags)"),
        Rule(token: "truncate", level: .elevated, reason: "คำสั่งตัดไฟล์ให้สั้นลง (truncate)"),
        Rule(token: "killall", level: .elevated, reason: "คำสั่งปิดโปรเซสทั้งหมดตามชื่อ (killall) — ปิดผิดตัวระบบจะรีสปริง"),
        Rule(token: "launchctl", level: .destructive, reason: "คำสั่งจัดการบริการของระบบ (launchctl) — อาจทำให้เครื่องค้างหรือรีสปริง"),
        Rule(token: "sbreload", level: .destructive, reason: "คำสั่งรีสตาร์ท SpringBoard (sbreload)"),
        Rule(token: "uicache", level: .elevated, reason: "คำสั่งรีเฟรชไอคอนแอป (uicache)"),
        Rule(token: "ldid", level: .elevated, reason: "คำสั่งเซ็นไบนารีใหม่ (ldid) — เซ็นผิดแอปจะเปิดไม่ขึ้น"),
        Rule(token: "dpkg", level: .destructive, reason: "คำสั่งติดตั้ง/ถอนแพ็กเกจ jailbreak (dpkg)"),
        Rule(token: "apt", level: .destructive, reason: "คำสั่งจัดการแพ็กเกจ jailbreak (apt)"),
        Rule(token: "apt-get", level: .destructive, reason: "คำสั่งจัดการแพ็กเกจ jailbreak (apt-get)"),
        Rule(token: "sileo", level: .elevated, reason: "คำสั่งจัดการแพ็กเกจผ่าน Sileo"),
        Rule(token: "opainject", level: .elevated, reason: "คำสั่งแทรกไลบรารีเข้าแอปอื่น (opainject)"),
        Rule(token: "nvram", level: .destructive, reason: "คำสั่งแก้ตัวแปรระบบ (nvram)"),
        Rule(token: "csrutil", level: .destructive, reason: "คำสั่งแก้การป้องกันระบบ (csrutil)"),
        Rule(token: "mount", level: .elevated, reason: "คำสั่งเมานต์ระบบไฟล์ (mount)"),
        Rule(token: "umount", level: .elevated, reason: "คำสั่งยกเลิกเมานต์ระบบไฟล์ (umount)")
    ]

    /// คำสั่งที่อ่านอย่างเดียว — ถือว่าปลอดภัย ไม่ต้องอนุมัติแม้โหมดอนุมัติจะเปิด
    private static let readOnlyTokens: Set<String> = [
        "ls", "cat", "head", "tail", "grep", "find", "wc", "df", "du", "ps",
        "uname", "id", "whoami", "pwd", "echo", "date", "stat", "file", "which", "env",
        "printenv", "sw_vers", "sysctl", "ifconfig", "netstat", "md5", "shasum", "sed", "awk",
        "sort", "uniq", "tr", "cut", "basename", "dirname", "realpath", "readlink", "lsusb",
        "plutil", "defaults", "sqlite3", "strings", "xxd", "hexdump", "top", "uptime", "who"
    ]

    // MARK: ประเมินคำสั่ง shell

    static func assess(shellCommand: String, workspace: String = PathGuard.defaultWorkspace) -> RiskAssessment {
        let command = shellCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else { return .safe }

        var level: RiskLevel = .normal
        var reasons: [String] = []

        func raise(_ newLevel: RiskLevel, _ reason: String) {
            if !reasons.contains(reason) {
                reasons.append(reason)
            }
            if newLevel > level {
                level = newLevel
            }
        }

        // ตัดทุกคำสั่งย่อย (คั่นด้วย ; | && || & ขึ้นบรรทัดใหม่) แล้วตรวจทีละตัว
        for segment in splitSegments(command) {
            let tokens = segment.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            guard !tokens.isEmpty else { continue }

            // ข้ามตัวนำหน้าแบบ sudo/env ที่ไม่มีบน iOS แต่โมเดลอาจใส่
            var index = 0
            while index < tokens.count, ["sudo", "env", "time", "nohup", "ios-deploy"].contains(tokens[index]) {
                index += 1
            }
            guard index < tokens.count else { continue }

            let executable = (tokens[index] as NSString).lastPathComponent
            let rest = tokens[(index + 1)...].joined(separator: " ")

            if let rule = rules.first(where: { $0.token == executable }) {
                raise(rule.level, "\(rule.reason) → \(executable) \(rest.prefix(80))")
            }

            // พิเศษ: rm ที่ยิงใส่ path ของระบบ = เสี่ยงสูงสุด
            if executable == "rm" {
                for target in tokens.dropFirst(index + 1) where target.hasPrefix("/") {
                    if let reason = PathGuard.protectionReason(for: target, workspace: workspace) {
                        raise(.destructive, "ลบไฟล์ในที่ของระบบ: \(reason)")
                    }
                }
                if rest.contains("-r") || rest.contains("-R") {
                    raise(.destructive, "ลบแบบเรียกซ้ำ (ลบทั้งโฟลเดอร์)")
                }
            }

            // คำสั่งที่อ่านอย่างเดียว + ไม่มีตัวดำเนินการเขียน → ไม่ใช่ความเสี่ยง
            if readOnlyTokens.contains(executable), level == .normal {
                continue
            }
        }

        // การเปลี่ยนเส้นทาง (redirect) ไปยังไฟล์
        for target in redirectTargets(in: command) {
            if let reason = PathGuard.protectionReason(for: target, workspace: workspace) {
                raise(.destructive, "เขียนทับไฟล์ของระบบด้วยตัวดำเนินการ > : \(reason)")
            } else if level == .normal {
                raise(.elevated, "เขียนไฟล์ด้วยตัวดำเนินการ > (จะสร้างหรือเขียนทับ \(target))")
            }
        }

        // ดาวน์โหลดแล้วรันสคริปต์ตรง ๆ
        let flattened = command.replacingOccurrences(of: " ", with: "")
        if (flattened.contains("curl") || flattened.contains("wget")) && (flattened.contains("|sh") || flattened.contains("|bash") || flattened.contains("|/bin/sh")) {
            raise(.destructive, "ดาวน์โหลดสคริปต์จากอินเทอร์เน็ตแล้วรันทันที (curl | sh) — เนื้อหาที่โหลดมาถูกสั่งให้ทำอะไรก็ได้")
        }

        // แตะ path ของระบบด้วยคำสั่งอื่น ๆ (เช่น cat /System/… ที่ตามด้วยการเขียน)
        for token in command.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init) where token.hasPrefix("/") {
            if let reason = PathGuard.protectionReason(for: token, workspace: workspace), level == .normal {
                raise(.elevated, "คำสั่งอ้างถึง path ของระบบ: \(reason)")
            }
        }

        if level == .normal {
            return RiskAssessment(level: .normal, reasons: ["เป็นคำสั่งอ่านข้อมูลทั่วไป"])
        }
        return RiskAssessment(level: level, reasons: reasons)
    }

    // MARK: ประเมินการเขียนไฟล์ผ่าน tool

    static func assessWrite(path: String, workspace: String = PathGuard.defaultWorkspace) -> RiskAssessment {
        if let reason = PathGuard.protectionReason(for: path, workspace: workspace) {
            return RiskAssessment(level: .destructive, reasons: [reason])
        }
        return .safe
    }

    /// การดาวน์โหลดทับไฟล์ที่มีอยู่แล้วถือเป็นการเขียนทับ → ต้องอนุมัติ
    static func assessDownload(destination: String,
                               fileExists: Bool,
                               workspace: String = PathGuard.defaultWorkspace) -> RiskAssessment {
        if let reason = PathGuard.protectionReason(for: destination, workspace: workspace) {
            return RiskAssessment(level: .destructive, reasons: [reason])
        }
        if fileExists {
            return RiskAssessment(level: .elevated,
                                  reasons: ["ไฟล์ปลายทางมีอยู่แล้ว — การดาวน์โหลดจะเขียนทับไฟล์เดิม"])
        }
        return .safe
    }

    // MARK: ตัวช่วยภายใน

    /// แยกคำสั่งผสมออกเป็นคำสั่งย่อย (โดยไม่พยายามเข้าใจเครื่องหมายคำพูด — เพียงพอสำหรับการประเมิน)
    private static func splitSegments(_ command: String) -> [String] {
        var segments: [String] = []
        var current = ""
        var index = command.startIndex
        while index < command.endIndex {
            let character = command[index]
            if character == ";" || character == "\n" {
                segments.append(current)
                current = ""
            } else if character == "|" || character == "&" {
                // || และ && ถือเป็นตัวคั่นด้วย (ตรวจแต่ละฝั่งแยกกัน)
                let next = command.index(after: index)
                if next < command.endIndex, command[next] == "|" || command[next] == "&" {
                    index = next
                }
                segments.append(current)
                current = ""
            } else {
                current.append(character)
            }
            index = command.index(after: index)
        }
        segments.append(current)
        return segments.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// หา path ปลายทางของการเปลี่ยนเส้นทางด้วย > หรือ >>
    private static func redirectTargets(in command: String) -> [String] {
        var targets: [String] = []
        let characters = Array(command)
        var index = 0
        while index < characters.count {
            if characters[index] == ">" {
                var cursor = index + 1
                if cursor < characters.count, characters[cursor] == ">" {
                    cursor += 1
                }
                while cursor < characters.count, characters[cursor] == " " {
                    cursor += 1
                }
                var token = ""
                while cursor < characters.count, characters[cursor] != " ", characters[cursor] != "\n" {
                    token.append(characters[cursor])
                    cursor += 1
                }
                let trimmed = token.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty, !trimmed.hasPrefix("&") {
                    targets.append(trimmed)
                }
                index = cursor
            } else {
                index += 1
            }
        }
        return targets
    }
}
