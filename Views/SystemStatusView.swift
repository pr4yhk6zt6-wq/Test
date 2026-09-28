//
//  SystemStatusView.swift
//  iOS Agent Sandbox
//
//  หน้าสถานะระบบ (เฟส 5): เครือข่าย • สิทธิ์การเข้าถึงไฟล์ • โฟลเดอร์ทำงาน • ข้อเสนอแนะ
//  แสดงผลจริงจาก ConnectivityMonitor / PrivilegeService / SystemAccessChecker
//

import SwiftUI

struct SystemStatusView: View {

    @EnvironmentObject private var settings: AppSettings
    @ObservedObject private var connectivity = ConnectivityMonitor.shared

    @State private var report: PrivilegeReport?
    @State private var isRefreshing = false

    var body: some View {
        List {
            Section(header: Text("เครือข่าย")) {
                HStack(spacing: 10) {
                    Image(systemName: connectivity.symbolName)
                        .foregroundColor(connectivity.isConnected ? .green : .red)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(connectivity.statusText)
                        Text("อนุญาตให้ Agent ใช้อินเทอร์เน็ต: \(settings.allowInternet ? "เปิด" : "ปิด") • เฉพาะ Wi-Fi: \(settings.wifiOnly ? "เปิด" : "ปิด")")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                if settings.allowInternet && settings.wifiOnly && !connectivity.isWiFi {
                    Label("ตอนนี้ไม่ได้ต่อ Wi-Fi → เครื่องมือที่ใช้อินเทอร์เน็ตจะถูกบล็อก", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                if connectivity.isExpensive {
                    Label("เครือข่ายนี้ถูกจำกัดการใช้งาน (hotspot/ประหยัดดาต้า)", systemImage: "speedometer")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Section(header: Text("สิทธิ์การเข้าถึงไฟล์")) {
                if let report = report {
                    HStack {
                        Image(systemName: report.isFullyPrivileged ? "checkmark.shield.fill" : "exclamationmark.shield")
                            .foregroundColor(report.isFullyPrivileged ? .green : .orange)
                        Text(report.summaryText)
                            .font(.footnote)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    ForEach(report.checklist, id: \.title) { item in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: item.isOK ? "checkmark.circle.fill" : "xmark.circle")
                                .foregroundColor(item.isOK ? .green : .secondary)
                                .font(.caption)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title)
                                    .font(.footnote)
                                Text(item.value)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                if let note = item.note {
                                    Text(note)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }

                    if !report.pendingAdvice.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("สิ่งที่ทำได้ต่อ")
                                .font(.footnote.weight(.medium))
                            ForEach(report.pendingAdvice, id: \.self) { advice in
                                Text("• \(advice)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                } else {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("กำลังตรวจสิทธิ์…")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Section(header: Text("โฟลเดอร์ทำงาน")) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(settings.workspacePath)
                        .font(.caption.monospaced())
                        .lineLimit(2)
                    Text("ไฟล์แนบของผู้ใช้: \(settings.uploadsPath)")
                        .font(.caption2.monospaced())
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }

            Section {
                Button {
                    refresh()
                } label: {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text(isRefreshing ? "กำลังตรวจใหม่…" : "ตรวจสิทธิ์ใหม่")
                    }
                    .frame(minHeight: 44)
                }
                .disabled(isRefreshing)
            }
        }
        .listStyle(GroupedListStyle())
        .navigationTitle("สถานะระบบ")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: refresh)
    }

    private func refresh() {
        isRefreshing = true
        PrivilegeService.invalidateCache()
        let workspace = settings.workspacePath
        let preferRoot = settings.preferRootShell
        DispatchQueue.global(qos: .userInitiated).async {
            let fresh = PrivilegeService.probe(workspacePath: workspace, preferRootShell: preferRoot)
            DispatchQueue.main.async {
                report = fresh
                isRefreshing = false
            }
        }
    }
}
