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
    /// ข้อความระบุตัวคีย์ที่ใช้อยู่จริง (ไม่เปิดเผยคีย์เต็ม)
    @State private var keyDiagnosticsText: String = "(ยังไม่มีคีย์)"
    /// คำเตือนเมื่อพบคีย์เก่าค้างในที่เก็บสำรองแล้วล้างให้
    @State private var staleFallbackNotice: String?

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
    /// ผลตรวจสิทธิ์แบบละเอียดของเฟส 3 (persona/root, entitlements, shell ที่ใช้จริง)
    @State private var privilegeReport: PrivilegeReport?
    @State private var showEntitlementSheet = false

    // เฟส 2 — สถานะการเชื่อมต่อเครือข่าย (ใช้กับตัวเลือก "ใช้เฉพาะ Wi-Fi")
    @ObservedObject private var connectivity = ConnectivityMonitor.shared
    @ObservedObject private var notifier: AgentNotifier = .shared

    // แจ้งเตือน
    @AppStorage(SettingsKeys.appearance) private var appearanceRawValue: String = AppAppearance.system.rawValue
    @AppStorage(SettingsKeys.chatFontScale) private var chatFontScale: Double = 1.0
    @AppStorage(SettingsKeys.hasCompletedOnboarding) private var hasCompletedOnboarding: Bool = false
    @State private var showsOnboarding: Bool = false

    @State private var alertTitle: String = ""
    @State private var alertMessage: String = ""
    @State private var showAlert: Bool = false

    var body: some View {
        Form {
            apiKeySection
            modelSection
            agentSection
            voiceSection
            connectionSection
            usageSection
            toolsSection
            attachmentSection
            appearanceSection
            screenSection
            notificationSection
            accessSection
            privilegeSection
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
        .sheet(isPresented: $showsOnboarding) {
            OnboardingView(onFinish: {
                hasCompletedOnboarding = true
                showsOnboarding = false
            })
        }
        .sheet(isPresented: $showEntitlementSheet) {
            EntitlementExplanationView(scan: privilegeReport?.entitlements,
                                       workspacePath: settings.workspacePath)
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

            HStack(alignment: .firstTextBaseline) {
                Text("คีย์ที่ใช้อยู่")
                Spacer(minLength: 8)
                Text(keyDiagnosticsText)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.trailing)
            }
            .font(.footnote)

            Button {
                refreshKeyDiagnostics()
            } label: {
                Label("ตรวจคีย์ที่บันทึกไว้ใหม่", systemImage: "arrow.clockwise")
                    .frame(minHeight: 44)
            }
            .font(.footnote)

            if let notice = staleFallbackNotice {
                Text(notice)
                    .font(.caption)
                    .foregroundColor(.orange)
            }

            if let warning = settings.storageWarning, settings.apiKeyState == .inFallback {
                Text("⚠️ Keychain ใช้ไม่ได้ (\(warning)) แอปจึงเก็บ API Key ไว้ใน UserDefaults แบบไม่เข้ารหัส ควรเซ็นแอปใหม่โดยมี entitlements ด้าน Keychain หรือระวังเครื่องที่ใช้ร่วมกัน")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        } header: {
            Text("OpenRouter API Key")
        } footer: {
            Text("เก็บใน Keychain ของเครื่อง • ขอได้ที่ openrouter.ai/keys • " +
                 "แอปจะตัดช่องว่าง/อักขระล่องหนที่ติดมากับการคัดลอกให้อัตโนมัติ และถ้าพบคีย์เก่าค้างอยู่จะล้างทิ้งให้ " +
                 "(คีย์ใหม่จะถูกใช้เสมอ) • ถ้า Keychain ใช้ไม่ได้ ระบบจะเก็บแบบสำรองและแจ้งเตือนที่นี่")
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

    // MARK: - Section: Agent (เฟส 2)

    private var agentSection: some View {
        Section {
            Toggle(isOn: $settings.requireApproval) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("ขออนุมัติก่อนทำสิ่งที่เปลี่ยนเครื่อง")
                    Text("ถามก่อนรันคำสั่ง shell ทุกครั้ง และก่อนเขียนทับไฟล์ที่มีอยู่แล้ว")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .frame(minHeight: 44)

            Toggle(isOn: $settings.allowInternet) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("อนุญาตให้ใช้ internet")
                    Text("ให้ Agent เรียก HTTP, ค้นหาเว็บ, ดึงหน้าเว็บ และดาวน์โหลดไฟล์")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .frame(minHeight: 44)

            Toggle(isOn: $settings.wifiOnly) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("ใช้เฉพาะ Wi-Fi")
                    Text("บล็อกการใช้เครือข่ายเมื่อต่อผ่านเซลลูลาร์ (กันดาต้าหมด)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .frame(minHeight: 44)

            HStack {
                Label("เครือข่ายตอนนี้", systemImage: connectivity.symbolName)
                    .font(.footnote)
                Spacer()
                Text(connectivity.statusText)
                    .font(.caption)
                    .foregroundColor(settings.wifiOnly && !connectivity.isWiFi ? .orange : .secondary)
            }
            .frame(minHeight: 32)

            Stepper(value: $settings.maxDownloadMegabytes, in: 10...2_000, step: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("ขนาดดาวน์โหลดสูงสุด: \(settings.maxDownloadMegabytes) MB")
                    Text("ถ้าไฟล์ใหญ่กว่านี้ Agent จะไม่ดาวน์โหลด (ตรวจจาก Content-Length ก่อน)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .frame(minHeight: 44)

            Picker(selection: $settings.contextLengthTokens) {
                Text("8K").tag(8_192)
                Text("16K").tag(16_384)
                Text("32K (ค่าเริ่มต้น)").tag(32_768)
                Text("64K").tag(65_536)
                Text("128K").tag(131_072)
                Text("200K").tag(200_000)
            } label: {
                Text("ขอบเขต context")
            }
            .frame(minHeight: 44)
        } header: {
            Text("Agent")
        } footer: {
            Text("Agent ทำงานเป็นรอบ (คิด → เรียก tool → อ่านผล) สูงสุด \(AgentEngine.maximumToolRounds) รอบต่อหนึ่งคำสั่ง • " +
                 "เมื่อบทสนทนาใช้เกิน 80% ของขอบเขต context ระบบจะตัดผลลัพธ์ tool ที่เก่าที่สุดออกก่อน เพื่อให้คุยต่อได้ • " +
                 "โฟลเดอร์ทำงานของ Agent: \(settings.workspacePath)")
        }
    }

    // MARK: - Section: โหมดเสียง

    private var voiceSection: some View {
        Section {
            Toggle("โหมดเสียง (พูดแทนพิมพ์)", isOn: $settings.voiceInputEnabled)
            Text("เปิดแล้วจะมีปุ่มไมโครโฟนในช่องพิมพ์ — คำพูดถูกถอดเป็นข้อความและรอให้คุณตรวจก่อนส่งเสมอ")
                .font(.footnote)
                .foregroundColor(.secondary)
            Text("เสียงถูกใช้เฉพาะตอนคุณกดปุ่มพูด และแอปไม่เก็บไฟล์เสียงไว้ในเครื่อง ถ้าเครื่องถอดเสียงในตัวไม่ได้ ระบบจะบอกก่อนว่าเสียงจะถูกส่งไปประมวลผลออนไลน์")
                .font(.footnote)
                .foregroundColor(.secondary)
        } header: {
            Text("โหมดเสียง")
        } footer: {
            Text("ปิดไว้เป็นค่าเริ่มต้น เพราะเป็นสิทธิ์ของไมโครโฟน — ปิดคืนได้ทุกเมื่อ")
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

    // MARK: - Section: เครื่องมือของ Agent (เฟส 6)

    private var toolsSection: some View {
        Section {
            NavigationLink {
                toolsInventoryView
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("เครื่องมือที่ Agent ใช้ได้")
                    Text("\(ToolRegistry.makeDefault().tools.count) รายการ — แตะเพื่อดูทั้งหมด")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(minHeight: 44)
            }

            HStack {
                Text("เพดานบริบทที่ตั้งไว้")
                Spacer()
                Text(verbatim: NumberFormatter.localizedString(from: NSNumber(value: settings.contextLengthTokens),
                                                               number: .decimal) + " โทเคน")
                    .foregroundColor(.secondary)
            }
            .font(.footnote)
        } header: {
            Text("ความสามารถของ Agent")
        } footer: {
            Text("นับรวมเครื่องมือจัดการไฟล์ (คัดลอก/ย้าย/ลบ/สร้างโฟลเดอร์) และการค้นหาข้อความในไฟล์ • การลบไฟล์จะถามอนุมัติทุกครั้ง")
        }
    }

    private var toolsInventoryView: some View {
        List {
            Section {
                ForEach(ToolRegistry.makeDefault().tools, id: \.descriptor.name) { tool in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(tool.descriptor.name)
                                .font(.system(.footnote, design: .monospaced))
                            Spacer(minLength: 0)
                            Text(tool.descriptor.category.thaiName)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        Text(tool.descriptor.thaiLabel)
                            .font(.caption)
                        Text(tool.descriptor.summary)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(minHeight: 44)
                }
            } footer: {
                Text("Agent จะเลือกใช้เครื่องมือเองตามคำสั่งของคุณ และจะขออนุมัติก่อนทำสิ่งที่เปลี่ยนเครื่อง (เขียนทับ/ลบ/รันคำสั่ง)")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("เครื่องมือของ Agent")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Section: ไฟล์แนบ (เฟส 5)

    private var attachmentSection: some View {
        Section {
            Picker(selection: $settings.visionOverrideRaw) {
                ForEach(VisionOverride.allCases, id: \.rawValue) { option in
                    Text(option.thaiName).tag(option.rawValue)
                }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("ส่งรูปให้โมเดล")
                    Text(VisionSupport.explanation(modelID: settings.modelID,
                                                   override: settings.visionOverride))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(minHeight: 44)

            VStack(alignment: .leading, spacing: 4) {
                Text("โฟลเดอร์ไฟล์แนบ")
                    .font(.footnote)
                Text(settings.uploadsPath)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                Text("ไฟล์ที่แนบจะถูกคัดลอกเข้าโฟลเดอร์นี้ เพื่อให้ Agent เปิดอ่านเองได้ด้วย tool")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            NavigationLink {
                SystemStatusView()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: ConnectivityMonitor.shared.symbolName)
                        .foregroundColor(ConnectivityMonitor.shared.isConnected ? .green : .red)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("สถานะระบบ (เครือข่าย/สิทธิ์)")
                        Text(ConnectivityMonitor.shared.statusText)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(minHeight: 44)
            }
        } header: {
            Text("ไฟล์แนบและระบบ")
        } footer: {
            Text("ไฟล์ข้อความเล็กกว่า 20 KB ถูกฝังเนื้อหาไปกับข้อความ • รูปถูกย่อให้ด้านยาวไม่เกิน 1024 px (JPEG 0.7) ก่อนส่ง")
        }
    }

    // MARK: - Section: รูปลักษณ์ (เฟส 5)

    /// ส่วน "การแจ้งเตือน" — ขออนุญาตจาก iOS เฉพาะเมื่อผู้ใช้เปิดสวิตช์เอง (เฟส 5 ส่วนที่ 6)
    private var notificationSection: some View {
        Section {
            Toggle("แจ้งเตือนเมื่องานเสร็จหรือต้องตอบ", isOn: Binding(
                get: { notifier.isEnabled },
                set: { newValue in notifier.setEnabled(newValue) }
            ))
            .frame(minHeight: 44)

            Text(notifier.statusExplanation)
                .font(.caption)
                .foregroundColor(.secondary)

            NavigationLink(destination: AgentCapabilitiesScreen()) {
                Label("เครื่องมือและบริการของ Agent", systemImage: "wrench.and.screwdriver")
                    .frame(minHeight: 44)
            }
        } header: {
            Text("การแจ้งเตือนและความสามารถ")
        } footer: {
            Text("แจ้งเตือนของแอปนี้ไม่มีปุ่มอนุมัติ และไม่แสดงรายละเอียดงานบนหน้าจอล็อก — ต้องเปิดแอปเพื่อดูบริบทให้ครบก่อนตัดสินใจ")
        }
    }

    /// ส่วน "หน้าจอ" — สวิตช์ระหว่างหน้าจอใหม่/เดิม และระดับรายละเอียดกิจกรรม (ดีไซน์ v2)
    private var screenSection: some View {
        Section {
            Toggle("ใช้หน้าจอดีไซน์ใหม่", isOn: $settings.useNewChatUI)
                .frame(minHeight: 44)

            VStack(alignment: .leading, spacing: 6) {
                Picker("ระดับรายละเอียดกิจกรรม", selection: $settings.activityLevelRaw) {
                    ForEach(ActivityDetailLevel.allCases) { level in
                        Text(level.thaiName).tag(level.rawValue)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .frame(minHeight: 44)

                Text(settings.activityLevel.explanation)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(minHeight: 44)

            Text("หน้าจอใหม่แสดงไทม์ไลน์ว่า Agent ทำอะไรบ้าง โดยไม่เปลี่ยนข้อมูลหรือสิทธิ์ใด ๆ — ปิดสวิตช์นี้เพื่อกลับไปใช้หน้าจอเดิมได้ทุกเมื่อ")
                .font(.caption)
                .foregroundColor(.secondary)
        } header: {
            Text("หน้าจอ")
        } footer: {
            Text("ระดับรายละเอียดเปลี่ยนแค่สิ่งที่เห็นบนจอ ไม่ได้เปลี่ยนข้อมูลที่ระบบเก็บหรือส่งให้โมเดล")
        }
    }

    private var appearanceSection: some View {
        Section {
            Picker("ธีม", selection: $appearanceRawValue) {
                ForEach(AppAppearance.allCases) { appearance in
                    Text(appearance.title).tag(appearance.rawValue)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            .frame(minHeight: 44)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("ขนาดตัวอักษรในแชท")
                    Spacer()
                    Text(String(format: "%.0f%%", chatFontScale * 100))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Slider(value: $chatFontScale, in: 0.85...1.45, step: 0.05)
                    .accessibilityLabel("ขนาดตัวอักษรในแชท")
            }
            .frame(minHeight: 44)

            Button {
                showsOnboarding = true
            } label: {
                Label("ดูคำแนะนำการใช้งานอีกครั้ง", systemImage: "questionmark.circle")
                    .frame(minHeight: 44)
            }
        } header: {
            Text("รูปลักษณ์และการใช้งาน")
        }
    }

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
            Text("ถ้า /var/mobile อ่านไม่ได้ แปลว่าแอปยังถูก sandbox อยู่ ต้องติดตั้งผ่าน TrollStore (มี entitlements no-sandbox) หรือเจลเบรคด้วย palera1n • ถ้าอ่านได้ tools ฝั่งไฟล์และ shell ของ Agent จะทำงานเต็มรูปแบบ (เฟส 2)")
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

    // MARK: - Section: สิทธิ์ของแอป (เฟส 3)

    private var privilegeSection: some View {
        Section {
            if let report = privilegeReport {
                ForEach(report.checklist, id: \.title) { item in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: item.isOK ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                            .foregroundColor(item.isOK ? .green : .orange)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .font(.footnote)
                            Text(item.value)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundColor(.secondary)
                            if let note = item.note {
                                Text(note)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: 44)
                }

                Toggle(isOn: rootShellBinding) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("ลองรันคำสั่งเป็น root")
                        Text("สลับ persona (TrollStore) ให้ execute_shell รันเป็น root — ถ้าทำไม่ได้จะถอยไปรันแบบผู้ใช้ปัจจุบันโดยอัตโนมัติ")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(minHeight: 44)

                ForEach(report.pendingAdvice, id: \.self) { advice in
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "lightbulb")
                            .font(.caption2)
                            .foregroundColor(.yellow)
                        Text(advice)
                            .font(.caption)
                    }
                }

                Button {
                    showEntitlementSheet = true
                } label: {
                    Label("คำอธิบาย entitlements ทั้ง \(PrivilegePolicy.entitlements.count) คีย์", systemImage: "lock.shield")
                        .frame(minHeight: 44)
                }

                Button {
                    refreshPrivileges()
                } label: {
                    Label("ตรวจสิทธิ์ใหม่", systemImage: "arrow.clockwise")
                        .frame(minHeight: 44)
                }
            } else {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("กำลังตรวจสิทธิ์และสแกน entitlements…")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                .frame(minHeight: 44)
            }
        } header: {
            Text("สิทธิ์ของแอป (เฟส 3)")
        } footer: {
            Text("ตรวจจากของจริงทุกครั้งที่กด: uid ที่รัน, shell ที่ใช้, การอ่าน/เขียน /var/mobile, ฟังก์ชัน persona ของ TrollStore " +
                 "และ entitlements ที่ฝังในไบนารี • ผู้ใช้ที่ยังไม่ได้รับสิทธิ์จะเห็นคำแนะนำให้ติดตั้งผ่าน TrollStore/palera1n")
        }
    }

    /// สวิตช์ "ลองรันเป็น root" — เปลี่ยนค่าแล้วตรวจสิทธิ์ใหม่ทันที
    private var rootShellBinding: Binding<Bool> {
        Binding(get: { settings.preferRootShell },
                set: { newValue in
                    settings.preferRootShell = newValue
                    refreshPrivileges()
                })
    }

    private func refreshPrivileges() {
        PrivilegeService.invalidateCache()
        privilegeReport = PrivilegeService.probe(workspacePath: settings.workspacePath,
                                                 preferRootShell: settings.preferRootShell)
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
                Text("1 – 5 (ไฟล์แนบ + หลายห้องสนทนา)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        } header: {
            Text("เกี่ยวกับแอป")
        } footer: {
            Text("Agent ทำงานจริงบนเครื่อง: tools 9 ตัว (อ่าน/เขียนไฟล์, ดูโฟลเดอร์, ค้นหาไฟล์, รันคำสั่ง shell, HTTP, ดาวน์โหลด, ค้นหาเว็บ, ดึงหน้าเว็บ) " +
                 "โหมดอนุมัติทีละครั้ง เพดานเวลา 30 วินาที ผลลัพธ์จำกัด 10,000 ตัวอักษร และการตัด context อัตโนมัติ • " +
                 "เฟส 5 เพิ่มไฟล์แนบ (รูป/ไฟล์/กล้อง/คลิปบอร์ด), หลายห้องสนทนา, ส่งออก .md/.json, แก้ไฟล์ในแอป และคำแนะนำการใช้งาน")
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
        refreshKeyDiagnostics()
        accessReport = SystemAccessChecker.check()
        refreshPrivileges()
    }

    /// อัปเดตข้อความระบุตัวคีย์ + คำเตือนกรณีเพิ่งล้างคีย์เก่าที่ค้างอยู่
    private func refreshKeyDiagnostics() {
        let diagnostics = KeychainHelper.shared.diagnostics(for: .openRouterAPIKey)
        keyDiagnosticsText = diagnostics.fingerprint
        if diagnostics.purgedStaleFallback {
            staleFallbackNotice = "พบคีย์เก่าค้างอยู่ในที่เก็บสำรอง และล้างออกให้แล้ว — " +
                "นี่คือสาเหตุที่คีย์ใหม่ไม่ถูกนำไปใช้ ตอนนี้ระบบใช้คีย์ใน \(diagnostics.storageText) แล้ว"
        } else {
            staleFallbackNotice = nil
        }
    }

    private func saveAPIKey() {
        let cleaned = APIKeySanitizer.sanitize(apiKeyInput)
        guard !cleaned.cleaned.isEmpty else {
            show(title: "ยังไม่ได้กรอก API Key", message: "กรอก API Key ของ OpenRouter ก่อนกดบันทึก (ขอได้ที่ openrouter.ai/keys)")
            return
        }
        let problem = APIKeySanitizer.validate(cleaned.cleaned)
        do {
            try settings.saveAPIKey(cleaned.cleaned)
            apiKeyInput = cleaned.cleaned
            refreshKeyDiagnostics()

            var message = settings.apiKeyStateText
            message += "\n• คีย์ที่ใช้อยู่: \(keyDiagnosticsText)"
            if let note = cleaned.changeDescription {
                message += "\n• \(note)"
            }
            if KeychainHelper.shared.purgedStaleFallback {
                message += "\n• พบคีย์เก่าค้างในที่เก็บสำรอง และล้างให้แล้ว (นี่คือสาเหตุที่คีย์ใหม่ไม่ถูกใช้)"
            }
            if let problem = problem {
                message += "\n\n⚠️ \(problem)"
                show(title: "บันทึกแล้ว (มีข้อควรระวัง)", message: message)
            } else {
                show(title: "บันทึกแล้ว", message: message)
            }
        } catch {
            show(title: "บันทึก API Key ไม่สำเร็จ", message: error.localizedDescription)
        }
    }

    private func deleteAPIKey() {
        do {
            try settings.deleteAPIKey()
            apiKeyInput = ""
            testResult = nil
            refreshKeyDiagnostics()
            show(title: "ลบ API Key แล้ว", message: "ลบทั้งใน Keychain และที่เก็บสำรองแล้ว — ใส่คีย์ใหม่ได้ทุกเมื่อ")
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
        // ถ้ามีคีย์ที่พิมพ์/วางค้างในช่อง ให้บันทึกก่อนทดสอบ → ทดสอบคีย์ที่เห็นบนจอจริง ๆ
        let pendingKey = APIKeySanitizer.sanitize(apiKeyInput).cleaned
        if !pendingKey.isEmpty {
            do {
                try settings.saveAPIKey(pendingKey)
                apiKeyInput = pendingKey
                refreshKeyDiagnostics()
            } catch {
                show(title: "บันทึกคีย์ก่อนทดสอบไม่สำเร็จ", message: error.localizedDescription)
                return
            }
        }

        guard let apiKey = try? KeychainHelper.shared.string(for: .openRouterAPIKey), !apiKey.isEmpty else {
            show(title: "ยังไม่มี API Key", message: "บันทึก API Key ก่อนทดสอบการเชื่อมต่อ")
            return
        }
        let diagnostics = KeychainHelper.shared.diagnostics(for: .openRouterAPIKey)
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
                var message = error.localizedDescription
                message += "\n\nคีย์ที่ส่งไป: \(diagnostics.fingerprint)"
                message += "\nที่เก็บ: \(diagnostics.storageText)"
                if !diagnostics.isOpenRouterFormat {
                    message += "\n⚠️ คีย์นี้ไม่ได้ขึ้นต้นด้วย sk-or- — ตรวจว่าคัดลอกคีย์ของ OpenRouter มาจริง"
                }
                if message.contains("401") {
                    message += "\n\nวิธีแก้เร็ว: กด \"ลบ API Key\" แล้ววางคีย์ใหม่จาก openrouter.ai/keys อีกครั้ง " +
                        "(บิลด์นี้ล้างคีย์เก่าที่ค้างอยู่ในที่เก็บสำรองให้อัตโนมัติแล้ว จึงไม่ถูกคีย์เก่าบดบัง)"
                }
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
