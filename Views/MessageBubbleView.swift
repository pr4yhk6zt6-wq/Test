//
//  MessageBubbleView.swift
//  iOS Agent Sandbox
//
//  Bubble ข้อความในแชท + เมนูกดค้าง (คัดลอก / แชร์ / ลบ)
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct MessageBubbleView: View {

    let message: ChatMessage
    let fontScale: Double
    /// true = บับเบิลนี้กำลังสตรีม/คิดอยู่ (แสดงสปินเนอร์) — งานที่จบแล้วต้องไม่หมุนค้าง
    var isThinking: Bool = false
    let onDelete: () -> Void
    let onShare: (String) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if message.role == .user {
                Spacer(minLength: 40)
                userBubble
            } else {
                assistantBubble
                Spacer(minLength: 16)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - User

    private var userBubble: some View {
        VStack(alignment: .trailing, spacing: 6) {
            // ไฟล์แนบที่ผู้ใช้ส่งมา (เฟส 5) — แสดงเป็นชิปพร้อมรูปย่อ เหนือข้อความ
            if let attachments = message.attachments, !attachments.isEmpty {
                ForEach(attachments) { attachment in
                    AttachmentChipView(attachment: attachment, style: .onAccent)
                }
            }

            Text(message.text)
                .font(.system(size: 16 * fontScale))
                .foregroundColor(.white)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.accentColor)
                )
        }
        .contextMenu {
                Button {
                    copyToPasteboard(message.text)
                } label: {
                    Label("คัดลอก", systemImage: "doc.on.doc")
                }
                Button {
                    onShare(message.text)
                } label: {
                    Label("แชร์", systemImage: "square.and.arrow.up")
                }
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("ลบข้อความ", systemImage: "trash")
                }
            }
    }

    // MARK: - Assistant / System

    private var assistantBubble: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(timeText)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            if message.isTextEmpty {
                if isThinking {
                    HStack(spacing: 6) {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("…")
                            .foregroundColor(.secondary)
                    }
                    .frame(minHeight: 24)
                } else {
                    Text("(ไม่มีข้อความ)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .frame(minHeight: 20)
                }
            } else {
                MessageContentView(markdown: message.text, fontScale: fontScale)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(UIColor.secondarySystemBackground))
        )
        .contextMenu {
            Button {
                copyToPasteboard(message.text)
            } label: {
                Label("คัดลอก", systemImage: "doc.on.doc")
            }
            Button {
                onShare(message.text)
            } label: {
                Label("แชร์", systemImage: "square.and.arrow.up")
            }
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("ลบข้อความ", systemImage: "trash")
            }
        }
    }

    private var timeText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "th_TH")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: message.createdAt)
    }

    private func copyToPasteboard(_ text: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }
}
