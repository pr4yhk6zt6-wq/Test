//
//  ConnectivityMonitor.swift
//  iOS Agent Sandbox
//
//  เฝ้าดูสถานะเครือข่ายด้วย NWPathMonitor (iOS 12+ ใช้ได้บน iOS 15 แน่นอน)
//  ใช้กับตัวเลือก "ใช้เฉพาะ Wi-Fi" และแสดงสถานะบนหน้าตั้งค่า/หน้าแชท
//
//  หมายเหตุ: ไฟล์นี้ใช้ Network framework จึงรันได้เฉพาะบน iOS/macOS
//  ส่วนตรรกะการตัดสินใจอยู่ใน NetworkPolicy (ทดสอบได้บน Linux)
//

import Foundation
import Network

final class ConnectivityMonitor: ObservableObject {

    static let shared = ConnectivityMonitor()

    /// มีการเชื่อมต่อเครือข่ายอยู่หรือไม่ (Wi-Fi หรือเซลลูลาร์)
    @Published private(set) var isConnected: Bool = true
    /// เชื่อมต่อผ่าน Wi-Fi อยู่หรือไม่ (ใช้กับตัวเลือก "ใช้เฉพาะ Wi-Fi")
    @Published private(set) var isWiFi: Bool = false
    /// เชื่อมต่อผ่านเซลลูลาร์อยู่หรือไม่
    @Published private(set) var isCellular: Bool = false
    /// true = ถูกดักจับด้วยแคปทีฟพอร์ทัล (ต้องล็อกอินผ่านหน้าเว็บ)
    @Published private(set) var isExpensive: Bool = false

    private let monitor: NWPathMonitor
    private let queue = DispatchQueue(label: "com.example.iosagentsandbox.connectivity")

    private init() {
        monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let connected = path.status == .satisfied
            let wifi = path.usesInterfaceType(.wifi)
            let cellular = path.usesInterfaceType(.cellular)
            let expensive = path.isExpensive

            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isConnected = connected
                self.isWiFi = connected && wifi
                self.isCellular = connected && cellular
                self.isExpensive = expensive
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }

    /// ข้อความสถานะภาษาไทยสำหรับแสดงบนหน้าจอ
    var statusText: String {
        if !isConnected {
            return "ไม่ได้เชื่อมต่อเครือข่าย"
        }
        if isWiFi {
            return isExpensive ? "Wi-Fi (ถูกจำกัดการใช้งาน)" : "Wi-Fi"
        }
        if isCellular {
            return "เครือข่ายมือถือ (เซลลูลาร์)"
        }
        return "เชื่อมต่ออยู่ (ไม่ทราบชนิด)"
    }

    /// ไอคอนที่เหมาะกับสถานะปัจจุบัน
    var symbolName: String {
        if !isConnected { return "wifi.slash" }
        if isWiFi { return "wifi" }
        if isCellular { return "antenna.radiowaves.left.and.right" }
        return "network"
    }
}
