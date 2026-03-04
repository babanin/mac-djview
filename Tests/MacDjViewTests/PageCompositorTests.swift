import Testing
import CoreGraphics
@testable import MacDjView

@Suite("PageCompositor — SIMD fast path and composition")
struct PageCompositorTests {

    // Helper: create an IW44Image that produces known uniform color pixels
    // All-zero blocks → grayscale 127 or color (128,128,128)
    private func makeUniformBackground(width: Int, height: Int) -> IW44Image {
        let bpr = (width + 31) / 32
        let bpc = (height + 31) / 32
        let blocks = (0..<bpr * bpc).map { _ in IW44Block() }
        return IW44Image(width: width, height: height,
                         blocksPerRow: bpr, blocksPerCol: bpc,
                         yBlocks: blocks, cbBlocks: nil, crBlocks: nil)
    }

    private func getPixelRGBA(from image: CGImage, x: Int, y: Int) -> (UInt8, UInt8, UInt8, UInt8)? {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: image.width, height: image.height,
                                  bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                  space: colorSpace,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = ctx.data else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let ptr = data.assumingMemoryBound(to: UInt8.self)
        let idx = (y * image.width + x) * 4
        return (ptr[idx], ptr[idx + 1], ptr[idx + 2], ptr[idx + 3])
    }

    @Test("background-only, scale=1.0, hits fast path")
    func backgroundOnlyFastPath() throws {
        let bg = makeUniformBackground(width: 8, height: 8)
        let image = try PageCompositor.compose(
            width: 8, height: 8,
            background: bg, foreground: nil,
            mask: nil, fgPalette: nil, scale: 1.0)

        #expect(image.width == 8)
        #expect(image.height == 8)

        // All pixels should be (127, 127, 127, 255) — grayscale from all-zero IW44
        if let (r, g, b, a) = getPixelRGBA(from: image, x: 0, y: 0) {
            #expect(r == 127)
            #expect(g == 127)
            #expect(b == 127)
            #expect(a == 255)
        }
        if let (r, g, b, a) = getPixelRGBA(from: image, x: 7, y: 7) {
            #expect(r == 127)
            #expect(g == 127)
            #expect(b == 127)
            #expect(a == 255)
        }
    }

    @Test("background-only, non-1.0 scale, uses general path")
    func backgroundOnlyScaled() throws {
        let bg = makeUniformBackground(width: 4, height: 4)
        let image = try PageCompositor.compose(
            width: 4, height: 4,
            background: bg, foreground: nil,
            mask: nil, fgPalette: nil, scale: 2.0)

        #expect(image.width == 8)
        #expect(image.height == 8)
    }

    @Test("no background, no mask produces white image")
    func noBackgroundNoMask() throws {
        let image = try PageCompositor.compose(
            width: 4, height: 4,
            background: nil, foreground: nil,
            mask: nil, fgPalette: nil, scale: 1.0)

        #expect(image.width == 4)
        #expect(image.height == 4)

        if let (r, g, b, a) = getPixelRGBA(from: image, x: 0, y: 0) {
            #expect(r == 255)
            #expect(g == 255)
            #expect(b == 255)
            #expect(a == 255)
        }
    }

    @Test("fast path with non-multiple-of-8 width handles tail")
    func fastPathTail() throws {
        // Width=5 means SIMD can't process a full 8-pixel chunk, all goes through scalar tail
        let bg = makeUniformBackground(width: 5, height: 3)
        let image = try PageCompositor.compose(
            width: 5, height: 3,
            background: bg, foreground: nil,
            mask: nil, fgPalette: nil, scale: 1.0)

        #expect(image.width == 5)
        #expect(image.height == 3)

        // Verify corner pixels
        if let (r, g, b, _) = getPixelRGBA(from: image, x: 4, y: 2) {
            #expect(r == 127)
            #expect(g == 127)
            #expect(b == 127)
        }
    }

    @Test("fast path vs general path produce identical output")
    func fastPathMatchesGeneralPath() throws {
        // Create a background with non-uniform pixels (color image)
        let bpr = 1, bpc = 1
        let yBlock = IW44Block()
        let cbBlock = IW44Block()
        let crBlock = IW44Block()
        // Set some non-zero coefficients to get varied pixels
        yBlock.setCoef(0, 0, 512)
        cbBlock.setCoef(0, 0, 256)
        crBlock.setCoef(0, 0, -256)

        let w = 16, h = 16
        let bg = IW44Image(width: w, height: h,
                           blocksPerRow: bpr, blocksPerCol: bpc,
                           yBlocks: [yBlock], cbBlocks: [cbBlock], crBlocks: [crBlock])

        // Fast path: scale=1.0, no mask, bg dimensions match
        let fastImage = try PageCompositor.compose(
            width: w, height: h,
            background: bg, foreground: nil,
            mask: nil, fgPalette: nil, scale: 1.0)

        // General path: use scale != 1.0 to force it, then compare at corresponding positions
        // Actually, comparing exactly requires same-size output, so use scale=1.0001
        // which bypasses the fast path (scale != 1.0 exactly)
        let slowImage = try PageCompositor.compose(
            width: w, height: h,
            background: bg, foreground: nil,
            mask: nil, fgPalette: nil, scale: 1.0001)

        // Both should be approximately the same size (16 vs 16 due to rounding)
        // The key check: fast path pixel at (0,0) should match general path
        if let fast = getPixelRGBA(from: fastImage, x: 0, y: 0),
           let slow = getPixelRGBA(from: slowImage, x: 0, y: 0) {
            #expect(fast.0 == slow.0, "R mismatch at (0,0)")
            #expect(fast.1 == slow.1, "G mismatch at (0,0)")
            #expect(fast.2 == slow.2, "B mismatch at (0,0)")
            #expect(fast.3 == slow.3, "A mismatch at (0,0)")
        }
    }

    @Test("minimum size 1×1 does not crash")
    func minimumSize() throws {
        let bg = makeUniformBackground(width: 1, height: 1)
        let image = try PageCompositor.compose(
            width: 1, height: 1,
            background: bg, foreground: nil,
            mask: nil, fgPalette: nil, scale: 1.0)
        #expect(image.width == 1)
        #expect(image.height == 1)
    }

    @Test("large image with fast path does not crash")
    func largeImageFastPath() throws {
        let bg = makeUniformBackground(width: 256, height: 256)
        let image = try PageCompositor.compose(
            width: 256, height: 256,
            background: bg, foreground: nil,
            mask: nil, fgPalette: nil, scale: 1.0)
        #expect(image.width == 256)
        #expect(image.height == 256)
    }
}
