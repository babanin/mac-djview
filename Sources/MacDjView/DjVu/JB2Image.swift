import Foundation

/// JB2 decoded image: a list of blits on a canvas
final class JB2Image {
    let width: Int
    let height: Int
    private(set) var blits: [JB2Blit] = []

    init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    func addBlit(_ blit: JB2Blit) {
        blits.append(blit)
    }

    /// Render all blits onto a 1-bit canvas, return as full bitmap.
    /// Ported from DjVu.js JB2Image.getBitmap() / copyToBitmap()
    func render() -> JB2Bitmap {
        let canvas = JB2Bitmap(width: width, height: height)
        for blit in blits {
            let bm = blit.bitmap
            for k in 0..<bm.height {
                let i = blit.y + k
                for t in 0..<bm.width {
                    let j = blit.x + t
                    if bm.get(k, t) != 0 {
                        canvas.set(i, j)
                    }
                }
            }
        }
        return canvas
    }
}
