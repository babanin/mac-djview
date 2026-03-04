import SwiftUI
import AppKit

struct ContentView: View {
    @State private var document: DjVuDocument?
    @State private var currentPage = 0
    @State private var pageImage: NSImage?
    @State private var zoom: Double = 1.0
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var fileName: String?

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Button("Open") { openFile() }
                    .keyboardShortcut("o", modifiers: .command)

                Spacer()

                if let document {
                    Button("◀") { navigatePage(-1) }
                        .disabled(currentPage <= 0)
                        .keyboardShortcut(.leftArrow, modifiers: [])

                    Text("Page \(currentPage + 1) of \(document.pageCount)")
                        .monospacedDigit()

                    Button("▶") { navigatePage(1) }
                        .disabled(currentPage >= document.pageCount - 1)
                        .keyboardShortcut(.rightArrow, modifiers: [])

                    Spacer()

                    Button("−") { adjustZoom(-0.25) }
                        .keyboardShortcut("-", modifiers: .command)
                    Text("\(Int(zoom * 100))%")
                        .monospacedDigit()
                        .frame(width: 50)
                    Button("+") { adjustZoom(0.25) }
                        .keyboardShortcut("=", modifiers: .command)
                    Button("Fit") { zoom = 1.0; renderCurrentPage() }
                }
            }
            .padding(8)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // Content area
            ZStack {
                Color(nsColor: .controlBackgroundColor)

                if isLoading {
                    ProgressView("Decoding page...")
                } else if let errorMessage {
                    VStack {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                        Text(errorMessage)
                            .foregroundStyle(.secondary)
                    }
                } else if let pageImage {
                    PageImageView(image: pageImage, zoom: zoom)
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "doc.richtext")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text("Open a DjVu file to begin")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Status bar
            if let fileName {
                Divider()
                HStack {
                    Text(fileName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let document {
                        let page = document.pages[currentPage]
                        Text("\(page.width)×\(page.height) @ \(page.dpi) DPI")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(nsColor: .windowBackgroundColor))
            }
        }
        .frame(minWidth: 600, minHeight: 400)
        .onReceive(NotificationCenter.default.publisher(for: .openDjVuFile)) { _ in
            openFile()
        }
    }

    private func openFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [
            .init(filenameExtension: "djvu")!,
            .init(filenameExtension: "djv")!
        ]
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        loadDocument(url: url)
    }

    private func loadDocument(url: URL) {
        isLoading = true
        errorMessage = nil
        pageImage = nil
        fileName = url.lastPathComponent

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let data = try Data(contentsOf: url)
                let doc = try DjVuDocument(data: data)
                DispatchQueue.main.async {
                    self.document = doc
                    self.currentPage = 0
                    self.zoom = 1.0
                    renderCurrentPage()
                }
            } catch {
                DispatchQueue.main.async {
                    self.errorMessage = "Failed to open: \(error.localizedDescription)"
                    self.isLoading = false
                }
            }
        }
    }

    private func navigatePage(_ delta: Int) {
        guard let document else { return }
        let newPage = currentPage + delta
        guard newPage >= 0, newPage < document.pageCount else { return }
        currentPage = newPage
        renderCurrentPage()
    }

    private func adjustZoom(_ delta: Double) {
        zoom = max(0.25, min(4.0, zoom + delta))
        renderCurrentPage()
    }

    private func renderCurrentPage() {
        guard let document else { return }
        isLoading = true
        errorMessage = nil

        let pageIndex = currentPage
        let currentZoom = zoom

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let cgImage = try document.renderPage(at: pageIndex, scale: currentZoom)
                let nsImage = NSImage(cgImage: cgImage, size: NSSize(
                    width: CGFloat(cgImage.width),
                    height: CGFloat(cgImage.height)
                ))
                DispatchQueue.main.async {
                    self.pageImage = nsImage
                    self.isLoading = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.errorMessage = "Decode error: \(error.localizedDescription)"
                    self.isLoading = false
                }
            }
        }
    }
}
