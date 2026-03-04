import Foundation

/// 1-bit packed bitmap for JB2
final class JB2Bitmap {
    let width: Int
    let height: Int
    var data: [UInt8]

    init(width: Int, height: Int) {
        self.width = max(0, width)
        self.height = max(0, height)
        let length = (self.width * self.height + 7) / 8
        self.data = [UInt8](repeating: 0, count: length)
    }

    func hasRow(_ r: Int) -> Bool { r >= 0 && r < height }

    /// Get pixel at (row, col). Returns 0 or 1.
    func get(_ row: Int, _ col: Int) -> Int {
        guard row >= 0, row < height, col >= 0, col < width else { return 0 }
        let idx = row * width + col
        return Int((data[idx >> 3] >> (7 - (idx & 7))) & 1)
    }

    /// Set pixel at (row, col) to 1
    func set(_ row: Int, _ col: Int) {
        guard row >= 0, row < height, col >= 0, col < width else { return }
        let idx = row * width + col
        data[idx >> 3] |= (0x80 >> (idx & 7))
    }

    /// Get n consecutive bits starting at (row, col), packed into an integer.
    /// Bit at (row, col) goes into position (bitCount-1), bit at (row, col+bitCount-1) into position 0.
    func getBits(_ row: Int, _ col: Int, _ bitCount: Int) -> Int {
        guard row >= 0, row < height else { return 0 }
        var result = 0
        var j = col
        for bit in 0..<bitCount {
            if j >= 0 && j < width {
                result |= get(row, j) << (bitCount - 1 - bit)
            }
            j += 1
        }
        return result
    }

    /// Remove empty rows and columns from all edges.
    /// Ported from DjVu.js Bitmap.removeEmptyEdges()
    func removeEmptyEdges() -> JB2Bitmap {
        var bottomShift = 0
        var topShift = 0
        var leftShift = 0
        var rightShift = 0

        // Bottom empty rows (row 0 is bottom in DjVu convention)
        bottomLoop: for i in 0..<height {
            for j in 0..<width {
                if get(i, j) != 0 { break bottomLoop }
            }
            bottomShift += 1
        }

        // Top empty rows
        topLoop: for i in stride(from: height - 1, through: 0, by: -1) {
            for j in 0..<width {
                if get(i, j) != 0 { break topLoop }
            }
            topShift += 1
        }

        // Left empty columns
        leftLoop: for j in 0..<width {
            for i in 0..<height {
                if get(i, j) != 0 { break leftLoop }
            }
            leftShift += 1
        }

        // Right empty columns
        rightLoop: for j in stride(from: width - 1, through: 0, by: -1) {
            for i in 0..<height {
                if get(i, j) != 0 { break rightLoop }
            }
            rightShift += 1
        }

        if topShift > 0 || bottomShift > 0 || leftShift > 0 || rightShift > 0 {
            let newWidth = width - leftShift - rightShift
            let newHeight = height - topShift - bottomShift
            if newWidth <= 0 || newHeight <= 0 {
                return JB2Bitmap(width: 1, height: 1)
            }
            let newBm = JB2Bitmap(width: newWidth, height: newHeight)
            for p in 0..<newHeight {
                for q in 0..<newWidth {
                    if get(p + bottomShift, q + leftShift) != 0 {
                        newBm.set(p, q)
                    }
                }
            }
            return newBm
        }
        return self
    }
}

/// Blit record: a bitmap placed at (x, y) on the page
struct JB2Blit {
    let bitmap: JB2Bitmap
    let x: Int
    let y: Int
}

/// Baseline: median-of-3 filter for stable vertical positioning
final class Baseline {
    private var arr: [Int] = [0, 0, 0]
    private var index: Int = -1

    func add(_ val: Int) {
        index += 1
        if index == 3 { index = 0 }
        arr[index] = val
    }

    func getVal() -> Int {
        if (arr[0] >= arr[1] && arr[0] <= arr[2]) || (arr[0] <= arr[1] && arr[0] >= arr[2]) {
            return arr[0]
        } else if (arr[1] >= arr[0] && arr[1] <= arr[2]) || (arr[1] <= arr[0] && arr[1] >= arr[2]) {
            return arr[1]
        } else {
            return arr[2]
        }
    }

    func fill(_ val: Int) {
        arr[0] = val; arr[1] = val; arr[2] = val
    }
}
