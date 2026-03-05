import SwiftUI

#if os(macOS)
import AppKit
typealias PlatformImage = NSImage
#else
import UIKit
typealias PlatformImage = UIImage
#endif

extension PlatformImage {
    convenience init(fromCGImage cgImage: CGImage) {
        #if os(macOS)
        self.init(cgImage: cgImage, size: NSSize(
            width: CGFloat(cgImage.width),
            height: CGFloat(cgImage.height)
        ))
        #else
        self.init(cgImage: cgImage)
        #endif
    }
}

extension Image {
    init(platformImage: PlatformImage) {
        #if os(macOS)
        self.init(nsImage: platformImage)
        #else
        self.init(uiImage: platformImage)
        #endif
    }
}

extension Color {
    static var platformBackground: Color {
        #if os(macOS)
        Color(nsColor: .controlBackgroundColor)
        #else
        Color(uiColor: .systemBackground)
        #endif
    }
}
