import Foundation
import CoreGraphics

final class DjVuPage {
    let chunk: IFFChunk
    let info: DjVuDocument.PageInfo
    let sharedDict: JB2Dict?

    let width: Int
    let height: Int
    let dpi: Int

    init(chunk: IFFChunk, info: DjVuDocument.PageInfo, sharedDict: JB2Dict?) {
        self.chunk = chunk
        self.info = info
        self.sharedDict = sharedDict
        self.width = info.width
        self.height = info.height
        self.dpi = info.dpi
    }

    func render(scale: Double) throws -> CGImage {
        // Collect chunks by type
        var bg44Chunks: [Data] = []
        var fg44Chunks: [Data] = []
        var sjbzData: Data?
        var fgbzData: Data?
        var inclChunks: [String] = []

        for child in chunk.children {
            switch child.id {
            case "BG44":
                bg44Chunks.append(child.data)
            case "FG44":
                fg44Chunks.append(child.data)
            case "Sjbz":
                sjbzData = child.data
            case "FGbz":
                fgbzData = child.data
            case "INCL":
                if let name = String(data: child.data, encoding: .ascii) {
                    inclChunks.append(name.trimmingCharacters(in: .controlCharacters))
                }
            default:
                break
            }
        }

        // Decode background (IW44)
        var bgImage: IW44Image?
        if !bg44Chunks.isEmpty {
            let decoder = IW44Decoder()
            for chunkData in bg44Chunks {
                try decoder.decodeChunk(data: chunkData)
            }
            bgImage = try decoder.getImage()
        }

        // Decode foreground color (IW44)
        var fgImage: IW44Image?
        if !fg44Chunks.isEmpty {
            let decoder = IW44Decoder()
            for chunkData in fg44Chunks {
                try decoder.decodeChunk(data: chunkData)
            }
            fgImage = try decoder.getImage()
        }

        // Decode mask (JB2)
        var maskImage: JB2Image?
        if let sjbzData {
            maskImage = try JB2Decoder.decode(data: sjbzData, sharedDict: sharedDict)
        }

        // Decode foreground colors palette
        var fgbzPalette: FGbzPalette?
        if let fgbzData {
            fgbzPalette = try FGbzPalette.decode(from: fgbzData)
        }

        // Compose layers
        return try PageCompositor.compose(
            width: width,
            height: height,
            background: bgImage,
            foreground: fgImage,
            mask: maskImage,
            fgPalette: fgbzPalette,
            scale: scale
        )
    }
}

struct FGbzPalette {
    let colors: [(r: UInt8, g: UInt8, b: UInt8)]
    let blitColors: [Int] // color index per blit

    static func decode(from data: Data) throws -> FGbzPalette {
        let stream = ByteStream(data: data)
        let header = try stream.readUInt8()
        let hasIndices = (header >> 7) & 1
        let version = header & 0x7F
        guard version == 0 else {
            throw DjVuError.invalidFormat("Unsupported FGbz version: \(version)")
        }

        let numColors = Int(try stream.readUInt16())
        var colors: [(r: UInt8, g: UInt8, b: UInt8)] = []
        for _ in 0..<numColors {
            let b = try stream.readUInt8()
            let g = try stream.readUInt8()
            let r = try stream.readUInt8()
            colors.append((r: r, g: g, b: b))
        }

        var blitColors: [Int] = []
        if hasIndices != 0 {
            let zp = ZPCodec(stream: stream)
            let numBlitsCtx = NumContext()
            let numBlits = zp.decodeNum(ctx: numBlitsCtx, low: 0, high: 0xFFFFFF)
            let colorCtx = NumContext()
            for _ in 0..<numBlits {
                let colorIdx = zp.decodeNum(ctx: colorCtx, low: 0, high: max(0, numColors - 1))
                blitColors.append(colorIdx)
            }
        }

        return FGbzPalette(colors: colors, blitColors: blitColors)
    }
}
