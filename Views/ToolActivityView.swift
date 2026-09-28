//
//  ToolActivityView.swift
//  iOS Agent Sandbox
//
//  การ์ดแสดงการทำงานของ tool หนึ่งครั้งในหน้าแชท (เฟส 2)
//  ย่อไว้ก่อนเพื่อไม่ให้บังบทสนทนา — แตะเพื่อกางดู arguments + ผลลัพธ์เต็ม และคัดลอกได้
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct ToolActivityView: View {

    let message: ChatMessage
    let fontScale: Double
    let onShare: (String) -> Void

    @State private var isExpanded: Bool = false
    @State private var copied: Bool = false

    private var isError: Bool {
        message.toolIsError ?? false
    }

    private var symbolName: String {
        if isError {
            return "exclamationmark.triangle"
        }
        switch message.name {
        case "read_file": return "doc.text"
        case "write_file": return "square.and.pencil"
        case "list_directory": return "folder"
        case "search_files": return "magnifyingglass"
        case "execute_shell": return "terminal"
        case "http_request": return "arrow.up.arrow.down.circle"
        case "download_file": return "arrow.down.circle"
        case "web_search": return "magnifyingglass.circle"
        case "fetch_webpage": return "globe"
        default: return "wrench.and.screwdriver"
        }
    }

    private var durationText: String {
        guard let duration = message.toolDuration else { return "" }
        if duration < 1 {
            return String(format: "%.0f มิลลิวินาที", duration * 1000)
        }
        return String(format: "%.2f วินาที", duration)
    }

    private var statusText: String {
        if isError {
            return "ผิดพลาด"
        }
        return "สำเร็จ"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if isExpanded {
                Divider()
                details
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(UIColor.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke((isError ? Color.red : Color.gray).opacity(0.35), lineWidth: 0.5)
        )
        .padding(.vertical, 2)
    }

    // MARK: - หัวการ์ด (แตะเพื่อกาง)

    private var header: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                isExpanded.toggle()
            }
            #if canImport(UIKit)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: symbolName)
                        .font(.footnote)
                        .foregroundColor(isError ? .red : .accentColor)
                        .frame(width: 20)
                    Text(message.toolDisplayName)
                        .font(.system(size: 14 * fontScale, weight: .semibold))
                        .foregroundColor(.primary)
                    Spacer(minLength: 0)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                HStack(spacing: 8) {
                    Text(statusText)
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(isError ? .red : .green)
                    if !durationText.isEmpty {
                        Text("• \(durationText)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    if message.text.contains("ตัดทอน") {
                        Text("• ตัดทอนผลลัพธ์")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                }
                if !isExpanded {
                    Text(message.text.split(separator: "\n").first.map(String.init) ?? "")
                        .font(.system(size: 12 * fontScale, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(message.toolDisplayName) \(statusText) — แตะเพื่อ\(isExpanded ? "ย่อ" : "ขยาย")")
    }

    // MARK: - รายละเอียดที่กางออก

    private var details: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let arguments = message.toolArguments, !arguments.isEmpty {
                labeledBlock(title: "arguments", text: arguments, color: Color(UIColor.tertiarySystemBackground))
            }
            labeledBlock(title: isError ? "ข้อผิดพลาด" : "ผลลัพธ์",
                         text: message.text,
                         color: isError ? Color.red.opacity(0.08) : Color(UIColor.tertiarySystemBackground))

            HStack(spacing: 10) {
                Button {
                    copyToPasteboard(message.text)
                } label: {
                    Label(copied ? "คัดลอกแล้ว" : "คัดลอกผลลัพธ์",
                          systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.caption)
                        .frame(minHeight: 32)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("คัดลอกผลลัพธ์ของ tool")

                Button {
                    onShare("\(message.toolDisplayName)\n\(message.text)")
                } label: {
                    Label("แชร์", systemImage: "square.and.arrow.up")
                        .font(.caption)
                        .frame(minHeight: 32)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("แชร์ผลลัพธ์ของ tool")
            }
        }
        .padding(10)
    }

    private func labeledBlock(title: String, text: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundColor(.secondary)
            ScrollView(.vertical, showsIndicators: true) {
                Text(text)
                    .font(.system(size: 12 * fontScale, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .frame(maxHeight: 260)
            .background(color)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private func copyToPasteboard(_ text: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
        copied = true
    }
}
