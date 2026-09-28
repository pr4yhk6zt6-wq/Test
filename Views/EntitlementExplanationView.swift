//
//  EntitlementExplanationView.swift
//  iOS Agent Sandbox
//
//  หน้าจออธิบาย entitlements ทั้ง 5 คีย์ที่โปรเจกต์นี้ใช้ (เฟส 3)
//  • แสดงว่าคีย์ไหนพบจริงในไบนารีที่ติดตั้งอยู่ และคีย์ไหนขาด
//  • อธิบายว่าคีย์นั้นเปิดอะไรให้แอป และถ้าไม่มีจะเป็นอย่างไร
//  • ปุ่มบันทึกไฟล์ .entitlements ลงโฟลเดอร์ทำงาน เพื่อเอาไปใช้กับ ldid เองได้
//
//  UI ภาษาไทยทั้งหมด รองรับ Dynamic Type และปุ่มขนาด ≥44pt
//

import SwiftUI

struct EntitlementExplanationView: View {

    /// ผลสแกนไบนารี (nil = ยังไม่ได้ตรวจ)
    let scan: EntitlementScanResult?
    /// โฟลเดอร์ที่ใช้บันทึกไฟล์ .entitlements
    let workspacePath: String

    @Environment(\.presentationMode) private var presentationMode

    @State private var statusMessage: String?
    @State private var isShowingStatus = false

    var body: some View {
        NavigationView {
            List {
                scanSection
                keysSection
                howToUseSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("entitlements")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("ปิด") { presentationMode.wrappedValue.dismiss() }
                        .frame(minHeight: 44)
                }
            }
        }
        .navigationViewStyle(.stack)
        .alert("ผลการบันทึก", isPresented: $isShowingStatus) {
            Button("ตกลง", role: .cancel) { }
        } message: {
            Text(statusMessage ?? "")
        }
    }

    // MARK: - สถานะการตรวจ

    private var scanSection: some View {
        Section {
            if let scan {
                HStack {
                    Image(systemName: scan.hasAllFive ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .foregroundColor(scan.hasAllFive ? .green : .orange)
                    Text(scan.hasAllFive ? "พบ entitlements ครบทั้ง 5 คีย์" : "entitlements ยังไม่ครบ")
                        .font(.footnote)
                }
                .frame(minHeight: 32)

                Text(scan.summaryText)
                    .font(.caption)
                    .foregroundColor(.secondary)

                if let path = scan.binaryPath {
                    HStack(alignment: .top) {
                        Text("ไบนารี")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(path)
                            .font(.system(.caption2, design: .monospaced))
                            .multilineTextAlignment(.trailing)
                    }
                }

                if scan.fileSizeBytes > 0 {
                    HStack {
                        Text("สแกนไป")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(NetworkPolicy.formatBytes(scan.scannedBytes)) จาก \(NetworkPolicy.formatBytes(scan.fileSizeBytes)) • พบข้อความคีย์ \(scan.totalMatches) ครั้ง")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } else {
                Text("ยังไม่ได้ตรวจไบนารี — กลับไปหน้าตั้งค่าแล้วกด \"ตรวจสิทธิ์ใหม่\"")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        } header: {
            Text("สถานะในไบนารีที่ติดตั้งอยู่")
        } footer: {
            Text("การตรวจนี้จะอ่านไฟล์ไบนารีของแอปเองทีละก้อน (ไม่โหลดทั้งไฟล์) เพื่อหาข้อความคีย์ entitlements ที่ ldid ฝังไว้")
        }
    }

    // MARK: - คำอธิบาย 5 คีย์

    private var keysSection: some View {
        Section {
            ForEach(PrivilegePolicy.entitlements, id: \.key) { explanation in
                EntitlementRow(explanation: explanation, isFound: isFound(explanation))
            }
        } header: {
            Text("คำอธิบาย entitlements ทั้ง \(PrivilegePolicy.entitlements.count) คีย์")
        } footer: {
            Text("คีย์ที่มีเครื่องหมายถูกคือคีย์ที่พบในไบนารีนี้ • ค่าที่ต้องเป็น true/false คือค่าที่ไฟล์ entitlements ของโปรเจกต์นี้กำหนดไว้")
        }
    }

    private func isFound(_ explanation: PrivilegePolicy.EntitlementExplanation) -> Bool {
        guard let scan else { return false }
        return scan.foundKeys.contains(explanation.key)
    }

    // MARK: - วิธีใช้

    private var howToUseSection: some View {
        Section {
            Button {
                saveEntitlementsFile()
            } label: {
                Label("บันทึกไฟล์ .entitlements ลงโฟลเดอร์ทำงาน", systemImage: "square.and.arrow.down")
                    .frame(minHeight: 44)
            }

            Text(workspacePath)
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(.secondary)

            Text("ldid -S\"iOSAgentSandbox.entitlements\" Payload/iOSAgentSandbox.app/iOSAgentSandbox")
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(.secondary)
        } header: {
            Text("นำไปใช้กับ ldid")
        } footer: {
            Text("ใช้เมื่อคุณบิลด์เองบน Mac: แตก .ipa → เซ็นไบนารีด้วย ldid กับไฟล์นี้ → บีบกลับเป็น .ipa → ติดตั้งผ่าน TrollStore • " +
                 "ถ้าไม่เซ็น ตัวแอปจะเปิดได้แต่ยังถูก sandbox ทำให้อ่าน /var/mobile ไม่ได้")
        }
    }

    private func saveEntitlementsFile() {
        do {
            let report = try PrivilegeService.writeEntitlementsFile(to: workspacePath)
            statusMessage = "บันทึกแล้ว: \(report.path)\nขนาด \(report.bytesWritten) ไบต์ (\(PrivilegePolicy.entitlements.count) คีย์)"
        } catch {
            statusMessage = error.localizedDescription
        }
        isShowingStatus = true
    }
}

/// หนึ่งแถวของแต่ละคีย์ — กดเพื่อกางดูคำอธิบายเต็ม
private struct EntitlementRow: View {

    let explanation: PrivilegePolicy.EntitlementExplanation
    let isFound: Bool

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() }
            } label: {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: isFound ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(isFound ? .green : .red)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(explanation.thaiName)
                            .font(.footnote.weight(.medium))
                        Text(explanation.key)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    Text("ค่าในไฟล์นี้: \(explanation.expectedValue ? "true" : "false")")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("เปิดอะไรให้แอป")
                        .font(.caption.weight(.semibold))
                    Text(explanation.effect)
                        .font(.caption)

                    Text("ถ้าไม่มีคีย์นี้")
                        .font(.caption.weight(.semibold))
                    Text(explanation.withoutIt)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.leading, 28)
                .padding(.bottom, 4)
            }
        }
        .padding(.vertical, 2)
    }
}
