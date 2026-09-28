//
//  ToolCore.swift
//  iOS Agent Sandbox
//
//  สัญญา (contract) กลางของ tools ทั้งหมดในเฟส 2
//  - ทุก tool ต้องมี descriptor (ชื่อ + คำอธิบายไทย + หมวด) และ definition (สคีมาที่ส่งให้โมเดล)
//  - ทุก tool ต้องคืน ToolExecutionResult เสมอ ไม่ throw ออกมา (engine จับ error เอง)
//  - ผลลัพธ์ทุกชิ้นต้องผ่าน ToolOutputLimiter เพื่อคุมหน่วยความจำบนเครื่อง RAM 2GB
//
//  ไฟล์นี้เป็น Foundation-only (ไม่แตะ UIKit/SwiftUI) จึงถูกนำไปรัน unit test บน Linux/macOS ได้
//

import Foundation

// MARK: - หมวดของ tool

enum ToolCategory: String, Codable, Equatable {
    case fileSystem
    case shell
    case network

    /// ป้ายภาษาไทยที่แสดงใน UI
    var thaiName: String {
        switch self {
        case .fileSystem: return "ไฟล์"
        case .shell: return "คำสั่ง shell"
        case .network: return "อินเทอร์เน็ต"
        }
    }

    /// ชื่อไอคอน SF Symbols (ใช้เฉพาะฝั่ง UI — ที่นี่เก็บเป็น string เพื่อไม่ผูกกับ SwiftUI)
    var symbolName: String {
        switch self {
        case .fileSystem: return "doc.text"
        case .shell: return "terminal"
        case .network: return "globe"
        }
    }
}

// MARK: - ชนิดของข้อผิดพลาด

/// ชนิดข้อผิดพลาดของ tool — ใช้ตัดสินใจฝั่ง UI และบอกโมเดลว่าควรลองใหม่แบบไหน
enum ToolErrorKind: String, Codable, Equatable {
    /// arguments ที่โมเดลส่งมาไม่ครบ/ผิดชนิด
    case invalidArguments
    /// ไม่พบไฟล์หรือโฟลเดอร์ปลายทาง
    case notFound
    /// ระบบปฏิบัติการไม่ให้สิทธิ์ (sandbox / สิทธิ์ไฟล์)
    case permissionDenied
    /// ถูกนโยบายของแอปบล็อก (ปิดอินเทอร์เน็ต, ไม่ใช่ HTTPS, ไฟล์ใหญ่เกิน)
    case blocked
    /// หมดเวลา
    case timeout
    /// ผู้ใช้กดหยุด
    case cancelled
    /// ไฟล์ใหญ่เกินขอบเขตที่กำหนด
    case tooLarge
    /// ข้อผิดพลาดอื่น ๆ (I/O, เครือข่าย, exit code)
    case failed

    var thaiName: String {
        switch self {
        case .invalidArguments: return "arguments ไม่ถูกต้อง"
        case .notFound: return "ไม่พบไฟล์/ปลายทาง"
        case .permissionDenied: return "ไม่มีสิทธิ์เข้าถึง"
        case .blocked: return "ถูกนโยบายของแอปบล็อก"
        case .timeout: return "หมดเวลา"
        case .cancelled: return "ถูกยกเลิก"
        case .tooLarge: return "ไฟล์ใหญ่เกินขอบเขต"
        case .failed: return "ทำงานไม่สำเร็จ"
        }
    }
}

// MARK: - ผลลัพธ์ของ tool

/// ผลลัพธ์ที่จะถูกส่งกลับให้โมเดลในบทบาท role = "tool"
/// (ทำตาม Error ด้วย เพื่อให้ใช้เป็นค่าความล้มเหลวใน Result ได้โดยตรง)
struct ToolExecutionResult: Equatable, Error {
    /// ข้อความที่จะให้โมเดลอ่าน (ผ่านการจำกัดความยาวแล้ว)
    let text: String
    /// true = เป็นข้อผิดพลาด (โมเดลควรอ่านแล้วแก้ทางเอง)
    let isError: Bool
    /// ชนิดข้อผิดพลาด (nil = สำเร็จ)
    let kind: ToolErrorKind?
    /// true = ข้อความถูกตัดเพราะยาวเกินขอบเขต
    let truncated: Bool

    init(text: String, isError: Bool, kind: ToolErrorKind? = nil, truncated: Bool = false) {
        self.text = text
        self.isError = isError
        self.kind = kind
        self.truncated = truncated
    }

