# Epson QX-11 / QC-11 GAVDP — Reverse Engineering Notes

> **Updated:** 2026-09-21  
> **Status:** based on repeatable real-hardware tests and QX-11 BIOS disassembly.
>
> When emulator behavior differs from the physical QX-11, **real hardware is the reference**.

## 1. Overview

The GAVDP is the custom Epson video gate-array used by the QX-11 / QC-11 display subsystem.

The most important result of the current reverse engineering is that the CPU does **not** see VRAM through one fixed layout. The same framebuffer can be exposed through two different CPU address organizations:

- **row-centric / scanline-major**
- **column-centric / byte-column-major**

The organization is selected by **bit 7 of the memory-mapped register at physical address `8D068h`**.

The display origin is controlled separately by `C462h` and `C663h`.

The three registers currently understood best are:

| Physical address | Current interpretation |
|---|---|
| `8D068h` | CPU VRAM organization + monitor/output profile |
| `8C462h` | horizontal display origin + Mode-7 200-line half selector |
| `8C663h` | vertical display origin |

This document replaces earlier interpretations that described VRAM as permanently column-oriented, `C663` as a 25-row ring index, or `D068` as having a "bit 8 scroll mode".

---

## 2. Common Pixel Packing

For the 640-pixel-wide modes:

```text
xbyte = x >> 3
mask  = 80h >> (x & 7)
```

Each byte represents eight horizontal pixels, MSB first.

What changes with `D068.7` is the relationship between `xbyte`, `y`, and the CPU-visible offset.

---

## 3. D068 — CPU VRAM Organization

### 3.1 Bit 7

Real-hardware testing establishes:

```text
D068.7 = 0 -> column-centric CPU VRAM organization
D068.7 = 1 -> row-centric CPU VRAM organization
```

The BIOS contains two complementary routines which do exactly this.

Conceptually:

```text
ROW routine:
    load row-oriented segment table
    profile |= 80h
    D068 = profile

COLUMN routine:
    load column-oriented segment table
    profile &= 7Fh
    D068 = profile
```

The state is persistent. The BIOS does not automatically restore one universal "default" after every service.

A useful way to describe the BIOS behavior is:

```text
mode set / pixels / clears / scrolling -> row-centric
characters / software cursor           -> column-centric
```

### 3.2 Row-centric formula

With `D068.7 = 1`:

```text
offset = y * 0100h + xbyte
```

Bytes across a scanline are consecutive.

This is naturally efficient for:

- horizontal lines
- scanline fills
- rectangular clears
- horizontal spans
- row-oriented bitmap transfers

### 3.3 Column-centric formula

With `D068.7 = 0`:

```text
offset = xbyte * 0200h + y
```

for a 200-line half.

This is naturally efficient for:

- character glyph rendering
- vertical stems and lines
- byte-column-oriented sprites
- the BIOS software cursor

---

## 4. D068 Lower Bits — Monitor / Output Profile

The BIOS does not use only bit 7.

During mode setup it derives the lower profile from the monitor DIP-switch configuration.

The four values used by the BIOS are:

```text
DIP index 00 -> 05h
DIP index 01 -> 02h
DIP index 10 -> 07h
DIP index 11 -> 03h
```

The monochrome configuration uses:

```text
02h
```

The other three values correspond to the three color/output configurations selected by the monitor DIP switches.

Current safe interpretation:

| D068 bits | Meaning |
|---|---|
| bit 7 | CPU VRAM organization |
| bits 6..3 | not set by the BIOS paths analyzed so far; unknown/reserved |
| bits 2..0 | monitor/output profile |

The individual electrical meaning of bits 0..2 is **not yet fully decoded**.

Software should preserve the lower profile bits when changing only the VRAM organization:

```text
row state    = current_profile | 80h
column state = current_profile & 7Fh
```

For the monochrome profile:

```text
column = 02h
row    = 82h
```

---

## 5. Mode 7 — 640×400 Monochrome

Mode 7 uses two physical 200-line halves.

The CPU segment alias for the lower half changes with `D068.7`.

### 5.1 Column-centric Mode 7

With:

```text
D068.7 = 0
```

the hardware-confirmed mapping is:

```text
Y = 0..199
    segment = 8000h
    offset  = (X >> 3) * 0200h + Y

Y = 200..399
    segment = 8010h
    offset  = (X >> 3) * 0200h + (Y - 200)

mask = 80h >> (X & 7)
```

### 5.2 Row-centric Mode 7

With:

```text
D068.7 = 1
```

the mapping is:

```text
Y = 0..199
    segment = 8000h
    offset  = Y * 0100h + (X >> 3)

Y = 200..399
    segment = 9000h
    offset  = (Y - 200) * 0100h + (X >> 3)

mask = 80h >> (X & 7)
```

Important:

```text
upper half remains 8000h
lower half:
    column view -> 8010h
    row view    -> 9000h
```

The `9000h` lower-half behavior in the row-oriented state has been observed on real hardware and is also consistent with the BIOS Mode-7 pixel path.

### 5.3 Mode-7 summary

| `D068.7` | CPU organization | Y=0..199 | Y=200..399 |
|---|---|---:|---:|
| `0` | column-centric | `8000h` | `8010h` |
| `1` | row-centric | `8000h` | `9000h` |

---

## 6. Mode 6 — 640×200 Monochrome

Mode 6 is especially useful for direct monochrome software because combined/broadcast write apertures have been identified.

### 6.1 Column-centric Mode 6

```text
D068.7 = 0

offset = (X >> 3) * 0200h + Y
mask   = 80h >> (X & 7)
```

A real-hardware test confirmed the combined/broadcast write aperture:

```text
9010h
```

Writing the test image through `9010h` produced the complete visible monochrome result.

### 6.2 Row-centric Mode 6

```text
D068.7 = 1

offset = Y * 0100h + (X >> 3)
mask   = 80h >> (X & 7)
```

The BIOS row-oriented individual plane aliases are:

```text
9000h
8008h
8000h
```

The corresponding combined/broadcast aperture identified in the row-oriented diagnostic is:

```text
9008h
```

### 6.3 Combined-aperture caution

The combined apertures are established as useful **write paths**.

Do not assume that reads from `9010h` or `9008h` return the same value as an ordinary framebuffer plane until that behavior is separately verified.

For read/modify/write operations, use a known readable aperture, modify the byte in the CPU, then write the result through the combined aperture if desired.

---

## 7. C462 — Horizontal Origin and Mode-7 Half Select

`C462` is a display-origin register. It is independent of the CPU VRAM organization selected by `D068`.

### 7.1 Bits 0..6 — horizontal origin

Real-hardware testing establishes:

```text
C462[6:0] = horizontal byte-column origin
```

One increment corresponds to one byte column:

```text
1 step = 8 pixels
```

Increasing the value moves the displayed image left, with circular wrap behavior.

### 7.2 Bit 7 — Mode-7 200-line half selector

In Mode 7:

```text
C462.7 = 0 -> upper 200-line half is displayed first
C462.7 = 1 -> lower 200-line half is displayed first
```

Therefore:

```text
C462 = 00h:
    upper half
    lower half

C462 = 80h:
    lower half
    upper half
```

This half swap is confirmed on real hardware.

The BIOS also explicitly uses `C462.7` this way when a Mode-7 logical vertical origin crosses the 200-line boundary.

---

## 8. C663 — Vertical Display Origin

Real-hardware testing establishes:

```text
1 C663 step = 1 scanline
```

Increasing `C663` moves the displayed image upward.

For Mode 7 the BIOS represents a logical 0..399 vertical origin as:

```text
if origin < 200:
    C462.7 = 0
    C663   = origin
else:
    C462.7 = 1
    C663   = origin - 200
```

Examples:

```text
origin   0 -> C462.7=0, C663=00h
origin 199 -> C462.7=0, C663=C7h
origin 200 -> C462.7=1, C663=00h
origin 399 -> C462.7=1, C663=C7h
```

Thus the 400-line Mode-7 vertical origin is split between:

```text
C462.7 = which 200-line half is first
C663   = line offset inside that half
```

---

## 9. CPU VRAM Organization vs Display Origin

These are separate mechanisms.

```text
D068
    controls how the CPU addresses VRAM

C462 / C663
    control which part of the framebuffer is displayed
```

Changing `D068` changes the CPU's address interpretation.

Changing `C462` or `C663` changes the display origin without copying framebuffer contents.

A useful high-level model is:

```text
                         QX-11 GAVDP
                              |
              +---------------+---------------+
              |                               |
        CPU VRAM VIEW                    DISPLAY ORIGIN
              |                               |
            D068                         C462 + C663
              |                               |
      bit7 selects layout            C462[6:0] horizontal
         /             \              C462[7]  half select
      ROW            COLUMN           C663     vertical
```

---

## 10. BIOS Use of the Two Organizations

The BIOS deliberately selects the organization appropriate to the operation.

### 10.1 Mode initialization

The common `INT 10h / AH=00h` mode-set path eventually selects the row-oriented state.

Therefore after a BIOS mode set, for the mode actually established:

```text
D068.7 = 1
```

