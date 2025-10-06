# QX-11 BIOS — INT 10h Reference (Supported Calls)

This document lists **all** INT 10h services implemented by the QX-11/QC-11 BIOS as determined from reverse-engineering.  
The dispatcher services **two ranges only**:

- **Standard:** `AH = 00h–10h`
- **OEM:** `AH = 40h–4Fh`

All others (`11h–3Fh`, `≥50h`) are **not handled**.

> Conventions:
> - Code addresses are from the system BIOS (segment `F000h`) unless noted.
> - BIOS workspace lives in low memory segment `0000h` (e.g., mode, geometry, plane pointers).
> - Text rendering is **tri-plane**: separate planes for **char** and **attribute hi/lo**.

---

## Dispatcher & Jump Table

- INT 10h indexes a table at **`CS:4AD8`**:
  - `AH=00h–10h` → entries `0x00–0x10`
  - `AH=40h–4Fh` → entries `0x11–0x20` (index = `AH−2Fh`)

---

## Standard Block (`AH=00h–10h`)

### AH=00h — Set Video Mode
**Entry:** `F000:16E8`  
Validates/remaps `AL (0..7)` via DIP/flags; stores mode to `[0449]`.  
Seeds geometry/timing/flags; clears screen; copies **11-byte mode block** from `CS:4A78 → [0808]`; programs GA/CRTC via `CS:4A62` (+ optional `CS:4AD0/4AD4`); blanks VRAM.  
Sets up data used by OEM text/graphics helpers.

---

### AH=01h — Write GA/CRTC Table (helper)
**Entry:** `F000:18B5`  
Writes `CX` entries: **value from `DS:BX` → ES=8000h:[word offset from `CS:SI`]**.  
Used during mode set/palette commits.

---

### AH=02h — Set Cursor Position
**Entry:** `F000:1952`  
`BH=page(0..1)`, `DH=row`, `DL=col`; bounds vs `[044A]` max col (0-based) and `[0854]` max row.  
Stores `word [0450 + BH*2] = DX`.

### AH=03h — Get Cursor Position/Shape
**Entry:** `F000:197F`  
`BH=page`; returns `DH:DL` from `[0450+BH*2]`, `CH:CL` from `[0460]`.

### AH=05h — Set Active Page
**Entry:** `F000:1999`  
`AL=page(0..1)`; wraps **page-flip core** `sub_F19B1` with pre/post hooks.

- **sub_F19B1 (`F000:19B1`)** — swaps per-page CRTC starts (`[085A]/[085C]/[085E]`), updates pointers `[0868]/[086A]`, cursor preset `[0859]`, and (if live flag set) pokes GA/CRTC shadow `ES=8000h:0C060/0C663/0C462`.

### AH=06h — Scroll Window Up  
### AH=07h — Scroll Window Down
**Entry:** `F000:1A40`  
Standard IBM semantics with rectangle copy + fill of revealed band; direction seeded in `[08BB]` (`+1` up, `FFh` down).  
Fast path for full-screen 1-line scroll (`sub_F2014`).

### AH=08h — Read Char & Attribute at Cursor
**Entry:** `F000:1E6D`  
`BH=page`; internally switches page (no HW change), fetches cell, returns `AL=char`, `AH=attr`.

### AH=09h — Write Char & Attribute (repeat)
**Entry:** `F000:1E8D`  
`AL=char`, `BL=attr`, `BH=page`, `CX=count`.  
Non-visible page swap; loop writes tri-plane cell and advances cursor.

### AH=0Ah — Write Char Only (repeat)
**Entry:** `F000:20CC`  
Text mode: preserves existing attribute (reads it each time).  
Graphics mode: redirects to **AH=09h**.

### AH=0Bh — Palette/Background Control (modes 4/5)
**Entry:** `F000:2143`  
- `BH=0`: set **background & border** to nibble `BL` (writes indices 0 and 4).  
- `BH≠0`: load preset palette set from `CS:4A5C/4A5F` into indices 1,2,3,5,6,7.  
Commit 4 control bytes via table `CS:4A70` and the write-table helper.

### AH=0Ch — Write Pixel / Raster-Op (graphics)
**Entry:** `F000:219E`  
`AL`: low 3 bits **pattern index (0..7)**, bit7 **toggle**.  
Parses XY; per plane: clear/set/toggle bit using masks from helpers; commit.

### AH=0Dh — Read Pixel (graphics)
**Entry:** `F000:229E`  
Parses XY; tests bit in each plane; **ORs** per-plane pattern byte into `AL`.

### AH=0Eh — Teletype Output (print AL)
**Entry:** `F000:22D6`  
Handles **BEL/BS/CR/LF**. Printable path maps glyph and writes; text preserves current attribute; handles EOL/scroll.

