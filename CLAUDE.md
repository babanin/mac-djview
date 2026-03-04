# CLAUDE.md

## Project Overview
MacDjView is a **pure Swift** DjVu document viewer for macOS — no external C libraries. It implements the DjVu file format decoder from scratch (IFF parser, ZP-Coder, IW44 wavelet, JB2 symbol codec, layer composition) and renders pages via a native SwiftUI/AppKit UI.

## Quick Reference
- **Build**: `swift build` (debug) / `swift build -c release` (release)
- **Run**: `swift run MacDjView` (GUI)
- **Unit tests**: `make unit-test` (or `./scripts/run-tests.sh`)
- **CLI test**: `swift run -c release MacDjView -- --test file.djvu [startPage]` — renders all pages, reports per-page timing/memory and summary (avg/median/p95/max time, base/peak/final memory)
- **App bundle**: `./scripts/make-app-bundle.sh`
- **Platform**: macOS 14+, Swift 5.10, Swift Package Manager (no Xcode project)
- **No external dependencies**

## Coding Conventions
All project conventions, architecture details, and coding standards are in [docs/](./docs/):
- [docs/code-best-practices.md](./docs/code-best-practices.md) — Swift coding rules
- [docs/key-files.md](./docs/key-files.md) — Project structure and key files
- [docs/naming-conventions.md](./docs/naming-conventions.md) — Naming patterns
- [docs/architecture.md](./docs/architecture.md) — Decoder architecture and DjVu format details
- [docs/git-conventions.md](./docs/git-conventions.md) — Git and commit conventions
