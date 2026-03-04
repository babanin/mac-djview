import Foundation

/// Per-channel IW44 decoder state. Each color plane (Y, Cb, Cr) gets its own instance.
/// Faithfully ported from DjVu.js IWDecoder.js + IWCodecBaseClass.js
private final class IW44ChannelDecoder {
    var blocks: [IW44Block] = []
    var curband: Int = 0

    // Quantization state (mutable copies, independent per channel)
    var quantLo: [UInt32] = quant_lo
    var quantHi: [UInt32] = quant_hi

    // ZP context arrays (per-channel, as in DjVu.js)
    var decodeBucketCtx: [UInt8] = [0]
    var decodeCoefCtx: [UInt8] = [UInt8](repeating: 0, count: 80)
    var activateCoefCtx: [UInt8] = [UInt8](repeating: 0, count: 16)
    var inreaseCoefCtx: [UInt8] = [0]

    // Per-block temporary state
    var coeffstate: [[UInt8]] = Array(repeating: [UInt8](repeating: 0, count: 16), count: 16)
    var bucketstate: [UInt8] = [UInt8](repeating: 0, count: 16)
    var bbstate: UInt8 = 0

    func initBlocks(count: Int) {
        blocks = (0..<count).map { _ in IW44Block() }
    }

    /// Decode one slice from the ZP bitstream.
    /// Corresponds to DjVu.js IWDecoder.decodeSlice()
    func decodeSlice(zp: ZPCodec) {
        if !isNullSlice() {
            let band = curband
            let bb = bandBuckets[band]
            let bcount = bb.to - bb.from + 1

            for block in blocks {
                preliminaryFlagComputation(block: block, band: band)
                if blockBandDecodingPass(zp: zp, bcount: bcount) {
                    bucketDecodingPass(zp: zp, block: block, band: band)
                    newlyActiveCoefficientDecodingPass(zp: zp, block: block, band: band)
                }
                previouslyActiveCoefficientDecodingPass(zp: zp, block: block, band: band)
            }
        }
        finishCodeSlice()
    }

    private func isNullSlice() -> Bool {
        if curband == 0 {
            var isNull = true
            for i in 0..<16 {
                let threshold = quantLo[i]
                coeffstate[0][i] = CoefficientFlag.ZERO
                if threshold > 0 && threshold < 0x8000 {
                    coeffstate[0][i] = CoefficientFlag.UNK
                    isNull = false
                }
            }
            return isNull
        } else {
            let threshold = quantHi[curband]
            return !(threshold > 0 && threshold < 0x8000)
        }
    }

    private func preliminaryFlagComputation(block: IW44Block, band: Int) {
        bbstate = 0
        let bb = bandBuckets[band]

        if band != 0 {
            var boff = 0
            for j in bb.from...bb.to {
                var bstatetmp: UInt8 = 0
                for k in 0..<16 {
                    if block.getCoef(j, k) == 0 {
                        coeffstate[boff][k] = CoefficientFlag.UNK
                    } else {
                        coeffstate[boff][k] = CoefficientFlag.ACTIVE
                    }
                    bstatetmp |= coeffstate[boff][k]
                }
                bucketstate[boff] = bstatetmp
                bbstate |= bstatetmp
                boff += 1
            }
        } else {
            var bstatetmp: UInt8 = 0
            for k in 0..<16 {
                if coeffstate[0][k] != CoefficientFlag.ZERO {
                    if block.getCoef(0, k) == 0 {
                        coeffstate[0][k] = CoefficientFlag.UNK
                    } else {
                        coeffstate[0][k] = CoefficientFlag.ACTIVE
                    }
                }
                bstatetmp |= coeffstate[0][k]
            }
            bucketstate[0] = bstatetmp
            bbstate |= bstatetmp
        }
    }

    private func blockBandDecodingPass(zp: ZPCodec, bcount: Int) -> Bool {
        if bcount < 16 || (bbstate & CoefficientFlag.ACTIVE != 0) {
            bbstate |= CoefficientFlag.NEW
        } else if bbstate & CoefficientFlag.UNK != 0 {
            if zp.decode(ctx: &decodeBucketCtx, n: 0) != 0 {
                bbstate |= CoefficientFlag.NEW
            }
        }
        return bbstate & CoefficientFlag.NEW != 0
    }

    private func bucketDecodingPass(zp: ZPCodec, block: IW44Block, band: Int) {
        let bb = bandBuckets[band]
        var boff = 0

        for i in bb.from...bb.to {
            if bucketstate[boff] & CoefficientFlag.UNK == 0 {
                boff += 1
                continue
            }

            var n = 0
            if band != 0 {
                let t = 4 * i
                for j in t..<t + 4 {
                    let bucket = j / 16
                    let ci = j % 16
                    if block.getCoef(bucket, ci) != 0 {
                        n += 1
                    }
                }
                if n == 4 { n -= 1 }
            }
            if bbstate & CoefficientFlag.ACTIVE != 0 {
                n |= 4
            }

            if zp.decode(ctx: &decodeCoefCtx, n: n + band * 8) != 0 {
                bucketstate[boff] |= CoefficientFlag.NEW
            }

            boff += 1
        }
    }

