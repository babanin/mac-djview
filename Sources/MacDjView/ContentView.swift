import SwiftUI
import AppKit

enum PageLayout: String {
    case single = "Single Page"
    case twoPage = "Two Pages"
}

enum ScrollMode: String {
    case paged = "Paged"
    case continuous = "Continuous"
}

private struct DocumentState: Codable {
    var currentPage: Int
    var zoom: Double
    var pageLayout: String
    var scrollMode: String
}

struct ContentView: View {
    @State private var document: DjVuDocument?
    @State private var currentPage = 0
    @State private var pageImage: NSImage?
    @State private var rightPageImage: NSImage?
    @State private var zoom: Double = 1.0
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var fileName: String?
    @State private var pageLayout: PageLayout = .single
    @State private var scrollMode: ScrollMode = .paged
    @State private var pageCache = PageCache()
    @State private var scrollTarget: Int?
    @State private var viewportSize: CGSize = .zero
    @State private var documentURL: URL?

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

                    Group {
                        if pageLayout == .twoPage, currentPage > 0,
                           currentPage + 1 < document.pageCount {
                            Text("Pages \(currentPage + 1)–\(currentPage + 2) of \(document.pageCount)")
                        } else {
                            Text("Page \(currentPage + 1) of \(document.pageCount)")
                        }
                    }
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

                    Divider()
                        .frame(height: 20)

                    HStack(spacing: 2) {
                        Button {
                            pageLayout = .single
                        } label: {
                            Image(systemName: "doc")
                                .frame(width: 28, height: 22)
                        }
                        .buttonStyle(.bordered)
                        .tint(pageLayout == .single ? .accentColor : nil)
                        .help("Single Page")

                        Button {
                            pageLayout = .twoPage
                        } label: {
                            Image(systemName: "book")
                                .frame(width: 28, height: 22)
                        }
                        .buttonStyle(.bordered)
                        .tint(pageLayout == .twoPage ? .accentColor : nil)
                        .help("Two Pages")
                    }

                    Divider()
                        .frame(height: 20)

                    HStack(spacing: 2) {
                        Button {
                            scrollMode = .paged
                        } label: {
                            Image(systemName: "square")
                                .frame(width: 28, height: 22)
                        }
                        .buttonStyle(.bordered)
                        .tint(scrollMode == .paged ? .accentColor : nil)
                        .help("Paged")

                        Button {
                            scrollMode = .continuous
                        } label: {
                            Image(systemName: "square.3.layers.3d.down.left")
                                .frame(width: 28, height: 22)
                        }
                        .buttonStyle(.bordered)
                        .tint(scrollMode == .continuous ? .accentColor : nil)
                        .help("Continuous Scroll")
                    }

