//
//  AGSettingsScreen.swift
//  AgentApp — หน้าตั้งค่า (พอร์ตจาก phase3/phase4: ความละเอียดของกิจกรรม · ความปลอดภัย · ข้อมูลและค่าใช้จ่าย · ความช่วยเหลือ)
//
//  ทุกสวิตช์ผูกกับการตั้งค่าจริงที่มีผลกับ Agent ไม่มีสวิตช์ประดับ
//

import SwiftUI
import UIKit

struct AGSettingsScreen: View {

    @EnvironmentObject private var settings: AppSettings
    @ObservedObject private var usage: TokenUsageTracker = .shared
    @ObservedObject private var backup: WorkspaceBackup = .shared
    @ObservedObject private var notifier: AgentNotifier = .shared

    @AppStorage(SettingsKeys.activityLevel) private var activityLevelRaw: String = ActivityDetailLevel.normal.rawValue
    @AppStorage(SettingsKeys.chatFontScale) private var fontScale: Double = 1
    @AppStorage(SettingsKeys.appearance) private var appearanceRaw: String = AppAppearance.system.rawValue
    @AppStorage(SettingsKeys.hapticsEnabled) private var hapticsEnabled: Bool = true

    @State private var showApiKeySheet: Bool = false
    @State private var showModelSheet: Bool = false
    @State private var showLevelSheet: Bool = false
    @State private var showModelDetail: Bool = false
    @State private var showBackups: Bool = false
    @State private var showRevokeConfirm: Bool = false
    @State private var showAbout: Bool = false
    @State private var apiKeyDraft: String = ""

