import AppKit
import KeydeskCore
import ImageIO
import UniformTypeIdentifiers

enum ProjectImage {
    static let maximumBytes = 512 * 1024
    static func valid(_ data: Data) -> Bool {
        guard data.count <= maximumBytes,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetType(source) as String? == UTType.png.identifier,
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int,
              let h = props[kCGImagePropertyPixelHeight] as? Int else { return false }
        return w > 0 && h > 0 && w <= 256 && h <= 256
    }
    static func load(_ url: URL) throws -> Data {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true, let bytes = values.fileSize,
              bytes > 0, bytes <= 20 * 1024 * 1024,
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 256,
                kCGImageSourceCreateThumbnailWithTransform: true
              ] as CFDictionary) else { throw ProjectImageError.invalid }
        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .png, properties: [:]), valid(data) else { throw ProjectImageError.invalid }
        return data
    }
}
enum ProjectImageError: LocalizedError {
    case invalid
    var errorDescription: String? { L10n.tr("이미지를 읽을 수 없습니다. 20MB 이하의 PNG, JPEG, HEIC 또는 앱 아이콘 파일을 선택하세요.", "The image could not be read. Choose a PNG, JPEG, HEIC, or app icon file of 20 MB or less.") }
}
