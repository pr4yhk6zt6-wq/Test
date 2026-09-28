//
//  ActivityCenter.swift
//  iOS Agent Sandbox — ดีไซน์ v2 (เฟส 5 ส่วนที่ 3)
//
//  ตัวแปลงเหตุการณ์ของ engine (AgentEvent) ให้เป็น "กิจกรรม" ที่ UI ใหม่แสดงได้
//  - ไม่แก้ AgentEngine เลย: UI ใหม่สมัครรับเหตุการณ์ผ่าน ChatViewModel.activityObserver
//  - เก็บเฉพาะข้อมูลที่จำเป็นต่อการแสดงผล และปิดบังข้อมูลอ่อนไหวก่อนเก็บ
//  - เวลาที่แสดงเป็น "เวลาจริง" จาก startedAt/endedAt เท่านั้น ไม่มีการประมาณ
//

import Foundation
import Combine

/// ระดับรายละเอียดกิจกรรมที่ผู้ใช้เลือก (ตั้งค่า → หน้าจอ)
enum ActivityDetailLevel: String, CaseIterable, Identifiable {
    case concise
    case normal
    case detailed

    var id: String { rawValue }

    var thaiName: String {
        switch self {
        case .concise: return "น้อย"
        case .normal: return "ปกติ"
        case .detailed: return "ละเอียด"
        }
    }

    var explanation: String {
        switch self {
        case .concise: return "เห็นเฉพาะบรรทัดสรุปว่ากำลังทำอะไรอยู่"
        case .normal: return "เห็นขั้นตอนทั้งหมด กดดูรายละเอียดได้เป็นขั้น"
        case .detailed: return "เห็นรายละเอียดของทุกขั้นทันทีโดยไม่ต้องกด"
        }
    }

    static func current(defaults: UserDefaults = .standard) -> ActivityDetailLevel {
        let raw = defaults.string(forKey: SettingsKeys.activityLevel) ?? ""
        return ActivityDetailLevel(rawValue: raw) ?? .normal
    }
}

final class ActivityCenter: ObservableObject {

    static let shared = ActivityCenter()

    // MARK: - สถานะที่ UI อ่าน

    /// กิจกรรมทั้งหมดของงานปัจจุบัน (ไม่เกิน maxEvents รายการ)
    @Published private(set) var events: [ActivityEvent] = []
    @Published private(set) var isRunning: Bool = false
    @Published private(set) var startedAt: Date?
    @Published private(set) var elapsed: TimeInterval = 0
    /// ข้อความบรรทัดเดียวที่แถบสถานะสดแสดง
    @Published private(set) var liveLabel: String = ""
    /// ข้อความแจ้งเตือนล่าสุดจาก engine (แสดงเป็นแบนเนอร์ในแชท)
    @Published private(set) var notice: String?
    /// สรุปหลังจบงาน (ใช้แทนตัวเลขประมาณการทุกชนิด)
    @Published private(set) var finishedSummary: String?
    @Published private(set) var finishedAt: Date?

    // MARK: - ภายใน

    /// ตัวบอกว่ากำลังทำงานอยู่ในห้องไหน (ตั้งค่าโดยหน้าแชท) — ใช้ผูกการแจ้งเตือนกับห้องที่ถูกต้อง
    var roomIDProvider: (() -> UUID?)?

    private var timer: Timer?
    private var engineStatus: String = ""
    private var nextSeq: Int = 1
    private let maxEvents: Int = 120
    private let maxDetailCharacters: Int = 4_000

    deinit {
        timer?.invalidate()
    }

    // MARK: - เริ่ม/จบงาน

    /// เรียกก่อนส่งข้อความใหม่ทุกครั้ง (ล้างไทม์ไลน์ของงานก่อนหน้า)
    func beginRun() {
        events = []
        nextSeq = 1
        engineStatus = ""
        liveLabel = ""
        notice = nil
        finishedSummary = nil
        finishedAt = nil
        startedAt = Date()
        elapsed = 0
        isRunning = true
        startTimer()
    }