### AH=0Fh — Get Video Mode
**Entry:** `F000:23BB`  
Returns `AL=[0449]` mode, `AH = [044A]+1` columns, `BH=[0462]` page.

### AH=10h — Direct GA Palette Nibble Write
**Entry:** `F000:23CC`  
- `AL=0`: set one nibble — `BL=index(0..7)`, `BH=value(0..F)`.  
- `AL=1`: no-op.  
- `AL=2`: bulk load 8 nibbles from `ES:DX`.  
Commit via `CS:4A70` + write-table helper.

---

## OEM Block (`AH=40h–4Fh`)

> Operate on **tri-plane text**; plane segments:  
> **`[088E]` attr-hi**, **`[0890]` char**, **`[0892]` attr-lo** (segment `0000h`).

### AH=40h — Rectangle Blit (auto dir)
**Entry:** `F000:2430`  
Block copy within text VRAM; chooses direction to avoid overlap corruption.

### AH=41h — Rectangle Blit (forced backward)
**Entry:** `F000:2429`  
Same as 40h with fixed backward pass.

### AH=42h — Build/Activate Char-Map (profile 0..2)
**Entry:** `F000:252E` → `sub_F2535`  
Initializes 256-entry code→glyph map at `[0838]`; for `AL=1/2` overlays ROM slices at `F107:4890/4950`. Finalize via `sub_F25AC`.

### AH=43h — Set Layout Preset (0..0Bh) & Rebuild Map
**Entry:** `F000:259E`  
Stores preset in `[087C]`, re-invokes char-map build using current profile `[087B]`.

### AH=44h–47h — Rectangle Fill / Write (tri-plane)
**Entry:** `F000:262A`  
Writes same rectangle across planes:  
1) ES=`[088E]` ← **BH** (attr-hi)  
2) ES=`[0890]` ← **AL** (char)  
3) ES=`[0892]` ← **BL** (attr-lo)

### AH=48h — Read Cell at XY (tri-plane)
**Entry:** `F000:26E1`  
Returns `AL=char`, `BX=attr` (BH hi nibble/byte, BL low).

### AH=49h — Read GA Nibble (palette/etc.)
**Entry:** `F000:273E`  
`BL=0..7` → returns nibble in `BH`, using mapping table at `[080F]`.

### AH=4Ah — Hook Jump (far via data)
**Entry:** `F000:2873`  
Loads `ES` from `[1AAE]`, then `jmp word ptr [1AA8]` (pluggable extension, e.g., renderer/kanji).

### AH=4Bh — Display-List Runner (kbd-aware)
**Entry:** `F000:2B5F`  
Executes scripted display list interleaved with keyboard input; uses `[1AAC/1AAE]`, `[1AB6/1AB8]`, `[1AA6]`, `[1AC3]`.

### AH=4Ch — Non-Blocking Poll/Feeder
**Entry:** `F000:2BB5`  
Returns next byte from display list or keyboard if ready; sets/clears bit6 (0x40) in caller’s status at `[BP+14]`.

### AH=4Dh — Set/Init Display-List Buffer
**Entry:** `F000:2BFA`  
`ES:BX=buf`, `CX=size`. If empty → zero `[1AA6]`; else scans length-prefixed chunks, stores pointers/lengths to `[1AAC/AE]`, `[1AB6/B8]`, `[1AB0]`.

### AH=4Eh — (none)

### AH=4Fh — Keyboard OEM Trampoline
**Entry:** `F000:2C4B`  
`mov ah,40h` / `int 16h`.

---

## Key Workspace (segment `0000h`)

- **Mode/state:** `[0449]` mode, `[044A]` max col (0-based), `[0450]/[0452]` cursor per page, `[0460]` cursor shape, `[0462]` active page.  
- **Mode block:** `[0808]` (11-byte active), `[0809]` feature bits, `[080C]` profile id, `[080D]` GA/CRTC control shadow.  
- **Char map:** `[0838]` 256-word code→glyph table.  
- **Geometry/timing:** `[0854]` rows, `[0855]/[0857]` limits, `[0861]/[0862]` clocks, `[0868]/[086A]` pointers, flags `[086E]/[0872]/[0873]/[0874]`.  
- **Text planes:** `[088E]` attr-hi, `[0890]` char, `[0892]` attr-lo.

---

## Notes & Compatibility

- Only **modes 0..7** are accepted by **AH=00h**.  
- Text operations and OEM rectangle ops write **all three planes**.  
- **AH=0Bh** is restricted to **graphics 4/5**; **AH=10h** provides lower-level palette writes (no mode guard).  
- Page-sensitive ops often **switch pages internally** without changing hardware (no flicker).

---

## License / Attribution

Derived from reverse-engineering the QX-11/QC-11 BIOS.  
Please attribute this file when reusing parts of it.
