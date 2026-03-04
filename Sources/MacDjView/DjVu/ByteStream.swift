import Foundation

final class ByteStream {
    let data: Data
    private(set) var offset: Int

    init(data: Data) {
        self.data = data
        self.offset = 0
    }

    init(data: Data, offset: Int) {
        self.data = data
        self.offset = offset
    }

    var remaining: Int { data.count - offset }
    var isAtEnd: Bool { offset >= data.count }

    func seek(to position: Int) {
        self.offset = position
    }

    func skip(_ count: Int) {
        offset += count
    }

    func readUInt8() throws -> UInt8 {
        guard offset < data.count else { throw DjVuError.truncatedData }
        let value = data[data.startIndex + offset]
        offset += 1
        return value
    }

    func readUInt16() throws -> UInt16 {
        guard offset + 2 <= data.count else { throw DjVuError.truncatedData }
        let b0 = UInt16(data[data.startIndex + offset])
        let b1 = UInt16(data[data.startIndex + offset + 1])
        offset += 2
        return (b0 << 8) | b1
    }

    func readUInt24() throws -> UInt32 {
        guard offset + 3 <= data.count else { throw DjVuError.truncatedData }
        let b0 = UInt32(data[data.startIndex + offset])
        let b1 = UInt32(data[data.startIndex + offset + 1])
        let b2 = UInt32(data[data.startIndex + offset + 2])
        offset += 3
        return (b0 << 16) | (b1 << 8) | b2
    }

    func readUInt32() throws -> UInt32 {
        guard offset + 4 <= data.count else { throw DjVuError.truncatedData }
        let b0 = UInt32(data[data.startIndex + offset])
        let b1 = UInt32(data[data.startIndex + offset + 1])
        let b2 = UInt32(data[data.startIndex + offset + 2])
        let b3 = UInt32(data[data.startIndex + offset + 3])
        offset += 4
        return (b0 << 24) | (b1 << 16) | (b2 << 8) | b3
    }

    func readString(_ count: Int) throws -> String {
        guard offset + count <= data.count else { throw DjVuError.truncatedData }
        let range = (data.startIndex + offset)..<(data.startIndex + offset + count)
        offset += count
        return String(bytes: data[range], encoding: .ascii) ?? ""
    }

    func readData(_ count: Int) throws -> Data {
        guard offset + count <= data.count else { throw DjVuError.truncatedData }
        let range = (data.startIndex + offset)..<(data.startIndex + offset + count)
        offset += count
        return data[range]
    }

    func substream(length: Int) throws -> ByteStream {
        guard offset + length <= data.count else { throw DjVuError.truncatedData }
        let sub = ByteStream(data: data[data.startIndex + offset ..< data.startIndex + offset + length])
        offset += length
        return sub
    }

    // Read a byte without advancing
    func peek() throws -> UInt8 {
        guard offset < data.count else { throw DjVuError.truncatedData }
        return data[data.startIndex + offset]
    }

    // For ZP-Coder: read bytes as needed
    subscript(index: Int) -> UInt8 {
        if index < data.count {
            return data[data.startIndex + index]
        }
        return 0xFF
    }

    /// Create a new stream from the remaining data (DjVu.js fork())
    func fork() -> ByteStream {
        let start = data.startIndex + offset
        let end = data.endIndex
        return ByteStream(data: data[start..<end])
    }

    /// Read a null-terminated string
    func readStrNT() -> String {
        var bytes: [UInt8] = []
        while offset < data.count {
            let b = data[data.startIndex + offset]
            offset += 1
            if b == 0 { break }
            bytes.append(b)
        }
        return String(bytes: bytes, encoding: .utf8) ?? ""
    }

    var isEmpty: Bool { offset >= data.count }
}
