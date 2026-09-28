//
//  AttachmentChipView.swift
//  iOS Agent Sandbox
//
//  ชิปไฟล์แนบ (เฟส 5): รูปย่อ/ไอคอน + ชื่อไฟล์ + ขนาด + ปุ่มลบ
//  แสดงทั้งในช่องพิมพ์ (ก่อนส่ง) และในบับเบิลข้อความที่ส่งแล้ว
//

#if canImport(UIKit)
import UIKit
#endif
import SwiftUI

struct AttachmentChipView: View {

    let attachment: Attachment
    /// true = แสดงปุ่มลบ (ใช้ในช่องพิมพ์)
    var showsRemoveButton: Bool = false
    /// ธีมสีของชิป (ในบับเบิลผู้ใช้จะใช้สีขาวโปร่งแสง)
    var style: Style = .standard
    var onRemove: (() -> Void)?
    var onTap: (() -> Void)?

    enum Style {
        case standard
        case onAccent

        var titleColor: Color { self == .standard ? .primary : .white }
        var subtitleColor: Color { self == .standard ? .secondary : Color.white.opacity(0.85) }
        var background: Color { self == .standard ? Color(UIColor.secondarySystemBackground) : Color.white.opacity(0.18) }
    }

    @State private var thumbnail: UIImage?

    var body: some View {
        HStack(spacing: 8) {
            thumbnailView

            VStack(alignment: .leading, spacing: 1) {
                Text(attachment.originalName)
                    .font(.caption)
                    .foregroundColor(style.titleColor)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(attachment.chipSubtitle)
                    .font(.caption2)
                    .foregroundColor(style.subtitleColor)
                    .lineLimit(1)
            }

            if showsRemoveButton {
                Button {
                    onRemove?()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(style.subtitleColor)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("เอา \(attachment.originalName) ออก")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: 240, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(style.background)
        )
        .contentShape(Rectangle())
        .onTapGesture { onTap?() }
        .onAppear(perform: loadThumbnailIfNeeded)
    }

    @ViewBuilder
    private var thumbnailView: some View {
        if let image = thumbnail {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 34, height: 34)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        } else {
            Image(systemName: attachment.kind.iconName)
                .font(.system(size: 16))
                .foregroundColor(style.subtitleColor)
                .frame(width: 34, height: 34)
        }
    }

    /// โหลดรูปย่อเฉพาะไฟล์รูป และทำในคิวเบื้องหลังเพื่อไม่ให้ UI กระตุก
    private func loadThumbnailIfNeeded() {
        guard thumbnail == nil, attachment.isImage else { return }
        let path = attachment.path
        DispatchQueue.global(qos: .utility).async {
            let data = ImageDownscaler.thumbnailData(fileAt: path)
            guard let data = data, let image = UIImage(data: data) else { return }
            DispatchQueue.main.async {
                thumbnail = image
            }
        }
    }
}

/// แถวชิปไฟล์แนบแบบเลื่อนแนวนอน (ใช้ในช่องพิมพ์)
struct AttachmentChipRow: View {

    let attachments: [Attachment]
    var onRemove: ((Attachment) -> Void)?
    var onTap: ((Attachment) -> Void)?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(attachments) { attachment in
                    AttachmentChipView(attachment: attachment,
                                       showsRemoveButton: onRemove != nil,
                                       onRemove: { onRemove?(attachment) },
                                       onTap: { onTap?(attachment) })
                }
            }
            .padding(.horizontal, 2)
        }
        .frame(height: 50)
    }
}
