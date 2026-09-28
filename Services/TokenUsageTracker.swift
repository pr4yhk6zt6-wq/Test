//
//  TokenUsageTracker.swift
//  iOS Agent Sandbox
//
//  รวม Token Usage ของทั้งเซสชัน (prompt / completion / total / ค่าใช้จ่าย)
//  หมายเหตุ: เรียกใช้จาก main thread เท่านั้น (เรียกผ่าน MainActor.run เมื่ออยู่ใน Task)
//

import Foundation

final class TokenUsageTracker: ObservableObject, UsageRecording {

    static let shared = TokenUsageTracker()

    @Published private(set) var promptTokens: Int = 0
    @Published private(set) var completionTokens: Int = 0
    @Published private(set) var totalTokens: Int = 0
    @Published private(set) var requestCount: Int = 0
    @Published private(set) var costCredits: Double?

    init() { }

    /// บวก usage ที่ได้จาก OpenRouter เข้ากับยอดรวมของเซสชัน
    func add(_ usage: TokenUsage?) {
        guard let usage = usage, !usage.isEmpty else { return }
        promptTokens += usage.promptTokens
        completionTokens += usage.completionTokens
        totalTokens += usage.totalTokens
        requestCount += 1
        if let cost = usage.cost {
            costCredits = (costCredits ?? 0) + cost
        }
    }

    func reset() {
        promptTokens = 0
        completionTokens = 0
        totalTokens = 0
        requestCount = 0
        costCredits = nil
    }

    var costText: String {
        guard let cost = costCredits else { return "—" }
        return String(format: "$%.6f", cost)
    }

    var hasData: Bool {
        requestCount > 0
    }

    /// ข้อความสั้นสำหรับแถบ Token Usage ในหน้าแชท
    var shortText: String {
        "↑\(promptTokens) ↓\(completionTokens) รวม \(totalTokens)"
    }

    /// ผลรวมแบบ TokenUsage (ใช้ส่งต่อ/บันทึก)
    var totals: TokenUsage {
        TokenUsage(promptTokens: promptTokens,
                   completionTokens: completionTokens,
                   totalTokens: totalTokens,
                   cost: costCredits)
    }
}