    /// สร้างผลลัพธ์สำเร็จ (จำกัดความยาวให้อัตโนมัติ)
    static func ok(_ text: String) -> ToolExecutionResult {
        let limited = ToolOutputLimiter.limit(text)
        return ToolExecutionResult(text: limited.text, isError: false, kind: nil, truncated: limited.truncated)
    }

    /// สร้างผลลัพธ์สำเร็จแบบไม่ต้องตัดความยาว (ใช้กับการตอบที่สั้นอยู่แล้ว เช่น ข้อความปฏิเสธ)
    static func short(_ text: String) -> ToolExecutionResult {
        ToolExecutionResult(text: text, isError: false, kind: nil, truncated: false)
    }

    /// สร้างผลลัพธ์ผิดพลาด (จำกัดความยาวให้อัตโนมัติ)
    static func failure(_ kind: ToolErrorKind, _ message: String) -> ToolExecutionResult {
        let limited = ToolOutputLimiter.limit(message)
        return ToolExecutionResult(text: limited.text, isError: true, kind: kind, truncated: limited.truncated)
    }

    /// ข้อความสั้นสำหรับแสดงบนการ์ดในหน้าแชท
    var shortSummary: String {
        let firstLine = text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .first
            .map(String.init) ?? ""
        let trimmed = firstLine.trimmingCharacters(in: .whitespaces)
        if trimmed.count <= 120 { return trimmed }
        return String(trimmed.prefix(120)) + "…"
    }
}

// MARK: - ข้อมูลของ tool ที่ UI ต้องรู้

struct ToolDescriptor: Equatable {
    /// ชื่อที่โมเดลใช้เรียก (ต้องตรงกับ definition เป๊ะ)
    let name: String
    /// ชื่อไทยที่แสดงบนการ์ด/หน้าอนุมัติ
    let thaiLabel: String
    /// คำอธิบายไทยสั้น ๆ ว่าทำอะไร (ใช้ในหน้า Settings + หน้าอนุมัติ)
    let summary: String
    let category: ToolCategory
    /// true = ต้องขออนุมัติทุกครั้งเมื่อเปิดโหมดอนุมัติ (ใช้กับ execute_shell)
    let alwaysRequiresApproval: Bool
}

// MARK: - บริบทที่ส่งให้ tool ตอนทำงาน

/// บริบทที่ engine ส่งให้ tool ทุกตัว (ค่าถูก "แช่แข็ง" ไว้ ณ ตอนเริ่มรัน
/// เพื่อให้ tool ทำงานได้โดยไม่ต้องอ่าน UserDefaults จากหลายเธรด)
struct ToolExecutionContext {

    /// โฟลเดอร์ทำงานเริ่มต้นของ Agent (ค่าเริ่มต้น /var/mobile/AgentWorkspace)
    let workspacePath: String
    /// ผู้ใช้เปิดให้ใช้อินเทอร์เน็ตหรือไม่
    let allowInternet: Bool
    /// ผู้ใช้ตั้งให้ใช้เฉพาะ Wi-Fi หรือไม่
    let wifiOnly: Bool
    /// ตอนนี้เชื่อมต่อผ่าน Wi-Fi อยู่หรือไม่ (มาจาก ConnectivityMonitor)
    let isWiFiConnected: Bool
    /// ขนาดไฟล์ดาวน์โหลดสูงสุดเป็นไบต์
    let maxDownloadBytes: Int64
    /// ผู้ใช้เพิ่งอนุมัติการเรียก tool นี้ไปแล้วหรือไม่ (ใช้กับ path ที่เป็นของระบบ)
    let isApproved: Bool
    /// รายงานความคืบหน้าให้ UI (เช่น "ดาวน์โหลด 42%") — ถูกเรียกจากเธรดใดก็ได้
    let reportProgress: (String) -> Void

    init(workspacePath: String,
         allowInternet: Bool,
         wifiOnly: Bool,
         isWiFiConnected: Bool,
         maxDownloadBytes: Int64,
         isApproved: Bool = false,
         reportProgress: @escaping (String) -> Void = { _ in }) {
        self.workspacePath = workspacePath
        self.allowInternet = allowInternet
        self.wifiOnly = wifiOnly
        self.isWiFiConnected = isWiFiConnected
        self.maxDownloadBytes = maxDownloadBytes
        self.isApproved = isApproved
        self.reportProgress = reportProgress
    }

    /// บริบทเดียวกันแต่ตั้งค่าธงอนุมัติ (ใช้ก่อน/หลังผ่านหน้าอนุมัติ)
    func approved(_ value: Bool) -> ToolExecutionContext {
        ToolExecutionContext(workspacePath: workspacePath,
                             allowInternet: allowInternet,
                             wifiOnly: wifiOnly,
                             isWiFiConnected: isWiFiConnected,
                             maxDownloadBytes: maxDownloadBytes,
                             isApproved: value,
                             reportProgress: reportProgress)
    }
}

