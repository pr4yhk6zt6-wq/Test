//
//  ChatViewModel.swift
//  iOS Agent Sandbox
//
//  ตรรกะของหน้าแชท (เฟส 1): ส่งข้อความ → สตรีมคำตอบ → แสดงข้อความทีละ chunk
//  เฟส 2 จะใช้คลาสนี้เป็นตัวเรียก AgentEngine (ReAct loop) แทนการสตรีมตรง ๆ
//

import Foundation

@MainActor
final class ChatViewModel: ObservableObject {

    // MARK: - สถานะที่ UI ใช้

    @Published private(set) var messages: [ChatMessage] = []
    @Published private(set) var isBusy: Bool = false
    /// ข้อความสถานะ เช่น "กำลังคิด…" / "กำลังใช้ tool: …"
    @Published private(set) var statusText: String = ""
    /// ข้อความแจ้งเตือนล่าสุด (เช่น กำลัง retry, tool call ที่ parse ไม่ได้)
    @Published private(set) var lastNotice: String?
    /// ข้อความ error ล่าสุด (แสดงเป็นแถบสีแดง)
    @Published var errorMessage: String?

    let backgroundKeeper = BackgroundTaskKeeper()
    private let usage = TokenUsageTracker.shared
    private var streamTask: Task<Void, Never>?

    /// ขีดจำกัดความยาวข้อความที่แสดงใน bubble เดียว (กันหน่วยความจำบนเครื่อง RAM 2GB)
    private let maxRenderedCharacters = 60_000

    // MARK: - ส่งข้อความ

    func send(_ rawText: String) {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard !isBusy else {
            lastNotice = "กำลังทำงานอยู่ — กดปุ่มหยุดก่อนส่งข้อความใหม่"
            return
        }

        let settings = AppSettings.shared
        let apiKey: String
        do {
            guard let stored = try KeychainHelper.shared.string(for: .openRouterAPIKey),
                  !stored.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                errorMessage = OpenRouterError.missingAPIKey.localizedDescription
                return
            }
            apiKey = stored
        } catch {
            errorMessage = "อ่าน API Key ไม่สำเร็จ: \(error.localizedDescription)"
            return
        }

        let modelID = settings.modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !modelID.isEmpty else {
            errorMessage = OpenRouterError.invalidModelID.localizedDescription
            return
        }

        errorMessage = nil
        lastNotice = nil
        messages.append(.user(text))

        let placeholder = ChatMessage.assistant("")
        messages.append(placeholder)

        let payloads = makePayloads(excludingMessageID: placeholder.id)
        isBusy = true
        statusText = "กำลังคิด…"
        backgroundKeeper.begin(name: "Agent กำลังตอบ")

