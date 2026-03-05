import SwiftUI
import os

private let sepiaColor = Color(red: 1.0, green: 0.94, blue: 0.84)

private func pageBackgroundColor(for theme: ColorTheme) -> Color {
    switch theme {
    case .normal: .white
    case .inverted: .black
    case .sepia: sepiaColor
    }
}

private extension View {
    @ViewBuilder
    func applyColorTheme(_ theme: ColorTheme) -> some View {
        switch theme {
        case .normal:
            self
        case .inverted:
            self.colorInvert()
        case .sepia:
            self.saturation(0.5)
                .colorMultiply(sepiaColor)
        }
    }
}

struct PageImageView: View {
    let image: PlatformImage
    let zoom: Double
    var colorTheme: ColorTheme = .normal

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            Image(platformImage: image)
                .resizable()
                .interpolation(.high)
                .applyColorTheme(colorTheme)
                .frame(
                    width: image.size.width * zoom,
                    height: image.size.height * zoom
                )
                .padding(20)
        }
    }
}

// MARK: - TwoPageView

struct TwoPageView: View {
    let leftImage: PlatformImage
    let rightImage: PlatformImage?
    let zoom: Double
    var colorTheme: ColorTheme = .normal

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            HStack(spacing: 12) {
                pageSlot(leftImage)
                if let rightImage {
                    pageSlot(rightImage)
                }
            }
            .padding(20)
        }
    }

    private func pageSlot(_ image: PlatformImage) -> some View {
        ZStack {
            pageBackgroundColor(for: colorTheme)
                .shadow(color: .black.opacity(0.2), radius: 4, y: 2)

            Image(platformImage: image)
                .resizable()
                .interpolation(.high)
                .applyColorTheme(colorTheme)
        }
        .frame(
            width: image.size.width * zoom,
            height: image.size.height * zoom
        )
    }
}

// MARK: - RenderToken

private final class RenderToken: Sendable {
    private let _cancelled = OSAllocatedUnfairLock(initialState: false)
    var isCancelled: Bool { _cancelled.withLock { $0 } }
    func cancel() { _cancelled.withLock { $0 = true } }
}

// MARK: - PageCache

final class PageCache {
    private let cache = NSCache<NSString, PlatformImage>()
    private let renderQueue = DispatchQueue(label: "com.mac-djview.render", qos: .userInitiated)

    init() {
        cache.countLimit = 10
        // 256 MB limit — each image costs width × height × 4 bytes
        cache.totalCostLimit = 256 * 1024 * 1024
    }

    func image(forPage pageIndex: Int, zoom zoomPercent: Int) -> PlatformImage? {
        cache.object(forKey: key(pageIndex, zoomPercent))
    }

    func store(_ image: PlatformImage, forPage pageIndex: Int, zoom zoomPercent: Int) {
        let w = Int(image.size.width)
        let h = Int(image.size.height)
        let cost = w * h * 4
        cache.setObject(image, forKey: key(pageIndex, zoomPercent), cost: cost)
    }

    func removeAll() {
        cache.removeAllObjects()
    }

    func render(document: DjVuDocument, pageIndex: Int, scale: Double) async throws -> PlatformImage {
        let token = RenderToken()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { cont in
                renderQueue.async {
                    if token.isCancelled {
                        cont.resume(throwing: CancellationError())
                        return
                    }
                    // Wrap in autoreleasepool to ensure temporary CGImage/CG objects are freed
                    // promptly between page renders, rather than accumulating in the queue's pool
                    autoreleasepool {
                        do {
                            let cgImage = try document.renderPage(at: pageIndex, scale: scale)
                            let image = PlatformImage(fromCGImage: cgImage)
                            cont.resume(returning: image)
                        } catch {
                            cont.resume(throwing: error)
                        }
                    }
                }
            }
        } onCancel: {
            token.cancel()
        }
    }

    private func key(_ pageIndex: Int, _ zoomPercent: Int) -> NSString {
        "\(pageIndex)@\(zoomPercent)" as NSString
    }
}

// MARK: - ContinuousPageView