This applies to the shared setup path for BIOS modes 0..7. A requested mode can be redirected depending on the monitor configuration, but the final mode is initialized row-centric.

### 10.2 Pixel services

The BIOS pixel services:

```text
INT 10h AH=0Ch -> Write Pixel
INT 10h AH=0Dh -> Read Pixel
```

use the common pixel-address preparation path which selects row-centric organization first.

Therefore:

```text
BIOS pixel addressing = row-centric
```

### 10.3 Character output

The BIOS character paths explicitly select column-centric organization.

This includes:

```text
INT 10h AH=09h -> write character + attribute
INT 10h AH=0Ah -> write character
INT 10h AH=0Eh -> teletype output
```

The BIOS software cursor uses the same column-selection path.

Therefore:

```text
BIOS character rendering = column-centric
BIOS software cursor     = column-centric
```

### 10.4 Scroll / clear

The general BIOS scroll-window path selects the row-oriented state before its framebuffer work.

Mode initialization also clears framebuffer rows while row-centric organization is selected.

That is consistent with the row layout, where bytes across X are consecutive.

### 10.5 No universal persistent default

The selected organization remains active until another BIOS or application operation changes it.

For example:

```text
Set video mode
    -> row-centric

Print a character
    -> column-centric

Read/write a pixel
    -> row-centric
```

So the most precise statement is:

> **Row-centric is the BIOS mode-initialization and graphics-operation state. Column-centric is the BIOS character/cursor-rendering state.**

---

## 11. BIOS Software Cursor and D068

The QX-11 software cursor is relevant because its periodic redraw can change `D068`.

### 11.1 Cursor interference discovered on real hardware

During early row-oriented tests the image sometimes became a mixture of horizontal and vertical fragments.

The reason was:

```text
application:
    D068.7 = 1
    begin row-oriented drawing

INT 71h:
    BIOS cursor renderer runs
    BIOS selects column organization
    D068.7 = 0

application resumes:
    continues using row-oriented offsets
    hardware now interprets them as column-oriented offsets
```

This explains the characteristic distortion seen in the original tests.

### 11.2 BIOS video-busy flag

The BIOS uses an internal video-busy byte at:

```text
0000:089C
```

Bit 0 is used by BIOS video operations.

The periodic cursor service checks the busy state and skips cursor rendering while video work is active.

Real-hardware testing confirmed that setting this busy flag protects a row-oriented operation while interrupts remain enabled.

### 11.3 Disabling the BIOS cursor

The normal BIOS cursor-shape call:

```asm
mov ah,01h
mov cx,2000h
int 10h
```

places the cursor service into a disabled state.

BIOS analysis shows that the `INT 71h` cursor service then skips the cursor-renderer call.

Consequently:

- `INT 71h` still runs
- timer services still run
- the cursor renderer does not run
- cursor blink no longer forces `D068.7=0`

An application that permanently disables the BIOS cursor, avoids BIOS text rendering during an application-owned row operation, and explicitly manages `D068` does not need to use the BIOS busy flag solely to protect against cursor blink.

---

## 12. D269 — Partial Decode

`D269` is still only partially understood.

The established display-control behavior is:

```text
D269.7 = 1 -> display disabled / blanked
D269.7 = 0 -> display enabled
```

The BIOS also modifies lower bits during character/attribute-related work, but their individual meanings are not yet sufficiently decoded.

The previous description of `D269` as a fully decoded PC-like attribute latch should therefore be considered obsolete.

---

## 13. Other GAVDP Control Locations

The following addresses are known to be actively programmed by the BIOS but remain incompletely decoded:

```text
C060
C261
C864
CA65
CC66
CE67
D46A
```

`C060` is especially interesting because BIOS page-switching code writes different values to it while also programming display-origin registers.

Do not assign exact meanings to these registers until isolated real-hardware tests or stronger BIOS evidence establish them.

---

## 14. MAME Implementation Notes

MAME should follow the physical hardware rules even if older emulator behavior allowed software to work with an always-column-oriented mapping.

### 14.1 Required D068 behavior

Conceptually:

```text
if D068.7 == 0:
    CPU uses column-oriented mapping

if D068.7 == 1:
    CPU uses row-oriented mapping
```

Mode 7 additionally changes the lower-half segment alias:

```text
column:
    top    = 8000h
    bottom = 8010h

row:
    top    = 8000h
    bottom = 9000h
```

### 14.2 Display origin is independent

`C462` and `C663` must be implemented as display-fetch origin state, not as consequences of the CPU VRAM layout.

At minimum:

```text
C462[6:0] = horizontal byte-column origin
C462[7]   = Mode-7 200-line half selector
C663      = vertical scanline origin within selected half
```

