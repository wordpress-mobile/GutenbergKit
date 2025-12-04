import Foundation
import SwiftUI

#if canImport(UIKit)
import UIKit

public typealias PlatformViewController = UIViewController
public typealias PlatformImage = UIImage
public typealias PlatformColor = UIColor

extension Image {
    init(platformImage: PlatformImage) {
        self.init(uiImage: platformImage)
    }
}

extension Color {
    init(platformColor: PlatformColor) {
        self = Color(uiColor: platformColor)
    }
}

#endif

#if canImport(AppKit)
import AppKit

public typealias PlatformViewController = NSViewController
public typealias PlatformImage = NSImage
public typealias PlatformColor = NSColor

extension PlatformImage {

    convenience init?(systemImage: String) {
        self.init(systemSymbolName: systemImage, accessibilityDescription: nil)
    }

    convenience init?(systemName: String) {
        self.init(systemSymbolName: systemName, accessibilityDescription: nil)
    }

    var cgImage: CGImage? {
        self.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    func byPreparingThumbnail(ofSize: CGSize) async -> PlatformImage? {
        self
    }

    func byPreparingForDisplay() async -> PlatformImage? {
        self
    }

    func jpegData(compressionQuality: CGFloat) -> Data? {
        Data()
    }
}

extension Image {
    init(platformImage: PlatformImage) {
        self.init(nsImage: platformImage)
    }
}

extension Color {
    init(platformColor: PlatformColor) {
        self = Color(nsColor: platformColor)
    }
}

extension PlatformColor {
    static let systemBackground = NSColor.red
    static let tertiarySystemBackground = NSColor.purple
    static let secondarySystemBackground = NSColor.orange
    static let label = NSColor.magenta
    static let opaqueSeparator = NSColor.purple
}

#endif
