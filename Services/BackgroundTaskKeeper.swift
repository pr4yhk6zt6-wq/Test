//
//  BackgroundTaskKeeper.swift
//  iOS Agent Sandbox
//
//  ขอเวลาทำงานเบื้องหลังจากระบบระหว่างที่ Agent กำลังทำงาน
//  (UIApplication.beginBackgroundTask) เพื่อให้คำขอยังเดินต่อได้แม้ผู้ใช้ปิดแอปลง
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif

@MainActor
final class BackgroundTaskKeeper: ObservableObject {

    @Published private(set) var isActive: Bool = false

    #if canImport(UIKit)
    private var taskIdentifier: UIBackgroundTaskIdentifier = .invalid
    #endif

    /// เวลาที่ระบบยังอนุญาตให้ทำงานเบื้องหลัง (วินาที)
    var remainingTime: TimeInterval {
        #if canImport(UIKit)
        return UIApplication.shared.backgroundTimeRemaining
        #else
        return 0
        #endif
    }

    /// เริ่มขอเวลาทำงานเบื้องหลัง (เรียกซ้ำได้ ไม่เกิด task ซ้ำ)
    func begin(name: String = "Agent กำลังทำงาน") {
        #if canImport(UIKit)
        guard taskIdentifier == .invalid else { return }
        taskIdentifier = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            // หมดเวลา ระบบจะฆ่าแอปถ้าไม่คืน task → คืนทันทีและหยุดงาน
            Task { @MainActor in
                self?.end()
            }
        }
        isActive = taskIdentifier != .invalid
        #endif
    }

    /// คืน task ให้ระบบ
    func end() {
        #if canImport(UIKit)
        guard taskIdentifier != .invalid else { return }
        let identifier = taskIdentifier
        taskIdentifier = .invalid
        isActive = false
        UIApplication.shared.endBackgroundTask(identifier)
        #endif
    }
}
