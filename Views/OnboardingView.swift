//
//  OnboardingView.swift
//  iOS Agent Sandbox
//
//  แนะนำการใช้งาน 3 หน้า (เฟส 5): ใส่ API Key → เลือกโมเดล → เลือกโหมดอนุมัติ
//  ใช้ TabView แบบ PageTabViewStyle (iOS 14+) ไม่ใช้ API ของ iOS 16
//

#if canImport(UIKit)
import UIKit
#endif
import SwiftUI

struct OnboardingView: View {

    /// เรียกเมื่อผู้ใช้กด "เริ่มใช้งาน" หรือ "ข้าม"
    let onFinish: () -> Void

    @EnvironmentObject private var settings: AppSettings

    @State private var pageIndex: Int = 0
    @State private var apiKeyInput: String = ""
    @State private var modelInput: String = ""
    @State private var message: String?

    private let pageCount = 3

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $pageIndex) {
                apiKeyPage.tag(0)
                modelPage.tag(1)
                approvalPage.tag(2)
            }
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .always))
            .animation(.easeInOut(duration: 0.2))

            if let message = message {
                Text(message)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal, 20)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 12) {
                Button("ข้าม") {
                    onFinish()
                }
                .buttonStyle(.bordered)
                .frame(minHeight: 44)

                Spacer(minLength: 0)

                if pageIndex < pageCount - 1 {
                    Button("ถัดไป") {
                        saveCurrentPage()
                        pageIndex += 1
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(minHeight: 44)
                } else {
                    Button("เริ่มใช้งาน") {
                        saveCurrentPage()
                        onFinish()
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(minHeight: 44)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .onAppear {
            apiKeyInput = (try? KeychainHelper.shared.string(for: .openRouterAPIKey)) ?? ""
            modelInput = settings.modelID
        }
    }

    // MARK: - หน้า 1: API Key

    private var apiKeyPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header(systemImage: "key.fill",
                       title: "ใส่ API Key ของ OpenRouter",
                       detail: "แอปนี้คุยกับโมเดลผ่าน OpenRouter — สมัครฟรีที่ openrouter.ai แล้วสร้างคีย์ในหน้า Keys")

                SecureField("sk-or-v1-…", text: $apiKeyInput)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .frame(minHeight: 44)

                Text("คีย์ถูกเก็บใน Keychain ของเครื่อง และถูกทำความสะอาด (ตัดช่องว่าง/อักขระล่องหน) ก่อนใช้ทุกครั้ง")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)
        }
    }

    // MARK: - หน้า 2: โมเดล

    private var modelPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header(systemImage: "cpu",
                       title: "เลือกโมเดล",
                       detail: "ใส่ Model ID ที่รองรับการเรียก tool เช่น vendor/model:free — ถ้าไม่รองรับ tool จะใช้ Agent ไม่ได้")

                TextField("vendor/model:free", text: $modelInput)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .frame(minHeight: 44)

                Text("ตัวอย่างที่ใช้ได้บ่อย")
                    .font(.caption)
                    .foregroundColor(.secondary)

                ForEach(suggestedModels, id: \.self) { model in
                    Button {
                        modelInput = model
                    } label: {
                        HStack {
                            Text(model)
                                .font(.caption.monospaced())
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: 0)
                            if modelInput == model {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.accentColor)
                            }
                        }
                        .padding(.horizontal, 10)
                        .frame(minHeight: 40)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color(UIColor.secondarySystemBackground))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
        }
    }

    private var suggestedModels: [String] {
        ["deepseek/deepseek-chat-v3-0324:free",
         "google/gemini-2.0-flash-exp:free",
         "openai/gpt-4o-mini",
         "anthropic/claude-3.5-haiku",
         "qwen/qwen-2.5-72b-instruct:free"]
    }

    // MARK: - หน้า 3: โหมดอนุมัติ

    private var approvalPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header(systemImage: "hand.raised.fill",
                       title: "โหมดขออนุมัติ",
                       detail: "เมื่อเปิด แอปจะถามทุกครั้งก่อนรันคำสั่ง shell หรือเขียนทับไฟล์สำคัญ — เลือกได้เป็นครั้ง ๆ")

                Toggle("ถามอนุมัติทุกครั้ง", isOn: $settings.requireApproval)
                    .frame(minHeight: 44)

                Toggle("อนุญาตให้ใช้อินเทอร์เน็ต", isOn: $settings.allowInternet)
                    .frame(minHeight: 44)

                Toggle("ใช้เฉพาะ Wi-Fi", isOn: $settings.wifiOnly)
                    .frame(minHeight: 44)

                Text("ถ้าปิดการถามอนุมัติ Agent จะรันคำสั่งได้เองทันที — เปิดไว้ก่อนจนกว่าจะคุ้นเคยจะปลอดภัยกว่า")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)
        }
    }

    private func header(systemImage: String, title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 34))
                .foregroundColor(.accentColor)
            Text(title)
                .font(.title3.weight(.semibold))
            Text(detail)
                .font(.footnote)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 4)
    }

    // MARK: - บันทึกค่าของแต่ละหน้า

    private func saveCurrentPage() {
        switch pageIndex {
        case 0:
            let sanitized = APIKeySanitizer.sanitize(apiKeyInput)
            let key = sanitized.cleaned
            guard !key.isEmpty else { return }
            if let problem = APIKeySanitizer.validate(key) {
                message = problem
                return
            }
            guard APIKeySanitizer.looksLikeOpenRouterKey(key) else {
                message = "คีย์ดูไม่เหมือนคีย์ของ OpenRouter (มักขึ้นต้นด้วย sk-or-) — ตรวจแล้วลองใหม่"
                return
            }
            do {
                try KeychainHelper.shared.set(key, for: .openRouterAPIKey)
                message = sanitized.changeDescription.map { "บันทึกคีย์แล้ว (\($0))" }
            } catch {
                message = "บันทึกคีย์ไม่สำเร็จ: \(error.localizedDescription)"
            }
        case 1:
            let model = modelInput.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !model.isEmpty else { return }
            settings.modelID = model
            message = nil
        default:
            message = nil
        }
    }
}