    private var activityLevel: ActivityDetailLevel {
        ActivityDetailLevel(rawValue: activityLevelRaw) ?? .normal
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AGMetric.s5) {
                if !settings.requireApproval { approvalWarning }
                activitySection
                safetySection
                dataSection
                helpSection
            }
            .padding(.horizontal, AGMetric.screenPadding)
            .padding(.vertical, AGMetric.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(AGColor.bg)
        .navigationTitle("ตั้งค่า")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showApiKeySheet) { apiKeySheet }
        .sheet(isPresented: $showModelSheet) { modelSheet }
        .sheet(isPresented: $showLevelSheet) { levelSheet }
        .sheet(isPresented: $showBackups) { backupsSheet }
        .alert("ปิดการถามก่อนทุกครั้ง?", isPresented: $showRevokeConfirm, actions: {
            Button("ปิดการถาม", role: .destructive) { settings.requireApproval = false }
            Button("ยกเลิก", role: .cancel) { }
        }, message: {
            Text("Agent จะทำสิ่งที่เสี่ยงได้โดยไม่ถามคุณก่อน รวมถึงการเขียนทับหรือลบไฟล์ในโฟลเดอร์ทำงาน — แนะนำให้เปิดไว้")
        })
        .alert("เกี่ยวกับแอปนี้", isPresented: $showAbout, actions: {
            Button("รับทราบ", role: .cancel) { }
        }, message: {
            Text("AI Agent Sandbox · เวอร์ชัน \(Self.versionText) · ทำงานกับโมเดลผ่าน OpenRouter โดยใช้คีย์ของคุณเอง\n\nข้อจำกัดที่บอกตรง ๆ: ทำต่อจากจุดเดิมได้แต่ไม่ใช่หยุด/เล่นต่อจริง · ไม่มีตัวเลขเวลาที่เหลือ · ไม่มีงานตามเวลา · การอนุมัติต้องทำในแอปเสมอ")
        })
    }

    // MARK: - เตือนเมื่อปิดเกราะสำคัญ

    private var approvalWarning: some View {
        AGBanner(tone: .warning,
                 title: "ตอนนี้ Agent ไม่ถามก่อนทำ",
                 message: "การเขียนทับ/ลบไฟล์จะเกิดขึ้นทันที ยังย้อนกลับได้ภายใน 10 นาที แต่ควรเปิดสวิตช์ \"ถามก่อนทุกครั้ง\" กลับไว้",
                 scale: fontScale)
    }

    // MARK: - กิจกรรมและการแสดงผล

    private var activitySection: some View {
        VStack(alignment: .leading, spacing: AGMetric.s2) {
            AGSectionTitle(text: "การแสดงกิจกรรม", scale: fontScale)
            AGCard(padding: 0) {
                VStack(spacing: 0) {
                    AGRow(icon: "list.bullet.indent",
                          title: "ความละเอียดของกิจกรรม",
                          subtitle: "\(activityLevel.thaiName) — \(activityLevel.explanation)",
                          showsChevron: true,
                          scale: fontScale) { showLevelSheet = true }
                    divider
                    AGRow(icon: "textformat.size",
                          title: "ขนาดตัวอักษรในแชท",
                          subtitle: fontScaleText,
                          showsChevron: false,
                          scale: fontScale,
                          accessory: AnyView(HStack(spacing: AGMetric.s2) {
                              Button(action: { fontScale = max(1.0, fontScale - 0.15) }) {
                                  Text("ก").font(AGFont.font(AGFont.cap, scale: fontScale))
                                      .foregroundColor(AGColor.t1)
                                      .frame(width: 36, height: AGMetric.touch)
                                      .contentShape(Rectangle())
                              }
                              .buttonStyle(AGPressableStyle())
                              .accessibilityLabel(Text("ลดขนาดตัวอักษร"))

                              Button(action: { fontScale = min(1.6, fontScale + 0.15) }) {
                                  Text("ก").font(AGFont.font(AGFont.head, scale: fontScale))
                                      .foregroundColor(AGColor.t1)
                                      .frame(width: 36, height: AGMetric.touch)
                                      .contentShape(Rectangle())
                              }
                              .buttonStyle(AGPressableStyle())
                              .accessibilityLabel(Text("เพิ่มขนาดตัวอักษร"))
                          }))
                    divider
                    segmentedRow(title: "ธีมหน้าจอ",
                                 options: AppAppearance.allCases.map { ($0.rawValue, $0.title) },
                                 selection: appearanceRaw) { raw in
                        appearanceRaw = raw
                    }
                    divider
                    AGRow(icon: "hand.tap",
                          title: "สั่นเบา ๆ เมื่อมีการตอบสนอง",
                          subtitle: hapticsEnabled ? "เปิดอยู่" : "ปิดอยู่",
                          showsChevron: false,
                          scale: fontScale,
                          accessory: AnyView(Toggle("", isOn: $hapticsEnabled)
                            .labelsHidden()
                            .accentColor(AGColor.accentInk)
                            .accessibilityLabel(Text("สั่นเบา ๆ เมื่อมีการตอบสนอง"))))
                }
            }
            Text("ธีมมืดใช้ค่าเดียวกันทั้งแอป เพราะโทเคนสีของระบบรองรับทั้งสองโหมด")
                .font(AGFont.font(AGFont.micro, scale: fontScale))
                .foregroundColor(AGColor.t3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var fontScaleText: String {
        switch fontScale {
        case ..<1.1: return "ปกติ"
        case ..<1.3: return "ใหญ่ขึ้นเล็กน้อย"
        case ..<1.5: return "ใหญ่"
        default: return "ใหญ่ที่สุด"
        }
    }

    // MARK: - ความปลอดภัยและการควบคุม

    private var safetySection: some View {
        VStack(alignment: .leading, spacing: AGMetric.s2) {
            AGSectionTitle(text: "ความปลอดภัยและการควบคุม", scale: fontScale)
            AGCard(padding: 0) {
                VStack(spacing: 0) {
                    AGRow(icon: "checkmark.shield",
                          title: "ถามก่อนทุกครั้ง",
                          subtitle: settings.requireApproval
                            ? "Agent จะขออนุญาตก่อนทำสิ่งที่เสี่ยงเสมอ"
                            : "ปิดอยู่ — Agent ทำได้ทันทีโดยไม่ถาม",
                          showsChevron: false,
                          scale: fontScale,
                          accessory: AnyView(Toggle("", isOn: Binding(
                            get: { settings.requireApproval },
                            set: { newValue in
                                if newValue { settings.requireApproval = true }
                                else { showRevokeConfirm = true }
                            }))
                            .labelsHidden()
                            .accentColor(AGColor.accentInk)
                            .accessibilityLabel(Text("ถามก่อนทุกครั้ง"))))
                    divider
                    AGRow(icon: "arrow.uturn.backward",
                          title: "การย้อนกลับที่ทำได้จริง",
                          subtitle: "ระบบสำรองไฟล์ก่อนแก้ · เก็บไว้ 10 นาที · ไฟล์ละไม่เกิน 20 MB · สูงสุด 30 รายการ",
                          showsChevron: true,
                          scale: fontScale) { showBackups = true }
                    divider
                    AGRow(icon: "lock.shield",
                          title: "การปิดบังข้อมูลอ่อนไหว",
                          subtitle: "ปิดบังอัตโนมัติก่อนแสดงผลและก่อนส่งออก",
                          showsChevron: false,
                          scale: fontScale,
                          accessory: AnyView(AGChip(text: "เปิดตลอด", tone: .ok, scale: fontScale)))
                    divider
                    AGRow(icon: "eye.trianglebadge.exclamationmark",
                          title: "คำเตือนข้อความหลอกลวง (prompt injection)",
                          subtitle: "ถ้าเนื้อหาที่ Agent อ่านจากเว็บ/ไฟล์สั่งให้ทำสิ่งอื่น แอปจะหยุดและถามคุณก่อน",
                          showsChevron: false,
                          scale: fontScale,
                          accessory: AnyView(AGChip(text: "ทำงานอัตโนมัติ", tone: .ok, scale: fontScale)))
                }
            }
            Text("ขอบเขตของสิทธิ์: การอนุมัติทุกครั้งเป็นแบบ \"ครั้งเดียว\" เท่านั้น (ยังไม่มีโหมดจำถาวร) และไม่มีหน้าเพิกถอนสิทธิ์ในบิลด์นี้ — ถ้าอนุมัติไปแล้วและเปลี่ยนใจ ให้กดหยุดงานในแชททันที")
                .font(AGFont.font(AGFont.micro, scale: fontScale))
                .foregroundColor(AGColor.t3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - ข้อมูลและค่าใช้จ่าย

    private var dataSection: some View {
        VStack(alignment: .leading, spacing: AGMetric.s2) {
            AGSectionTitle(text: "ข้อมูลและค่าใช้จ่าย", scale: fontScale)
            AGCard(padding: 0) {
                VStack(spacing: 0) {
                    AGRow(icon: "key",
                          title: "คีย์ของ OpenRouter",
                          subtitle: settings.hasAPIKey ? "ตั้งค่าไว้แล้ว · เก็บใน Keychain ของเครื่องนี้" : "ยังไม่ได้ตั้งค่า",
                          showsChevron: true,
                          scale: fontScale) {
                        apiKeyDraft = ""
                        showApiKeySheet = true
                    }
                    divider
                    AGRow(icon: "cpu",
                          title: "โมเดลที่ใช้",
                          subtitle: settings.modelID.isEmpty ? "ยังไม่ได้เลือก — ระบบจะใช้ค่าเริ่มต้น" : settings.modelID,
                          showsChevron: true,
                          scale: fontScale) { showModelSheet = true }
                    divider
                    AGRow(icon: "chart.bar.doc.horizontal",
                          title: "โทเคนและค่าใช้จ่าย",
                          subtitle: usageLineText,
                          showsChevron: false,
                          scale: fontScale,
                          accessory: AnyView(Button(action: {
                              guard usage.hasData else { return }
                              AGHaptic.light()
                              usage.reset()
                          }) {
                              Text(usage.hasData ? "รีเซ็ต" : "—")
                                  .font(AGFont.font(AGFont.cap, weight: .semibold, scale: fontScale))
                                  .foregroundColor(usage.hasData ? AGColor.accentInk : AGColor.t3)
                                  .frame(minWidth: AGMetric.touch, minHeight: AGMetric.touch)
                          })
                          .disabled(!usage.hasData)
                          .accessibilityLabel(Text("รีเซ็ตตัวเลขโทเคนและค่าใช้จ่าย")))
                    divider
                    AGRow(icon: "externaldrive",
                          title: "ที่เก็บไฟล์ทำงาน",
                          subtitle: settings.workspacePath,
                          showsChevron: false,
                          scale: fontScale)
                    divider
                    AGRow(icon: "wifi",
                          title: "ให้ Agent ต่ออินเทอร์เน็ตได้",
                          subtitle: settings.allowInternet ? "เปิด — ใช้ค้นเว็บและเปิดหน้าเว็บ" : "ปิด — Agent ทำงานกับไฟล์ในเครื่องเท่านั้น",
                          showsChevron: false,
                          scale: fontScale,
                          accessory: AnyView(Toggle("", isOn: $settings.allowInternet)
                            .labelsHidden()
                            .accentColor(AGColor.accentInk)
                            .accessibilityLabel(Text("ให้ Agent ต่ออินเทอร์เน็ตได้"))))
                    divider
                    AGRow(icon: "bell",
                          title: "แจ้งเตือนเมื่องานเสร็จ / ต้องการคำตอบ",
                          subtitle: notifier.isEnabled ? "เปิดอยู่ — ไม่มีการอนุมัติจากการแจ้งเตือน" : "ปิดอยู่",
                          showsChevron: false,
                          scale: fontScale,
                          accessory: AnyView(Toggle("", isOn: Binding(get: { notifier.isEnabled },
                                                                     set: { notifier.setEnabled($0) }))
                            .labelsHidden()
                            .accentColor(AGColor.accentInk)
                            .accessibilityLabel(Text("แจ้งเตือนเมื่องานเสร็จหรือต้องการคำตอบ"))))
                }
            }
        }
    }

    private var usageLineText: String {
        guard usage.hasData else { return "ยังไม่มีข้อมูล — จะขึ้นเมื่อมีการใช้งานจริง" }
        if let cost = usage.costCredits {
            return String(format: "%@ โทเคน · %.4f เครดิต", usage.compactShortText, cost)
        }
        return "\(usage.compactShortText) โทเคน · ค่าใช้จ่ายไม่ระบุ"
    }

    // MARK: - ช่วยเหลือ

    private var helpSection: some View {
        VStack(alignment: .leading, spacing: AGMetric.s2) {
            AGSectionTitle(text: "ช่วยเหลือ", scale: fontScale)
            AGCard(padding: 0) {
                VStack(spacing: 0) {
                    AGRow(icon: "questionmark.circle",
                          title: "ทำไม Agent ทำได้ไม่เหมือนในโฆษณา",
                          subtitle: "อธิบายตรง ๆ ว่าอะไรทำได้/ไม่ได้บน iOS 15",
                          showsChevron: true,
                          scale: fontScale) { showAbout = true }
                    divider
                    AGRow(icon: "lock.doc",
                          title: "คู่มือความปลอดภัย",
                          subtitle: "ข้อมูลอ่อนไหว · การปิดบัง · การกู้ไฟล์ · สิทธิ์ที่ให้ไปแล้ว",
                          showsChevron: true,
                          scale: fontScale) { showAbout = true }
                }
            }
        }
    }

    private var divider: some View {
        Rectangle().fill(AGColor.border).frame(height: 1).padding(.leading, 52)
    }

    // MARK: - แถวแบบเลือกได้

    private func segmentedRow(title: String,
                              options: [(String, String)],
                              selection: String,
                              onSelect: @escaping (String) -> Void) -> some View {
        VStack(alignment: .leading, spacing: AGMetric.s2) {
            Text(title)
                .font(AGFont.font(AGFont.sub, scale: fontScale))
                .foregroundColor(AGColor.t1)
            HStack(spacing: AGMetric.s2) {
                ForEach(options, id: \.0) { option in
                    AGButton(title: option.1,
                             kind: selection == option.0 ? .primary : .secondary,
                             scale: fontScale,
                             hint: "เปลี่ยนธีมหน้าจอเป็น \(option.1)") {
                        onSelect(option.0)
                    }
                }
            }
        }
        .padding(.horizontal, AGMetric.s4)
        .padding(.vertical, AGMetric.s3)
    }

    // MARK: - ชีตย่อย

    private var apiKeySheet: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AGMetric.s3) {
                AGBanner(tone: .info,
                         title: "คีย์ถูกเก็บไว้ใน Keychain ของเครื่องนี้",
                         message: "คีย์จะไม่ถูกส่งไปที่อื่นนอกจาก OpenRouter และไม่ถูกบันทึกลงไฟล์ประวัติหรือการส่งออก",
                         scale: fontScale)
                Text("วางคีย์ที่ขึ้นต้นด้วย sk-or-…")
                    .font(AGFont.font(AGFont.cap, scale: fontScale))
                    .foregroundColor(AGColor.t2)
                SecureField("คีย์ OpenRouter", text: $apiKeyDraft)
                    .font(AGFont.mono(AGFont.body, scale: fontScale))
                    .padding(.horizontal, AGMetric.s3)
                    .frame(minHeight: AGMetric.touch)
                    .background(RoundedRectangle(cornerRadius: AGMetric.rSM, style: .continuous).fill(AGColor.surface2))
                AGButton(title: "บันทึกคีย์", icon: "checkmark", kind: .primary, scale: fontScale) {
                    let trimmed = apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    do {
                        try settings.saveAPIKey(trimmed)
                        apiKeyDraft = ""
                        AGHaptic.success()
                        showApiKeySheet = false
                    } catch {
                        AGHaptic.warning()
                    }
                }
                if settings.hasAPIKey {
                    AGButton(title: "ลบคีย์ออกจากเครื่อง", icon: "trash", kind: .secondary, scale: fontScale) {
                        try? settings.deleteAPIKey()
                        AGHaptic.medium()
                        showApiKeySheet = false
                    }
                }
            }
            .padding(.horizontal, AGMetric.screenPadding)
            .padding(.vertical, AGMetric.s3)
        }
        .frame(maxHeight: 420)
    }

    private var modelSheet: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AGMetric.s3) {
                ForEach(AGSettingsScreen.suggestedModels, id: \.self) { model in
                    AGCard(padding: 0) {
                        AGRow(icon: settings.modelID == model ? "checkmark.circle.fill" : "cpu",
                              title: model,
                              subtitle: Self.note(for: model),
                              showsChevron: true,
                              scale: fontScale) {
                            settings.modelID = model
                            AGHaptic.light()
                            showModelSheet = false
                        }
                    }
                }
                AGCard(padding: AGMetric.s4) {
                    VStack(alignment: .leading, spacing: AGMetric.s2) {
                        Text("ใช้ชื่อโมเดลอื่นเอง")
                            .font(AGFont.font(AGFont.cap, weight: .semibold, scale: fontScale))
                            .foregroundColor(AGColor.t2)
                        TextField("เช่น vendor/model-name", text: $settings.modelID)
                            .font(AGFont.mono(AGFont.cap, scale: fontScale))
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .padding(.horizontal, AGMetric.s3)
                            .frame(minHeight: AGMetric.touch)
                            .background(RoundedRectangle(cornerRadius: AGMetric.rSM, style: .continuous).fill(AGColor.surface2))
                        Text("ต้องเป็นชื่อที่ OpenRouter รู้จัก ถ้าพิมพ์ผิด ระบบจะแจ้งข้อผิดพลาดจากผู้ให้บริการตรง ๆ ตอนส่งคำขอ")
                            .font(AGFont.font(AGFont.micro, scale: fontScale))
                            .foregroundColor(AGColor.t3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                    .font(AGFont.mono(AGFont.cap, scale: fontScale))
                    .padding(.horizontal, AGMetric.s3)
                    .frame(minHeight: AGMetric.touch)
                    .background(RoundedRectangle(cornerRadius: AGMetric.rSM, style: .continuous).fill(AGColor.surface2))
                AGButton(title: "ดูข้อจำกัดของโมเดลนี้", kind: .secondary, scale: fontScale) { showModelDetail = true }
            }
            .padding(.horizontal, AGMetric.screenPadding)
            .padding(.vertical, AGMetric.s3)
        }
        .frame(maxHeight: 460)
        .alert("เกี่ยวกับโมเดลที่เลือก", isPresented: $showModelDetail, actions: {
            Button("รับทราบ", role: .cancel) { }
        }, message: {
            Text("จำนวนรอบการทำงานต่อหนึ่งคำขอสูงสุด 20 รอบ และระบบตัดบริบทตามที่ตั้งไว้ \(settings.contextLengthTokens) โทเคน — โมเดลที่รองรับรูปภาพจะเห็นรูปที่คุณแนบได้ ส่วนค่าใช้จ่ายจะแสดงเมื่อโมเดลส่งข้อมูลกลับมา")
        })
    }

    private var levelSheet: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AGMetric.s3) {
                ForEach(ActivityDetailLevel.allCases, id: \.rawValue) { level in
                    AGCard(padding: 0) {
                        AGRow(icon: activityLevel == level ? "checkmark.circle.fill" : "list.bullet",
                              title: level.thaiName,
                              subtitle: level.explanation,
                              showsChevron: true,
                              scale: fontScale) {
                            activityLevelRaw = level.rawValue
                            AGHaptic.light()
                            showLevelSheet = false
                        }
                    }
                }
                Text("ระดับ \"ละเอียด\" จะแสดงชื่อเครื่องมือและรายละเอียดทางเทคนิค ซึ่งปกติซ่อนไว้เพราะไม่จำเป็นสำหรับการใช้งานทั่วไป")
                    .font(AGFont.font(AGFont.micro, scale: fontScale))
                    .foregroundColor(AGColor.t3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, AGMetric.screenPadding)
            .padding(.vertical, AGMetric.s3)
        }
        .frame(maxHeight: 460)
    }

    private var backupsSheet: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AGMetric.s3) {
                AGBanner(tone: .info,
                         title: "สำเนาที่กู้คืนได้ตอนนี้",
                         message: "เก็บเฉพาะไฟล์ที่ Agent เพิ่งแก้ใน 10 นาทีล่าสุด ถ้าเกินเวลาหรือไฟล์ใหญ่เกิน 20 MB ระบบจะไม่เก็บสำเนา",
                         scale: fontScale)
                if backup.undoableRecords.isEmpty {
                    Text("ยังไม่มีสำเนา — จะมีเมื่อ Agent ลงมือแก้ไฟล์ครั้งแรก")
                        .font(AGFont.font(AGFont.sub, scale: fontScale))
                        .foregroundColor(AGColor.t2)
                } else {
                    ForEach(backup.undoableRecords) { record in
                        AGCard(padding: AGMetric.s4) {
                            VStack(alignment: .leading, spacing: AGMetric.s2) {
                                Text((record.originalPath as NSString).lastPathComponent)
                                    .font(AGFont.font(AGFont.sub, weight: .semibold, scale: fontScale))
                                    .foregroundColor(AGColor.t1)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Text(record.kind.thaiExplanation)
                                    .font(AGFont.font(AGFont.cap, scale: fontScale))
                                    .foregroundColor(AGColor.t2)
                                    .fixedSize(horizontal: false, vertical: true)
                                if record.canUndo {
                                    Text("เหลือเวลาย้อนกลับ \(record.remainingText) นาที")
                                        .font(AGFont.font(AGFont.micro, scale: fontScale))
                                        .foregroundColor(AGColor.t3)
                                    AGButton(title: record.kind.thaiTitle, icon: "arrow.uturn.backward", kind: .secondary, scale: fontScale) {
                                        do {
                                            try WorkspaceBackup.shared.restore(record)
                                            AGHaptic.success()
                                        } catch {
                                            AGHaptic.warning()
                                        }
                                    }
                                } else {
                                    Text(record.skippedReason ?? "ย้อนกลับรายการนี้ไม่ได้แล้ว")
                                        .font(AGFont.font(AGFont.micro, scale: fontScale))
                                        .foregroundColor(AGColor.t3)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, AGMetric.screenPadding)
            .padding(.vertical, AGMetric.s3)
        }
        .frame(maxHeight: 520)
    }

    /// ชุดเดียวกับที่หน้าต้อนรับเสนอ — เคยใช้งานกับแอปนี้มาแล้ว
    static let suggestedModels: [String] = ["deepseek/deepseek-chat-v3-0324:free",
                                            "google/gemini-2.0-flash-exp:free",
                                            "openai/gpt-4o-mini",
                                            "anthropic/claude-3.5-haiku",
                                            "qwen/qwen-2.5-72b-instruct:free"]

    static func note(for model: String) -> String {
        if model.hasSuffix(":free") { return "รุ่นทดลองใช้ฟรี — เหมาะกับการลองงานสั้น" }
        if model.contains("haiku") { return "เร็วและประหยัด สำหรับงานทั่วไป" }
        if model.contains("gpt-4o-mini") { return "สมดุลระหว่างความเร็วและความสามารถ" }
        return "โมเดลจาก OpenRouter"
    }

    static var versionText: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }
}
