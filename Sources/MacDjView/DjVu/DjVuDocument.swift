import Foundation
import CoreGraphics

final class DjVuDocument: @unchecked Sendable {
    struct PageInfo {
        let width: Int
        let height: Int
        let dpi: Int
        let rotation: Int
        let version: Int
    }

    private let data: Data
    private let rootChunk: IFFChunk
    private(set) var pages: [PageInfo] = []
    private var pageChunks: [IFFChunk] = []
    private var sharedDicts: [JB2Dict] = []

    var pageCount: Int { pages.count }

    init(data: Data) throws {
        self.data = data
        self.rootChunk = try IFFParser.parse(data: data)

        guard rootChunk.isForm else {
            throw DjVuError.invalidFormat("Root is not a FORM chunk")
        }

        if rootChunk.formType == "DJVM" {
            try parseBundledDocument()
        } else if rootChunk.formType == "DJVU" {
            try parseSinglePage(rootChunk)
        } else {
            throw DjVuError.invalidFormat("Unknown FORM type: \(rootChunk.formType ?? "nil")")
        }
    }

    private func parseBundledDocument() throws {
        // Find all FORM:DJVU pages and FORM:DJVI shared pages
        var sharedChunks: [IFFChunk] = []

        for child in rootChunk.children {
            if child.isForm && child.formType == "DJVU" {
                pageChunks.append(child)
            } else if child.isForm && child.formType == "DJVI" {
                sharedChunks.append(child)
            }
        }

        // Parse shared dictionaries from DJVI chunks
        for shared in sharedChunks {
            for chunk in shared.children {
                if chunk.id == "Djbz" {
                    let dict = try JB2Dict.decode(from: chunk.data)
                    sharedDicts.append(dict)
                }
            }
        }

        // Parse page info for each page
        for pageChunk in pageChunks {
            let info = try parsePageInfo(from: pageChunk)
            pages.append(info)
        }

        if pages.isEmpty {
            throw DjVuError.invalidFormat("No pages found in document")
        }
    }

    private func parseSinglePage(_ chunk: IFFChunk) throws {
        pageChunks.append(chunk)
        let info = try parsePageInfo(from: chunk)
        pages.append(info)
    }

    private func parsePageInfo(from formChunk: IFFChunk) throws -> PageInfo {
        for chunk in formChunk.children {
            if chunk.id == "INFO" {
                let stream = ByteStream(data: chunk.data)
                // INFO chunk: width(2) height(2) minor_version(1) major_version(1) dpi(2) gamma(1) flags(1)
                let width = try stream.readUInt16()
                let height = try stream.readUInt16()
                let minorVersion = try stream.readUInt8()
                let majorVersion = try stream.readUInt8()
                // DPI is stored little-endian in DjVu INFO chunk
                let dpiLo = try stream.readUInt8()
                let dpiHi = try stream.readUInt8()
                let dpiRaw = Int(dpiHi) << 8 | Int(dpiLo)
                let dpi = dpiRaw == 0 ? 300 : dpiRaw
                let _ = try stream.readUInt8() // gamma
                let flags = stream.remaining > 0 ? (try stream.readUInt8()) : 0
                let rotation = Int(flags & 0x07) // rotation in low 3 bits

                return PageInfo(
                    width: Int(width),
                    height: Int(height),
                    dpi: dpi,
                    rotation: rotation,
                    version: Int(majorVersion) * 100 + Int(minorVersion)
                )
            }
        }
        throw DjVuError.invalidFormat("No INFO chunk found in page")
    }

    func renderPage(at index: Int, scale: Double = 1.0) throws -> CGImage {
        guard index >= 0, index < pageCount else {
            throw DjVuError.invalidPageIndex(index)
        }

        let pageChunk = pageChunks[index]
        let info = pages[index]

        let page = DjVuPage(chunk: pageChunk, info: info, sharedDicts: sharedDicts)
        return try page.render(scale: scale)
    }
}
