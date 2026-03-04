import Foundation

/// JB2 symbol dictionary - stores decoded bitmaps.
/// Faithfully ported from DjVu.js JB2Dict.js
final class JB2Dict {
    var symbols: [JB2Bitmap] = []

    init() {}

    /// Decode a standalone dictionary (Djbz chunk).
    /// Ported from DjVu.js JB2Dict.decode()
    static func decode(from data: Data) throws -> JB2Dict {
        let stream = ByteStream(data: data)
        let zp = ZPCodec(stream: stream)
        let dict = JB2Dict()

        var directBitmapCtx = [UInt8](repeating: 0, count: 1024)
        var refinementBitmapCtx = [UInt8](repeating: 0, count: 2048)

        let recordTypeCtx = NumContext()
        let imageSizeCtx = NumContext()
        let inheritDictSizeCtx = NumContext()
        let symbolWidthCtx = NumContext()
        let symbolHeightCtx = NumContext()
        let symbolIndexCtx = NumContext()
        let symbolWidthDiffCtx = NumContext()
        let symbolHeightDiffCtx = NumContext()
        let commentLengthCtx = NumContext()
        let commentOctetCtx = NumContext()

        // Step 1: Read initial record type (may be 9 for inherited dict)
        var type = zp.decodeNum(ctx: recordTypeCtx, low: 0, high: 11)
        if type == 9 {
            // Inherited dict size — we don't support nested inheritance yet
            let _ = zp.decodeNum(ctx: inheritDictSizeCtx, low: 0, high: 262142)
            type = zp.decodeNum(ctx: recordTypeCtx, low: 0, high: 11)
        }

        // Step 2: Read image size
        let _ = zp.decodeNum(ctx: imageSizeCtx, low: 0, high: 262142) // width
        let _ = zp.decodeNum(ctx: imageSizeCtx, low: 0, high: 262142) // height

        // Step 3: Read flag (raw ZP bit, NOT decodeNum)
        var flagCtx: [UInt8] = [0]
        let flag = zp.decode(ctx: &flagCtx, n: 0)
        if flag != 0 {
            throw DjVuError.decodingFailed("JB2Dict: bad flag")
        }

        // Step 4: Decode records
        type = zp.decodeNum(ctx: recordTypeCtx, low: 0, high: 11)

        while type != 11 {
            switch type {
            case 2: // New symbol - direct bitmap, add to library
                let w = zp.decodeNum(ctx: symbolWidthCtx, low: 0, high: 262142)
                let h = zp.decodeNum(ctx: symbolHeightCtx, low: 0, high: 262142)
                let bm = decodeBitmap(zp: zp, width: w, height: h, ctx: &directBitmapCtx)
                dict.symbols.append(bm)

            case 5: // Refinement bitmap, add to library
                let idx = zp.decodeNum(ctx: symbolIndexCtx, low: 0, high: max(0, dict.symbols.count - 1))
                let wdiff = zp.decodeNum(ctx: symbolWidthDiffCtx, low: -262143, high: 262142)
                let hdiff = zp.decodeNum(ctx: symbolHeightDiffCtx, low: -262143, high: 262142)
                let model = idx < dict.symbols.count ? dict.symbols[idx] : JB2Bitmap(width: 1, height: 1)
                let bm = decodeRefinementBitmap(zp: zp,
                    width: model.width + wdiff, height: model.height + hdiff,
                    model: model, ctx: &refinementBitmapCtx)
                dict.symbols.append(bm.removeEmptyEdges())

            case 9: // Numcoder reset
                resetNumContexts(recordTypeCtx, imageSizeCtx, inheritDictSizeCtx,
                                 symbolWidthCtx, symbolHeightCtx, symbolIndexCtx,
                                 symbolWidthDiffCtx, symbolHeightDiffCtx,
                                 commentLengthCtx, commentOctetCtx)

            case 10: // Comment
                let length = zp.decodeNum(ctx: commentLengthCtx, low: 0, high: 262142)
                for _ in 0..<length {
                    let _ = zp.decodeNum(ctx: commentOctetCtx, low: 0, high: 255)
                }

            default:
                break
            }

            type = zp.decodeNum(ctx: recordTypeCtx, low: 0, high: 11)
            if type > 11 { break }
        }

        return dict
    }
}

// MARK: - Bitmap decoding helpers (shared between JB2Dict and JB2Decoder)

/// Decode a direct bitmap using context-based ZP coding.
/// Ported from DjVu.js JB2Codec.decodeBitmap()
func decodeBitmap(zp: ZPCodec, width: Int, height: Int, ctx: inout [UInt8]) -> JB2Bitmap {
    let bm = JB2Bitmap(width: width, height: height)
    for i in stride(from: height - 1, through: 0, by: -1) {
        for j in 0..<width {
            var index = 0
            if bm.hasRow(i + 2) {
                index = bm.getBits(i + 2, j - 1, 3) << 7
            }
            if bm.hasRow(i + 1) {
                index |= bm.getBits(i + 1, j - 2, 5) << 2
            }
            index |= bm.getBits(i, j - 2, 2)
            if zp.decode(ctx: &ctx, n: index & 0x3FF) != 0 {
                bm.set(i, j)
            }
        }
    }
    return bm
}

/// Decode a refinement bitmap using a model bitmap.
/// Ported from DjVu.js JB2Codec.decodeBitmapRef() + getCtxIndexRef()
func decodeRefinementBitmap(zp: ZPCodec, width: Int, height: Int,
                            model: JB2Bitmap, ctx: inout [UInt8]) -> JB2Bitmap {
    let cbm = JB2Bitmap(width: width, height: height)

    // Alignment: match DjVu.js alignBitmaps()
    let crow = (height - 1) >> 1
    let ccol = (width - 1) >> 1
    let mrow = (model.height - 1) >> 1
    let mcol = (model.width - 1) >> 1
    let rowshift = mrow - crow
    let colshift = mcol - ccol

    for i in stride(from: height - 1, through: 0, by: -1) {
        for j in 0..<width {
            var index = 0

            // Current bitmap context
            let r1 = i + 1
            if cbm.hasRow(r1) {
                index = cbm.getBits(r1, j - 1, 3) << 8
            }
            index |= cbm.get(i, j - 1) << 7

            // Model bitmap context
            var mr = i + rowshift + 1
            let mc = j + colshift
            index |= (model.hasRow(mr) ? model.get(mr, mc) : 0) << 6
            mr -= 1
            if model.hasRow(mr) {
                index |= model.getBits(mr, mc - 1, 3) << 3
            }
            mr -= 1
            if model.hasRow(mr) {
                index |= model.getBits(mr, mc - 1, 3)
            }

            if zp.decode(ctx: &ctx, n: index & 0x7FF) != 0 {
                cbm.set(i, j)
            }
        }
    }
    return cbm
}

func resetNumContexts(_ ctxs: NumContext...) {
    for ctx in ctxs {
        ctx.ctx = [0]
    }
}
