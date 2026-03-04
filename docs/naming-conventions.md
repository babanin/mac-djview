---
description: Naming patterns used throughout the codebase
alwaysApply: true
---
# Naming Conventions

## File Naming
- Swift files use **PascalCase**: `IW44Decoder.swift`, `JB2Structures.swift`
- Each codec has a consistent file triplet:
  - `*Decoder.swift` — Decoding logic (reads ZP-coded bitstream)
  - `*Image.swift` — Reconstruction (inverse transform, pixel output, rendering)
  - `*Structures.swift` — Data types, constants, tables

## Type Naming
- Classes and structs: **PascalCase** — `IW44Decoder`, `JB2Bitmap`, `LinearBytemap`
- Enums: **PascalCase** — `DjVuError`, `CoefficientFlag`
- Protocols: Not currently used (concrete types preferred for this codec)

## Variable & Method Naming
- Properties and methods: **camelCase** — `blocksPerRow`, `decodeSlice()`, `getPixels()`
- Match DjVu.js names where possible for traceability:
  - `quantLo` / `quantHi` (not `quantizationLow`)
  - `curband` (not `currentBand`)
  - `bbstate` (not `blockBandState`)
  - `inreaseCoefCtx` (intentional misspelling — matches DjVu.js)
  - `decodeBucketCtx`, `decodeCoefCtx`, `activateCoefCtx`

## DjVu Chunk IDs
- Chunk IDs are **4-character ASCII strings**, case-sensitive:
  - `"BG44"` — Background IW44 data
  - `"FG44"` — Foreground IW44 data
  - `"Sjbz"` — JB2 mask data
  - `"Djbz"` — JB2 shared dictionary
  - `"FGbz"` — Foreground color palette
  - `"INFO"` — Page dimensions and DPI
  - `"DIRM"` — Document directory (multi-page)
  - `"INCL"` — Reference to shared dictionary by name
  - `"TXTz"` — Hidden text layer (compressed)
- FORM types: `"DJVM"` (multi-page document), `"DJVU"` (single page), `"DJVI"` (shared data)

## Constants
- Top-level constants: **camelCase** — `zigzagRow`, `zigzagCol`, `bandBuckets`, `quant_lo`, `quant_hi`
- Struct-scoped constants: **UPPER_CASE** via static lets — `CoefficientFlag.ZERO`, `.ACTIVE`, `.NEW`, `.UNK`

## Context Arrays (ZP-Coder)
- Named to match DjVu.js for easy cross-reference:
  - `decodeBucketCtx` — Block band activation
  - `decodeCoefCtx` — Bucket activation (80 entries)
  - `activateCoefCtx` — New coefficient activation (16 entries)
  - `inreaseCoefCtx` — Active coefficient refinement (1 entry)
  - `offsetTypeCtx` — JB2 new-line flag
  - `hoffCtx`, `voffCtx` — JB2 new-line offsets
  - `shoffCtx`, `svoffCtx` — JB2 same-line offsets
