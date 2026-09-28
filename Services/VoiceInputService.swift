//
//  VoiceInputService.swift
//  iOS Agent Sandbox — ดีไซน์ v2 (เฟส 5 ส่วนที่ 8)
//
//  โหมดเสียง (พูดแทนพิมพ์): ใช้ระบบถอดเสียงของ iOS แปลงคำพูดเป็นข้อความ แล้วให้ผู้ใช้ตรวจก่อนส่ง
//  ทำไมต้องมี: ผู้ใช้ถือมือเดียว พิมพ์ยาว ๆ บน iPhone 7 ไม่สะดวก — แต่ต้องไม่แลกกับความเป็นส่วนตัว
//
//  กติกาความซื่อสัตย์และความเป็นส่วนตัว (ห้ามละเมิด):
//   1. โหมดเสียงปิดไว้ก่อนเสมอ — ผู้ใช้ต้องเป็นคนเปิดเองในหน้าตั้งค่า
//   2. ขออนุญาตพร้อมเหตุผล "ก่อน" ที่ระบบจะเด้งกล่องขออนุญาต
//   3. บอกตรง ๆ ว่าเสียงถูกประมวลผลที่ไหน: ถ้าเครื่องถอดเสียงเองได้ = ไม่ส่งเสียงออกไป
//      ถ้าเครื่องทำไม่ได้ = ต้องใช้อินเทอร์เน็ตและเสียงจะถูกส่งไปประมวลผล (ต้องบอกก่อนเริ่มพูด)
//   4. ข้อความที่ถอดได้จะไม่ถูกส่งเอง — ต้องให้ผู้ใช้กดยืนยันหนึ่งครั้งเสมอ
//   5. ไม่เก็บไฟล์เสียงไว้ในเครื่องหลังจบการพูด (ใช้หน่วยความจำชั่วคราวของระบบเท่านั้น)
//
//  ไฟล์นี้ไม่ถูกดึงไปชุดทดสอบแกนกลาง (ต้องมี iOS SDK) — ตรรกะที่ทดสอบได้ถูกแยกไว้ที่อื่น
//

import Foundation
import AVFoundation
import Speech

@MainActor
final class VoiceInputService: NSObject, ObservableObject {

    /// สถานะที่ UI ต้องแยกให้ออก — ทุกสถานะมีข้อความไทยที่บอก "ทำอะไรต่อได้"
    enum Phase: Equatable {
        case idle
        case preparing
        case listening
        case denied
        case unavailable(String)
        case failed(String)
    }

    /// ภาษาเป้าหมาย — ไทยเป็นค่าเริ่มต้นของแอปนี้
    static let localeIdentifier = "th-TH"

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var transcript: String = ""
    @Published private(set) var level: Float = 0
    /// true = เครื่องถอดเสียงในเครื่องได้ (เสียงไม่ออกนอกเครื่อง)
    @Published private(set) var onDeviceOnly: Bool = false
    /// true = มีตัวถอดเสียงภาษาไทยในเครื่องนี้
    @Published private(set) var languageAvailable: Bool = true

    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let engine = AVAudioEngine()
    private var tapInstalled = false

    var isListening: Bool { phase == .listening }

    /// ตรวจความพร้อมของภาษา/เครื่อง ก่อนแสดงปุ่มเริ่มพูด (เรียกตอนเปิดชีต)
    func prepare() {
        let locale = Locale(identifier: VoiceInputService.localeIdentifier)
        let found = SFSpeechRecognizer(locale: locale)
        recognizer = found
        languageAvailable = found != nil
        onDeviceOnly = found?.supportsOnDeviceRecognition ?? false
        if found == nil {
            phase = .unavailable("เครื่องนี้ยังไม่มีตัวถอดเสียงภาษาไทย — พิมพ์แทนไปก่อนได้เลย")
        } else if phase != .listening {
            phase = .idle
        }
    }