    /// ล้างไทม์ไลน์ด้วยมือ (ปุ่ม "ล้างไทม์ไลน์")
    func clear() {
        events = []
        nextSeq = 1
        liveLabel = ""
        notice = nil
        finishedSummary = nil
        finishedAt = nil
        if !isRunning {
            startedAt = nil
            elapsed = 0
        }
    }

    private func startTimer() {
        timer?.invalidate()
        let newTimer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self, let start = self.startedAt else { return }
            self.elapsed = Date().timeIntervalSince(start)
        }
        RunLoop.main.add(newTimer, forMode: .common)
        timer = newTimer
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func beginIfNeeded() {
        if !isRunning {
            beginRun()
        }
    }

    // MARK: - รับเหตุการณ์จาก engine

    func consume(_ event: AgentEvent) {
        switch event {
        case .assistantStarted:
            beginIfNeeded()
            upsertThinking(status: .running)

        case .assistantDelta:
            break

        case .assistantFinished(_, let message):
            let hasAnswer = !(message?.isTextEmpty ?? true)
            closeKind(.thinking,
                      status: hasAnswer ? .succeeded : .skipped,
                      note: hasAnswer ? nil : "รอบนี้มีแต่การเรียกใช้เครื่องมือ")
            refreshLiveLabel()

        case .toolStarted(let invocation):
            beginIfNeeded()
            appendToolStarted(invocation)

        case .toolFinished(let invocation, let result, let duration):
            appendToolFinished(invocation: invocation, result: result, duration: duration)

        case .approvalRequested(let request):
            beginIfNeeded()
            appendPermissionRequest(request)

        case .approvalResolved(let id, let decision, let autoApproved):
            closePermission(id: id, decision: decision, autoApproved: autoApproved)

        case .status(let text):
            engineStatus = text
            refreshLiveLabel()

        case .notice(let text):
            notice = text

        case .usage:
            // ตัวนับโทเคน/ต้นทุนจัดการที่ TokenUsageTracker แล้ว (ไม่นับซ้ำ)
            break

        case .completed(let reason):
            finish(reason: reason)
        }
    }

    // MARK: - สร้าง/ปิดกิจกรรม

    private func upsertThinking(status: ActivityStatus) {
        if let index = events.firstIndex(where: { $0.kind == .thinking && $0.status.isActive }) {
            events[index].status = status
            if status != .running, events[index].endedAt == nil {
                events[index].endedAt = Date()
                events[index].duration = events[index].startedAt.map { Date().timeIntervalSince($0) }
            }
        } else {
            events.append(ActivityEvent(id: "thinking-\(nextSeq)",
                                        seq: takeSeq(),
                                        kind: .thinking,
                                        status: status,
                                        title: ActivityKind.thinking.runningPhraseTH,
                                        detail: nil,
                                        startedAt: Date()))
        }
        refreshLiveLabel()
        DSHaptic.light()
    }

    private func appendToolStarted(_ invocation: ToolInvocation) {
        let kind = ActivityKind.from(toolName: invocation.toolName)
        let maskedArguments = SensitiveMask.maskAndLimit(invocation.argumentsText,
                                                         maxCharacters: maxDetailCharacters)
        let event = ActivityEvent(id: invocation.id,
                                  seq: takeSeq(),
                                  kind: kind,
                                  status: .running,
                                  title: invocation.thaiLabel,
                                  detail: maskedArguments.text,
                                  rawDetail: maskedArguments.maskedCount > 0 ? invocation.argumentsText : nil,
                                  maskedCount: maskedArguments.maskedCount,
                                  startedAt: Date(),
                                  requiresApproval: false,
                                  isDestructive: invocation.risk.level == .destructive,
                                  artifactPath: ActivityCenter.undoPath(invocation: invocation),
                                  note: invocation.risk.level == .normal ? nil : invocation.risk.summaryText)
        events.append(event)
        trimIfNeeded()
        refreshLiveLabel()
        DSHaptic.light()
    }

