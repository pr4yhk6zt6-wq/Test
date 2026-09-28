//
//  SettingsView.swift
//  iOS Agent Sandbox
//
//  เฟส 1: ตั้งค่า API Key (Keychain) + Model ID (UserDefaults)
//  + ปุ่มทดสอบการเชื่อมต่อ + ปุ่มโหลดรายการโมเดล
//  + แสดง Token Usage ของเซสชันนี้
//

import SwiftUI

struct SettingsView: View {

    @EnvironmentObject private var settings: AppSettings
    @ObservedObject private var usage: TokenUsageTracker = .shared

    // API Key
    @State private var apiKeyInput: String = ""
    @State private var showDeleteKeyConfirmation: Bool = false

    // โมเดล
    @State private var modelInput: String = ""
    @State private var models: [OpenRouterModel] = []
    @State private var showModelPicker: Bool = false
    @State private var isLoadingModels: Bool = false

    // ทดสอบการเชื่อมต่อ
    @State private var isTesting: Bool = false
    @State private var testResult: ConnectionTestResult?

    // สิทธิ์การเข้าถึง
    @State private var accessReport: SystemAccessReport = SystemAccessChecker.check()

    // แจ้งเตือน
    @State private var alertTitle: String = ""
    @State private var alertMessage: String = ""
    @State private var showAlert: Bool = false