    private func newlyActiveCoefficientDecodingPass(zp: ZPCodec, block: IW44Block, band: Int) {
        let bb = bandBuckets[band]
        var boff = 0
        var step = quantHi[curband]

        for i in bb.from...bb.to {
            if bucketstate[boff] & CoefficientFlag.NEW != 0 {
                let shift: Int = (bucketstate[boff] & CoefficientFlag.ACTIVE != 0) ? 8 : 0

                var np = 0
                for j in 0..<16 {
                    if coeffstate[boff][j] & CoefficientFlag.UNK != 0 {
                        np += 1
                    }
                }

                for j in 0..<16 {
                    if coeffstate[boff][j] & CoefficientFlag.UNK != 0 {
                        let ip = min(7, np)
                        let des = zp.decode(ctx: &activateCoefCtx, n: shift + ip)
                        if des != 0 {
                            let sign: Int32 = zp.IWdecode() != 0 ? -1 : 1
                            np = 0
                            if band == 0 {
                                step = quantLo[j]
                            }
                            let value = sign * (Int32(step) + Int32(step >> 1) - Int32(step >> 3))
                            block.setCoef(i, j, Int16(truncatingIfNeeded: value))
                        }
                        if np > 0 { np -= 1 }
                    }
                }
            }
            boff += 1
        }
    }

    private func previouslyActiveCoefficientDecodingPass(zp: ZPCodec, block: IW44Block, band: Int) {
        let bb = bandBuckets[band]
        var boff = 0
        var step = quantHi[curband]

        for i in bb.from...bb.to {
            for j in 0..<16 {
                if coeffstate[boff][j] & CoefficientFlag.ACTIVE != 0 {
                    if band == 0 {
                        step = quantLo[j]
                    }
                    let coef = block.getCoef(i, j)
                    var absCoef = Int32(abs(Int32(coef)))
                    let des: Int
                    if absCoef <= 3 * Int32(step) {
                        des = zp.decode(ctx: &inreaseCoefCtx, n: 0)
                        absCoef += Int32(step >> 2)
                    } else {
                        des = zp.IWdecode()
                    }
                    if des != 0 {
                        absCoef += Int32(step >> 1)
                    } else {
                        absCoef += -Int32(step) + Int32(step >> 1)
                    }
                    block.setCoef(i, j, Int16(truncatingIfNeeded: coef < 0 ? -absCoef : absCoef))
                }
            }
            boff += 1
        }
    }

    private func finishCodeSlice() {
        if curband == 0 {
            for i in 0..<quantLo.count {
                quantLo[i] >>= 1
            }
        }
        quantHi[curband] >>= 1
        curband = (curband + 1) % 10
    }
}

/// IW44 progressive wavelet image decoder for DjVu BG44/FG44 chunks.
/// Manages separate channel decoders for Y, Cb, Cr planes.
/// Faithfully ported from DjVu.js IWImage.js
final class IW44Decoder {
    private var width: Int = 0
    private var height: Int = 0
    private var isColor: Bool = false
    private var delayInit: Int = 0
    private var cslice: Int = 0  // current slice counter (across all chunks)

    private var blocksPerRow: Int = 0
    private var blocksPerCol: Int = 0

    private var yCodec = IW44ChannelDecoder()
    private var cbCodec: IW44ChannelDecoder?
    private var crCodec: IW44ChannelDecoder?

    private var initialized = false

    func decodeChunk(data: Data) throws {
        let stream = ByteStream(data: data)

        let serial = try stream.readUInt8()
        let numSlices = Int(try stream.readUInt8())

        if serial == 0 && !initialized {
            let majver = try stream.readUInt8()
            let _ = try stream.readUInt8() // minver
            let cols = Int(try stream.readUInt16())
            let rows = Int(try stream.readUInt16())

            self.isColor = (majver & 0x80) == 0 // bit 7 clear = color, set = grayscale

            // Read delayInit byte (present in the header)
            let delayByte = try stream.readUInt8()
            self.delayInit = Int(delayByte & 0x7F)

            self.width = cols
            self.height = rows

            blocksPerRow = (width + 31) / 32
            blocksPerCol = (height + 31) / 32
            let numBlocks = blocksPerRow * blocksPerCol

            yCodec.initBlocks(count: numBlocks)
            if isColor {
                cbCodec = IW44ChannelDecoder()
                cbCodec!.initBlocks(count: numBlocks)
                crCodec = IW44ChannelDecoder()
                crCodec!.initBlocks(count: numBlocks)
            }

            initialized = true
        }

        guard initialized else {
            throw DjVuError.decodingFailed("IW44: non-zero serial without prior initialization")
        }

        let zp = ZPCodec(stream: stream)
        for _ in 0..<numSlices {
            cslice += 1
            yCodec.decodeSlice(zp: zp)
            if let cbCodec, let crCodec, cslice > delayInit {
                cbCodec.decodeSlice(zp: zp)
                crCodec.decodeSlice(zp: zp)
            }
        }
    }

    func getImage() throws -> IW44Image {
        guard initialized else { throw DjVuError.noImageData }
        return IW44Image(
            width: width, height: height,
            blocksPerRow: blocksPerRow, blocksPerCol: blocksPerCol,
            yBlocks: yCodec.blocks, cbBlocks: cbCodec?.blocks,
            crBlocks: crCodec?.blocks
        )
    }
}
