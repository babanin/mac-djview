import Foundation
import Testing
@testable import MacDjView

@Suite("ByteStream — UnsafeBufferPointer-backed reads")
struct ByteStreamTests {

    @Test("readUInt8 returns correct bytes")
    func readUInt8() throws {
        let data = Data([0xAB, 0xCD, 0xEF])
        let stream = ByteStream(data: data)
        #expect(try stream.readUInt8() == 0xAB)
        #expect(try stream.readUInt8() == 0xCD)
        #expect(try stream.readUInt8() == 0xEF)
        #expect(stream.isAtEnd)
    }

    @Test("readUInt8 throws on empty stream")
    func readUInt8Throws() {
        let stream = ByteStream(data: Data())
        #expect(throws: DjVuError.self) { try stream.readUInt8() }
    }

    @Test("readUInt16 big-endian")
    func readUInt16() throws {
        let stream = ByteStream(data: Data([0x01, 0x02, 0xFF, 0x00]))
        #expect(try stream.readUInt16() == 0x0102)
        #expect(try stream.readUInt16() == 0xFF00)
    }

    @Test("readUInt24 big-endian")
    func readUInt24() throws {
        let stream = ByteStream(data: Data([0x01, 0x02, 0x03]))
        #expect(try stream.readUInt24() == 0x010203)
    }

    @Test("readUInt32 big-endian")
    func readUInt32() throws {
        let stream = ByteStream(data: Data([0xDE, 0xAD, 0xBE, 0xEF]))
        #expect(try stream.readUInt32() == 0xDEADBEEF)
    }

    @Test("seek and skip move offset correctly")
    func seekAndSkip() throws {
        let stream = ByteStream(data: Data([10, 20, 30, 40, 50]))
        stream.skip(2)
        #expect(try stream.readUInt8() == 30)
        stream.seek(to: 0)
        #expect(try stream.readUInt8() == 10)
    }

    @Test("remaining and isAtEnd track position")
    func remainingTracking() throws {
        let stream = ByteStream(data: Data([1, 2, 3]))
        #expect(stream.remaining == 3)
        #expect(!stream.isAtEnd)
        _ = try stream.readUInt8()
        #expect(stream.remaining == 2)
        _ = try stream.readUInt16()
        #expect(stream.remaining == 0)
        #expect(stream.isAtEnd)
    }

    @Test("peek does not advance offset")
    func peek() throws {
        let stream = ByteStream(data: Data([0x42, 0x43]))
        #expect(try stream.peek() == 0x42)
        #expect(try stream.peek() == 0x42)
        _ = try stream.readUInt8()
        #expect(try stream.peek() == 0x43)
    }

    @Test("subscript returns 0xFF for out-of-range indices")
    func subscriptOutOfRange() {
        let stream = ByteStream(data: Data([0x01, 0x02]))
        #expect(stream[0] == 0x01)
        #expect(stream[1] == 0x02)
        #expect(stream[2] == 0xFF)
        #expect(stream[999] == 0xFF)
    }

    @Test("readString returns ASCII text")
    func readString() throws {
        let bytes: [UInt8] = [0x48, 0x69, 0x21]  // "Hi!"
        let stream = ByteStream(data: Data(bytes))
        #expect(try stream.readString(3) == "Hi!")
    }

    @Test("readData returns correct slice")
    func readData() throws {
        let stream = ByteStream(data: Data([1, 2, 3, 4, 5]))
        stream.skip(1)
        let sub = try stream.readData(3)
        #expect([UInt8](sub) == [2, 3, 4])
        #expect(stream.remaining == 1)
    }

    @Test("substream creates independent stream with correct data")
    func substream() throws {
        let stream = ByteStream(data: Data([10, 20, 30, 40, 50]))
        stream.skip(1)
        let sub = try stream.substream(length: 3)
        #expect(try sub.readUInt8() == 20)
        #expect(try sub.readUInt8() == 30)
        #expect(try sub.readUInt8() == 40)
        #expect(sub.isAtEnd)
        #expect(stream.remaining == 1)
    }

    @Test("fork creates stream from remaining data")
    func fork() throws {
        let stream = ByteStream(data: Data([1, 2, 3, 4]))
        _ = try stream.readUInt8()
        _ = try stream.readUInt8()
        let forked = stream.fork()
        #expect(try forked.readUInt8() == 3)
        #expect(try forked.readUInt8() == 4)
        #expect(forked.isAtEnd)
    }

    @Test("readStrNT reads null-terminated string")
    func readStrNT() {
        let bytes: [UInt8] = [0x41, 0x42, 0x43, 0x00, 0xFF]
        let stream = ByteStream(data: Data(bytes))
        #expect(stream.readStrNT() == "ABC")
        #expect(stream.remaining == 1)
    }

    @Test("init with non-zero startIndex Data (sliced)")
    func slicedData() throws {
        let full = Data([0, 0, 0xAA, 0xBB, 0xCC])
        let sliced = full[2...]  // startIndex = 2
        let stream = ByteStream(data: sliced)
        #expect(try stream.readUInt8() == 0xAA)
        #expect(try stream.readUInt8() == 0xBB)
        #expect(try stream.readUInt8() == 0xCC)
        #expect(stream.isAtEnd)
    }

    @Test("init with offset parameter starts at correct position")
    func initWithOffset() throws {
        let stream = ByteStream(data: Data([10, 20, 30]), offset: 1)
        #expect(try stream.readUInt8() == 20)
        #expect(stream.remaining == 1)
    }
}
