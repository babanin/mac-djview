import Foundation
import CoreGraphics

/// Reconstructed IW44 image with inverse wavelet transform and color conversion.
final class IW44Image {
    let width: Int
    let height: Int
    private let blocksPerRow: Int
    private let blocksPerCol: Int
    private let yBlocks: [IW44Block]
    private let cbBlocks: [IW44Block]?
    private let crBlocks: [IW44Block]?

    var isColor: Bool { cbBlocks != nil }

    init(width: Int, height: Int, blocksPerRow: Int, blocksPerCol: Int,
         yBlocks: [IW44Block], cbBlocks: [IW44Block]?, crBlocks: [IW44Block]?) {
        self.width = width
        self.height = height
        self.blocksPerRow = blocksPerRow
        self.blocksPerCol = blocksPerCol
        self.yBlocks = yBlocks
        self.cbBlocks = cbBlocks
        self.crBlocks = crBlocks
    }

    /// Get RGB pixel data (width × height × 3 bytes)
    func getPixels() -> [UInt8] {
        let yMap = getBytemap(blocks: yBlocks)
        if isColor, let cbBlocks, let crBlocks {
            let cbMap = getBytemap(blocks: cbBlocks)
            let crMap = getBytemap(blocks: crBlocks)
            return yuvToRGB(yMap: yMap, cbMap: cbMap, crMap: crMap)
        } else {
            return grayscaleToRGB(yMap: yMap)
        }
    }

    private func getBytemap(blocks: [IW44Block]) -> LinearBytemap {
        let bw = blocksPerRow * 32
        let bh = blocksPerCol * 32
        let map = LinearBytemap(width: bw, height: bh)

        // Lay out coefficients from blocks using zigzag tables
        for by in 0..<blocksPerCol {
            for bx in 0..<blocksPerRow {
                let blockIdx = by * blocksPerRow + bx
                let block = blocks[blockIdx]
                let rowOff = by * 32
                let colOff = bx * 32

                for coef in 0..<1024 {
                    let bucket = coef / 16
                    let ci = coef % 16
                    let value = block.getCoef(bucket, ci)
                    if value != 0 {
                        let r = rowOff + Int(zigzagRow[coef])
                        let c = colOff + Int(zigzagCol[coef])
                        if r < bh && c < bw {
                            map.set(r, c, value)
                        }
                    }
                }
            }
        }

        // Apply inverse wavelet transform
        inverseWaveletTransform(map: map)

        return map
    }

