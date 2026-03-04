import SwiftUI
import AppKit

enum PageLayout: String, CaseIterable {
    case single = "Single Page"
    case twoPage = "Two Pages"
}

enum ScrollMode: String, CaseIterable {
    case paged = "Paged"
    case continuous = "Continuous"
}

enum ColorTheme: String, CaseIterable, Codable {
    case normal = "Normal"
    case inverted = "Inverted"
    case sepia = "Sepia"
}

private struct DocumentState: Codable {
    var currentPage: Int
    var zoom: Double
    var pageLayout: String
    var scrollMode: String
    var colorTheme: String?
}

@Observable
final class DocumentViewModel {
    var document: DjVuDocument?
    var currentPage = 0
    var pageImage: NSImage?
    var rightPageImage: NSImage?
    var zoom: Double = 1.0
    var isLoading = false
    var errorMessage: String?
    var fileName: String?
    var pageLayout: PageLayout = .single
    var scrollMode: ScrollMode = .paged
    var colorTheme: ColorTheme = .normal
    var scrollTarget: Int?
    var documentURL: URL?
    var showFileImporter = false

    let pageCache = PageCache()

    private var renderTask: Task<Void, Never>?

    // MARK: - Computed

    var hasDocument: Bool { document != nil }

    var pageCount: Int { document?.pageCount ?? 0 }

    var canGoBack: Bool { currentPage > 0 }

    var canGoForward: Bool {
        guard let document else { return false }
        return currentPage < document.pageCount - 1
    }

    var pageIndicatorText: String {
        guard let document else { return "" }
        if pageLayout == .twoPage, currentPage > 0,
           currentPage + 1 < document.pageCount {
            return "Pages \(currentPage + 1)\u{2013}\(currentPage + 2) of \(document.pageCount)"
        }
        return "Page \(currentPage + 1) of \(document.pageCount)"
    }

    var navigationSubtitleText: String {
        guard document != nil else { return "" }
        return pageIndicatorText
    }

    // MARK: - Navigation

    func navigatePage(_ delta: Int) {
        guard let document else { return }

        let step = pageLayout == .twoPage ? delta * 2 : delta
        let newPage = currentPage + step
        guard newPage >= 0, newPage < document.pageCount else { return }

        currentPage = pageLayout == .twoPage ? spreadStartPage(for: newPage) : newPage

        if scrollMode == .continuous {
            scrollTarget = currentPage
        } else {
            renderCurrentPage()
        }
    }

    func goToFirstPage() {
        guard document != nil, currentPage != 0 else { return }
        currentPage = 0
        if scrollMode == .continuous {
            scrollTarget = currentPage
        } else {
            renderCurrentPage()
        }
    }

    func goToLastPage() {
        guard let document, currentPage != document.pageCount - 1 else { return }
        if pageLayout == .twoPage {
            currentPage = spreadStartPage(for: document.pageCount - 1)
        } else {
            currentPage = document.pageCount - 1
        }
        if scrollMode == .continuous {
            scrollTarget = currentPage
        } else {
            renderCurrentPage()
        }
    }

    /// Returns the start page of the spread containing `page`.
    /// Spread layout: [0], [1,2], [3,4], ... (page 0 is shown alone as a cover).
    func spreadStartPage(for page: Int) -> Int {
        if page <= 0 { return 0 }
        return page % 2 == 0 ? page - 1 : page
    }

    func cycleColorTheme() {
        let all = ColorTheme.allCases
        let idx = all.firstIndex(of: colorTheme)!
        colorTheme = all[(idx + 1) % all.count]
        saveDocumentState()
    }

    // MARK: - Zoom

    func adjustZoom(_ delta: Double) {
        zoom = max(0.25, min(4.0, zoom + delta))
        handleZoomChanged()
    }

    func zoomToActualSize() {
        zoom = 1.0
        handleZoomChanged()
    }

    func fitToHeight(viewportHeight: CGFloat) {
        guard let document else { return }
        let page = document.pages[currentPage]
        let availableHeight = viewportHeight - 40
        guard availableHeight > 0, page.height > 0 else { return }
        zoom = max(0.25, min(4.0, availableHeight / CGFloat(page.height)))
        handleZoomChanged()
    }

    private func handleZoomChanged() {
        if scrollMode == .paged {
            renderCurrentPage()
        }
    }

    // MARK: - Layout/Mode changes

    func handlePageLayoutChanged() {
        guard document != nil else { return }
        saveDocumentState()
        if pageLayout == .twoPage {
            currentPage = spreadStartPage(for: currentPage)
        }
        if scrollMode == .paged {
            renderCurrentPage()
        } else {
            scrollTarget = currentPage
        }
    }

