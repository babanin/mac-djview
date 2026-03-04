import Testing
@testable import MacDjView

@Suite("Inverse wavelet transform — unsafe buffer pointer correctness")
struct WaveletTransformTests {

    // The wavelet transform is private to IW44Image, so we test it indirectly through
    // getBytemap → getPixels. We verify properties that must hold if the transform is correct.

    @Test("all-zero coefficients remain zero after transform")
    func allZeroCoefficients() {
        // With all-zero blocks, the bytemap should remain all zeros after wavelet transform
        let bpr = 1, bpc = 1
        let block = IW44Block()
        let img = IW44Image(width: 32, height: 32,
                            blocksPerRow: bpr, blocksPerCol: bpc,
                            yBlocks: [block], cbBlocks: nil, crBlocks: nil)
        let pixels = img.getPixels()
        // normalize(0) = 0, grayscale = 127 - 0 = 127
        for byte in pixels {
            #expect(byte == 127, "All-zero coefficients should produce uniform gray")
        }
    }

    @Test("DC-only coefficient produces non-zero, uniform-ish output")
    func dcOnlyCoefficient() {
        let block = IW44Block()
        block.setCoef(0, 0, 2048)  // Strong DC value

        let img = IW44Image(width: 32, height: 32,
                            blocksPerRow: 1, blocksPerCol: 1,
                            yBlocks: [block], cbBlocks: nil, crBlocks: nil)
        let pixels = img.getPixels()

        // DC coefficient affects all pixels in the block
        // After wavelet transform, the DC propagates to create a roughly uniform value
        // All pixels should be the same (DC only = flat image)
        let firstR = pixels[0]
        #expect(firstR != 127, "DC should shift from default gray")

        // Check uniformity: all pixels should match the first one
        // (pure DC = no spatial variation)
        for i in stride(from: 0, to: pixels.count, by: 3) {
            #expect(pixels[i] == firstR, "DC-only image should be spatially uniform at pixel \(i/3)")
        }
    }

    @Test("different DC values produce different brightness levels")
    func dcBrightnessLevels() {
        var results: [Int16: UInt8] = [:]

        for dc: Int16 in [-2048, -1024, 0, 1024, 2048] {
            let block = IW44Block()
            block.setCoef(0, 0, dc)
            let img = IW44Image(width: 1, height: 1,
                                blocksPerRow: 1, blocksPerCol: 1,
                                yBlocks: [block], cbBlocks: nil, crBlocks: nil)
            let pixels = img.getPixels()
            results[dc] = pixels[0]
        }

        // Higher Y (positive) should produce darker pixels (grayscale = 127 - normalize(y))
        // So larger positive DC → darker, larger negative DC → brighter
        #expect(results[-2048]! > results[0]!, "Negative DC should be brighter than zero")
        #expect(results[0]! > results[2048]!, "Positive DC should be darker than zero")
    }

    @Test("wavelet transform is deterministic")
    func deterministic() {
        let block1 = IW44Block()
        block1.setCoef(0, 0, 500)
        block1.setCoef(1, 3, -200)

        let block2 = IW44Block()
        block2.setCoef(0, 0, 500)
        block2.setCoef(1, 3, -200)

        let img1 = IW44Image(width: 16, height: 16,
                             blocksPerRow: 1, blocksPerCol: 1,
                             yBlocks: [block1], cbBlocks: nil, crBlocks: nil)
        let img2 = IW44Image(width: 16, height: 16,
                             blocksPerRow: 1, blocksPerCol: 1,
                             yBlocks: [block2], cbBlocks: nil, crBlocks: nil)

        #expect(img1.getPixels() == img2.getPixels(), "Same coefficients must produce identical pixels")
    }

    @Test("multi-block image processes all blocks")
    func multiBlock() {
        // 64×64 image = 2×2 blocks
        let blocks = (0..<4).map { _ in IW44Block() }
        // Set different DC in each block
        blocks[0].setCoef(0, 0, 1000)
        blocks[1].setCoef(0, 0, -1000)
        blocks[2].setCoef(0, 0, 500)
        blocks[3].setCoef(0, 0, -500)

        let img = IW44Image(width: 64, height: 64,
                            blocksPerRow: 2, blocksPerCol: 2,
                            yBlocks: blocks, cbBlocks: nil, crBlocks: nil)
        let pixels = img.getPixels()
        #expect(pixels.count == 64 * 64 * 3)

        // Pixels from different quadrants should differ
        // Top-left of block (0,0) = row 0 of DjVu = bottom row of output (flipped)
        // Sample center of each quadrant
        let getGray = { (x: Int, y: Int) -> UInt8 in pixels[(y * 64 + x) * 3] }

        // Different blocks should produce different pixel values
        let topLeft = getGray(8, 8)
        let topRight = getGray(40, 8)
        let bottomLeft = getGray(8, 40)
        let bottomRight = getGray(40, 40)

        // At least some of these should differ (different DC values)
        let values = Set([topLeft, topRight, bottomLeft, bottomRight])
        #expect(values.count > 1, "Different DC coefficients should produce different pixel values")
    }

    @Test("non-power-of-2 dimensions work correctly")
    func nonPowerOf2() {
        let block = IW44Block()
        block.setCoef(0, 0, 512)

        // Width=13, Height=7 — not multiples of 32, not powers of 2
        let img = IW44Image(width: 13, height: 7,
                            blocksPerRow: 1, blocksPerCol: 1,
                            yBlocks: [block], cbBlocks: nil, crBlocks: nil)
        let pixels = img.getPixels()
        #expect(pixels.count == 13 * 7 * 3)
        // Should not crash and all pixels should be valid (0-255)
        for byte in pixels {
            #expect(byte <= 255)  // Always true for UInt8, but verifies no crash
        }
    }
}
