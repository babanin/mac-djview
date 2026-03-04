import Foundation

/// JB2 decoder for Sjbz chunks (mask/text layer).
/// Faithfully ported from DjVu.js JB2Image.js
final class JB2Decoder {

    static func decode(data: Data, sharedDict: JB2Dict?) throws -> JB2Image {
        let stream = ByteStream(data: data)
        let zp = ZPCodec(stream: stream)

        // Context arrays
        var directBitmapCtx = [UInt8](repeating: 0, count: 1024)
        var refinementBitmapCtx = [UInt8](repeating: 0, count: 2048)
        var offsetTypeCtx: [UInt8] = [0]

        let recordTypeCtx = NumContext()
        let imageSizeCtx = NumContext()
        let inheritDictSizeCtx = NumContext()
        let symbolWidthCtx = NumContext()
        let symbolHeightCtx = NumContext()
        let symbolIndexCtx = NumContext()
        let symbolWidthDiffCtx = NumContext()
        let symbolHeightDiffCtx = NumContext()
        let hoffCtx = NumContext()     // new-line horizontal offset
        let voffCtx = NumContext()     // new-line vertical offset
        let shoffCtx = NumContext()    // same-line horizontal offset
        let svoffCtx = NumContext()    // same-line vertical offset
        let commentLengthCtx = NumContext()
        let commentOctetCtx = NumContext()
        let horizontalAbsLocationCtx = NumContext()
        let verticalAbsLocationCtx = NumContext()

        // Step 1: Read initial record type (may be 9 for inherited dict)
        var initialDictLength = 0
        var type = zp.decodeNum(ctx: recordTypeCtx, low: 0, high: 11)
        if type == 9 {
            initialDictLength = zp.decodeNum(ctx: inheritDictSizeCtx, low: 0, high: 262142)
            type = zp.decodeNum(ctx: recordTypeCtx, low: 0, high: 11)
        }

        // Step 2: Read image size
        let imgWidth = zp.decodeNum(ctx: imageSizeCtx, low: 0, high: 262142)
        let imgHeight = zp.decodeNum(ctx: imageSizeCtx, low: 0, high: 262142)
        let w = imgWidth > 0 ? imgWidth : 200
        let h = imgHeight > 0 ? imgHeight : 200

        // Step 3: Read flag (raw ZP bit, NOT decodeNum)
        var flagCtx: [UInt8] = [0]
        let flag = zp.decode(ctx: &flagCtx, n: 0)
        if flag != 0 {
            throw DjVuError.decodingFailed("JB2: bad flag")
        }

        let image = JB2Image(width: w, height: h)

        // Build library from shared dict
        var library: [JB2Bitmap] = []
        if initialDictLength > 0, let sharedDict {
            library = Array(sharedDict.symbols.prefix(initialDictLength))
        }

        // Coordinate tracking (matching DjVu.js JB2Image.init())
        var lastRight = 0
        var firstLeft = -1       // DjVu.js initializes to -1
        var firstBottom = h - 1  // DjVu.js: this.height - 1
        let baseline = Baseline()
        baseline.fill(0)

        // Step 4: Decode records
        type = zp.decodeNum(ctx: recordTypeCtx, low: 0, high: 11)

        while type != 11 {
            switch type {
            case 1: // New symbol - add to image AND library (direct bitmap)
                let bw = zp.decodeNum(ctx: symbolWidthCtx, low: 0, high: 262142)
                let bh = zp.decodeNum(ctx: symbolHeightCtx, low: 0, high: 262142)
                let bm = decodeBitmap(zp: zp, width: bw, height: bh, ctx: &directBitmapCtx)
                let (x, y) = decodeSymbolCoords(
                    zp: zp, bmWidth: bm.width, bmHeight: bm.height,
                    offsetTypeCtx: &offsetTypeCtx,
                    hoffCtx: hoffCtx, voffCtx: voffCtx,
                    shoffCtx: shoffCtx, svoffCtx: svoffCtx,
                    baseline: baseline,
                    lastRight: &lastRight,
                    firstLeft: &firstLeft, firstBottom: &firstBottom,
                    imgHeight: h)
                image.addBlit(JB2Blit(bitmap: bm, x: x, y: y))
                library.append(bm.removeEmptyEdges())

            case 2: // New symbol - library only
                let bw = zp.decodeNum(ctx: symbolWidthCtx, low: 0, high: 262142)
                let bh = zp.decodeNum(ctx: symbolHeightCtx, low: 0, high: 262142)
                let bm = decodeBitmap(zp: zp, width: bw, height: bh, ctx: &directBitmapCtx)
                library.append(bm.removeEmptyEdges())

            case 3: // New symbol - image only
                let bw = zp.decodeNum(ctx: symbolWidthCtx, low: 0, high: 262142)
                let bh = zp.decodeNum(ctx: symbolHeightCtx, low: 0, high: 262142)
                let bm = decodeBitmap(zp: zp, width: bw, height: bh, ctx: &directBitmapCtx)
                let (x, y) = decodeSymbolCoords(
                    zp: zp, bmWidth: bm.width, bmHeight: bm.height,
                    offsetTypeCtx: &offsetTypeCtx,
                    hoffCtx: hoffCtx, voffCtx: voffCtx,
                    shoffCtx: shoffCtx, svoffCtx: svoffCtx,
                    baseline: baseline,
                    lastRight: &lastRight,
                    firstLeft: &firstLeft, firstBottom: &firstBottom,
                    imgHeight: h)
                image.addBlit(JB2Blit(bitmap: bm, x: x, y: y))

            case 4: // Refinement - add to image AND library
                let idx = zp.decodeNum(ctx: symbolIndexCtx, low: 0, high: max(0, library.count - 1))
                let wdiff = zp.decodeNum(ctx: symbolWidthDiffCtx, low: -262143, high: 262142)
                let hdiff = zp.decodeNum(ctx: symbolHeightDiffCtx, low: -262143, high: 262142)
                let model = idx < library.count ? library[idx] : JB2Bitmap(width: 1, height: 1)
                let bm = decodeRefinementBitmap(zp: zp,
                    width: model.width + wdiff, height: model.height + hdiff,
                    model: model, ctx: &refinementBitmapCtx)
                let (x, y) = decodeSymbolCoords(
                    zp: zp, bmWidth: bm.width, bmHeight: bm.height,
                    offsetTypeCtx: &offsetTypeCtx,
                    hoffCtx: hoffCtx, voffCtx: voffCtx,
                    shoffCtx: shoffCtx, svoffCtx: svoffCtx,
                    baseline: baseline,
                    lastRight: &lastRight,
                    firstLeft: &firstLeft, firstBottom: &firstBottom,
                    imgHeight: h)
                image.addBlit(JB2Blit(bitmap: bm, x: x, y: y))
                library.append(bm.removeEmptyEdges())

            case 5: // Refinement - library only
                let idx = zp.decodeNum(ctx: symbolIndexCtx, low: 0, high: max(0, library.count - 1))
                let wdiff = zp.decodeNum(ctx: symbolWidthDiffCtx, low: -262143, high: 262142)
                let hdiff = zp.decodeNum(ctx: symbolHeightDiffCtx, low: -262143, high: 262142)
                let model = idx < library.count ? library[idx] : JB2Bitmap(width: 1, height: 1)
                let bm = decodeRefinementBitmap(zp: zp,
                    width: model.width + wdiff, height: model.height + hdiff,
                    model: model, ctx: &refinementBitmapCtx)
                library.append(bm.removeEmptyEdges())

            case 6: // Refinement - image only
                let idx = zp.decodeNum(ctx: symbolIndexCtx, low: 0, high: max(0, library.count - 1))
                let wdiff = zp.decodeNum(ctx: symbolWidthDiffCtx, low: -262143, high: 262142)
                let hdiff = zp.decodeNum(ctx: symbolHeightDiffCtx, low: -262143, high: 262142)
                let model = idx < library.count ? library[idx] : JB2Bitmap(width: 1, height: 1)
                let bm = decodeRefinementBitmap(zp: zp,
                    width: model.width + wdiff, height: model.height + hdiff,
                    model: model, ctx: &refinementBitmapCtx)
                let (x, y) = decodeSymbolCoords(
                    zp: zp, bmWidth: bm.width, bmHeight: bm.height,
                    offsetTypeCtx: &offsetTypeCtx,
                    hoffCtx: hoffCtx, voffCtx: voffCtx,
                    shoffCtx: shoffCtx, svoffCtx: svoffCtx,
                    baseline: baseline,
                    lastRight: &lastRight,
                    firstLeft: &firstLeft, firstBottom: &firstBottom,
                    imgHeight: h)
                image.addBlit(JB2Blit(bitmap: bm, x: x, y: y))

            case 7: // Matched symbol copy (no refinement)
                let idx = zp.decodeNum(ctx: symbolIndexCtx, low: 0, high: max(0, library.count - 1))
                let bm = idx < library.count ? library[idx] : JB2Bitmap(width: 1, height: 1)
                let (x, y) = decodeSymbolCoords(
                    zp: zp, bmWidth: bm.width, bmHeight: bm.height,
                    offsetTypeCtx: &offsetTypeCtx,
                    hoffCtx: hoffCtx, voffCtx: voffCtx,
                    shoffCtx: shoffCtx, svoffCtx: svoffCtx,
                    baseline: baseline,
                    lastRight: &lastRight,
                    firstLeft: &firstLeft, firstBottom: &firstBottom,
                    imgHeight: h)
                image.addBlit(JB2Blit(bitmap: bm, x: x, y: y))

            case 8: // Non-symbol data (direct bitmap with absolute coordinates)
                let bw = zp.decodeNum(ctx: symbolWidthCtx, low: 0, high: 262142)
                let bh = zp.decodeNum(ctx: symbolHeightCtx, low: 0, high: 262142)
                let bm = decodeBitmap(zp: zp, width: bw, height: bh, ctx: &directBitmapCtx)
                let left = zp.decodeNum(ctx: horizontalAbsLocationCtx, low: 1, high: w)
                let top = zp.decodeNum(ctx: verticalAbsLocationCtx, low: 1, high: h)
                image.addBlit(JB2Blit(bitmap: bm, x: left, y: top - bh))

            case 9: // Numcoder reset
                resetNumContexts(recordTypeCtx, imageSizeCtx, inheritDictSizeCtx,
                                 symbolWidthCtx, symbolHeightCtx, symbolIndexCtx,
                                 symbolWidthDiffCtx, symbolHeightDiffCtx,
                                 hoffCtx, voffCtx, shoffCtx, svoffCtx,
                                 commentLengthCtx, commentOctetCtx,
                                 horizontalAbsLocationCtx, verticalAbsLocationCtx)

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

        return image
    }

    /// Decode symbol coordinates.
    /// Ported from DjVu.js JB2Image.decodeSymbolCoords()
    private static func decodeSymbolCoords(
        zp: ZPCodec,
        bmWidth: Int, bmHeight: Int,
        offsetTypeCtx: inout [UInt8],
        hoffCtx: NumContext, voffCtx: NumContext,
        shoffCtx: NumContext, svoffCtx: NumContext,
        baseline: Baseline,
        lastRight: inout Int,
        firstLeft: inout Int, firstBottom: inout Int,
        imgHeight: Int
    ) -> (Int, Int) {
        let isNewLine = zp.decode(ctx: &offsetTypeCtx, n: 0) != 0
        var x: Int
        var y: Int

        if isNewLine {
            // New line: use hoffCtx/voffCtx
            let hoff = zp.decodeNum(ctx: hoffCtx, low: -262143, high: 262142)
            let voff = zp.decodeNum(ctx: voffCtx, low: -262143, high: 262142)
            x = firstLeft + hoff
            y = firstBottom + voff - bmHeight + 1
            firstLeft = x
            firstBottom = y
            baseline.fill(y)
        } else {
            // Same line: use shoffCtx/svoffCtx
            let hoff = zp.decodeNum(ctx: shoffCtx, low: -262143, high: 262142)
            let voff = zp.decodeNum(ctx: svoffCtx, low: -262143, high: 262142)
            x = lastRight + hoff
            y = baseline.getVal() + voff
        }

        baseline.add(y)
        lastRight = x + bmWidth - 1  // DjVu.js: this.lastRight = x + width - 1
        return (x, y)
    }
}
