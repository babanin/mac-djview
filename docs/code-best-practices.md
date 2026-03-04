---
description: Swift coding rules for the MacDjView project
alwaysApply: true
---
# Code Best Practices — MacDjView (Pure Swift)

## 1) No External Dependencies
- The entire DjVu decoder is **pure Swift** — no C libraries, no third-party packages.
- `Package.swift` has zero dependencies. Keep it that way.
- Only use Foundation and system frameworks (CoreGraphics, AppKit, SwiftUI).

**Guardrail**
- If a proposed change adds an external dependency, reject it and implement in pure Swift.

## 2) Integer Arithmetic — Match DjVu.js Semantics
- DjVu.js uses `Int16Array` which wraps on overflow. Swift `Int16` does NOT wrap by default.
- Use **`&+`**, **`&-`**, **`&*`** (wrapping operators) where DjVu.js uses Int16Array arithmetic.
- `LinearBytemap.add()` / `.sub()` must use `&+=` / `&-=` to match wavelet transform behavior.
- Use `Int16(truncatingIfNeeded:)` when converting from wider types (Int32, UInt32) to Int16.
- Use `Int32` for intermediate wavelet computations to avoid premature overflow.

**Guardrail**
- If arithmetic on `Int16` values doesn't use wrapping operators, verify whether DjVu.js relies on wrapping for correctness.

## 3) Coordinate Systems
- **DjVu images are bottom-up**: row 0 = bottom of the image.
- **Screen/CGImage is top-down**: row 0 = top of the image.
- `IW44Image.getPixels()` flips rows when writing output pixels.
- `PageCompositor` flips y-coordinates when sampling the JB2 mask (`djvuY = height - 1 - py`).
- JB2 blit coordinates are in DjVu bottom-up space.

**Guardrail**
- Any code that maps between DjVu pixel data and screen output must account for the y-flip. If pixels appear upside-down, the flip is missing.

## 4) Per-Channel Decoder State (IW44)
- Each color channel (Y, Cb, Cr) **must** have its own `IW44ChannelDecoder` instance with independent:
  - `curband`, quantization tables (`quantLo`, `quantHi`)
  - ZP context arrays (`decodeBucketCtx`, `decodeCoefCtx`, etc.)
  - Coefficient state arrays (`coeffstate`, `bucketstate`, `bbstate`)
- All channels share the same ZP bitstream (same `ZPCodec` instance).
- The `delayInit` parameter gates when Cb/Cr decoding starts.

**Guardrail**
- Never share mutable decoder state across color channels. Each channel's state evolves independently.

## 5) JB2 Decoding Order
- **Init sequence**: Read record type first (may be 9 for inherited dict), then image size, then a **raw ZP bit** for the flag — NOT `decodeNum`.
- **Record type 4/5/6** (refinement): Decode symbol **index first**, then width/height **diffs** using separate `symbolWidthDiffCtx` / `symbolHeightDiffCtx` contexts.
- **Symbol coordinates** use separate context pairs: `hoffCtx`/`voffCtx` for new lines, `shoffCtx`/`svoffCtx` for same-line offsets.
- Bitmaps added to the library must call `.removeEmptyEdges()` first.

**Guardrail**
- If JB2 decoding produces 0 blits or wrong coordinates, check the init sequence order and context usage.

## 6) Error Handling
- Decoder methods that read from `ByteStream` are `throws` — propagate errors up.
- Use `DjVuError` enum for all failure cases.
- Do not silently swallow decoding errors; let them propagate to the UI layer.

## 7) Performance Considerations
- `IW44Block` uses lazy bucket allocation (most buckets in a block are zero).
- `JB2Bitmap` uses packed bit storage (1 bit per pixel, 8 pixels per byte).
- Wavelet transform operates on the full `LinearBytemap` in-place.
- The compositor iterates every pixel — avoid unnecessary allocations in the inner loop.

## 8) Prefer Editing Over Creating Files
- The codebase is intentionally compact. Prefer modifying existing files over adding new ones.
- Each decoder component has a clear file: `*Decoder.swift` (codec logic), `*Image.swift` (reconstruction), `*Structures.swift` (data types).

## 9) Testing
- Use `--test` CLI flag to exercise the decoder without the GUI: `.build/debug/MacDjView --test example.djvu`
- Rendered pages are saved to `/tmp/djvu_pageN.png` for visual inspection.
- When debugging decoder issues, compare byte-for-byte against DjVu.js reference output.