    private func appendToolFinished(invocation: ToolInvocation,
                                    result: ToolExecutionResult,
                                    duration: TimeInterval) {
        let maskedResult = SensitiveMask.maskAndLimit(result.text, maxCharacters: maxDetailCharacters)
        let failure = result.isError ? firstLine(maskedResult.text) : nil

        if let index = events.firstIndex(where: { $0.id == invocation.id }) {
            events[index].status = result.isError ? .failed : .succeeded
            events[index].endedAt = Date()
            events[index].duration = duration
            events[index].maskedCount += maskedResult.maskedCount
            events[index].detail = mergeDetail(previous: events[index].detail,
                                               result: maskedResult.text,
                                               truncatedByApp: result.truncated)
            if maskedResult.maskedCount > 0 {
                events[index].rawDetail = mergeDetail(previous: events[index].rawDetail,
                                                      result: result.text,
                                                      truncatedByApp: result.truncated)
            }
            events[index].failureMessage = failure
            events[index].artifactNames = artifacts(invocation: invocation)
        } else {
            // ไม่เคยเห็นเหตุการณ์เริ่ม (เช่น กลับมาจากเบื้องหลัง) — สร้างย้อนหลังให้ครบ
            let kind = ActivityKind.from(toolName: invocation.toolName)
            events.append(ActivityEvent(id: invocation.id,
                                        seq: takeSeq(),
                                        kind: kind,
                                        status: result.isError ? .failed : .succeeded,
                                        title: invocation.thaiLabel,
                                        detail: maskedResult.text,
                                        rawDetail: maskedResult.maskedCount > 0 ? result.text : nil,
                                        maskedCount: maskedResult.maskedCount,
                                        startedAt: Date().addingTimeInterval(-duration),
                                        endedAt: Date(),
                                        duration: duration,
                                        isDestructive: invocation.risk.level == .destructive,
                                        failureMessage: failure,
                                        artifactNames: artifacts(invocation: invocation),
                                        artifactPath: ActivityCenter.undoPath(invocation: invocation)))
        }

        trimIfNeeded()
        refreshLiveLabel()
        if result.isError {
            DSHaptic.warning()
            AgentNotifier.shared.notify(kind: .failed,
                                        roomID: roomIDProvider?(),
                                        detail: "\(invocation.thaiLabel) ไม่สำเร็จ — เปิดแอปเพื่อดูสาเหตุและลองใหม่")
        } else {
            DSHaptic.light()
        }
    }

    private func appendPermissionRequest(_ request: ApprovalRequest) {
        let masked = SensitiveMask.maskAndLimit(request.argumentsText, maxCharacters: maxDetailCharacters)
        var detailLines: [String] = []
        if !request.summary.isEmpty { detailLines.append(request.summary) }
        if let extra = request.detail, !extra.isEmpty { detailLines.append(extra) }
        if !masked.text.isEmpty { detailLines.append(masked.text) }

        // ปิดคำขอเดิมที่ยังค้างอยู่ (กรณีผู้ใช้กดปิดหน้าต่าง)
        for index in events.indices where events[index].kind == .permission && events[index].status == .waitingUser {
            events[index].status = .cancelled
            events[index].endedAt = Date()
        }

        events.append(ActivityEvent(id: request.id,
                                    seq: takeSeq(),
                                    kind: .permission,
                                    status: .waitingUser,
                                    title: "ต้องการอนุญาตก่อนทำต่อ",
                                    detail: detailLines.joined(separator: "\n"),
                                    rawDetail: masked.maskedCount > 0 ? request.argumentsText : nil,
                                    maskedCount: masked.maskedCount,
                                    startedAt: Date(),
                                    requiresApproval: true,
                                    isDestructive: request.isDestructive,
                                    note: request.risk.summaryText))
        trimIfNeeded()
        liveLabel = ActivityKind.permission.runningPhraseTH
        DSHaptic.medium()
        AgentNotifier.shared.notify(kind: .needsAnswer,
                                    roomID: roomIDProvider?(),
                                    detail: "Agent รอให้คุณอนุญาตก่อนทำต่อ")
    }