### 14.3 Remove the obsolete D068 "bit 8 scroll mode" model

`D068` is byte-written by the BIOS.

The current evidence supports bit 7 as the row/column organization selector. The earlier theory that `D068` had a "bit 8 scroll/erase mode" is not valid and should not be implemented.

Scrolling and clearing should instead be understood from the actual BIOS memory operations and the `C462/C663` display-origin mechanism.

### 14.4 Suggested emulator validation

A useful validation suite should test:

1. `D068.7=0` + column formula -> correct geometry.
2. `D068.7=1` + row formula -> same correct geometry.
3. Wrong formula under either organization -> expected characteristic distortion.
4. Mode-7 column lower half at `8010h`.
5. Mode-7 row lower half at `9000h`.
6. `C462` increments -> 8-pixel horizontal origin steps.
7. `C462.7` -> swap Mode-7 200-line halves.
8. `C663` increments -> one-scanline vertical origin steps.
9. BIOS character output -> leaves column organization selected.
10. BIOS pixel operation -> leaves row organization selected.
11. Cursor disabled with `CX=2000h` -> no periodic cursor-induced D068 switch.

---

## 15. Native Software Guidance

Applications should explicitly select the VRAM organization they require.

Do not depend on the organization left behind by an earlier BIOS call.

A safe policy is:

1. Preserve the monitor-profile bits.
2. Select row or column state explicitly.
3. Use the addressing formula that matches that state.
4. Avoid BIOS character output while temporarily using application-owned row mode.
5. If the BIOS cursor remains active, protect temporary row-mode operations.
6. If the BIOS cursor is permanently disabled, cursor-blink interference with `D068` is eliminated.

For monochrome Mode 6:

```text
column combined writes -> 9010h
row combined writes    -> 9008h
```

This permits primitives to choose the most efficient organization:

| Primitive | Natural organization |
|---|---|
| long horizontal line | row |
| horizontal fill / clear | row |
| staff line / beam | row |
| glyph | column |
| vertical stem | column |
| software cursor / sprite | column |
| arbitrary RMW pixel | explicitly managed |

---

## 16. Confirmed vs. Unresolved

### Confirmed on real hardware

- `D068.7=0` selects column-centric CPU addressing.
- `D068.7=1` selects row-centric CPU addressing.
- Mode-7 column mapping uses `8000h / 8010h`.
- Mode-7 row mapping uses `8000h / 9000h`.
- `C462[6:0]` changes the horizontal origin in 8-pixel steps.
- `C462.7` swaps the two Mode-7 200-line display halves.
- `C663` changes vertical origin one scanline per increment.
- Mode-6 `9010h` works as a column-oriented combined write aperture.
- Mode-6 `9008h` works as the row-oriented combined write aperture in the diagnostic.
- BIOS video-busy protection prevents software-cursor interference during row-oriented access.
- `D269.7` disables/blanks the display.

### Confirmed by BIOS analysis and consistent with hardware observations

- BIOS mode initialization selects row-centric access.
- BIOS pixel read/write selects row-centric access.
- BIOS scroll/clear paths select row-centric access.
- BIOS character rendering selects column-centric access.
- BIOS software cursor selects column-centric access.
- Mode-7 BIOS display-origin code splits a 400-line origin between `C462.7` and `C663`.
- `D068` lower-profile values are selected from `02h`, `03h`, `05h`, and `07h`.

### Still unresolved

- exact electrical/timing meaning of `D068` bits 2..0 beyond the known profile values
- exact mapping of `03h`, `05h`, and `07h` to the three color monitor configurations
- function, if any, of `D068` bits 6..3
- lower-bit semantics of `D269`
- exact functions of `C060`, `C261`, `C864`, `CA65`, `CC66`, `CE67`, and `D46A`
- read semantics of the combined/broadcast apertures
- any additional undocumented GAVDP modes or aliases

---

## 17. Summary

The QX-11 framebuffer should no longer be described as simply column-oriented.

The GAVDP exposes the same framebuffer through two selectable CPU organizations:

```text
D068.7 = 1 -> row-centric
D068.7 = 0 -> column-centric
```

The BIOS deliberately uses both:

```text
mode set / pixels / clears / scrolling -> row
characters / software cursor           -> column
```

The display origin is a separate mechanism:

```text
C462[6:0] -> horizontal byte-column origin
C462[7]   -> Mode-7 200-line half selector
C663      -> vertical scanline origin within that half
```

This model is supported by repeatable real-QX-11 tests and BIOS analysis and should be used as the reference behavior for future QX-11 software and emulator work.
