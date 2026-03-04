import Cocoa

// If --test flag is passed, run decoder test and exit
if CommandLine.arguments.contains("--test") {
    let path = CommandLine.arguments.last == "--test"
        ? "example.djvu"
        : CommandLine.arguments[CommandLine.arguments.firstIndex(of: "--test")! + 1]

    do {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        print("Loaded \(data.count) bytes from \(path)")

        let doc = try DjVuDocument(data: data)
        print("Document: \(doc.pageCount) pages")

        for i in 0..<min(3, doc.pageCount) {
            let info = doc.pages[i]
            print("  Page \(i+1): \(info.width)×\(info.height) @ \(info.dpi) DPI")
        }

        // Render and save test pages
        for pageIdx in 0..<min(5, doc.pageCount) {
            print("\nRendering page \(pageIdx + 1)...")
            let image = try doc.renderPage(at: pageIdx)
            print("Rendered: \(image.width)×\(image.height) pixels")

            let url = URL(fileURLWithPath: "/tmp/djvu_page\(pageIdx + 1).png")
            if let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) {
                CGImageDestinationAddImage(dest, image, nil)
                CGImageDestinationFinalize(dest)
                print("Saved to \(url.path)")
            }
        }
        print("\nSUCCESS")
    } catch {
        print("ERROR: \(error)")
    }
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