    /// Inverse wavelet transform — faithfully ported from DjVu.js IWDecoder.js
    /// Uses withUnsafeMutableBufferPointer to eliminate per-access bounds checks.
    private func inverseWaveletTransform(map: LinearBytemap) {
        var s = 16
        var sDegree = 4
        let mapW = map.width

        map.data.withUnsafeMutableBufferPointer { buf in
            while s >= 1 {
                let h = height
                let w = width

                // Process columns
                var kmax = (h - 1) >> sDegree
                var border = kmax - 3

                for i in stride(from: 0, to: w, by: s) {
                    var prev1: Int32 = 0
                    var next1: Int32 = 0
                    var next3: Int32 = 1 > kmax ? 0 : Int32(buf[(1 << sDegree) * mapW + i])
                    var prev3: Int32

                    var k = 0
                    while k <= kmax {
                        prev3 = prev1; prev1 = next1; next1 = next3
                        next3 = (k + 3) > kmax ? 0 : Int32(buf[((k + 3) << sDegree) * mapW + i])

                        let a = prev1 + next1
                        let c = prev3 + next3
                        buf[(k << sDegree) * mapW + i] &-= Int16(truncatingIfNeeded: ((a << 3) + a - c + 16) >> 5)
                        k += 2
                    }

                    k = 1
                    prev1 = Int32(buf[((k - 1) << sDegree) * mapW + i])
                    if k + 1 <= kmax {
                        next1 = Int32(buf[((k + 1) << sDegree) * mapW + i])
                        buf[(k << sDegree) * mapW + i] &+= Int16(truncatingIfNeeded: (prev1 + next1 + 1) >> 1)
                    } else {
                        buf[(k << sDegree) * mapW + i] &+= Int16(truncatingIfNeeded: prev1)
                    }

                    if border >= 3 {
                        next3 = Int32(buf[((k + 3) << sDegree) * mapW + i])
                    } else {
                        next3 = 0
                    }

                    k = 3
                    while k <= border {
                        prev3 = prev1; prev1 = next1; next1 = next3
                        next3 = Int32(buf[((k + 3) << sDegree) * mapW + i])

                        let a = prev1 + next1
                        buf[(k << sDegree) * mapW + i] &+= Int16(truncatingIfNeeded: ((a << 3) + a - (prev3 + next3) + 8) >> 4)
                        k += 2
                    }

                    while k <= kmax {
                        prev1 = next1; next1 = next3; next3 = 0
                        if k + 1 <= kmax {
                            buf[(k << sDegree) * mapW + i] &+= Int16(truncatingIfNeeded: (prev1 + next1 + 1) >> 1)
                        } else {
                            buf[(k << sDegree) * mapW + i] &+= Int16(truncatingIfNeeded: prev1)
                        }
                        k += 2
                    }
                }

                // Process rows
                kmax = (w - 1) >> sDegree
                border = kmax - 3

                for i in stride(from: 0, to: h, by: s) {
                    let rowBase = i * mapW

                    var prev1: Int32 = 0
                    var next1: Int32 = 0
                    var next3: Int32 = 1 > kmax ? 0 : Int32(buf[rowBase + (1 << sDegree)])
                    var prev3: Int32

                    var k = 0
                    while k <= kmax {
                        prev3 = prev1; prev1 = next1; next1 = next3
                        next3 = (k + 3) > kmax ? 0 : Int32(buf[rowBase + ((k + 3) << sDegree)])

                        let a = prev1 + next1
                        let c = prev3 + next3
                        buf[rowBase + (k << sDegree)] &-= Int16(truncatingIfNeeded: ((a << 3) + a - c + 16) >> 5)
                        k += 2
                    }

                    k = 1
                    prev1 = Int32(buf[rowBase + ((k - 1) << sDegree)])
                    if k + 1 <= kmax {
                        next1 = Int32(buf[rowBase + ((k + 1) << sDegree)])
                        buf[rowBase + (k << sDegree)] &+= Int16(truncatingIfNeeded: (prev1 + next1 + 1) >> 1)
                    } else {
                        buf[rowBase + (k << sDegree)] &+= Int16(truncatingIfNeeded: prev1)
                    }

                    if border >= 3 {
                        next3 = Int32(buf[rowBase + ((k + 3) << sDegree)])
                    } else {
                        next3 = 0
                    }

                    k = 3
                    while k <= border {
                        prev3 = prev1; prev1 = next1; next1 = next3
                        next3 = Int32(buf[rowBase + ((k + 3) << sDegree)])

                        let a = prev1 + next1
                        buf[rowBase + (k << sDegree)] &+= Int16(truncatingIfNeeded: ((a << 3) + a - (prev3 + next3) + 8) >> 4)
                        k += 2
                    }

                    while k <= kmax {
                        prev1 = next1; next1 = next3; next3 = 0
                        if k + 1 <= kmax {
                            buf[rowBase + (k << sDegree)] &+= Int16(truncatingIfNeeded: (prev1 + next1 + 1) >> 1)
                        } else {
                            buf[rowBase + (k << sDegree)] &+= Int16(truncatingIfNeeded: prev1)
                        }
                        k += 2
                    }
                }

                s >>= 1
                sDegree -= 1
            }
        }
    }

    @inline(__always)
    private static func normalize(_ val: Int16) -> Int32 {
        let v = (Int32(val) + 32) >> 6
        return max(-128, min(127, v))
    }

    @inline(__always)
    private static func clampByte(_ v: Int32) -> UInt8 {
        UInt8(max(0, min(255, v)))
    }

    private func grayscaleToRGB(yMap: LinearBytemap) -> [UInt8] {
        let w = width, h = height
        var pixels = [UInt8](repeating: 0, count: w * h * 3)
        let mapW = yMap.width

        pixels.withUnsafeMutableBufferPointer { outBuf in
            yMap.data.withUnsafeBufferPointer { yBuf in
                for row in 0..<h {
                    let flippedRow = h - 1 - row
                    let outBase = flippedRow * w * 3
                    let yBase = row * mapW

                    var col = 0
                    // SIMD: process 8 pixels at a time
                    let simdEnd = w & ~7  // round down to multiple of 8
                    while col < simdEnd {
                        // Load 8 Int16 values, normalize, and convert
                        let raw = SIMD8<Int32>(
                            Int32(yBuf[yBase + col]),     Int32(yBuf[yBase + col + 1]),
                            Int32(yBuf[yBase + col + 2]), Int32(yBuf[yBase + col + 3]),
                            Int32(yBuf[yBase + col + 4]), Int32(yBuf[yBase + col + 5]),
                            Int32(yBuf[yBase + col + 6]), Int32(yBuf[yBase + col + 7])
                        )
                        // normalize: clamp((val + 32) >> 6, -128, 127)
                        let normalized = ((raw &+ 32) &>> 6).clamped(lowerBound: SIMD8(repeating: -128),
                                                                      upperBound: SIMD8(repeating: 127))
                        // grayscale: 127 - normalized, then clamp to [0, 255]
                        let gray = (SIMD8(repeating: Int32(127)) &- normalized)
                            .clamped(lowerBound: SIMD8(repeating: 0), upperBound: SIMD8(repeating: 255))

                        for p in 0..<8 {
                            let byte = UInt8(gray[p])
                            let idx = outBase + (col + p) * 3
                            outBuf[idx] = byte
                            outBuf[idx + 1] = byte
                            outBuf[idx + 2] = byte
                        }
                        col += 8
                    }

                    // Scalar tail
                    while col < w {
                        let val = IW44Image.normalize(yBuf[yBase + col])
                        let byte = IW44Image.clampByte(127 - val)
                        let idx = outBase + col * 3
                        outBuf[idx] = byte
                        outBuf[idx + 1] = byte
                        outBuf[idx + 2] = byte
                        col += 1
                    }
                }
            }
        }
        return pixels
    }

