import SwiftUI

struct PageImageView: View {
    let image: NSImage
    let zoom: Double

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(
                    width: image.size.width * zoom,
                    height: image.size.height * zoom
                )
                .padding(20)
        }
    }
}