        streamTask = Task { [weak self] in
            guard let self = self else { return }
            await self.runStream(modelID: modelID,
                                 apiKey: apiKey,
                                 payloads: payloads,
                                 assistantID: placeholder.id)
        }
    }

    /// ยกเลิกคำขอที่กำลังทำงานอยู่
    func stop() {
        streamTask?.cancel()
        streamTask = nil
        isBusy = false
        statusText = ""
        lastNotice = "ผู้ใช้ยกเลิกคำขอ"
        backgroundKeeper.end()
    }

    /// ลบข้อความเดี่ยวออกจากประวัติ (ใช้จากเมนูกดค้างในแชท)
    func remove(message: ChatMessage) {
        messages.removeAll { $0.id == message.id }
    }

    /// ล้างประวัติการสนทนาในหน่วยความจำ
    func clearConversation() {
        stop()
        messages.removeAll()
        errorMessage = nil
        lastNotice = nil
    }

    func dismissNotice() {
        lastNotice = nil
    }

    // MARK: - ตัวทำงานจริง

    private func runStream(modelID: String,
                           apiKey: String,
                           payloads: [ChatMessagePayload],
                           assistantID: UUID) async {
        do {
            let stream = OpenRouterService.streamChat(modelID: modelID,
                                                      messages: payloads,
                                                      tools: nil,
                                                      temperature: 0.3,
                                                      maxTokens: nil,
                                                      apiKey: apiKey)
            for try await event in stream {
                if Task.isCancelled { break }
                handle(event: event, assistantID: assistantID)
            }
            finish()
        } catch is CancellationError {
            finish()
        } catch let error as OpenRouterError {
            if case .cancelled = error {
                finish()
            } else {
                isBusy = false
                statusText = ""
                errorMessage = error.localizedDescription
                if error.requiresModelChange {
                    lastNotice = "โมเดลนี้ใช้กับ Agent ไม่ได้ กรุณาเปลี่ยนโมเดลในหน้าตั้งค่า (ไม่ลองซ้ำอัตโนมัติ)"
                }
                backgroundKeeper.end()
            }
        } catch {
            isBusy = false
            statusText = ""
            errorMessage = error.localizedDescription
            backgroundKeeper.end()
        }
    }

    private func handle(event: ChatStreamEvent, assistantID: UUID) {
        switch event {
        case .textDelta(let delta):
            append(text: delta, to: assistantID)
            statusText = "กำลังตอบ…"

        case .reasoningDelta:
            // โมเดลสาย reasoning — เฟส 1 ไม่แสดงความคิด แค่บอกสถานะ
            statusText = "กำลังคิด…"

        case .toolCallsCompleted(let calls):
            let names = calls.map { $0.function.name }.joined(separator: ", ")
            let note = "โมเดลขอเรียก tool: \(names) — ระบบ tools จะเปิดใช้งานในเฟส 2"
            lastNotice = note
            append(text: note, to: assistantID)

        case .usage(let usageValue):
            usage.add(usageValue)

        case .finished(let finishReason):
            if let reason = finishReason {
                switch reason {
                case "length":
                    lastNotice = "คำตอบถูกตัดเพราะชนเพดาน max tokens — พิมพ์ \"ต่อ\" เพื่อให้ตอบต่อได้"
                case "content_filter":
                    lastNotice = "ผู้ให้บริการโมเดลตัดคำตอบด้วยตัวกรองเนื้อหา"
                case "tool_calls":
                    break
                default:
                    break
                }
            }

        case .notice(let text):
            lastNotice = text
        }
    }

    private func finish() {
        isBusy = false
        statusText = ""
        if let last = messages.last, last.role == .assistant, last.isTextEmpty {
            // ไม่มีข้อความตอบกลับเลย → แจ้งให้ผู้ใช้รู้ จะได้ไม่เห็น bubble ว่าง
            messages[messages.count - 1].text = "_(ไม่ได้รับข้อความตอบกลับ — ลองใหม่อีกครั้ง)_"
        }
        backgroundKeeper.end()
    }

    // MARK: - ตัวช่วย

    private func append(text delta: String, to id: UUID) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        if messages[index].text.count >= maxRenderedCharacters {
            return
        }
        messages[index].text += delta
        if messages[index].text.count > maxRenderedCharacters {
            let keep = String(messages[index].text.prefix(maxRenderedCharacters))
            messages[index].text = keep + "\n\n_(ตัดข้อความที่ยาวเกินแสดงผลชั่วคราว)_"
        }
    }

    /// สร้าง payload สำหรับส่ง API: system prompt + ประวัติ (ตัด assistant placeholder ออก)
    private func makePayloads(excludingMessageID excluded: UUID) -> [ChatMessagePayload] {
        var payloads: [ChatMessagePayload] = [.init(role: ChatRole.system.rawValue,
                                                    content: .string(SystemPrompt.build(tools: [])),
                                                    toolCallID: nil,
                                                    toolCalls: nil,
                                                    name: nil)]
        for message in messages where message.id != excluded {
            if message.role == .assistant && message.isTextEmpty && !message.hasToolCalls {
                continue
            }
            payloads.append(message.payload())
        }
        return payloads
    }
}
