//
//  ImageDownscaler.swift
//  iOS Agent Sandbox
//
//  ย่อรูปก่อนส่งให้โมเดล (เฟส 5) — ตามข้อกำหนดหน่วยความจำของเครื่อง RAM 2GB
//  - ด้านยาวไม่เกิน 1024 px, JPEG คุณภาพ 0.7
//  - ใช้ ImageIO อ่านแบบลดขนาด (thumbnail) จึง "ไม่โหลดรูปเต็มเข้าหน่วยความจำ"
//  - ใช้กับรูปจากคลิปบอร์ด/กล้อง/PHPicker
//

import Foundation
import ImageIO
import UIKit

enum ImageDownscaler {

    /// ด้านยาวที่สุดของรูปที่ส่งให้โมเดล
    static let maxPixelSize: CGFloat = 1_024
    /// คุณภาพ JPEG ที่ใช้ส่ง
    static let jpegQuality: CGFloat = 0.7
    /// ขนาดภาพย่อสำหรับชิปไฟล์แนบ
    static let thumbnailPixelSize: CGFloat = 96
    /// เพดาน base64 ต่อรูป (กันคำขอใหญ่เกิน) — ประมาณ 6 MB
    static let maxBase64Bytes = 6 * 1024 * 1024

    struct Result {
        let base64: String
        let dataURL: String
        let width: Int
        let height: Int
        let byteSize: Int
    }

    enum DownscaleError: LocalizedError {
        case unreadable
        case encodeFailed
        case tooLarge(Int)

        var errorDescription: String? {
            switch self {
            case .unreadable:
                return "อ่านรูปไม่สำเร็จ (ไฟล์อาจเสียหรือเป็นรูปแบบที่ระบบไม่รองรับ)"
            case .encodeFailed:
                return "แปลงรูปเป็น JPEG ไม่สำเร็จ"
            case .tooLarge(let bytes):
                return "รูปใหญ่เกินไปหลังย่อ: \(Attachment.sizeText(for: bytes)) (สูงสุด \(Attachment.sizeText(for: maxBase64Bytes)))"
            }
        }
    }

    /// ย่อรูปจากไฟล์และคืน base64 พร้อม data URL
    static func downscale(fileAt path: String,
                          maxPixel: CGFloat = maxPixelSize,
                          quality: CGFloat = jpegQuality) throws -> Result {
        guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) else {
            throw DownscaleError.unreadable
        }
        return try downscale(source: source, maxPixel: maxPixel, quality: quality)
    }

    /// ย่อรูปจากข้อมูลในหน่วยความจำ (ใช้กับคลิปบอร์ด)
    static func downscale(data: Data,
                          maxPixel: CGFloat = maxPixelSize,
                          quality: CGFloat = jpegQuality) throws -> Result {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw DownscaleError.unreadable
        }
        return try downscale(source: source, maxPixel: maxPixel, quality: quality)
    }

    /// ย่อรูปจาก UIImage (ใช้กับกล้อง)
    static func downscale(image: UIImage,
                          maxPixel: CGFloat = maxPixelSize,
                          quality: CGFloat = jpegQuality) throws -> Result {
        guard let cgImage = image.cgImage else { throw DownscaleError.unreadable }
        return try downscale(cgImage: cgImage, maxPixel: maxPixel, quality: quality)
    }

    /// ขนาดพิกเซลจริงของรูป (อ่านจาก metadata ไม่โหลดรูปเต็ม)
    static func pixelSize(ofImageAt path: String) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else {
            return nil
        }
        return (width, height)
    }

    /// สร้างภาพย่อขนาดเล็กสำหรับแสดงบนชิป (คืน PNG เพื่อให้โปร่งใสได้)
    static func thumbnailData(fileAt path: String, maxPixel: CGFloat = thumbnailPixelSize) -> Data? {
        guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
              let cgImage = thumbnail(from: source, maxPixel: maxPixel) else { return nil }
        return UIImage(cgImage: cgImage).pngData()
    }

    // MARK: - ภายใน

    private static func downscale(source: CGImageSource, maxPixel: CGFloat, quality: CGFloat) throws -> Result {
        guard let cgImage = thumbnail(from: source, maxPixel: maxPixel) else {
            throw DownscaleError.unreadable
        }
        return try encode(cgImage: cgImage, quality: quality)
    }

    private static func downscale(cgImage: CGImage, maxPixel: CGFloat, quality: CGFloat) throws -> Result {
        let longest = max(cgImage.width, cgImage.height)
        guard CGFloat(longest) > maxPixel else {
            return try encode(cgImage: cgImage, quality: quality)
        }
        // วาดใหม่ในบริบทขนาดย่อ (หน่วยความจำตามขนาดปลายทางเท่านั้น)
        let scale = maxPixel / CGFloat(longest)
        let width = max(1, Int(CGFloat(cgImage.width) * scale))
        let height = max(1, Int(CGFloat(cgImage.height) * scale))
        guard let context = CGContext(data: nil,
                                      width: width,
                                      height: height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw DownscaleError.unreadable
        }
        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let scaled = context.makeImage() else { throw DownscaleError.unreadable }
        return try encode(cgImage: scaled, quality: quality)
    }

    private static func thumbnail(from source: CGImageSource, maxPixel: CGFloat) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(64, maxPixel)
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private static func encode(cgImage: CGImage, quality: CGFloat) throws -> Result {
        let image = UIImage(cgImage: cgImage)
        guard let data = image.jpegData(compressionQuality: quality) else {
            throw DownscaleError.encodeFailed
        }
        guard data.count <= maxBase64Bytes else {
            throw DownscaleError.tooLarge(data.count)
        }
        let base64 = data.base64EncodedString()
        return Result(base64: base64,
                      dataURL: AttachmentMessageBuilder.dataURL(mimeType: "image/jpeg", base64: base64),
                      width: cgImage.width,
                      height: cgImage.height,
                      byteSize: data.count)
    }
}