                    Divider()
                        .frame(height: 20)

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
                } else if scrollMode == .continuous && pageLayout == .twoPage {
                    ContinuousTwoPageView(
                        document: document!,
                        zoom: zoom,
                        pageCache: pageCache,
                        currentPage: $currentPage,
                        scrollTarget: $scrollTarget
                    )
                } else if scrollMode == .continuous {
                    ContinuousPageView(
                        document: document!,
                        zoom: zoom,
                        pageCache: pageCache,
                        currentPage: $currentPage,
                        scrollTarget: $scrollTarget
                    )
                } else if pageLayout == .twoPage {
                    if isLoading {
                        ProgressView("Decoding pages...")
                    } else if let errorMessage {
                        VStack {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.largeTitle)
                            Text(errorMessage)
                                .foregroundStyle(.secondary)
                        }
                    } else if let pageImage {
                        TwoPageView(
                            leftImage: pageImage,
                            rightImage: rightPageImage,
                            zoom: zoom
                        )
                    }
                } else {
                    // Single page + paged mode
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
                        if pageLayout == .twoPage, currentPage > 0,
                           currentPage + 1 < document.pageCount {
                            let right = document.pages[currentPage + 1]
                            Text("L: \(page.width)×\(page.height)  R: \(right.width)×\(right.height) @ \(page.dpi) DPI")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("\(page.width)×\(page.height) @ \(page.dpi) DPI")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(nsColor: .windowBackgroundColor))
            }
        }
        .frame(minWidth: 600, minHeight: 400)
        .onChange(of: pageLayout) { _, newLayout in
            guard document != nil else { return }
            saveDocumentState()
            if newLayout == .twoPage {
                currentPage = spreadStartPage(for: currentPage)
            }
            if scrollMode == .paged {
                renderCurrentPage()
            } else {
                scrollTarget = currentPage
            }
        }
        .onChange(of: scrollMode) { _, newMode in
            guard document != nil else { return }
            saveDocumentState()
            if newMode == .paged {
                renderCurrentPage()
            } else {
                scrollTarget = currentPage
            }
        }
        .onChange(of: currentPage) { _, _ in
            saveDocumentState()
        }
        .onChange(of: zoom) { _, _ in
            saveDocumentState()
        }
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
        documentURL = url
        pageCache.removeAll()

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let data = try Data(contentsOf: url)
                let doc = try DjVuDocument(data: data)
                DispatchQueue.main.async {
                    self.document = doc
                    if let saved = restoreDocumentState() {
                        self.currentPage = min(max(saved.currentPage, 0), doc.pageCount - 1)
                        self.zoom = saved.zoom
                        if let layout = PageLayout(rawValue: saved.pageLayout) {
                            self.pageLayout = layout
                        }
                        if let mode = ScrollMode(rawValue: saved.scrollMode) {
                            self.scrollMode = mode
                        }
                    } else {
                        self.currentPage = 0
                        self.zoom = 1.0
                    }
                    if self.scrollMode == .paged {
                        renderCurrentPage()
                    } else {
                        self.scrollTarget = self.currentPage
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

        let step: Int
        if pageLayout == .twoPage {
            step = delta * 2
        } else {
            step = delta
        }

        let newPage = currentPage + step
        guard newPage >= 0, newPage < document.pageCount else { return }

        if pageLayout == .twoPage {
            currentPage = spreadStartPage(for: newPage)
        } else {
            currentPage = newPage
        }

        if scrollMode == .continuous {
            scrollTarget = currentPage
        } else {
            renderCurrentPage()
        }
    }

    /// Returns the start page of the spread containing `page`.
    /// Spread layout: [0], [1,2], [3,4], ... (page 0 is shown alone as a cover).
    private func spreadStartPage(for page: Int) -> Int {
        if page <= 0 { return 0 }
        // Pages 1,2 -> 1; pages 3,4 -> 3; pages 5,6 -> 5 ...
        return page % 2 == 0 ? page - 1 : page
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
        if scrollMode == .paged {
            renderCurrentPage()
        }
        // Continuous mode re-renders automatically via .task(id:) in ContinuousPageSlot
    }

    private func saveDocumentState() {
        guard document != nil, let documentURL else { return }
        let state = DocumentState(
            currentPage: currentPage,
            zoom: zoom,
            pageLayout: pageLayout.rawValue,
            scrollMode: scrollMode.rawValue
        )
        guard let data = try? JSONEncoder().encode(state) else { return }
        UserDefaults.standard.set(data, forKey: "docState:\(documentURL.path)")
    }

    private func restoreDocumentState() -> DocumentState? {
        guard let documentURL,
              let data = UserDefaults.standard.data(forKey: "docState:\(documentURL.path)")
        else { return nil }
        return try? JSONDecoder().decode(DocumentState.self, from: data)
    }

    private func renderCurrentPage() {
        guard let document else { return }

        let pageIndex = currentPage
        let currentZoom = zoom
        let zoomPercent = Int(currentZoom * 100)

        // Determine right page index for two-page mode
        let rightIndex: Int? = {
            guard pageLayout == .twoPage, pageIndex > 0,
                  pageIndex + 1 < document.pageCount else { return nil }
            return pageIndex + 1
        }()

        // Check cache for left page
        if let cached = pageCache.image(forPage: pageIndex, zoom: zoomPercent) {
            self.pageImage = cached

            // Check cache for right page too
            if let ri = rightIndex,
               let cachedRight = pageCache.image(forPage: ri, zoom: zoomPercent) {
                self.rightPageImage = cachedRight
                self.isLoading = false
                return
            } else if rightIndex == nil {
                self.rightPageImage = nil
                self.isLoading = false
                return
            }
        }

        isLoading = true
        errorMessage = nil

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                // Render left page
                let leftImage: NSImage
                if let cached = pageCache.image(forPage: pageIndex, zoom: zoomPercent) {
                    leftImage = cached
                } else {
                    let cgImage = try document.renderPage(at: pageIndex, scale: currentZoom)
                    leftImage = NSImage(cgImage: cgImage, size: NSSize(
                        width: CGFloat(cgImage.width),
                        height: CGFloat(cgImage.height)
                    ))
                    DispatchQueue.main.async {
                        self.pageCache.store(leftImage, forPage: pageIndex, zoom: zoomPercent)
                    }
                }

                // Render right page if needed
                var rightImage: NSImage?
                if let ri = rightIndex {
                    if let cached = pageCache.image(forPage: ri, zoom: zoomPercent) {
                        rightImage = cached
                    } else {
                        let cgImage = try document.renderPage(at: ri, scale: currentZoom)
                        rightImage = NSImage(cgImage: cgImage, size: NSSize(
                            width: CGFloat(cgImage.width),
                            height: CGFloat(cgImage.height)
                        ))
                        DispatchQueue.main.async {
                            self.pageCache.store(rightImage!, forPage: ri, zoom: zoomPercent)
                        }
                    }
                }

                DispatchQueue.main.async {
                    self.pageImage = leftImage
                    self.rightPageImage = rightImage
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