struct ContinuousPageView: View {
    let document: DjVuDocument
    let zoom: Double
    let pageCache: PageCache
    var colorTheme: ColorTheme = .normal
    @Binding var currentPage: Int
    @Binding var scrollTarget: Int?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView([.horizontal, .vertical]) {
                LazyVStack(spacing: 12) {
                    ForEach(0..<document.pageCount, id: \.self) { pageIndex in
                        ContinuousPageSlot(
                            document: document,
                            pageIndex: pageIndex,
                            zoom: zoom,
                            pageCache: pageCache,
                            colorTheme: colorTheme
                        )
                        .id(pageIndex)
                        .onAppear {
                            currentPage = pageIndex
                        }
                    }
                }
                .padding(20)
            }
            .onChange(of: scrollTarget) { _, target in
                guard let target else { return }
                withAnimation {
                    proxy.scrollTo(target, anchor: .top)
                }
                scrollTarget = nil
            }
        }
    }
}

// MARK: - ContinuousTwoPageView

struct ContinuousTwoPageView: View {
    let document: DjVuDocument
    let zoom: Double
    let pageCache: PageCache
    var colorTheme: ColorTheme = .normal
    @Binding var currentPage: Int
    @Binding var scrollTarget: Int?

    private var spreadCount: Int {
        if document.pageCount <= 1 { return document.pageCount }
        return 1 + Int((document.pageCount - 1 + 1) / 2)
    }

    private func spreadPages(for spreadIndex: Int) -> (left: Int, right: Int?) {
        if spreadIndex == 0 {
            return (0, nil)
        }
        let left = 1 + (spreadIndex - 1) * 2
        let right = left + 1
        return (left, right < document.pageCount ? right : nil)
    }

    private func spreadIndex(for page: Int) -> Int {
        if page <= 0 { return 0 }
        return 1 + (page - 1) / 2
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView([.horizontal, .vertical]) {
                LazyVStack(spacing: 12) {
                    ForEach(0..<spreadCount, id: \.self) { sIndex in
                        let pages = spreadPages(for: sIndex)
                        HStack(spacing: 12) {
                            ContinuousPageSlot(
                                document: document,
                                pageIndex: pages.left,
                                zoom: zoom,
                                pageCache: pageCache,
                                colorTheme: colorTheme
                            )
                            if let right = pages.right {
                                ContinuousPageSlot(
                                    document: document,
                                    pageIndex: right,
                                    zoom: zoom,
                                    pageCache: pageCache,
                                    colorTheme: colorTheme
                                )
                            }
                        }
                        .id(sIndex)
                        .onAppear {
                            currentPage = pages.left
                        }
                    }
                }
                .padding(20)
            }
            .onChange(of: scrollTarget) { _, target in
                guard let target else { return }
                let sIndex = spreadIndex(for: target)
                withAnimation {
                    proxy.scrollTo(sIndex, anchor: .top)
                }
                scrollTarget = nil
            }
        }
    }
}

// MARK: - ContinuousPageSlot

struct ContinuousPageSlot: View {
    let document: DjVuDocument
    let pageIndex: Int
    let zoom: Double
    let pageCache: PageCache
    var colorTheme: ColorTheme = .normal

    @State private var image: PlatformImage?
    @State private var error: String?

    private var pageWidth: CGFloat {
        CGFloat(document.pages[pageIndex].width) * zoom
    }

    private var pageHeight: CGFloat {
        CGFloat(document.pages[pageIndex].height) * zoom
    }

    var body: some View {
        ZStack {
            pageBackgroundColor(for: colorTheme)
                .shadow(color: .black.opacity(0.2), radius: 4, y: 2)

            if let image {
                Image(platformImage: image)
                    .resizable()
                    .interpolation(.high)
                    .applyColorTheme(colorTheme)
            } else if let error {
                VStack {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                ProgressView()
            }
        }
        .frame(width: pageWidth, height: pageHeight)
        .task(id: TaskKey(pageIndex: pageIndex, zoom: zoom)) {
            await loadImage()
        }
    }

    private struct TaskKey: Equatable {
        let pageIndex: Int
        let zoom: Double
    }

    private func loadImage() async {
        let zoomPercent = Int(zoom * 100)

        if let cached = pageCache.image(forPage: pageIndex, zoom: zoomPercent) {
            self.image = cached
            return
        }

        self.image = nil
        self.error = nil

        let doc = document
        let idx = pageIndex
        let scale = zoom

        do {
            let nsImage = try await pageCache.render(
                document: doc, pageIndex: idx, scale: scale
            )
            try Task.checkCancellation()
            pageCache.store(nsImage, forPage: idx, zoom: zoomPercent)
            self.image = nsImage
        } catch is CancellationError {
            // Slot recycled by LazyVStack — ignore
        } catch {
            self.error = "Page \(idx + 1): \(error.localizedDescription)"
        }
    }
}