    private func closePermission(id: String, decision: ApprovalDecision, autoApproved: Bool) {
        if let index = events.firstIndex(where: { $0.id == id && $0.kind == .permission }) {
            events[index].status = decision.isAllowed ? .succeeded : .cancelled
            events[index].endedAt = Date()
            events[index].duration = events[index].startedAt.map { Date().timeIntervalSince($0) }
            if autoApproved {
                events[index].note = "อนุญาตอัตโนมัติตามที่ตั้งไว้ในแอป"
            }
        } else if let index = events.lastIndex(where: {
            $0.kind == .permission && $0.status == .waitingUser
        }) {
            events[index].status = decision.isAllowed ? .succeeded : .cancelled
            events[index].endedAt = Date()
        }
        refreshLiveLabel()
    }

    private func closeKind(_ kind: ActivityKind, status: ActivityStatus, note: String?) {
        guard let index = events.lastIndex(where: { $0.kind == kind && $0.status.isActive }) else { return }
        events[index].status = status
        events[index].endedAt = Date()
        events[index].duration = events[index].startedAt.map { Date().timeIntervalSince($0) }
        if let note = note { events[index].note = note }
    }

    private func finish(reason: AgentStopReason) {
        isRunning = false
        stopTimer()
        if let start = startedAt {
            elapsed = Date().timeIntervalSince(start)
        }

        // ปิดกิจกรรมที่ยังค้างอยู่ให้ตรงตามสาเหตุจริง (ห้ามรายงานขั้นที่สำเร็จแล้วว่าล้มเหลว)
        for index in events.indices where events[index].status.isActive {
            if reason == .cancelled {
                events[index].status = .cancelled
            } else if events[index].status == .pending {
                events[index].status = .skipped
                events[index].note = "งานจบก่อนขั้นนี้จะเริ่ม"
            }
            if events[index].endedAt == nil { events[index].endedAt = Date() }
        }

        switch reason {
        case .answered:
            finishedSummary = "ทำเสร็จแล้ว ใช้เวลา \(DSFormat.duration(elapsed))"
            DSHaptic.success()
            AgentNotifier.shared.notify(kind: .finished,
                                        roomID: roomIDProvider?(),
                                        detail: finishedSummary)
        case .cancelled:
            finishedSummary = "ยกเลิกตามที่คุณสั่ง — ผลที่ทำไว้แล้วยังอยู่ครบ"
        case .roundLimitReached:
            finishedSummary = "หยุดเพราะครบเพดานรอบต่อคำสั่ง — พิมพ์บอกต่อได้เลยว่าจะให้ทำอะไร"
            AgentNotifier.shared.notify(kind: .needsAnswer,
                                        roomID: roomIDProvider?(),
                                        detail: "งานยาวเกินเพดานต่อคำสั่ง — เปิดแอปเพื่อสั่งทำต่อ")
        case .failed:
            finishedSummary = "งานนี้ไม่สำเร็จ — ผลที่ทำไว้แล้วยังอยู่ครบ ลองใหม่ได้"
            AgentNotifier.shared.notify(kind: .failed,
                                        roomID: roomIDProvider?(),
                                        detail: "เปิดแอปเพื่อดูสาเหตุของขั้นที่ล้มเหลวและลองใหม่")
        }
        finishedAt = Date()
        liveLabel = ""
    }

    /// เรียกเมื่อพบว่าแอปถูก iOS ระงับงานกลางทาง (กลับมาแล้ว engine ไม่ทำงานต่อ แต่ไทม์ไลน์ยังค้างว่ากำลังทำ)
    /// รายงานตามจริงว่า "ถูกระบบระงับ" ไม่ใช่ "เสร็จ" และไม่ลบข้อมูลที่ทำไว้แล้ว
    func markSystemPaused() {
        guard isRunning else { return }
        stopTimer()
        isRunning = false
        if let start = startedAt {
            elapsed = Date().timeIntervalSince(start)
        }
        let now = Date()
        events.append(ActivityEvent(id: "system-paused-\(takeSeq())",
                                    seq: takeSeq(),
                                    kind: .other,
                                    status: .cancelled,
                                    title: "ระบบหยุดงานชั่วคราว",
                                    detail: "iOS ไม่ให้แอปทำงานเบื้องหลังได้นาน — งานหยุดที่ขั้นล่าสุด ผลที่ทำไว้แล้วยังอยู่ครบ",
                                    startedAt: now,
                                    endedAt: now,
                                    duration: 0,
                                    note: "ใช้ปุ่ม \"ให้ Agent ทำต่อจากจุดนี้\" เพื่อทำงานต่อ"))
        finishedSummary = "ระบบหยุดงานชั่วคราว — ทำต่อจากจุดเดิมได้เลย"
        finishedAt = now
        liveLabel = ""
        DSHaptic.warning()
    }

