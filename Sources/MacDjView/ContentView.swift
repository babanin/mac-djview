import SwiftUI
import AppKit

enum ViewMode: String, CaseIterable {
    case singlePage = "Single Page"
    case continuous = "Continuous"
}

struct ContentView: View {
    @State private var document: DjVuDocument?
    @State private var currentPage = 0
    @State private var pageImage: NSImage?
    @State private var zoom: Double = 1.0
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var fileName: String?
    @State private var viewMode: ViewMode = .singlePage
    @State private var pageCache = PageCache()
    @State private var scrollTarget: Int?
    @State private var viewportSize: CGSize = .zero

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Button("Open") { openFile() }

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

                    // Page Up / Page Down navigation
                    Button("") { navigatePage(-1) }
                        .keyboardShortcut(.pageUp, modifiers: [])
                        .frame(width: 0, height: 0)
                        .opacity(0)

                    Button("") { navigatePage(1) }
                        .keyboardShortcut(.pageDown, modifiers: [])
                        .frame(width: 0, height: 0)
                        .opacity(0)

                    Spacer()

                    HStack(spacing: 2) {
                        Button {
                            viewMode = .singlePage
                        } label: {
                            Image(systemName: "doc")
                                .frame(width: 28, height: 22)
                        }
                        .buttonStyle(.bordered)
                        .tint(viewMode == .singlePage ? .accentColor : nil)
                        .help("Single Page")

                        Button {
                            viewMode = .continuous
                        } label: {
                            Image(systemName: "scroll")
                                .frame(width: 28, height: 22)
                        }
                        .buttonStyle(.bordered)
                        .tint(viewMode == .continuous ? .accentColor : nil)
                        .help("Continuous Scroll")
                    }

                    Spacer()

                    Button("−") { adjustZoom(-0.25) }
                        .keyboardShortcut("-", modifiers: .command)
                    Text("\(Int(zoom * 100))%")
                        .monospacedDigit()
                        .frame(width: 50)
                    Button("+") { adjustZoom(0.25) }
                        .keyboardShortcut("=", modifiers: .command)
                    Button("Fit") { fitToHeight(); handleZoomChanged() }
                }
            }
            .padding(8)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // Content area
            GeometryReader { geo in
            ZStack {
                Color(nsColor: .controlBackgroundColor)

                if document == nil {
                    if let errorMessage {
                        VStack {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.largeTitle)
                            Text(errorMessage)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        VStack(spacing: 12) {
                            Image(systemName: "doc.richtext")
                                .font(.system(size: 48))
                                .foregroundStyle(.secondary)
                            Text("Open a DjVu file to begin")
                                .foregroundStyle(.secondary)
                        }
                    }
                } else if viewMode == .continuous {
                    ContinuousPageView(
                        document: document!,
                        zoom: zoom,
                        pageCache: pageCache,
                        currentPage: $currentPage,
                        scrollTarget: $scrollTarget
                    )
                } else {
                    // Single page mode
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
                    }
                }
            }
            .onAppear { viewportSize = geo.size }
            .onChange(of: geo.size) { _, newSize in viewportSize = newSize }
            } // GeometryReader

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
        .onReceive(NotificationCenter.default.publisher(for: .openDjVuFile)) { notification in
            if let url = notification.object as? URL {
                loadDocument(url: url)
            } else {
                openFile()
            }
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
        pageCache.removeAll()

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let data = try Data(contentsOf: url)
                let doc = try DjVuDocument(data: data)
                DispatchQueue.main.async {
                    self.document = doc
                    self.currentPage = 0
                    self.zoom = 1.0
                    if self.viewMode == .singlePage {
                        renderCurrentPage()
                    } else {
                        self.isLoading = false
                    }
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

        if viewMode == .continuous {
            scrollTarget = newPage
        } else {
            renderCurrentPage()
        }
    }

    private func fitToHeight() {
        guard let document else { return }
        let page = document.pages[currentPage]
        let availableHeight = viewportSize.height - 40  // subtract padding (20 top + 20 bottom)
        guard availableHeight > 0, page.height > 0 else { return }
        zoom = max(0.25, min(4.0, availableHeight / CGFloat(page.height)))
    }

    private func adjustZoom(_ delta: Double) {
        zoom = max(0.25, min(4.0, zoom + delta))
        handleZoomChanged()
    }

    private func handleZoomChanged() {
        if viewMode == .singlePage {
            renderCurrentPage()
        }
        // Continuous mode re-renders automatically via .task(id:) in ContinuousPageSlot
    }

    private func renderCurrentPage() {
        guard let document else { return }

        let pageIndex = currentPage
        let currentZoom = zoom
        let zoomPercent = Int(currentZoom * 100)

        // Check cache first
        if let cached = pageCache.image(forPage: pageIndex, zoom: zoomPercent) {
            self.pageImage = cached
            self.isLoading = false
            return
        }

        isLoading = true
        errorMessage = nil

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let cgImage = try document.renderPage(at: pageIndex, scale: currentZoom)
                let nsImage = NSImage(cgImage: cgImage, size: NSSize(
                    width: CGFloat(cgImage.width),
                    height: CGFloat(cgImage.height)
                ))
                DispatchQueue.main.async {
                    self.pageCache.store(nsImage, forPage: pageIndex, zoom: zoomPercent)
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
