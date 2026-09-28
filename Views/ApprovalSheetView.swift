//
//  ApprovalSheetView.swift
//  iOS Agent Sandbox
//
//  หน้าต่างขออนุมัติก่อน Agent ลงมือทำสิ่งที่เปลี่ยนเครื่อง (เฟส 2)
//  แสดง: ชื่อ tool, สรุปว่าทำอะไร, arguments, รายละเอียด (เช่น URL + ขนาดไฟล์), เหตุผลความเสี่ยง
//  ปุ่ม: อนุญาตครั้งนี้ / อนุญาตตลอดเซสชัน / ไม่อนุญาต
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct ApprovalSheetView: View {

    let request: ApprovalRequest
    let onDecision: (ApprovalDecision) -> Void

    @Environment(\.presentationMode) private var presentationMode

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    headerCard
                    if let detail = request.detail, !detail.isEmpty {
                        detailCard(detail)
                    }
                    argumentsCard
                    riskCard
                    explanation
                }
                .padding(14)
            }
            .navigationTitle("ขออนุมัติ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        decide(.deny)
                    } label: {
                        Text("ไม่อนุญาต")
                            .frame(minHeight: 44)
                    }
                    .foregroundColor(.red)
                }
            }
            .safeAreaInset(edge: .bottom) {
                actionButtons
            }
        }
        .navigationViewStyle(.stack)
    }

    // MARK: - ส่วนต่าง ๆ

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: request.isDestructive ? "exclamationmark.triangle.fill" : "hand.raised.fill")
                    .foregroundColor(request.isDestructive ? .red : .orange)
                Text(request.thaiLabel)
                    .font(.headline)
                Spacer(minLength: 0)
                Text(request.toolName)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            Text(request.summary)
                .font(.footnote)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(UIColor.secondarySystemBackground))
        )
    }

    private func detailCard(_ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("รายละเอียด", systemImage: "info.circle")
                .font(.subheadline.weight(.semibold))
            Text(detail)
                .font(.system(.footnote, design: .monospaced))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(UIColor.secondarySystemBackground))
        )
    }

    private var argumentsCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("สิ่งที่ Agent จะทำ", systemImage: "curlybraces")
                .font(.subheadline.weight(.semibold))
            ScrollView(.horizontal, showsIndicators: true) {
                Text(request.argumentsText)
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(8)
            }
            .frame(maxHeight: 180)
            .background(Color(UIColor.tertiarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(UIColor.secondarySystemBackground))
        )
    }

    @ViewBuilder
    private var riskCard: some View {
        if request.risk.level != .normal {
            VStack(alignment: .leading, spacing: 6) {
                Label("ความเสี่ยงที่ตรวจพบ: \(request.risk.level.thaiName)",
                      systemImage: request.isDestructive ? "exclamationmark.octagon.fill" : "exclamationmark.triangle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(request.isDestructive ? .red : .orange)
                ForEach(Array(request.risk.reasons.enumerated()), id: \.offset) { _, reason in
                    Text("• \(reason)")
                        .font(.footnote)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill((request.isDestructive ? Color.red : Color.orange).opacity(0.12))
            )
        }
    }

    private var explanation: some View {
        Text("โหมดอนุมัติเปิดอยู่ (ค่าเริ่มต้น) — Agent จะถามก่อนรันคำสั่ง shell และก่อนเขียนทับไฟล์ใน path ของระบบ " +
             "ทุกครั้ง ไม่จำคำตอบเก่า ถ้าไม่อยากให้ถามเลยปิดได้ที่แท็บตั้งค่า > Agent")
            .font(.caption)
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var actionButtons: some View {
        VStack(spacing: 8) {
            Button {
                decide(.allowOnce)
            } label: {
                Label("อนุญาตครั้งนี้", systemImage: "checkmark.circle.fill")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)

            Button {
                decide(.deny)
            } label: {
                Label("ไม่อนุญาตครั้งนี้", systemImage: "xmark.circle")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)

            Text("การอนุญาตมีผลเฉพาะครั้งนี้เท่านั้น — ครั้งต่อไปที่ต้องอนุมัติ ระบบจะถามใหม่เสมอ")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(Color(UIColor.systemBackground))
    }

    // MARK: - ตอบคำขอ

    private func decide(_ decision: ApprovalDecision) {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: decision == .deny ? .rigid : .light).impactOccurred()
        #endif
        onDecision(decision)
        presentationMode.wrappedValue.dismiss()
    }
}
