# MacDjView

A native macOS DjVu document viewer written entirely in Swift — no external C libraries or dependencies. Implements the DjVu file format decoder from scratch, including IFF parsing, ZP-Coder arithmetic decoding, IW44 wavelet image codec, JB2 symbol codec, and layer composition.

![MacDjView screenshot](docs/screenshot.jpeg)

## Features

- Full DjVu decoder: IFF85 container, BZZ, ZP-Coder, IW44 wavelets, JB2 bitmaps
- Multi-page document support with shared symbol dictionaries
- Background image + foreground text/mask layer composition
- SwiftUI viewer with page navigation and zoom
- Standalone `.app` bundle via build script

## Requirements

- macOS 14 (Sonoma) or later
- Swift 5.10+
- Xcode 15+ or standalone Swift toolchain

## Building

```bash
# Debug build
swift build

# Release build
swift build -c release

# Run directly
swift run MacDjView

# Create .app bundle
./scripts/make-app-bundle.sh
```

You can also open the project in Xcode — just open `Package.swift`.

## Unit Tests

```bash
# Run all unit tests
make unit-test

# Or directly
./scripts/run-tests.sh
```

Tests cover the decoder's post-decode pipeline: ByteStream reads, LinearBytemap wavelet storage, IW44 color conversion (SIMD and scalar paths), wavelet transform correctness, and PageCompositor layer composition.

CI runs automatically on pushes to `main` and pull requests via GitHub Actions.

## CLI Test & Performance Testing

The `--test` flag renders all pages headlessly and reports per-page timing and memory usage:

```bash
# Render all pages (always use release mode for meaningful numbers)
swift run -c release MacDjView -- --test document.djvu

# Start from a specific page (0-indexed)
swift run -c release MacDjView -- --test document.djvu 100
```

Output includes per-page render time and resident memory, plus a summary:

```
=== Performance Summary ===
Pages rendered: 1170/1170 (0 errors)
Total time: 120450ms
Per-page: avg=103ms median=85ms p95=210ms max=450ms
Memory: base=52MB peak=380MB final=290MB
===========================
```

To catch performance regressions, save and diff results:

```bash
swift run -c release MacDjView -- --test large.djvu 2> perf-baseline.txt
# ... make changes ...
swift run -c release MacDjView -- --test large.djvu 2> perf-after.txt
diff perf-baseline.txt perf-after.txt
```

Key metrics to watch: **p95 render time** and **peak memory**.

## Contributing

1. Fork the repository and create a feature branch
2. Make your changes following the conventions in [`docs/`](./docs/):
   - [Code best practices](./docs/code-best-practices.md)
   - [Naming conventions](./docs/naming-conventions.md)
   - [Architecture overview](./docs/architecture.md)
   - [Git conventions](./docs/git-conventions.md)
3. Run unit tests: `make unit-test`
4. Visual test: `.build/debug/MacDjView --test <your-file>.djvu`
4. Submit a pull request

### Key guidelines

- **No external dependencies** — everything is implemented from scratch using only Swift standard library and Apple frameworks
- Use wrapping arithmetic (`&+`, `&-`, `&*`) in codec code to match DjVu spec behavior
- DjVu images are bottom-up (row 0 = bottom) — coordinate flips happen at the rendering boundary
- Reference implementation for spec questions: [DjVu.js by RussCoder](https://github.com/nicuss/DjVujs)

## Project Structure

```
Sources/MacDjView/
├── DjVu/              # Decoder library
│   ├── ByteStream.swift
│   ├── IFFParser.swift
│   ├── ZPCodec.swift
│   ├── IW44Decoder.swift
│   ├── IW44Image.swift
│   ├── JB2Decoder.swift
│   ├── JB2Dict.swift
│   ├── JB2Image.swift
│   ├── JB2Structures.swift
│   ├── PageCompositor.swift
│   ├── DjVuDocument.swift
│   └── DjVuPage.swift
├── UI/                # SwiftUI viewer
└── main.swift
Tests/MacDjViewTests/  # Unit tests
```

## License

<!-- TODO: choose a license -->
