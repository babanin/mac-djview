import Foundation

struct IFFChunk {
    let id: String
    let data: Data
    let children: [IFFChunk]
    let formType: String?  // non-nil for FORM chunks

    var isForm: Bool { formType != nil }
}

final class IFFParser {
    static func parse(data: Data) throws -> IFFChunk {
        let stream = ByteStream(data: data)

        // Check for AT&TFORM magic
        let magic = try stream.readString(4)
        guard magic == "AT&T" else {
            throw DjVuError.invalidMagic
        }

        return try parseChunk(stream: stream)
    }

    static func parseChunk(stream: ByteStream) throws -> IFFChunk {
        let id = try stream.readString(4)
        let length = try stream.readUInt32()

        if id == "FORM" {
            let formType = try stream.readString(4)
            let contentLength = Int(length) - 4
            var children: [IFFChunk] = []
            let endOffset = stream.offset + contentLength

            while stream.offset < endOffset {
                let child = try parseChunk(stream: stream)
                children.append(child)
            }

            return IFFChunk(id: id, data: Data(), children: children, formType: formType)
        } else {
            let chunkData = try stream.readData(Int(length))
            // Pad to even boundary
            if length % 2 != 0 && !stream.isAtEnd {
                stream.skip(1)
            }
            return IFFChunk(id: id, data: chunkData, children: [], formType: nil)
        }
    }

    static func findChunks(in chunk: IFFChunk, withId targetId: String) -> [IFFChunk] {
        var results: [IFFChunk] = []
        if chunk.id == targetId {
            results.append(chunk)
        }
        for child in chunk.children {
            results.append(contentsOf: findChunks(in: child, withId: targetId))
        }
        return results
    }
}
