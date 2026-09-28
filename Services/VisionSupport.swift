//
//  VisionSupport.swift
//  iOS Agent Sandbox
//
//  ประเมินว่าโมเดลที่ผู้ใช้เลือก "รับรูปภาพ" ได้หรือไม่ (เฟส 5)
//  - ใช้รายการชื่อโมเดลที่รู้จัก (จับแบบ substring)
//  - ผู้ใช้ override ได้ในหน้าตั้งค่า (อัตโนมัติ / รับรูป / ไม่รับรูป)
//  - เป็น Foundation ล้วน จึงทดสอบได้ทุกแพลตฟอร์ม
//

import Foundation

/// ตัวเลือกการตัดสินใจของผู้ใช้
enum VisionOverride: String, Codable, CaseIterable {
    case automatic
    case always
    case never

    var thaiName: String {
        switch self {
        case .automatic: return "อัตโนมัติ"
        case .always: return "รับรูปแน่นอน"
        case .never: return "ไม่รับรูป"
        }
    }

    var detail: String {
        switch self {
        case .automatic: return "ให้แอปเดาจากชื่อโมเดล (ค่าเริ่มต้น)"
        case .always: return "บังคับให้ส่งรูปเป็น image_url เสมอ"
        case .never: return "ส่งเฉพาะพาธไฟล์เสมอ (ประหยัดโทเคน)"
        }
    }
}

enum VisionSupport {

    /// คำที่บ่งชี้ว่าโมเดลรับรูปได้ (ตัวพิมพ์เล็กทั้งหมด)
    static let visionMarkers: [String] = [
        // ตระกูลที่รองรับรูปโดยทั่วไป
        "gpt-4o", "gpt-4.1", "gpt-4-turbo", "gpt-5", "o3", "o4-mini", "chatgpt-4o",
        "claude-3", "claude-4", "claude-sonnet", "claude-opus", "claude-haiku",
        "gemini", "gemma-3", "grok-2-vision", "grok-4", "grok-vision",
        "qwen-vl", "qwen2-vl", "qwen2.5-vl", "qwen3-vl", "qwen3-coder-vl", "qvq",
        "llama-4", "llama-3.2-vision", "llama-3.2-11b-vision", "llama-3.2-90b-vision",
        "pixtral", "mistral-small-3", "magistral", "internvl", "llava", "moondream",
        "phi-4-multimodal", "phi-3.5-vision", "glm-4v", "glm-4.1v", "yi-vision",
        "minicpm-v", "step-1v", "ernie-4.5-vl", "kimi-vl", "nemotron-nano-vl", "idefics",
        "paligemma", "vl-", "-vl", "vision", "multimodal"
    ]

    /// คำที่บ่งชี้ว่าเป็นโมเดลข้อความล้วน (กันคำว่า "vision" หลุดจากชื่ออื่น)
    static let textOnlyMarkers: [String] = [
        "deepseek-r1", "deepseek-v3", "deepseek-chat", "codestral", "qwen3-coder", "coder",
        "command-r", "north-mini-code", "hermes", "nous", "wizardlm", "dolphin", "mythomax"
    ]

    /// ตัดสินจากชื่อโมเดลเท่านั้น
    static func markerDecision(modelID: String) -> Bool {
        let lower = modelID.lowercased()
        // คำที่ชี้ "ข้อความล้วน" ต้องเช็คก่อน เพื่อไม่ให้ "coder-vision" ถูกตีความผิด
        for marker in textOnlyMarkers where lower.contains(marker) {
            if !lower.contains("vision") && !lower.contains("-vl") { return false }
        }
        for marker in visionMarkers where lower.contains(marker) {
            return true
        }
        return false
    }

    /// ผลรวมของ marker + ค่าที่ผู้ใช้เลือก
    static func supportsImages(modelID: String, override: VisionOverride) -> Bool {
        switch override {
        case .always: return true
        case .never: return false
        case .automatic: return markerDecision(modelID: modelID)
        }
    }

    /// ข้อความอธิบายสั้น ๆ สำหรับแสดงในหน้าตั้งค่า
    static func explanation(modelID: String, override: VisionOverride) -> String {
        if modelID.isEmpty { return "ยังไม่ได้เลือกโมเดล" }
        let detected = markerDecision(modelID: modelID)
        switch override {
        case .automatic:
            return detected ? "เดาว่าโมเดลนี้รับรูปได้ → จะส่งรูปเป็น image_url"
                           : "เดาว่าโมเดลนี้รับรูปไม่ได้ → จะส่งเฉพาะพาธไฟล์"
        case .always:
            return "บังคับส่งรูปเสมอ (ถ้าโมเดลไม่รับ อาจได้ error จากผู้ให้บริการ)"
        case .never:
            return "จะส่งเฉพาะพาธไฟล์เสมอ (Agent เปิดอ่านไฟล์เองได้)"
        }
    }
}
