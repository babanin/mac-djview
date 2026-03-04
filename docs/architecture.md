---
description: Decoder architecture and DjVu format reference
alwaysApply: true
---
# Architecture — DjVu Decoder

## Decoding Pipeline

```
DjVu file (IFF container)
  │
  ├── IFFParser.parse() → IFFChunk tree
  │
  ├── DjVuDocument → parses DIRM directory, enumerates pages
  │     │
  │     └── DjVuPage.render() → CGImage
  │           │
  │           ├── BG44 chunks → IW44Decoder → IW44Image → background pixels (RGB)
  │           ├── FG44 chunks → IW44Decoder → IW44Image → foreground pixels (RGB)
  │           ├── Sjbz chunk  → JB2Decoder  → JB2Image  → mask bitmap (1-bit)
  │           ├── FGbz chunk  → FGbzPalette → per-blit colors
  │           ├── Djbz chunk  → JB2Dict     → shared symbol dictionary
  │           │
  │           └── PageCompositor.compose()
  │                 For each pixel:
  │                   mask[x,y] ? foreground[x,y] : background[x,y]
```

## IW44 Wavelet Decoder

### Chunk Header (BG44/FG44)
```
Byte 0:    serial (uint8) — 0 for first chunk
Byte 1:    numSlices (uint8)
If serial == 0:
  Byte 2:  majver (uint8) — bit 7: grayscale flag; bits 6-0: unused
  Byte 3:  minver (uint8)
  Byte 4-5: width (uint16 big-endian)
  Byte 6-7: height (uint16 big-endian)
  Byte 8:  delayInit byte — bits 6-0: delay before color decoding starts
```

### Channel Architecture
- **Separate decoder per channel**: `IW44ChannelDecoder` for Y, Cb, Cr
- Each has independent: `curband`, `quantLo[]`, `quantHi[]`, ZP contexts, coefficient state
- All share the same `ZPCodec` bitstream
- `delayInit`: Cb/Cr decoding starts after `delayInit` slices (Y always decodes)

### Decode Phases (per slice, per block)
1. **Preliminary flag computation** — classify coefficients as ZERO/UNK/ACTIVE
2. **Block band decoding pass** — decide if block-band has new coefficients
3. **Bucket decoding pass** — activate individual buckets within the band
4. **Newly active coefficient pass** — decode new coefficient values
5. **Previously active coefficient refinement** — refine existing coefficients

### Inverse Wavelet Transform
- 4-level lifting-based DDL 4,4 wavelet
- Operates on `LinearBytemap` (Int16 array with wrapping arithmetic)
- Processes columns first, then rows, at each scale level (s=16,8,4,2,1)

### Color Conversion
- Grayscale: `pixel = 127 - normalize(y)` where `normalize(v) = clamp((v + 32) >> 6, -128, 127)`
- Color (YCbCr → RGB):
  ```
  t2 = r + (r >> 1)
  t3 = y + 128 - (b >> 2)
  R = y + 128 + t2
  G = t3 - (t2 >> 1)
  B = t3 + (b << 1)
  ```

## JB2 Symbol Decoder

### Init Sequence (critical order)
1. Read record type via `decodeNum(0, 11, recordTypeCtx)`
2. If type == 9: read inherited dict size, read next type
3. Read image width and height via `decodeNum(0, 262142, imageSizeCtx)`
4. Read flag via **raw ZP bit** `zp.decode(ctx, 0)` — NOT `decodeNum`!

### Record Types
| Type | Description | Library | Image |
|------|-------------|---------|-------|
| 1 | New symbol (direct bitmap) | add | add blit |
| 2 | New symbol (direct bitmap) | add | — |
| 3 | New symbol (direct bitmap) | — | add blit |
| 4 | Refinement from library | add | add blit |
| 5 | Refinement from library | add | — |
| 6 | Refinement from library | — | add blit |
| 7 | Matched copy (no refinement) | — | add blit |
| 8 | Non-symbol data (absolute coords) | — | add blit |
| 9 | Numcoder reset | — | — |
| 10 | Comment | — | — |
| 11 | End of data | — | — |

### Coordinate System
- Blit coordinates (x, y) are in DjVu bottom-up space
- `firstLeft` initializes to **-1** (not 0)
- `lastRight = x + width - 1` (not `x + width`)
- New-line and same-line offsets use **separate** NumContext pairs

### Refinement Alignment
```
rowshift = ((model.height - 1) >> 1) - ((new.height - 1) >> 1)
colshift = ((model.width - 1) >> 1) - ((new.width - 1) >> 1)
model_row = current_row + rowshift
model_col = current_col + colshift
```

## ZP-Coder (Arithmetic Decoder)

- Adaptive binary arithmetic coding with 256-entry probability state table
- `decode(ctx, n)` — decode one bit using context array at index n
- `IWdecode()` — decode one bit without context (for IW44 sign bits)
- `decodeNum(ctx, low, high)` — 3-phase number decoding (sign, magnitude class, binary refinement)
- `NumContext` — binary tree of ZP contexts for multi-bit number encoding

## Page Composition

The compositor combines layers at the page's native resolution:
1. **Background** (IW44): Often lower resolution than the page; upscaled via nearest-neighbor
2. **Foreground** (IW44 or FGbz palette): Provides color for masked pixels
3. **Mask** (JB2): 1-bit at page resolution; determines which pixels use foreground vs background
4. **Output rule**: `pixel = mask[x,y] ? foreground_color : background_color`
5. All coordinate conversions handle the DjVu bottom-up → screen top-down flip
