import AVFoundation
import Foundation
import ImageIO
import OSLog
import UniformTypeIdentifiers

/// A small JPEG to show in a block while native code uploads the real file.
enum MediaPreview {
    /// The longest side of a preview, in pixels.
    static let maxPixelSize = 1600

    /// Writes a preview of the image or video at `fileURL` next to it, and returns
    /// where. `nil` for other files, or when the file can't be decoded.
    static func write(for fileURL: URL, mimeType: String) async -> URL? {
        let data: Data?
        if mimeType.hasPrefix("image/") {
            data = imagePreview(for: fileURL)
        } else if mimeType.hasPrefix("video/") {
            data = await videoPreview(for: fileURL)
        } else {
            data = nil
        }
        guard let data else { return nil }
        let previewURL = fileURL.deletingLastPathComponent().appending(component: ".preview.jpg")
        do {
            try data.write(to: previewURL)
            return previewURL
        } catch {
            Logger.media.error("Failed to write a preview of \(fileURL.lastPathComponent): \(error)")
            return nil
        }
    }

    private static func imagePreview(for fileURL: URL) -> Data? {
        guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
              ] as CFDictionary) else {
            return nil
        }
        return jpeg(image)
    }

    private static func videoPreview(for fileURL: URL) async -> Data? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: fileURL))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxPixelSize, height: maxPixelSize)
        guard let (image, _) = try? await generator.image(at: .zero) else { return nil }
        return jpeg(image)
    }

    private static func jpeg(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