    var body: some View {
        Form {
            apiKeySection
            modelSection
            connectionSection
            usageSection
            accessSection
            aboutSection
        }
        .navigationTitle("ตั้งค่า")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: loadStoredValues)
        .sheet(isPresented: $showModelPicker) {
            ModelPickerView(models: models) {
                showModelPicker = false
            } onSelect: { model in
                modelInput = model.id
                settings.modelID = model.id
                showModelPicker = false
                // เลือกโมเดลแล้ว รันทดสอบการเชื่อมต่อให้อัตโนมัติ
                runConnectionTest()
            }
        }
        .alert(alertTitle, isPresented: $showAlert) {
            Button("ตกลง", role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
        .confirmationDialog("ลบ API Key ออกจากเครื่อง?", isPresented: $showDeleteKeyConfirmation, titleVisibility: .visible) {
            Button("ลบ API Key", role: .destructive) { deleteAPIKey() }
            Button("ยกเลิก", role: .cancel) { }
        } message: {
            Text("Agent จะใช้งานไม่ได้จนกว่าจะใส่ API Key ใหม่")
        }
    }

    // MARK: - Section: API Key

    private var apiKeySection: some View {
        Section {
            SecureField("sk-or-v1-…", text: $apiKeyInput)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 44)

            Button {
                saveAPIKey()
            } label: {
                Label("บันทึก API Key", systemImage: "key.fill")
                    .frame(minHeight: 44)
            }

            if settings.hasAPIKey {
                Button(role: .destructive) {
                    showDeleteKeyConfirmation = true
                } label: {
                    Label("ลบ API Key", systemImage: "trash")
                        .frame(minHeight: 44)
                }
            }

            HStack {
                Text("สถานะ")
                Spacer()
                Text(settings.apiKeyStateText)
                    .foregroundColor(settings.hasAPIKey ? .secondary : .orange)
                    .multilineTextAlignment(.trailing)
            }
            .font(.footnote)

            if let warning = settings.storageWarning, settings.apiKeyState == .inFallback {
                Text("⚠️ Keychain ใช้ไม่ได้ (\(warning)) แอปจึงเก็บ API Key ไว้ใน UserDefaults แบบไม่เข้ารหัส ควรเซ็นแอปใหม่โดยมี entitlements ด้าน Keychain หรือระวังเครื่องที่ใช้ร่วมกัน")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        } header: {
            Text("OpenRouter API Key")
        } footer: {
            Text("เก็บใน Keychain ของเครื่อง • ขอได้ที่ openrouter.ai/keys • ถ้าแอปเซ็นแบบไม่มี entitlement ของ Keychain ระบบจะสลับไปเก็บแบบสำรองอัตโนมัติและแจ้งเตือนที่นี่")
        }
    }

    // MARK: - Section: โมเดล

    private var modelSection: some View {
        Section {
            TextField("provider/model:free", text: $modelInput)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 44)

            Button {
                saveModelID()
            } label: {
                Label("บันทึก Model ID", systemImage: "checkmark.circle")
                    .frame(minHeight: 44)
            }

            Button {
                loadModels()
            } label: {
                HStack {
                    Label("โหลดรายการโมเดล", systemImage: "arrow.down.circle")
                    Spacer()
                    if isLoadingModels {
                        ProgressView()
                    } else if !models.isEmpty {
                        Text("\(models.count)")
                            .foregroundColor(.secondary)
                    }
                }
                .frame(minHeight: 44)
            }
            .disabled(!settings.hasAPIKey || isLoadingModels)

            if settings.modelID.isEmpty == false {
                HStack {
                    Text("โมเดลที่ใช้อยู่")
                    Spacer()
                    Text(settings.modelID)
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.trailing)
                }
            }
        } header: {
            Text("โมเดล")
        } footer: {
            Text("รูปแบบ provider/model เช่น deepseek/deepseek-chat-v3-0324:free หรือ meta-llama/llama-3.3-70b-instruct:free • โมเดลที่ใช้ Agent ต้องรองรับ tool calling")
        }
    }

    // MARK: - Section: ทดสอบการเชื่อมต่อ

    private var connectionSection: some View {
        Section {
            Button {
                runConnectionTest()
            } label: {
                HStack {
                    Label("ทดสอบการเชื่อมต่อ", systemImage: "antenna.radiowaves.left.and.right")
                    Spacer()
                    if isTesting { ProgressView() }
                }
                .frame(minHeight: 44)
            }
            .disabled(isTesting || !settings.hasAPIKey)

            if let result = testResult {
                VStack(alignment: .leading, spacing: 6) {
                    Label("เชื่อมต่อสำเร็จ (\(String(format: "%.2f", result.latency)) วินาที)",
                          systemImage: "checkmark.seal.fill")
                        .foregroundColor(.green)
                        .font(.footnote.weight(.semibold))

                    Text("โมเดล: \(result.modelID)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)

                    Text(result.toolCallDetected
                         ? "รองรับ tool calling: ใช่ (โมเดลเรียกฟังก์ชัน ping ได้จริง)"
                         : "รองรับ tool calling: ไม่แน่ชัด (โมเดลไม่ได้เรียกฟังก์ชัน ping – แนะนำเปลี่ยนโมเดล)")
                        .font(.caption)
                        .foregroundColor(result.toolCallDetected ? .secondary : .orange)

                    if let preview = result.replyPreview {
                        Text("ตอบกลับ: \(preview)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    if let usage = result.usage {
                        Text("โทเคนที่ใช้ทดสอบ: \(usage.shortText)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
        } header: {
            Text("ทดสอบการเชื่อมต่อ")
        } footer: {
            Text("จะยิงคำขอสั้น ๆ + tool ตัวอย่าง 1 ตัวไปยังโมเดลที่เลือก เพื่อยืนยันว่า API Key ใช้ได้และโมเดลรองรับ tool calling (401 = คีย์ผิด, 404 = โมเดลไม่รองรับ/ไม่มี endpoint)")
        }
    }

    // MARK: - Section: Token Usage

    private var usageSection: some View {
        Section {
            usageRow(title: "Prompt", value: "\(usage.promptTokens)")
            usageRow(title: "Completion", value: "\(usage.completionTokens)")
            usageRow(title: "Total", value: "\(usage.totalTokens)")
            usageRow(title: "จำนวนคำขอ", value: "\(usage.requestCount)")
            usageRow(title: "ค่าใช้จ่ายสะสม", value: usage.costText)
            Button(role: .destructive) {
                usage.reset()
            } label: {
                Label("รีเซ็ตตัวนับโทเคน", systemImage: "arrow.counterclockwise")
                    .frame(minHeight: 44)
            }
            .disabled(!usage.hasData)
        } header: {
            Text("Token Usage (เซสชันนี้)")
        } footer: {
            Text("นับรวมทุกคำขอที่แอปส่งไปในเซสชันนี้ รวมถึงการทดสอบการเชื่อมต่อ • จะรีเซ็ตเมื่อปิดแอป")
        }
    }

    private func usageRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .font(.body.monospacedDigit())
                .foregroundColor(.secondary)
        }
        .frame(minHeight: 32)
    }

    // MARK: - Section: สิทธิ์การเข้าถึง

    private var accessSection: some View {
        Section {
            HStack {
                Text("ผู้ใช้ที่รัน")
                Spacer()
                Text(accessReport.privilegeText)
                    .foregroundColor(.secondary)
            }
            .font(.footnote)
            .frame(minHeight: 32)

            accessRow(path: "/var/mobile", ok: accessReport.isVarMobileReadable)
            accessRow(path: "/var/containers", ok: accessReport.isVarContainersReadable)
            accessRow(path: "/private/var", ok: accessReport.isPrivateVarReadable)
            accessRow(path: "/var/jb", ok: accessReport.isVarJailbreakReadable)

            if !accessReport.jailbreakMarkers.isEmpty {
                Text("พบร่องรอย: \(accessReport.jailbreakMarkers.joined(separator: ", "))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Button {
                accessReport = SystemAccessChecker.check()
            } label: {
                Label("ตรวจสอบสิทธิ์ใหม่", systemImage: "arrow.clockwise")
                    .frame(minHeight: 44)
            }
        } header: {
            Text("สิทธิ์การเข้าถึงไฟล์")
        } footer: {
            Text("ถ้า /var/mobile อ่านไม่ได้ แปลว่าแอปยังถูก sandbox อยู่ ต้องติดตั้งผ่าน TrollStore (มี entitlements no-sandbox) หรือเจลเบรคด้วย palera1n • การอ่านไฟล์ได้จริงจะเริ่มใช้ในเฟส 3")
        }
    }

    private func accessRow(path: String, ok: Bool) -> some View {
        HStack {
            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(ok ? .green : .red)
            Text(path)
                .font(.system(.footnote, design: .monospaced))
            Spacer()
            Text(ok ? "อ่านได้" : "อ่านไม่ได้")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(minHeight: 32)
    }

    // MARK: - Section: เกี่ยวกับ

    private var aboutSection: some View {
        Section {
            HStack {
                Text("เวอร์ชัน")
                Spacer()
                Text(appVersionText)
                    .foregroundColor(.secondary)
            }
            .font(.footnote)
            HStack {
                Text("Base URL")
                Spacer()
                Text(OpenRouterService.baseURLString)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            HStack {
                Text("เฟสที่ทำเสร็จ")
                Spacer()
                Text("1 – Settings + OpenRouterService")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        } header: {
            Text("เกี่ยวกับแอป")
        } footer: {
            Text("Phase 1: ตั้งค่า + บริการ OpenRouter (streaming, tool_calls delta, retry/error handling, token usage)")
        }
    }

    private var appVersionText: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    // MARK: - Actions

    private func loadStoredValues() {
        modelInput = settings.modelID
        if let stored = try? KeychainHelper.shared.string(for: .openRouterAPIKey) {
            apiKeyInput = stored
        } else {
            apiKeyInput = ""
        }
        settings.refreshAPIKeyState()
        accessReport = SystemAccessChecker.check()
    }

    private func saveAPIKey() {
        let trimmed = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            show(title: "ยังไม่ได้กรอก API Key", message: "กรอก API Key ของ OpenRouter ก่อนกดบันทึก (ขอได้ที่ openrouter.ai/keys)")
            return
        }
        do {
            try settings.saveAPIKey(trimmed)
            show(title: "บันทึกแล้ว", message: settings.apiKeyStateText)
        } catch {
            show(title: "บันทึก API Key ไม่สำเร็จ", message: error.localizedDescription)
        }
    }

    private func deleteAPIKey() {
        do {
            try settings.deleteAPIKey()
            apiKeyInput = ""
            testResult = nil
            show(title: "ลบ API Key แล้ว", message: "ใส่คีย์ใหม่ได้ทุกเมื่อ")
        } catch {
            show(title: "ลบ API Key ไม่สำเร็จ", message: error.localizedDescription)
        }
    }

    private func saveModelID() {
        let trimmed = modelInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            show(title: "ยังไม่ได้ระบุโมเดล", message: "กรอกรูปแบบ provider/model เช่น deepseek/deepseek-chat-v3-0324:free")
            return
        }
        guard trimmed.contains("/") else {
            show(title: "รูปแบบ Model ID ไม่ถูกต้อง", message: "Model ID ของ OpenRouter ต้องมีเครื่องหมาย / คั่น เช่น provider/model:free")
            return
        }
        settings.modelID = trimmed
        modelInput = trimmed
        show(title: "บันทึกโมเดลแล้ว", message: trimmed)
    }

    private func loadModels() {
        guard let apiKey = try? KeychainHelper.shared.string(for: .openRouterAPIKey), !apiKey.isEmpty else {
            show(title: "ยังไม่มี API Key", message: "บันทึก API Key ก่อนจึงจะโหลดรายการโมเดลได้")
            return
        }
        isLoadingModels = true
        Task {
            do {
                let loaded = try await OpenRouterService.fetchModels(apiKey: apiKey)
                models = loaded
                isLoadingModels = false
                showModelPicker = true
            } catch {
                isLoadingModels = false
                show(title: "โหลดรายการโมเดลไม่สำเร็จ", message: error.localizedDescription)
            }
        }
    }

    private func runConnectionTest() {
        guard let apiKey = try? KeychainHelper.shared.string(for: .openRouterAPIKey), !apiKey.isEmpty else {
            show(title: "ยังไม่มี API Key", message: "บันทึก API Key ก่อนทดสอบการเชื่อมต่อ")
            return
        }
        let model = modelInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? settings.modelID
            : modelInput.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !model.isEmpty else {
            show(title: "ยังไม่ได้ระบุโมเดล", message: "กรอก Model ID หรือกด \"โหลดรายการโมเดล\" เพื่อเลือกก่อนทดสอบ")
            return
        }

        isTesting = true
        testResult = nil
        Task {
            do {
                let result = try await OpenRouterService.testConnection(modelID: model, apiKey: apiKey)
                testResult = result
                usage.add(result.usage)
                isTesting = false
            } catch {
                isTesting = false
                let message = error.localizedDescription
                show(title: "ทดสอบการเชื่อมต่อไม่สำเร็จ", message: message)
            }
        }
    }

    private func show(title: String, message: String) {
        alertTitle = title
        alertMessage = message
        showAlert = true
    }
}
