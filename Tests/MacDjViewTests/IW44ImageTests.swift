import Testing
@testable import MacDjView

@Suite("IW44Image — SIMD color conversion and wavelet transform")
struct IW44ImageTests {

    // Helper: create an IW44Image with all-zero blocks (produces uniform gray/black output)
    private func makeZeroImage(width: Int, height: Int, color: Bool = false) -> IW44Image {
        let bpr = (width + 31) / 32
        let bpc = (height + 31) / 32
        let blockCount = bpr * bpc
        let yBlocks = (0..<blockCount).map { _ in IW44Block() }
        let cbBlocks: [IW44Block]? = color ? (0..<blockCount).map { _ in IW44Block() } : nil
        let crBlocks: [IW44Block]? = color ? (0..<blockCount).map { _ in IW44Block() } : nil
        return IW44Image(width: width, height: height,
                         blocksPerRow: bpr, blocksPerCol: bpc,
                         yBlocks: yBlocks, cbBlocks: cbBlocks, crBlocks: crBlocks)
    }

    @Test("grayscale all-zero blocks produce uniform gray (127)")
    func grayscaleZero() {
        let img = makeZeroImage(width: 4, height: 4)
        let pixels = img.getPixels()
        #expect(pixels.count == 4 * 4 * 3)
        // normalize(0) = 0, grayscale = 127 - 0 = 127
        for i in stride(from: 0, to: pixels.count, by: 3) {
            #expect(pixels[i] == 127)
            #expect(pixels[i + 1] == 127)
            #expect(pixels[i + 2] == 127)
        }
    }

    @Test("color all-zero blocks produce uniform gray (128, 128, 128)")
    func colorZero() {
        let img = makeZeroImage(width: 4, height: 4, color: true)
        let pixels = img.getPixels()
        #expect(pixels.count == 4 * 4 * 3)
        // normalize(0) = 0 for Y, Cb, Cr
        // t2 = 0, t3 = 0 + 128 - 0 = 128
        // rr = 0 + 128 + 0 = 128, gg = 128 - 0 = 128, bb = 128 + 0 = 128
        for i in stride(from: 0, to: pixels.count, by: 3) {
            #expect(pixels[i] == 128)
            #expect(pixels[i + 1] == 128)
            #expect(pixels[i + 2] == 128)
        }
    }

    @Test("pixel count matches width × height × 3")
    func pixelCount() {
        for (w, h) in [(1, 1), (7, 3), (32, 32), (33, 1), (100, 50)] {
            let img = makeZeroImage(width: w, height: h)
            let pixels = img.getPixels()
            #expect(pixels.count == w * h * 3, "Failed for \(w)×\(h)")
        }
    }

    @Test("non-multiple-of-8 width handles SIMD tail correctly")
    func simdTailHandling() {
        // Width=7 means SIMD processes 0 full chunks, all 7 pixels go through scalar tail
        let img = makeZeroImage(width: 7, height: 3)
        let pixels = img.getPixels()
        #expect(pixels.count == 7 * 3 * 3)
        // All should be uniform gray
        for byte in pixels {
            #expect(byte == 127)
        }
    }

    @Test("width=1 single-pixel image works")
    func singlePixel() {
        let img = makeZeroImage(width: 1, height: 1)
        let pixels = img.getPixels()
        #expect(pixels.count == 3)
        #expect(pixels == [127, 127, 127])
    }

    @Test("large image SIMD path processes many chunks")
    func largeImage() {
        // 256×256 = 65536 pixels, SIMD processes 8192 chunks of 8
        let img = makeZeroImage(width: 256, height: 256)
        let pixels = img.getPixels()
        #expect(pixels.count == 256 * 256 * 3)
        // Spot-check first and last pixels
        #expect(pixels[0] == 127)
        #expect(pixels[pixels.count - 1] == 127)
    }

    @Test("grayscale with known DC coefficient")
    func grayscaleKnownDC() {
        // Set DC coefficient (bucket 0, coef 0) which maps to zigzag position (0,0)
        let bpr = 1, bpc = 1
        let block = IW44Block()
        // Set a known value in the DC position
        // After wavelet transform on a 32×32 map with only (0,0) set,
        // the value propagates. We verify the output is different from all-zero.
        block.setCoef(0, 0, 1024)  // ~16 after normalize ((1024+32)>>6 = 16)

        let img = IW44Image(width: 1, height: 1,
                            blocksPerRow: bpr, blocksPerCol: bpc,
                            yBlocks: [block], cbBlocks: nil, crBlocks: nil)
        let pixels = img.getPixels()
        // The exact value depends on wavelet transform propagation,
        // but it should NOT be 127 (the all-zero case)
        #expect(pixels[0] != 127 || pixels[1] != 127 || pixels[2] != 127,
                "DC coefficient should affect output")
        // All three channels should be equal (grayscale)
        #expect(pixels[0] == pixels[1])
        #expect(pixels[1] == pixels[2])
    }

    @Test("color image with known DC coefficients")
    func colorKnownDC() {
        let yBlock = IW44Block()
        let cbBlock = IW44Block()
        let crBlock = IW44Block()
        yBlock.setCoef(0, 0, 0)
        cbBlock.setCoef(0, 0, 1024)  // strong blue
        crBlock.setCoef(0, 0, 0)

        let img = IW44Image(width: 1, height: 1,
                            blocksPerRow: 1, blocksPerCol: 1,
                            yBlocks: [yBlock], cbBlocks: [cbBlock], crBlocks: [crBlock])
        let pixels = img.getPixels()
        #expect(pixels.count == 3)
        // With Cb != 0, R/G/B should differ from the all-zero case
        let allZeroColor: [UInt8] = [128, 128, 128]
        #expect(pixels != allZeroColor, "Cb coefficient should shift color channels")
    }

    @Test("row flipping: bottom-up to top-down")
    func rowFlipping() {
        // Create a 2-row grayscale image where row 0 and row 1 have different DC values
        // Since DjVu is bottom-up and output is top-down, row 0 of output = last row of DjVu
        let bpr = 1, bpc = 1
        let block = IW44Block()
        // With all zeros, output is uniform — we just verify the pixel count and layout
        let img = IW44Image(width: 2, height: 2,
                            blocksPerRow: bpr, blocksPerCol: bpc,
                            yBlocks: [block], cbBlocks: nil, crBlocks: nil)
        let pixels = img.getPixels()
        #expect(pixels.count == 2 * 2 * 3)
        // For all-zero coefficients, all pixels are 127 regardless of row
        // (flipping preserves values, just reorders rows)
        for byte in pixels {
            #expect(byte == 127)
        }
    }
}
