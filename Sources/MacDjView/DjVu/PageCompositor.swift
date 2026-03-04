import Foundation
import CoreGraphics

/// Combines mask, foreground, and background layers into a final CGImage.
/// DjVu images use bottom-up coordinates; this compositor flips to top-down for output.
enum PageCompositor {
    static func compose(
        width: Int, height: Int,
        background: IW44Image?,
        foreground: IW44Image?,
        mask: JB2Image?,
        fgPalette: FGbzPalette?,
        scale: Double
    ) throws -> CGImage {
        let scaledW = max(1, Int(Double(width) * scale))
        let scaledH = max(1, Int(Double(height) * scale))

        // Get background pixels (already flipped to top-down by IW44Image.getPixels())
        var bgPixels: [UInt8]?
        var bgW = 0, bgH = 0
        if let background {
            bgPixels = background.getPixels()
            bgW = background.width
            bgH = background.height
        }

        // Get foreground pixels (already flipped to top-down)
        var fgPixels: [UInt8]?
        var fgW = 0, fgH = 0
        if let foreground {
            fgPixels = foreground.getPixels()
            fgW = foreground.width
            fgH = foreground.height
        }

        // Render mask bitmap (in DjVu bottom-up coordinates)
        var maskBitmap: JB2Bitmap?
        if let mask {
            maskBitmap = mask.render()
        }

        // Pre-render foreground palette colors into a buffer (DjVu bottom-up coords)
        // so we do O(1) lookup per pixel instead of scanning all blits
        var fgColorBuf: [UInt8]?
        if let fgPalette, let mask {
            var buf = [UInt8](repeating: 0, count: width * height * 3)
            for (blitIdx, blit) in mask.blits.enumerated() {
                guard blitIdx < fgPalette.blitColors.count else { continue }
                let colorIdx = fgPalette.blitColors[blitIdx]
                guard colorIdx < fgPalette.colors.count else { continue }
                let color = fgPalette.colors[colorIdx]
                for by in 0..<blit.bitmap.height {
                    for bx in 0..<blit.bitmap.width {
                        if blit.bitmap.get(by, bx) != 0 {
                            let px = blit.x + bx
                            let py = blit.y + by
                            if px >= 0 && px < width && py >= 0 && py < height {
                                let i = (py * width + px) * 3
                                buf[i] = color.r; buf[i + 1] = color.g; buf[i + 2] = color.b
                            }
                        }
                    }
                }
            }
            fgColorBuf = buf
        }

        // Create CGContext and write pixels directly (avoids separate output buffer + copy)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: scaledW, height: scaledH,
                                  bitsPerComponent: 8, bytesPerRow: scaledW * 4,
                                  space: colorSpace,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = ctx.data else {
            throw DjVuError.decodingFailed("Failed to create graphics context")
        }

        let output = data.assumingMemoryBound(to: UInt8.self)

        for y in 0..<scaledH {
            for x in 0..<scaledW {
                let srcX = Double(x) / scale
                let srcY = Double(y) / scale
                let px = Int(srcX)
                let py = Int(srcY)

                let idx = (y * scaledW + x) * 4
                var r: UInt8 = 255, g: UInt8 = 255, b: UInt8 = 255

                // Check mask (DjVu bottom-up: flip py)
                let isMasked: Bool
                if let maskBitmap {
                    let djvuY = height - 1 - py  // flip to DjVu coords
                    isMasked = maskBitmap.get(djvuY, px) != 0
                } else {
                    isMasked = false
                }

                if isMasked {
                    // Use foreground color
                    if let fgColorBuf {
                        let djvuY = height - 1 - py
                        let i = (djvuY * width + px) * 3
                        r = fgColorBuf[i]; g = fgColorBuf[i + 1]; b = fgColorBuf[i + 2]
                    } else if let fgPixels {
                        // Sample from foreground IW44 image (already top-down)
                        let fgX = min(px * fgW / max(1, width), fgW - 1)
                        let fgY = min(py * fgH / max(1, height), fgH - 1)
                        let fgIdx = (fgY * fgW + fgX) * 3
                        if fgIdx + 2 < fgPixels.count {
                            r = fgPixels[fgIdx]; g = fgPixels[fgIdx + 1]; b = fgPixels[fgIdx + 2]
                        } else { r = 0; g = 0; b = 0 }
                    } else {
                        r = 0; g = 0; b = 0
                    }
                } else {
                    // Use background (already top-down)
                    if let bgPixels {
                        let bgX = min(px * bgW / max(1, width), bgW - 1)
                        let bgY = min(py * bgH / max(1, height), bgH - 1)
                        let bgIdx = (bgY * bgW + bgX) * 3
                        if bgIdx + 2 < bgPixels.count {
                            r = bgPixels[bgIdx]; g = bgPixels[bgIdx + 1]; b = bgPixels[bgIdx + 2]
                        }
                    }
                }

                output[idx] = r; output[idx + 1] = g; output[idx + 2] = b; output[idx + 3] = 255
            }
        }

        guard let image = ctx.makeImage() else {
            throw DjVuError.decodingFailed("Failed to create image")
        }

        return image
    }
}