    func handleScrollModeChanged() {
        guard document != nil else { return }
        saveDocumentState()
        if scrollMode == .paged {
            renderCurrentPage()
        } else {
            scrollTarget = currentPage
        }
    }

    // MARK: - Document Loading

    func loadDocument(url: URL) {
        isLoading = true
        errorMessage = nil
        pageImage = nil
        rightPageImage = nil
        fileName = url.lastPathComponent
        documentURL = url
        pageCache.removeAll()

        renderTask?.cancel()
        renderTask = Task {
            do {
                let data = try Data(contentsOf: url)
                let doc = try DjVuDocument(data: data)
                await MainActor.run {
                    self.document = doc
                    if let saved = self.restoreDocumentState() {
                        self.currentPage = min(max(saved.currentPage, 0), doc.pageCount - 1)
                        self.zoom = saved.zoom
                        if let layout = PageLayout(rawValue: saved.pageLayout) {
                            self.pageLayout = layout
                        }
                        if let mode = ScrollMode(rawValue: saved.scrollMode) {
                            self.scrollMode = mode
                        }
                        if let theme = saved.colorTheme.flatMap({ ColorTheme(rawValue: $0) }) {
                            self.colorTheme = theme
                        }
                    } else {
                        self.currentPage = 0
                        self.zoom = 1.0
                    }
                    if self.scrollMode == .paged {
                        self.renderCurrentPage()
                    } else {
                        self.scrollTarget = self.currentPage
                        self.isLoading = false
                    }
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Failed to open: \(error.localizedDescription)"
                    self.isLoading = false
                }
            }
        }
    }

    // MARK: - Rendering

    func renderCurrentPage() {
        guard let document else { return }

        let pageIndex = currentPage
        let currentZoom = zoom
        let zoomPercent = Int(currentZoom * 100)

        let rightIndex: Int? = {
            guard pageLayout == .twoPage, pageIndex > 0,
                  pageIndex + 1 < document.pageCount else { return nil }
            return pageIndex + 1
        }()

        // Check cache for left page
        if let cached = pageCache.image(forPage: pageIndex, zoom: zoomPercent) {
            self.pageImage = cached

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

        renderTask?.cancel()
        renderTask = Task {
            do {
                // Render left page
                let leftImage: NSImage
                if let cached = pageCache.image(forPage: pageIndex, zoom: zoomPercent) {
                    leftImage = cached
                } else {
                    leftImage = try await pageCache.render(
                        document: document, pageIndex: pageIndex, scale: currentZoom
                    )
                    try Task.checkCancellation()
                    pageCache.store(leftImage, forPage: pageIndex, zoom: zoomPercent)
                }

                // Render right page if needed
                let renderedRight: NSImage?
                if let ri = rightIndex {
                    if let cached = pageCache.image(forPage: ri, zoom: zoomPercent) {
                        renderedRight = cached
                    } else {
                        let img = try await pageCache.render(
                            document: document, pageIndex: ri, scale: currentZoom
                        )
                        try Task.checkCancellation()
                        pageCache.store(img, forPage: ri, zoom: zoomPercent)
                        renderedRight = img
                    }
                } else {
                    renderedRight = nil
                }

                await MainActor.run {
                    self.pageImage = leftImage
                    self.rightPageImage = renderedRight
                    self.isLoading = false
                }
            } catch is CancellationError {
                // Cancelled by new render — ignore
            } catch {
                await MainActor.run {
                    self.errorMessage = "Decode error: \(error.localizedDescription)"
                    self.isLoading = false
                }
            }
        }
    }

    // MARK: - State Persistence

    func saveDocumentState() {
        guard document != nil, let documentURL else { return }
        let state = DocumentState(
            currentPage: currentPage,
            zoom: zoom,
            pageLayout: pageLayout.rawValue,
            scrollMode: scrollMode.rawValue,
            colorTheme: colorTheme.rawValue
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
}

// MARK: - FocusedValues

struct DocumentActions {
    var navigatePage: (Int) -> Void
    var goToFirstPage: () -> Void
    var goToLastPage: () -> Void
    var adjustZoom: (Double) -> Void
    var zoomToActualSize: () -> Void
    var fitToHeight: () -> Void
    var canGoBack: Bool
    var canGoForward: Bool
    var hasDocument: Bool
    var colorTheme: Binding<ColorTheme>
    var pageLayout: Binding<PageLayout>
    var scrollMode: Binding<ScrollMode>
    var showFileImporter: Binding<Bool>
}

struct DocumentActionsKey: FocusedValueKey {
    typealias Value = DocumentActions
}

extension FocusedValues {
    var documentActions: DocumentActions? {
        get { self[DocumentActionsKey.self] }
        set { self[DocumentActionsKey.self] = newValue }
    }
}
