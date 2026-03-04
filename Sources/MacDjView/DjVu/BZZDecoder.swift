import Foundation

/// BZZ block-sorting decoder (Burrows-Wheeler + MTF + ZP arithmetic coding).
/// Ported from DjVu.js BZZDecoder.js
final class BZZDecoder {
    private let zp: ZPCodec
    private let maxblock = 4096
    private let FREQMAX = 4
    private let CTXIDS = 3
    private var ctx = [UInt8](repeating: 0, count: 300)
    private var blocksize = 0
    private var data: [UInt8]?

    init(zp: ZPCodec) {
        self.zp = zp
    }

    private func decodeRaw(_ bits: Int) -> Int {
        var n = 1
        let m = 1 << bits
        while n < m {
            let b = zp.decodeBit()
            n = (n << 1) | b
        }
        return n - m
    }

    private func decodeBinary(_ ctxoff: Int, _ bits: Int) -> Int {
        var n = 1
        let m = 1 << bits
        let off = ctxoff - 1
        while n < m {
            let b = zp.decode(ctx: &ctx, n: off + n)
            n = (n << 1) | b
        }
        return n - m
    }

    private func decodeBlock() -> Int {
        let size = decodeRaw(24)
        guard size > 0 else { return 0 }
        guard size <= maxblock * 1024 else { return 0 }

        if blocksize < size {
            blocksize = size
            data = [UInt8](repeating: 0, count: blocksize)
        } else if data == nil {
            data = [UInt8](repeating: 0, count: blocksize)
        }

        // Decode estimation speed
        var fshift = 0
        if zp.decodeBit() != 0 {
            fshift += 1
            if zp.decodeBit() != 0 {
                fshift += 1
            }
        }

        // Prepare quasi-MTF
        var mtf = [UInt8](repeating: 0, count: 256)
        for i in 0..<256 { mtf[i] = UInt8(i) }
        var freq = [Int](repeating: 0, count: FREQMAX)
        var fadd = 4

        var mtfno = 3
        var markerpos = -1

        for i in 0..<size {
            var ctxid = CTXIDS - 1
            if ctxid > mtfno { ctxid = mtfno }
            var ctxoff = 0

            // Decode MTF rank using cascading binary decisions
            if zp.decode(ctx: &ctx, n: ctxoff + ctxid) != 0 {
                mtfno = 0; data![i] = mtf[mtfno]
            } else {
                ctxoff += CTXIDS
                if zp.decode(ctx: &ctx, n: ctxoff + ctxid) != 0 {
                    mtfno = 1; data![i] = mtf[mtfno]
                } else {
                    ctxoff += CTXIDS
                    if zp.decode(ctx: &ctx, n: ctxoff) != 0 {
                        mtfno = 2 + decodeBinary(ctxoff + 1, 1)
                        data![i] = mtf[mtfno]
                    } else {
                        ctxoff += 1 + 1
                        if zp.decode(ctx: &ctx, n: ctxoff) != 0 {
                            mtfno = 4 + decodeBinary(ctxoff + 1, 2)
                            data![i] = mtf[mtfno]
                        } else {
                            ctxoff += 1 + 3
                            if zp.decode(ctx: &ctx, n: ctxoff) != 0 {
                                mtfno = 8 + decodeBinary(ctxoff + 1, 3)
                                data![i] = mtf[mtfno]
                            } else {
                                ctxoff += 1 + 7
                                if zp.decode(ctx: &ctx, n: ctxoff) != 0 {
                                    mtfno = 16 + decodeBinary(ctxoff + 1, 4)
                                    data![i] = mtf[mtfno]
                                } else {
                                    ctxoff += 1 + 15
                                    if zp.decode(ctx: &ctx, n: ctxoff) != 0 {
                                        mtfno = 32 + decodeBinary(ctxoff + 1, 5)
                                        data![i] = mtf[mtfno]
                                    } else {
                                        ctxoff += 1 + 31
                                        if zp.decode(ctx: &ctx, n: ctxoff) != 0 {
                                            mtfno = 64 + decodeBinary(ctxoff + 1, 6)
                                            data![i] = mtf[mtfno]
                                        } else {
                                            ctxoff += 1 + 63
                                            if zp.decode(ctx: &ctx, n: ctxoff) != 0 {
                                                mtfno = 128 + decodeBinary(ctxoff + 1, 7)
                                                data![i] = mtf[mtfno]
                                            } else {
                                                // Marker position
                                                mtfno = 256
                                                data![i] = 0
                                                markerpos = i
                                                continue
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Rotate MTF according to empirical frequencies
            fadd = fadd + (fadd >> fshift)
            if fadd > 0x10000000 {
                fadd >>= 24
                for k in 0..<FREQMAX { freq[k] >>= 24 }
            }

            var fc = fadd
            if mtfno < FREQMAX { fc += freq[mtfno] }

            var k = mtfno
            while k >= FREQMAX {
                mtf[k] = mtf[k - 1]
                k -= 1
            }
            while k > 0 && UInt32(truncatingIfNeeded: fc) >= UInt32(truncatingIfNeeded: freq[k - 1]) {
                mtf[k] = mtf[k - 1]
                freq[k] = freq[k - 1]
                k -= 1
            }
            mtf[k] = data![i]
            freq[k] = fc
        }

        // Inverse Burrows-Wheeler transform
        guard markerpos >= 1 && markerpos < size else { return 0 }

        var pos = [UInt32](repeating: 0, count: size)
        var count = [Int](repeating: 0, count: 256)

        for i in 0..<markerpos {
            let c = Int(data![i])
            pos[i] = UInt32(c << 24) | UInt32(count[c] & 0xFFFFFF)
            count[c] += 1
        }
        for i in (markerpos + 1)..<size {
            let c = Int(data![i])
            pos[i] = UInt32(c << 24) | UInt32(count[c] & 0xFFFFFF)
            count[c] += 1
        }

        var last = 1
        for i in 0..<256 {
            let tmp = count[i]
            count[i] = last
            last += tmp
        }

        var j = 0
        var remaining = size - 1
        while remaining > 0 {
            let n = pos[j]
            let c = Int(n >> 24)
            remaining -= 1
            data![remaining] = UInt8(c & 0xFF)
            j = count[c & 0xFF] + Int(n & 0xFFFFFF)
        }

        return size
    }

    /// Decode BZZ-compressed data into a ByteStream
    static func decode(stream: ByteStream) -> ByteStream {
        let zp = ZPCodec(stream: stream)
        let decoder = BZZDecoder(zp: zp)
        var result = Data()
        while true {
            let size = decoder.decodeBlock()
            guard size > 0, let blockData = decoder.data else { break }
            // DATA[0...size-2] contains the decoded bytes
            result.append(contentsOf: blockData[0..<(size - 1)])
        }
        return ByteStream(data: result)
    }
}