    private func yuvToRGB(yMap: LinearBytemap, cbMap: LinearBytemap, crMap: LinearBytemap) -> [UInt8] {
        let w = width, h = height
        var pixels = [UInt8](repeating: 0, count: w * h * 3)
        let mapW = yMap.width

        pixels.withUnsafeMutableBufferPointer { outBuf in
            yMap.data.withUnsafeBufferPointer { yBuf in
                cbMap.data.withUnsafeBufferPointer { cbBuf in
                    crMap.data.withUnsafeBufferPointer { crBuf in
                        let low = SIMD8<Int32>(repeating: -128)
                        let high = SIMD8<Int32>(repeating: 127)
                        let bias32 = SIMD8<Int32>(repeating: 32)
                        let zero = SIMD8<Int32>(repeating: 0)
                        let max255 = SIMD8<Int32>(repeating: 255)
                        let c128 = SIMD8<Int32>(repeating: 128)

                        for row in 0..<h {
                            let flippedRow = h - 1 - row
                            let outBase = flippedRow * w * 3
                            let srcBase = row * mapW

                            var col = 0
                            let simdEnd = w & ~7

                            while col < simdEnd {
                                let off = srcBase + col

                                // Load and normalize Y, Cb, Cr
                                let yRaw = SIMD8<Int32>(
                                    Int32(yBuf[off]), Int32(yBuf[off+1]), Int32(yBuf[off+2]), Int32(yBuf[off+3]),
                                    Int32(yBuf[off+4]), Int32(yBuf[off+5]), Int32(yBuf[off+6]), Int32(yBuf[off+7]))
                                let cbRaw = SIMD8<Int32>(
                                    Int32(cbBuf[off]), Int32(cbBuf[off+1]), Int32(cbBuf[off+2]), Int32(cbBuf[off+3]),
                                    Int32(cbBuf[off+4]), Int32(cbBuf[off+5]), Int32(cbBuf[off+6]), Int32(cbBuf[off+7]))
                                let crRaw = SIMD8<Int32>(
                                    Int32(crBuf[off]), Int32(crBuf[off+1]), Int32(crBuf[off+2]), Int32(crBuf[off+3]),
                                    Int32(crBuf[off+4]), Int32(crBuf[off+5]), Int32(crBuf[off+6]), Int32(crBuf[off+7]))

                                let yN = ((yRaw &+ bias32) &>> 6).clamped(lowerBound: low, upperBound: high)
                                let bN = ((cbRaw &+ bias32) &>> 6).clamped(lowerBound: low, upperBound: high)
                                let rN = ((crRaw &+ bias32) &>> 6).clamped(lowerBound: low, upperBound: high)

                                // YUV→RGB (DjVu color space)
                                let t2 = rN &+ (rN &>> 1)
                                let t3 = yN &+ c128 &- (bN &>> 2)
                                let rr = (yN &+ c128 &+ t2).clamped(lowerBound: zero, upperBound: max255)
                                let gg = (t3 &- (t2 &>> 1)).clamped(lowerBound: zero, upperBound: max255)
                                let bb = (t3 &+ (bN &<< 1)).clamped(lowerBound: zero, upperBound: max255)

                                for p in 0..<8 {
                                    let idx = outBase + (col + p) * 3
                                    outBuf[idx] = UInt8(rr[p])
                                    outBuf[idx + 1] = UInt8(gg[p])
                                    outBuf[idx + 2] = UInt8(bb[p])
                                }
                                col += 8
                            }

                            // Scalar tail
                            while col < w {
                                let off = srcBase + col
                                let yV = IW44Image.normalize(yBuf[off])
                                let bV = IW44Image.normalize(cbBuf[off])
                                let rV = IW44Image.normalize(crBuf[off])

                                let t2 = rV + (rV >> 1)
                                let t3 = yV + 128 - (bV >> 2)

                                let idx = outBase + col * 3
                                outBuf[idx] = IW44Image.clampByte(yV + 128 + t2)
                                outBuf[idx + 1] = IW44Image.clampByte(t3 - (t2 >> 1))
                                outBuf[idx + 2] = IW44Image.clampByte(t3 + (bV << 1))
                                col += 1
                            }
                        }
                    }
                }
            }
        }
        return pixels
    }
}