    /// เริ่มฟัง (จะขออนุญาตถ้ายังไม่เคยอนุญาต)
    func start() {
        guard !isListening else { return }
        if recognizer == nil { prepare() }
        guard let recognizer = recognizer else { return }

        guard recognizer.isAvailable else {
            phase = .unavailable("ตัวถอดเสียงยังไม่พร้อมใช้ตอนนี้ (เครื่องอาจไม่มีอินเทอร์เน็ต) — พิมพ์แทนได้เลย")
            return
        }

        phase = .preparing
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch status {
                case .authorized:
                    self.requestMicrophoneAccess()
                case .denied:
                    self.phase = .denied
                case .restricted:
                    self.phase = .unavailable("เครื่องนี้ไม่อนุญาตให้ใช้การถอดเสียง — พิมพ์แทนได้เลย")
                default:
                    self.phase = .idle
                }
            }
        }
    }

    /// หยุดฟังแต่เก็บข้อความที่ถอดได้ไว้ให้ผู้ใช้ตรวจ
    func stop() {
        guard isListening else { return }
        teardown()
        phase = .idle
    }

    /// ล้างข้อความที่ถอดได้และเริ่มใหม่
    func reset() {
        transcript = ""
        level = 0
        if !isListening { phase = .idle }
    }

    // MARK: - ภายใน

    private func requestMicrophoneAccess() {
        AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if granted {
                    self.beginListening()
                } else {
                    self.phase = .denied
                }
            }
        }
    }

    private func beginListening() {
        guard let recognizer = recognizer else { return }

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            phase = .failed("เปิดไมโครโฟนไม่สำเร็จ — ปิดแอปอื่นที่ใช้ไมโครโฟนอยู่ แล้วลองอีกครั้ง")
            return
        }

        let newRequest = SFSpeechAudioBufferRecognitionRequest()
        newRequest.shouldReportPartialResults = true
        // ถ้าเครื่องถอดเสียงเองได้ ให้ทำในเครื่อง (เสียงไม่ออกนอกเครื่อง) — ถ้าไม่ได้ ระบบจะใช้อินเทอร์เน็ต
        newRequest.requiresOnDeviceRecognition = onDeviceOnly
        request = newRequest
        transcript = ""
        level = 0

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            newRequest.append(buffer)
            let measured = VoiceInputService.level(of: buffer)
            DispatchQueue.main.async {
                self?.level = measured
            }
        }
        tapInstalled = true

        engine.prepare()
        do {
            try engine.start()
        } catch {
            teardown()
            phase = .failed("เริ่มอัดเสียงไม่สำเร็จ — ตรวจว่าไม่มีแอปอื่นใช้ไมโครโฟนอยู่ แล้วลองอีกครั้ง")
            return
        }

        task = recognizer.recognitionTask(with: newRequest) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let result = result {
                    self.transcript = result.bestTranscription.formattedString
                    if result.isFinal {
                        self.teardown()
                        self.phase = .idle
                    }
                }
                if let error = error, self.transcript.isEmpty {
                    self.teardown()
                    self.phase = .failed(VoiceInputService.thaiMessage(for: error))
                }
            }
        }

        phase = .listening
    }

    /// หยุดอัดเสียง + คืนทรัพยากรระบบ (ไม่เก็บไฟล์เสียงไว้ในเครื่อง)
    private func teardown() {
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        if engine.isRunning {
            engine.stop()
        }
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        level = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// ระดับเสียงแบบง่าย (0…1) สำหรับแสดงหลอดวัด — ไม่เก็บเสียงไว้ที่ไหน
    private static func level(of buffer: AVAudioPCMBuffer) -> Float {
        guard let channel = buffer.floatChannelData?[0] else { return 0 }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return 0 }
        let step = max(1, count / 256)
        var sum: Float = 0
        var sampled = 0
        var index = 0
        while index < count {
            sum += abs(channel[index])
            sampled += 1
            index += step
        }
        guard sampled > 0 else { return 0 }
        let average = sum / Float(sampled)
        return min(1, average * 6)
    }

    /// แปลข้อผิดพลาดเป็นคำที่ผู้ใช้เข้าใจ + บอกทางไปต่อ
    private static func thaiMessage(for error: Error) -> String {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return "ตอนนี้ออฟไลน์และเครื่องนี้ยังถอดเสียงในเครื่องไม่ได้ — ต่ออินเทอร์เน็ตแล้วลองใหม่ หรือพิมพ์แทน"
        }
        if nsError.domain == "kAFAssistantErrorDomain" {
            return "ถอดเสียงไม่สำเร็จชั่วคราว — ลองพูดอีกครั้งในที่เงียบขึ้น"
        }
        return "ถอดเสียงไม่สำเร็จ — ลองพูดอีกครั้งในที่เงียบขึ้น หรือพิมพ์แทนได้เลย"
    }
}