// MARK: - สัญญาของ tool

protocol AgentTool {

    /// ข้อมูลที่ UI ใช้แสดง
    var descriptor: ToolDescriptor { get }

    /// สคีมาที่ส่งให้โมเดล (OpenAI function calling)
    var definition: ToolDefinition { get }

    /// ทำงานจริง — ห้าม throw ออกมา ให้คืน ToolExecutionResult.failure แทน
    func execute(arguments: [String: JSONValue], context: ToolExecutionContext) async -> ToolExecutionResult

    /// ข้อความที่แสดงในหน้าขออนุมัติ (เช่น URL + ขนาดไฟล์ของ download_file)
    /// tool ส่วนใหญ่ไม่ต้องใช้ — ค่าเริ่มต้นคืน nil
    func approvalDetail(arguments: [String: JSONValue]) async -> String?

    /// ประเมินความเสี่ยงของคำขอนี้ (ใช้ตัดสินใจว่าต้องเด้งหน้าขออนุมัติหรือไม่)
    /// tool ที่แตะไฟล์/คำสั่ง/เครือข่ายเขียนทับจะ override ตัวนี้
    func assessRisk(arguments: [String: JSONValue], workspace: String) -> RiskAssessment
}

extension AgentTool {

    func approvalDetail(arguments: [String: JSONValue]) async -> String? {
        nil
    }

    func assessRisk(arguments: [String: JSONValue], workspace: String) -> RiskAssessment {
        .safe
    }
}

/// ตัวสร้างผลลัพธ์มาตรฐานที่ใช้ซ้ำในทุก tool
enum ToolResults {

    /// arguments ที่โมเดลส่งมาผิด/ไม่ครบ — บอกสั้น ๆ ให้โมเดลแก้เองแล้วเรียกใหม่
    static func invalidArguments(_ message: String) -> ToolExecutionResult {
        .failure(.invalidArguments, "arguments ไม่ถูกต้อง: \(message)")
    }
}

// MARK: - ช่องทางรายงาน token usage
//
// engine ต้องอัปเดตยอด token ของเซสชัน แต่ TokenUsageTracker เป็น ObservableObject (ใช้ Combine)
// ซึ่งไม่มีบน Linux จึงผูกผ่าน protocol นี้แทน — ทำให้ AgentEngine รัน E2E ได้ทุกแพลตฟอร์ม

protocol UsageRecording: AnyObject {
    func add(_ usage: TokenUsage?)
}

// MARK: - ตัวช่วยแปลง error ของระบบเป็นข้อความไทย

enum ToolErrorMapper {

    /// แปลง error จาก FileManager/URLSession ให้เป็นข้อความที่โมเดลและผู้ใช้อ่านเข้าใจ
    static func describe(_ error: Error, path: String? = nil) -> (kind: ToolErrorKind, message: String) {
        let nsError = error as NSError

        if nsError.domain == NSCocoaErrorDomain {
            switch nsError.code {
            case NSFileNoSuchFileError, NSFileReadNoSuchFileError:
                return (.notFound, "ไม่พบไฟล์หรือโฟลเดอร์: \(path ?? "—")")
            case NSFileReadNoPermissionError, NSFileWriteNoPermissionError:
                return (.permissionDenied,
                        "ไม่มีสิทธิ์เข้าถึง \(path ?? "—") — ถ้าเป็น path ของระบบ ต้องติดตั้งผ่าน TrollStore (entitlements no-sandbox) หรือรันเป็น root ผ่าน palera1n")
            case NSFileWriteFileExistsError:
                return (.failed, "ปลายทางมีอยู่แล้ว: \(path ?? "—")")
            case NSFileReadUnknownError, NSFileWriteUnknownError:
                return (.failed, "อ่าน/เขียนไฟล์ไม่สำเร็จ (\(nsError.localizedDescription))")
            default:
                break
            }
        }

        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut:
                return (.timeout, "คำขอเครือข่ายหมดเวลา (\(Int(NetworkTimeouts.requestSeconds)) วินาที)")
            case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost, .cannotFindHost:
                return (.failed, "เชื่อมต่อเครือข่ายไม่สำเร็จ: \(urlError.localizedDescription)")
            case .cancelled:
                return (.cancelled, "คำขอถูกยกเลิก")
            default:
                return (.failed, "เครือข่ายผิดพลาด: \(urlError.localizedDescription)")
            }
        }

        if error is CancellationError {
            return (.cancelled, "งานถูกยกเลิก")
        }

        return (.failed, error.localizedDescription)
    }
}
