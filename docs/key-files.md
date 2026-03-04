---
description: Project structure and key files reference
alwaysApply: true
---
# Key Files

## Project Layout

```
mac-djview/
├── Package.swift                          # SPM manifest (macOS 14+, Swift 5.10)
├── CLAUDE.md                              # Entry point for AI assistants
├── docs/                                  # Coding guidelines and conventions
├── Sources/MacDjView/
│   ├── main.swift                         # NSApplication bootstrap + --test CLI mode
│   ├── AppDelegate.swift                  # Window creation, menus, activation
│   ├── ContentView.swift                  # SwiftUI: page navigation, zoom, File>Open
│   ├── PageImageView.swift                # Scrollable image display
│   │
│   └── DjVu/                             # Pure Swift DjVu decoder (no external deps)
│       ├── ByteStream.swift               # Binary reader (big-endian, bit-level)
│       ├── IFFParser.swift                # FORM/chunk container parser
│       ├── DjVuDocument.swift             # Multi-page document, DIRM directory
│       ├── DjVuPage.swift                 # Single page: decode + compose layers
│       ├── DjVuError.swift                # Error types
│       │
│       ├── ZPCodec.swift                  # ZP-Coder adaptive arithmetic decoder
│       │
│       ├── IW44Decoder.swift              # IW44 wavelet coefficient decoder (BG44/FG44)
│       ├── IW44Image.swift                # Inverse wavelet transform + pixel output
│       ├── IW44Structures.swift           # Blocks, bands, buckets, zigzag tables
│       │
│       ├── JB2Decoder.swift               # JB2 symbol/bitmap decoder (Sjbz chunks)
│       ├── JB2Dict.swift                  # Symbol dictionary (Djbz chunks)
│       ├── JB2Image.swift                 # Blit list rendering to bitmap
│       ├── JB2Structures.swift            # Bitmap, NumContext, Baseline, Blit
│       │
│       └── PageCompositor.swift           # Combine mask + FG + BG → CGImage
│
├── scripts/
│   └── make-app-bundle.sh                 # Creates .app bundle with Info.plist
└── example.djvu                           # Test file (127-page bundled document)
```

## Build & Run

| Command | Purpose |
|---------|---------|
| `swift build` | Debug build |
| `swift build -c release` | Release build |
| `swift run MacDjView` | Launch GUI app |
| `.build/debug/MacDjView --test example.djvu` | CLI test: decode + render pages to /tmp |
| `./scripts/make-app-bundle.sh` | Create MacDjView.app bundle |

## Reference Implementation
The decoder is ported from **DjVu.js** (https://github.com/RussCoder/djvujs). To fetch reference source files:
```bash
gh api "repos/RussCoder/djvujs/contents/library/src/iw44/IWDecoder.js" --jq '.content' | base64 -D
gh api "repos/RussCoder/djvujs/contents/library/src/jb2/JB2Codec.js" --jq '.content' | base64 -D
```
