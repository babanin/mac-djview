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
    private func inverseWaveletTransform(map: LinearBytemap) {
        var s = 16
        var sDegree = 4

        while s >= 1 {
            let h = height
            let w = width

            // Process columns
            var kmax = (h - 1) >> sDegree
            var border = kmax - 3

            for i in stride(from: 0, to: w, by: s) {
                // Lifting phase (even indices)
                var prev1: Int32 = 0
                var next1: Int32 = 0
                var next3: Int32 = 1 > kmax ? 0 : Int32(map.get(1 << sDegree, i))
                var prev3: Int32

                var k = 0
                while k <= kmax {
                    prev3 = prev1; prev1 = next1; next1 = next3
                    next3 = (k + 3) > kmax ? 0 : Int32(map.get((k + 3) << sDegree, i))

                    let a = prev1 + next1
                    let c = prev3 + next3
                    map.sub(k << sDegree, i, Int16(truncatingIfNeeded: ((a << 3) + a - c + 16) >> 5))
                    k += 2
                }

                // Prediction phase (odd indices)
                k = 1
                prev1 = Int32(map.get((k - 1) << sDegree, i))
                if k + 1 <= kmax {
                    next1 = Int32(map.get((k + 1) << sDegree, i))
                    map.add(k << sDegree, i, Int16(truncatingIfNeeded: (prev1 + next1 + 1) >> 1))
                } else {
                    map.add(k << sDegree, i, Int16(truncatingIfNeeded: prev1))
                }

                if border >= 3 {
                    next3 = Int32(map.get((k + 3) << sDegree, i))
                } else {
                    next3 = 0
                }

                k = 3
                while k <= border {
                    prev3 = prev1; prev1 = next1; next1 = next3
                    next3 = Int32(map.get((k + 3) << sDegree, i))

                    let a = prev1 + next1
                    map.add(k << sDegree, i,
                            Int16(truncatingIfNeeded: ((a << 3) + a - (prev3 + next3) + 8) >> 4))
                    k += 2
                }

                while k <= kmax {
                    prev1 = next1; next1 = next3; next3 = 0
                    if k + 1 <= kmax {
                        map.add(k << sDegree, i, Int16(truncatingIfNeeded: (prev1 + next1 + 1) >> 1))
                    } else {
                        map.add(k << sDegree, i, Int16(truncatingIfNeeded: prev1))
                    }
                    k += 2
                }
            }

            // Process rows
            kmax = (w - 1) >> sDegree
            border = kmax - 3

            for i in stride(from: 0, to: h, by: s) {
                // Lifting phase (even indices)
                var prev1: Int32 = 0
                var next1: Int32 = 0
                var next3: Int32 = 1 > kmax ? 0 : Int32(map.get(i, 1 << sDegree))
                var prev3: Int32

                var k = 0
                while k <= kmax {
                    prev3 = prev1; prev1 = next1; next1 = next3
                    next3 = (k + 3) > kmax ? 0 : Int32(map.get(i, (k + 3) << sDegree))

                    let a = prev1 + next1
                    let c = prev3 + next3
                    map.sub(i, k << sDegree, Int16(truncatingIfNeeded: ((a << 3) + a - c + 16) >> 5))
                    k += 2
                }

                // Prediction phase (odd indices)
                k = 1
                prev1 = Int32(map.get(i, (k - 1) << sDegree))
                if k + 1 <= kmax {
                    next1 = Int32(map.get(i, (k + 1) << sDegree))
                    map.add(i, k << sDegree, Int16(truncatingIfNeeded: (prev1 + next1 + 1) >> 1))
                } else {
                    map.add(i, k << sDegree, Int16(truncatingIfNeeded: prev1))
                }

                if border >= 3 {
                    next3 = Int32(map.get(i, (k + 3) << sDegree))
                } else {
                    next3 = 0
                }

                k = 3
                while k <= border {
                    prev3 = prev1; prev1 = next1; next1 = next3
                    next3 = Int32(map.get(i, (k + 3) << sDegree))

                    let a = prev1 + next1
                    map.add(i, k << sDegree,
                            Int16(truncatingIfNeeded: ((a << 3) + a - (prev3 + next3) + 8) >> 4))
                    k += 2
                }

                while k <= kmax {
                    prev1 = next1; next1 = next3; next3 = 0
                    if k + 1 <= kmax {
                        map.add(i, k << sDegree, Int16(truncatingIfNeeded: (prev1 + next1 + 1) >> 1))
                    } else {
                        map.add(i, k << sDegree, Int16(truncatingIfNeeded: prev1))
                    }
                    k += 2
                }
            }

            s >>= 1
            sDegree -= 1
        }
    }

    private func normalize(_ val: Int16) -> Int {
        let v = (Int(val) + 32) >> 6
        return max(-128, min(127, v))
    }

    private func clampByte(_ v: Int) -> UInt8 {
        UInt8(max(0, min(255, v)))
    }

    private func grayscaleToRGB(yMap: LinearBytemap) -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: width * height * 3)
        for row in 0..<height {
            for col in 0..<width {
                let y = 127 - normalize(yMap.get(row, col))
                let byte = clampByte(y)
                let flippedRow = height - 1 - row
                let idx = (flippedRow * width + col) * 3
                pixels[idx] = byte
                pixels[idx + 1] = byte
                pixels[idx + 2] = byte
            }
        }
        return pixels
    }

    private func yuvToRGB(yMap: LinearBytemap, cbMap: LinearBytemap, crMap: LinearBytemap) -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: width * height * 3)
        for row in 0..<height {
            for col in 0..<width {
                let y = normalize(yMap.get(row, col))
                let b = normalize(cbMap.get(row, col))
                let r = normalize(crMap.get(row, col))

                let t2 = r + (r >> 1)
                let t3 = y + 128 - (b >> 2)
                let rr = y + 128 + t2
                let gg = t3 - (t2 >> 1)
                let bb = t3 + (b << 1)

                let flippedRow = height - 1 - row
                let idx = (flippedRow * width + col) * 3
                pixels[idx] = clampByte(rr)
                pixels[idx + 1] = clampByte(gg)
                pixels[idx + 2] = clampByte(bb)
            }
        }
        return pixels
    }
}
