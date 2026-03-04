import Foundation

final class ByteStream {
    let data: Data
    private let bytes: [UInt8]
    private(set) var offset: Int

    init(data: Data) {
        self.data = data
        self.bytes = [UInt8](data)
        self.offset = 0
    }

    init(data: Data, offset: Int) {
        self.data = data
        self.bytes = [UInt8](data)
        self.offset = offset
    }

    var remaining: Int { bytes.count - offset }
    var isAtEnd: Bool { offset >= bytes.count }

    func seek(to position: Int) {
        self.offset = position
    }

    func skip(_ count: Int) {
        offset += count
    }

    func readUInt8() throws -> UInt8 {
        guard offset < bytes.count else { throw DjVuError.truncatedData }
        let value = bytes[offset]
        offset += 1
        return value
    }

    func readUInt16() throws -> UInt16 {
        guard offset + 2 <= bytes.count else { throw DjVuError.truncatedData }
        let b0 = UInt16(bytes[offset])
        let b1 = UInt16(bytes[offset + 1])
        offset += 2
        return (b0 << 8) | b1
    }

    func readUInt24() throws -> UInt32 {
        guard offset + 3 <= bytes.count else { throw DjVuError.truncatedData }
        let b0 = UInt32(bytes[offset])
        let b1 = UInt32(bytes[offset + 1])
        let b2 = UInt32(bytes[offset + 2])
        offset += 3
        return (b0 << 16) | (b1 << 8) | b2
    }

    func readUInt32() throws -> UInt32 {
        guard offset + 4 <= bytes.count else { throw DjVuError.truncatedData }
        let b0 = UInt32(bytes[offset])
        let b1 = UInt32(bytes[offset + 1])
        let b2 = UInt32(bytes[offset + 2])
        let b3 = UInt32(bytes[offset + 3])
        offset += 4
        return (b0 << 24) | (b1 << 16) | (b2 << 8) | b3
    }

    func readString(_ count: Int) throws -> String {
        guard offset + count <= bytes.count else { throw DjVuError.truncatedData }
        let slice = bytes[offset..<(offset + count)]
        offset += count
        return String(bytes: slice, encoding: .ascii) ?? ""
    }

    func readData(_ count: Int) throws -> Data {
        guard offset + count <= bytes.count else { throw DjVuError.truncatedData }
        let result = Data(bytes[offset..<(offset + count)])
        offset += count
        return result
    }

    func substream(length: Int) throws -> ByteStream {
        guard offset + length <= bytes.count else { throw DjVuError.truncatedData }
        let sub = ByteStream(data: Data(bytes[offset..<(offset + length)]))
        offset += length
        return sub
    }

    // Read a byte without advancing
    func peek() throws -> UInt8 {
        guard offset < bytes.count else { throw DjVuError.truncatedData }
        return bytes[offset]
    }

    // For ZP-Coder: read bytes as needed
    subscript(index: Int) -> UInt8 {
        if index < bytes.count {
            return bytes[index]
        }
        return 0xFF
    }

    /// Create a new stream from the remaining data (DjVu.js fork())
    func fork() -> ByteStream {
        return ByteStream(data: Data(bytes[offset...]))
    }

    /// Read a null-terminated string
    func readStrNT() -> String {
        var result: [UInt8] = []
        while offset < bytes.count {
            let b = bytes[offset]
            offset += 1
            if b == 0 { break }
            result.append(b)
        }
        return String(bytes: result, encoding: .utf8) ?? ""
    }

    var isEmpty: Bool { offset >= bytes.count }
}
