import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var viewModel = DocumentViewModel()
    @State private var viewportSize: CGSize = .zero
    #if !os(macOS)
    @State private var showSettings = false
    #endif
    private var openURLHandler = OpenURLHandler.shared

    var body: some View {
        contentArea
            #if os(macOS)
            .frame(minWidth: 600, minHeight: 400)
            #endif
            .navigationTitle(viewModel.fileName ?? "MacDjView")
            #if os(macOS)
            .navigationSubtitle(viewModel.navigationSubtitleText)
            #endif
            .toolbar { toolbarContent }
            .safeAreaInset(edge: .bottom) { statusBar }
            .fileImporter(
                isPresented: $viewModel.showFileImporter,
                allowedContentTypes: djvuContentTypes
            ) { result in
                if case .success(let url) = result {
                    viewModel.loadDocument(url: url)
                }
            }
            .dropDestination(for: URL.self) { urls, _ in
                guard let url = urls.first,
                      ["djvu", "djv"].contains(url.pathExtension.lowercased())
                else { return false }
                viewModel.loadDocument(url: url)
                return true
            }
            #if os(macOS)
            .focusedSceneValue(\.documentActions, documentActions)
            #endif
            .onChange(of: viewModel.pageLayout) { _, _ in
                viewModel.handlePageLayoutChanged()
            }
            .onChange(of: viewModel.scrollMode) { _, _ in
                viewModel.handleScrollModeChanged()
            }
            .onChange(of: viewModel.currentPage) { _, _ in
                viewModel.saveDocumentState()
            }
            .onChange(of: viewModel.zoom) { _, _ in
                viewModel.saveDocumentState()
            }
            .onChange(of: openURLHandler.pendingURL) { _, url in
                guard let url else { return }
                viewModel.loadDocument(url: url)
                openURLHandler.pendingURL = nil
            }
            #if !os(macOS)
            .sheet(isPresented: $showSettings) {
                NavigationStack {
                    SettingsView()
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { showSettings = false }
                            }
                        }
                }
            }
            #endif
    }

    // MARK: - Content Area

    @ViewBuilder
    private var contentArea: some View {
        GeometryReader { geo in
            ZStack {
                Color.platformBackground

                if !viewModel.hasDocument {
                    if let errorMessage = viewModel.errorMessage {
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
                } else if viewModel.scrollMode == .continuous && viewModel.pageLayout == .twoPage {
                    ContinuousTwoPageView(
                        document: viewModel.document!,
                        zoom: viewModel.zoom,
                        pageCache: viewModel.pageCache,
                        colorTheme: viewModel.colorTheme,
                        currentPage: Binding(
                            get: { viewModel.currentPage },
                            set: { viewModel.currentPage = $0 }
                        ),
                        scrollTarget: Binding(
                            get: { viewModel.scrollTarget },
                            set: { viewModel.scrollTarget = $0 }
                        )
                    )
                } else if viewModel.scrollMode == .continuous {
                    ContinuousPageView(
                        document: viewModel.document!,
                        zoom: viewModel.zoom,
                        pageCache: viewModel.pageCache,
                        colorTheme: viewModel.colorTheme,
                        currentPage: Binding(
                            get: { viewModel.currentPage },
                            set: { viewModel.currentPage = $0 }
                        ),
                        scrollTarget: Binding(
                            get: { viewModel.scrollTarget },
                            set: { viewModel.scrollTarget = $0 }
                        )
                    )
                } else if viewModel.pageLayout == .twoPage {
                    if viewModel.isLoading {
                        ProgressView("Decoding pages...")
                    } else if let errorMessage = viewModel.errorMessage {
                        VStack {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.largeTitle)
                            Text(errorMessage)
                                .foregroundStyle(.secondary)
                        }
                    } else if let pageImage = viewModel.pageImage {
                        TwoPageView(
                            leftImage: pageImage,
                            rightImage: viewModel.rightPageImage,
                            zoom: viewModel.zoom,
                            colorTheme: viewModel.colorTheme
                        )
                    }
                } else {
                    if viewModel.isLoading {
                        ProgressView("Decoding page...")
                    } else if let errorMessage = viewModel.errorMessage {
                        VStack {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.largeTitle)
                            Text(errorMessage)
                                .foregroundStyle(.secondary)
                        }
                    } else if let pageImage = viewModel.pageImage {
                        PageImageView(image: pageImage, zoom: viewModel.zoom, colorTheme: viewModel.colorTheme)
                    }
                }
            }
            .onAppear { viewportSize = geo.size }
            .onChange(of: geo.size) { _, newSize in viewportSize = newSize }
            #if !os(macOS)
            .gesture(pinchToZoomGesture)
            .gesture(swipeGesture)
            #endif
        }
    }

    // MARK: - Touch Gestures (iOS)

    #if !os(macOS)
    private var pinchToZoomGesture: some Gesture {
        MagnifyGesture()
            .onEnded { value in
                let delta = value.magnification - 1.0
                viewModel.adjustZoom(delta)
            }
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 50)
            .onEnded { value in
                guard viewModel.scrollMode == .paged else { return }
                let horizontal = value.translation.width
                if horizontal < -50 {
                    viewModel.navigatePage(1)
                } else if horizontal > 50 {
                    viewModel.navigatePage(-1)
                }
            }
    }
    #endif

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button { viewModel.navigatePage(-1) } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(!viewModel.canGoBack)
            .help("Previous Page")

            Text(viewModel.pageIndicatorText)
                .monospacedDigit()
                .frame(minWidth: 120, minHeight: 16)

            Button { viewModel.navigatePage(1) } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(!viewModel.canGoForward)
            .help("Next Page")
        }

        #if os(macOS)
        ToolbarItemGroup(placement: .principal) {
            Picker("Layout", selection: Binding(
                get: { viewModel.pageLayout },
                set: { viewModel.pageLayout = $0 }
            )) {
                Label("Single Page", systemImage: "doc").tag(PageLayout.single)
                Label("Two Pages", systemImage: "book").tag(PageLayout.twoPage)
            }
            .pickerStyle(.segmented)
            .frame(width: 140)
            .help("Page Layout")

            Picker("Scroll", selection: Binding(
                get: { viewModel.scrollMode },
                set: { viewModel.scrollMode = $0 }
            )) {
                Label("Paged", systemImage: "square").tag(ScrollMode.paged)
                Label("Continuous", systemImage: "square.3.layers.3d.down.left").tag(ScrollMode.continuous)
            }
            .pickerStyle(.segmented)
            .frame(width: 160)
            .help("Scroll Mode")
        }
        #endif

        ToolbarItemGroup(placement: .automatic) {
            #if !os(macOS)
            Menu {
                Picker("Layout", selection: Binding(
                    get: { viewModel.pageLayout },
                    set: { viewModel.pageLayout = $0 }
                )) {
                    Label("Single Page", systemImage: "doc").tag(PageLayout.single)
                    Label("Two Pages", systemImage: "book").tag(PageLayout.twoPage)
                }

                Picker("Scroll", selection: Binding(
                    get: { viewModel.scrollMode },
                    set: { viewModel.scrollMode = $0 }
                )) {
                    Label("Paged", systemImage: "square").tag(ScrollMode.paged)
                    Label("Continuous", systemImage: "square.3.layers.3d.down.left").tag(ScrollMode.continuous)
                }
            } label: {
                Image(systemName: "rectangle.split.2x1")
            }
            .disabled(!viewModel.hasDocument)
            #endif

            Menu {
                ForEach(ColorTheme.allCases, id: \.self) { theme in
                    Button {
                        viewModel.colorTheme = theme
                        viewModel.saveDocumentState()
                    } label: {
                        if viewModel.colorTheme == theme {
                            Label(theme.rawValue, systemImage: "checkmark")
                        } else {
                            Text(theme.rawValue)
                        }
                    }
                }
            } label: {
                Image(systemName: "circle.lefthalf.filled")
            }
            .help("Color Theme")
            .disabled(!viewModel.hasDocument)

            Button { viewModel.adjustZoom(-0.25) } label: {
                Image(systemName: "minus.magnifyingglass")
            }
            .help("Zoom Out")

            Text("\(Int(viewModel.zoom * 100))%")
                .monospacedDigit()
                .frame(width: 50, height: 16)

            Button { viewModel.adjustZoom(0.25) } label: {
                Image(systemName: "plus.magnifyingglass")
            }
            .help("Zoom In")

            Button {
                viewModel.fitToHeight(viewportHeight: viewportSize.height)
            } label: {
                Image(systemName: "arrow.up.and.down.text.horizontal")
            }
            .help("Fit to Height")

            #if !os(macOS)
            Button { showSettings = true } label: {
                Image(systemName: "gear")
            }
            .help("Settings")
            #endif
        }
    }

    // MARK: - Status Bar

    @ViewBuilder
    private var statusBar: some View {
        if let document = viewModel.document {
            HStack {
                Spacer()
                let page = document.pages[viewModel.currentPage]
                if viewModel.pageLayout == .twoPage, viewModel.currentPage > 0,
                   viewModel.currentPage + 1 < document.pageCount {
                    let right = document.pages[viewModel.currentPage + 1]
                    Text("L: \(page.width)\u{00D7}\(page.height)  R: \(right.width)\u{00D7}\(right.height) @ \(page.dpi) DPI")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(page.width)\u{00D7}\(page.height) @ \(page.dpi) DPI")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.bar)
        }
    }

    // MARK: - Helpers

    private var djvuContentTypes: [UTType] {
        [UTType(filenameExtension: "djvu"), UTType(filenameExtension: "djv")].compactMap { $0 }
    }

    #if os(macOS)
    private var documentActions: DocumentActions {
        DocumentActions(
            navigatePage: { viewModel.navigatePage($0) },
            goToFirstPage: { viewModel.goToFirstPage() },
            goToLastPage: { viewModel.goToLastPage() },
            adjustZoom: { viewModel.adjustZoom($0) },
            zoomToActualSize: { viewModel.zoomToActualSize() },
            fitToHeight: { viewModel.fitToHeight(viewportHeight: viewportSize.height) },
            canGoBack: viewModel.canGoBack,
            canGoForward: viewModel.canGoForward,
            hasDocument: viewModel.hasDocument,
            colorTheme: Binding(
                get: { viewModel.colorTheme },
                set: { viewModel.colorTheme = $0 }
            ),
            pageLayout: Binding(
                get: { viewModel.pageLayout },
                set: { viewModel.pageLayout = $0 }
            ),
            scrollMode: Binding(
                get: { viewModel.scrollMode },
                set: { viewModel.scrollMode = $0 }
            ),
            showFileImporter: $viewModel.showFileImporter
        )
    }
    #endif
}