    // MARK: - ตัวช่วย

    private func takeSeq() -> Int {
        nextSeq += 1
        return nextSeq
    }

    private func mergeDetail(previous: String?, result: String, truncatedByApp: Bool) -> String? {
        var parts: [String] = []
        if let previous = previous, !previous.isEmpty { parts.append(previous) }
        if !result.isEmpty { parts.append(result) }
        if truncatedByApp { parts.append("(ข้อความยาวเกินจึงแสดงไม่ครบ)") }
        let merged = parts.joined(separator: "\n")
        return merged.count > maxDetailCharacters ? String(merged.prefix(maxDetailCharacters)) : merged
    }

    /// path ของไฟล์ที่ "การย้อนกลับ" ต้องใช้: ย้ายไฟล์ใช้ต้นทาง (source) ตัวอื่นใช้ path ปลายทาง
    static func undoPath(invocation: ToolInvocation) -> String? {
        let keys = invocation.toolName == "move_file"
            ? ["source", "path", "file_path", "target"]
            : ["path", "file_path", "target"]
        for key in keys {
            if case .string(let value)? = invocation.arguments[key], !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private func artifacts(invocation: ToolInvocation) -> [String] {
        // ดึงชื่อไฟล์จาก arguments ที่รู้จัก (ไม่เดา: ถ้าไม่มีก็เว้นว่าง)
        let keys = ["path", "file_path", "target", "destination", "to", "from", "source"]
        var names: [String] = []
        for key in keys {
            if case .string(let value)? = invocation.arguments[key], !value.isEmpty {
                let name = (value as NSString).lastPathComponent
                if !name.isEmpty { names.append(name) }
            }
        }
        var seen = Set<String>()
        return names.filter { seen.insert($0).inserted }
    }

    private func trimIfNeeded() {
        if events.count > maxEvents {
            events.removeFirst(events.count - maxEvents)
        }
    }

    private func firstLine(_ text: String) -> String? {
        text.split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
    }

    /// ข้อความบรรทัดเดียวของแถบสถานะสด: ใช้ข้อความจาก engine ก่อน (เป็นความจริงจากแหล่งเดียวกัน)
    /// ถ้าไม่มีจึงใช้ข้อความของกิจกรรมที่กำลังทำอยู่
    private func refreshLiveLabel() {
        if !engineStatus.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            liveLabel = engineStatus
            return
        }
        if let active = events.last(where: { $0.status == .running }) {
            liveLabel = active.kind.runningPhraseTH
        } else if let waiting = events.last(where: { $0.status == .waitingUser }) {
            liveLabel = waiting.kind.runningPhraseTH
        } else if isRunning {
            liveLabel = ActivityKind.thinking.runningPhraseTH
        } else {
            liveLabel = ""
        }
    }
}

// MARK: - ประวัติการเรียกเครื่องมือจากข้อความในห้อง

extension ActivityCenter {

    /// แปลงข้อความผลลัพธ์ของ tool ที่เก็บในประวัติ ให้เป็นการ์ดแบบเดียวกับไทม์ไลน์ (ใช้แสดงย้อนหลัง)
    static func historyEvents(from messages: [ChatMessage]) -> [ActivityEvent] {
        messages
            .filter { $0.role == .tool }
            .map { ActivityEvent.fromToolMessage($0) }
    }
}
