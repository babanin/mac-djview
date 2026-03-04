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
    /// Map from component ID string to parsed JB2Dict
    private var sharedDictsByID: [String: JB2Dict] = [:]
    /// Fallback: all shared dicts in order (for documents without DIRM)
    private var sharedDicts: [JB2Dict] = []

    var pageCount: Int { pages.count }
    var sharedDictCount: Int { sharedDictsByID.count + sharedDicts.count }

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
        // Collect all children in order: DIRM, then FORM:DJVI and FORM:DJVU
        var dirmChunk: IFFChunk?
        var allFormChildren: [IFFChunk] = [] // DJVI and DJVU in document order

        for child in rootChunk.children {
            if child.id == "DIRM" {
                dirmChunk = child
            } else if child.isForm && (child.formType == "DJVU" || child.formType == "DJVI") {
                allFormChildren.append(child)
            }
        }

        // Parse DIRM to get component IDs
        var componentIDs: [String]?
        var componentFlags: [UInt8]?
        if let dirm = dirmChunk {
            let parsed = try parseDIRM(data: dirm.data)
            componentIDs = parsed.ids
            componentFlags = parsed.flags
        }

        // Build maps using DIRM info
        if let ids = componentIDs, let flags = componentFlags, ids.count == allFormChildren.count {
            for (i, child) in allFormChildren.enumerated() {
                let id = ids[i]
                let flag = flags[i]
                let componentType = flag & 0x3F

                if child.isForm && child.formType == "DJVI" && componentType == 0 {
                    // Shared component — parse its Djbz dictionary
                    for subchunk in child.children {
                        if subchunk.id == "Djbz" {
                            let dict = try JB2Dict.decode(from: subchunk.data)
                            sharedDictsByID[id] = dict
                        }
                    }
                } else if child.isForm && child.formType == "DJVU" && componentType == 1 {
                    pageChunks.append(child)
                }
            }
        } else {
            // Fallback: no DIRM or mismatched counts — use old approach
            for child in allFormChildren {
                if child.isForm && child.formType == "DJVU" {
                    pageChunks.append(child)
                } else if child.isForm && child.formType == "DJVI" {
                    for subchunk in child.children {
                        if subchunk.id == "Djbz" {
                            let dict = try JB2Dict.decode(from: subchunk.data)
                            sharedDicts.append(dict)
                        }
                    }
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

    /// Parse DIRM chunk to extract component IDs and flags
    private func parseDIRM(data: Data) throws -> (ids: [String], flags: [UInt8]) {
        let stream = ByteStream(data: data)
        let dflags = try stream.readUInt8()
        let isBundled = (dflags >> 7) != 0
        let nfiles = Int(try stream.readUInt16())

        // Skip offsets array for bundled documents
        if isBundled {
            stream.skip(nfiles * 4) // Int32 per file
        }

        // Decode BZZ-compressed body
        let bzzStream = BZZDecoder.decode(stream: stream.fork())

        // Read sizes (3 bytes each)
        for _ in 0..<nfiles {
            let _ = try bzzStream.readUInt24()
        }

        // Read flags (1 byte each)
        var flags = [UInt8]()
        for _ in 0..<nfiles {
            flags.append(try bzzStream.readUInt8())
        }

        // Read IDs (null-terminated strings)
        var ids = [String]()
        for i in 0..<nfiles {
            guard !bzzStream.isEmpty else { break }
            let id = bzzStream.readStrNT()
            ids.append(id)
            // Skip name if hasname flag set
            if flags[i] & 128 != 0 {
                let _ = bzzStream.readStrNT()
            }
            // Skip title if hastitle flag set
            if flags[i] & 64 != 0 {
                let _ = bzzStream.readStrNT()
            }
        }

        return (ids: ids, flags: flags)
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
                let width = try stream.readUInt16()
                let height = try stream.readUInt16()
                let minorVersion = try stream.readUInt8()
                let majorVersion = try stream.readUInt8()
                let dpiLo = try stream.readUInt8()
                let dpiHi = try stream.readUInt8()
                let dpiRaw = Int(dpiHi) << 8 | Int(dpiLo)
                let dpi = dpiRaw == 0 ? 300 : dpiRaw
                let _ = try stream.readUInt8() // gamma
                let flags = stream.remaining > 0 ? (try stream.readUInt8()) : 0
                let rotation = Int(flags & 0x07)

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

    /// Find the shared dict for a page by resolving its INCL chunk
    private func sharedDictForPage(at index: Int) -> JB2Dict? {
        let pageChunk = pageChunks[index]

        // Look for INCL chunk in this page
        for child in pageChunk.children {
            if child.id == "INCL" {
                let ref = String(data: child.data, encoding: .utf8)?
                    .trimmingCharacters(in: .controlCharacters) ?? ""
                if let dict = sharedDictsByID[ref] {
                    return dict
                }
            }
        }

        // Fallback: use first available dict
        if !sharedDictsByID.isEmpty {
            return sharedDictsByID.values.first
        }
        return sharedDicts.first
    }

    func renderPage(at index: Int, scale: Double = 1.0) throws -> CGImage {
        guard index >= 0, index < pageCount else {
            throw DjVuError.invalidPageIndex(index)
        }

        let pageChunk = pageChunks[index]
        let info = pages[index]
        let dict = sharedDictForPage(at: index)

        let page = DjVuPage(chunk: pageChunk, info: info, sharedDict: dict)
        return try page.render(scale: scale)
    }
}
