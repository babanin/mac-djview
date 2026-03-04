import Testing
@testable import MacDjView

@Suite("LinearBytemap — unsafe buffer pointer operations")
struct LinearBytemapTests {

    @Test("get/set basic operations")
    func getSet() {
        let map = LinearBytemap(width: 4, height: 4)
        map.set(0, 0, 100)
        map.set(1, 2, -50)
        map.set(3, 3, Int16.max)
        #expect(map.get(0, 0) == 100)
        #expect(map.get(1, 2) == -50)
        #expect(map.get(3, 3) == Int16.max)
        #expect(map.get(2, 2) == 0)  // unset = 0
    }

    @Test("add uses wrapping arithmetic")
    func addWrapping() {
        let map = LinearBytemap(width: 2, height: 2)
        map.set(0, 0, Int16.max)
        map.add(0, 0, 1)
        #expect(map.get(0, 0) == Int16.min)  // wraps around

        map.set(1, 1, 100)
        map.add(1, 1, -150)
        #expect(map.get(1, 1) == -50)
    }

    @Test("sub uses wrapping arithmetic")
    func subWrapping() {
        let map = LinearBytemap(width: 2, height: 2)
        map.set(0, 0, Int16.min)
        map.sub(0, 0, 1)
        #expect(map.get(0, 0) == Int16.max)  // wraps around

        map.set(1, 0, 50)
        map.sub(1, 0, 30)
        #expect(map.get(1, 0) == 20)
    }

    @Test("data array is correctly sized")
    func dataSize() {
        let map = LinearBytemap(width: 10, height: 20)
        #expect(map.data.count == 200)
    }

    @Test("withUnsafeMutableBufferPointer accesses same storage")
    func unsafeAccess() {
        let map = LinearBytemap(width: 4, height: 4)
        map.set(2, 3, 42)

        // Access through unsafe pointer and verify
        map.data.withUnsafeMutableBufferPointer { buf in
            #expect(buf[2 * 4 + 3] == 42)
            buf[0 * 4 + 1] = 99
        }
        #expect(map.get(0, 1) == 99)
    }

    @Test("row-major layout: index = row * width + col")
    func rowMajorLayout() {
        let map = LinearBytemap(width: 5, height: 3)
        for r in 0..<3 {
            for c in 0..<5 {
                map.set(r, c, Int16(r * 10 + c))
            }
        }
        // Verify direct data layout
        #expect(map.data[0] == 0)    // (0,0)
        #expect(map.data[4] == 4)    // (0,4)
        #expect(map.data[5] == 10)   // (1,0)
        #expect(map.data[14] == 24)  // (2,4)
    }
}
