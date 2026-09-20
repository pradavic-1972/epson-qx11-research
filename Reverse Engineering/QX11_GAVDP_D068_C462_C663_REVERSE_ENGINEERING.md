# Epson QX-11 / QC-11 GAVDP: VRAM Organization and Display-Origin Registers

## Status

This document records behavior confirmed while reverse-engineering the Epson QX-11 / QC-11 GAVDP video hardware.

The findings below are based primarily on **real QX-11 hardware tests**, cross-checked against the Epson BIOS disassembly. Where MAME behavior differs, **real hardware is considered authoritative**.

The three registers covered here are:

- `8000:D068` — CPU VRAM organization / monitor-output profile
- `8000:C462` — horizontal display origin plus 200-line half selector
- `8000:C663` — vertical display origin within a 200-line half

Physical addresses are therefore `8D068h`, `8C462h`, and `8C663h`.

---

# 1. D068 — CPU VRAM Organization

The most important discovery is that **bit 7 of D068 changes how the CPU sees VRAM**.

## D068 bit 7

| D068 bit 7 | CPU VRAM organization | Confirmed |
|---|---|---|
| `0` | Column-centric | Yes, real hardware |
| `1` | Row-centric | Yes, real hardware |

This is not just a software convention. The same physical framebuffer can be accessed through two different address organizations selected by the GAVDP.

---

## 1.1 Column-centric organization

With `D068.7 = 0`, bytes belonging to one 8-pixel-wide vertical column are grouped together.

For a pixel at `(x,y)`:

```text
xbyte  = x >> 3
mask   = 80h >> (x & 7)
offset = xbyte * 0200h + y
```

For 640x200 modes:

```text
offset = (x >> 3) * 0200h + y
```

For Mode 7, which is 640x400 monochrome, the screen is split into two 200-line halves:

```text
Y =   0..199:
    segment = 8000h
    offset  = (x >> 3) * 0200h + y

Y = 200..399:
    segment = 8010h
    offset  = (x >> 3) * 0200h + (y - 200)
```

This is the organization traditionally used by our QX-11 640x400 software.

It is especially convenient for:

- character rendering
- 8-pixel-wide glyph columns
- vertical bitmap operations
- software sprites organized by scanline within a byte column

---

## 1.2 Row-centric organization

With `D068.7 = 1`, scanline bytes become contiguous.

For a pixel at `(x,y)`:

```text
xbyte  = x >> 3
mask   = 80h >> (x & 7)
offset = y * 0100h + xbyte
```

For Mode 7:

```text
Y =   0..199:
    segment = 8000h
    offset  = y * 0100h + (x >> 3)

Y = 200..399:
    segment = 9000h
    offset  = (y - 200) * 0100h + (x >> 3)
```

The upper 200-line half remains at `8000h`.

The lower 200-line half changes alias:

```text
D068.7 = 0  -> lower half = 8010h
D068.7 = 1  -> lower half = 9000h
```

This behavior was observed previously on real hardware and is also visible in the BIOS Mode-7 pixel path.

Row-centric organization is especially convenient for:

- horizontal lines
- scanline fills
- horizontal block copies
- operations where sequential bytes across X are desirable

---

# 2. Mode 6 Combined Apertures

Mode 6 is 640x200 monochrome, but internally the BIOS still uses the GAVDP plane mapping machinery.

Real-hardware testing identified combined apertures that allow the visible monochrome result to be written without separately updating all individual plane aliases.

## Column-centric Mode 6

With:

```text
D068.7 = 0
```

the combined aperture is:

```text
segment 9010h
```

using:

```text
offset = (x >> 3) * 0200h + y
```

A complete test image could be drawn through `9010h` alone.

The `8000h` segment is also usable for the visible monochrome framebuffer in this organization and is useful when ordinary read/modify/write behavior is required.

---

## Row-centric Mode 6

With:

```text
D068.7 = 1
```

the BIOS plane aliases are:

```text
9000h
8008h
8000h
```

and the corresponding combined/broadcast aperture observed in testing is:

```text
9008h
```

using:

```text
offset = y * 0100h + (x >> 3)
```

The BIOS itself uses the individual plane aliases for graphics pixel operations.

---

# 3. BIOS Protection While Switching D068

An important real-hardware issue was discovered while testing row-centric access.

The BIOS timer/cursor service can modify `D068` asynchronously. The BIOS software cursor renderer uses the column-centric path and can therefore clear `D068.7` while an application is in the middle of row-centric drawing.

That produces mixed-addressing corruption.

A typical failure looked like this:

```text
application sets D068.7 = 1
application begins row-centric drawing

INT 71h occurs
BIOS cursor code switches D068.7 back to 0

application continues using row-centric offsets
but hardware is now interpreting them column-centrically
```

This explains earlier test images containing a mixture of horizontal and vertical fragments.

## BIOS busy flag

The Epson BIOS protects its own video operations with an internal busy flag.

The tested flag is:

```text
0000:089C bit 0
```

When this busy flag is set, the periodic cursor service does not interfere with the current video operation.

Real-hardware testing confirmed that:

- interrupts can remain enabled
- `D068.7` can remain in row-centric mode
- the expected image is drawn correctly
- the BIOS cursor service no longer changes the organization underneath the application

Therefore long `CLI` sections are not required.

A safe application sequence is:

```text
set BIOS video-busy flag
set D068.7 = 1
perform row-centric VRAM operation
restore expected D068 state
clear BIOS video-busy flag
```

This is preferable for software that depends on interrupts for:

- keyboard handling
- timing
- RTC services
- sound/music playback

---

# 4. D068 Lower Bits

The BIOS does not use only bit 7.

Bits `2:0` are loaded from a four-entry table selected by the upper two bits of the monitor DIP-switch input.

The values used by the BIOS are:

```text
DIP index 00 -> 05h
DIP index 01 -> 02h
DIP index 10 -> 07h
DIP index 11 -> 03h
```

The monochrome configuration is known to use:

```text
02h
```

The other three values correspond to the color monitor configurations selected by DIP switches 7 and 8.

Known monitor choices are:

- Monochrome
- RGB / NTSC positive sync
- NTSC negative sync
- PAL

The exact assignment of `03h`, `05h`, and `07h` to the three color configurations has not yet been proven.

Therefore the current safe interpretation is:

| D068 bits | Meaning |
|---|---|
| bit 7 | CPU VRAM organization: `0=column`, `1=row` |
| bits 6..3 | Not used by the BIOS in observed configurations |
| bits 2..0 | Monitor/output profile selected from DIP configuration |

The individual electrical meaning of bits 0, 1, and 2 should not yet be treated as proven.

---

# 5. C462 — Horizontal Origin and 200-Line Half Selector

`C462` has two distinct functions.

## Bits 0..6 — horizontal origin

Bits `0..6` control the horizontal framebuffer origin in units of one byte column.

Since one VRAM byte represents 8 horizontal pixels:

```text
1 register step = 8 pixels
```

Increasing the register value moves the displayed image to the left, with circular wraparound.

So:

```text
C462 bits 0..6 = horizontal byte-column origin
```

The meaningful visible 640-pixel screen contains 80 byte columns, although the register field itself is 7 bits wide.

---

## Bit 7 — Mode-7 200-line half selector

In Mode 7, bit 7 selects which 200-line half forms the first half of the displayed 400-line circular framebuffer.

```text
C462.7 = 0
    upper 200-line half is displayed first

C462.7 = 1
    lower 200-line half is displayed first
```

At:

```text
C462 = 80h
```

the upper and lower 200-line halves swap display order.

This was first observed experimentally and is also explicitly implemented by the BIOS.

---

# 6. C663 — Vertical Origin Within a Half

`C663` controls vertical display origin.

One increment corresponds to one scanline:

```text
1 register step = 1 scanline
```

Increasing `C663` moves the displayed image upward, with circular behavior.

For Mode 7, the BIOS treats the 400-line vertical origin as a combination of:

```text
C462 bit 7 = which 200-line half is first
C663       = line offset within that half
```

The BIOS logic is effectively:

```text
if vertical_origin < 200:
    C462.7 = 0
    C663   = vertical_origin
else:
    C462.7 = 1
    C663   = vertical_origin - 200
```

Examples:

```text
logical origin 0:
    C462.7 = 0
    C663   = 00h

logical origin 199:
    C462.7 = 0
    C663   = C7h

logical origin 200:
    C462.7 = 1
    C663   = 00h

logical origin 399:
    C462.7 = 1
    C663   = C7h
```

This gives the GAVDP a circular 400-line display-origin mechanism without requiring a single 9-bit vertical register.

---

# 7. Summary Table

| Register | Bits / value | Function | Status |
|---|---|---|---|
| `D068` | bit 7 = `0` | Column-centric CPU VRAM organization | **Confirmed on real hardware** |
| `D068` | bit 7 = `1` | Row-centric CPU VRAM organization | **Confirmed on real hardware** |
| `D068` | bits 2..0 | Monitor/output profile | **Confirmed as profile field** |
| `D068` | `02h` | Monochrome profile | **Confirmed** |
| `D068` | `03h`,`05h`,`07h` | Three color-output profiles | **Confirmed values; exact mapping unresolved** |
| `D068` | bits 6..3 | Unknown / unused by observed BIOS code | Not established |
| `C462` | bits 0..6 | Horizontal origin in 8-pixel byte columns | **Confirmed on real hardware** |
| `C462` | bit 7 | Select/swap first 200-line display half in Mode 7 | **Confirmed on real hardware and BIOS** |
| `C663` | bits 0..7 | Vertical origin within selected 200-line half | **Confirmed on real hardware and BIOS** |

---

# 8. Mode-7 Addressing Summary

## Column-centric

```text
D068.7 = 0

Top 200 lines:
    segment = 8000h
    offset  = Xbyte * 0200h + Y

Bottom 200 lines:
    segment = 8010h
    offset  = Xbyte * 0200h + (Y - 200)
```

## Row-centric

```text
D068.7 = 1

Top 200 lines:
    segment = 8000h
    offset  = Y * 0100h + Xbyte

Bottom 200 lines:
    segment = 9000h
    offset  = (Y - 200) * 0100h + Xbyte
```

where:

```text
Xbyte = X >> 3
mask  = 80h >> (X & 7)
```

---

# 9. Display-Origin Summary

The display origin is independent from the CPU VRAM organization.

```text
D068
    controls how the CPU addresses VRAM

C462
    bits 0..6 = horizontal byte-column origin
    bit 7     = Mode-7 200-line display-half selector

C663
    vertical line origin within the selected 200-line half
```

This distinction is important:

Changing `D068` changes the **CPU's view of VRAM**.

Changing `C462` or `C663` changes **what part of that framebuffer the GAVDP displays**, without moving the framebuffer contents.

---

# 10. BIOS Evidence

The BIOS contains two complementary routines:

```text
sub_F186F
    loads the graphics/row-oriented segment table
    sets D068 bit 7

sub_F1892
    loads the character/column-oriented segment table
    clears D068 bit 7
```

The BIOS pixel path uses the row-oriented formula:

```text
offset = Y * 0100h + Xbyte
```

The BIOS character/cursor path uses the column-oriented organization.

For Mode 7, the BIOS also explicitly switches the lower-half segment according to the selected organization:

```text
column-centric lower half -> 8010h
row-centric lower half    -> 9000h
```

The BIOS display-origin code explicitly maps a 400-line logical origin to:

```text
C462 bit 7
C663
```

at the 200-line boundary.

---

# 11. MAME Compatibility Note

Some earlier software appeared to work in MAME while violating the real-hardware `D068` organization rules.

For QX-11 development, software should therefore follow the real hardware model even if MAME currently accepts combinations that the physical machine does not.

In particular:

- do not assume column-centric addressing works while `D068.7=1`
- do not assume row-centric addressing works while `D068.7=0`
- protect temporary row-centric operations from the BIOS cursor service
- preserve the monitor-profile bits when changing only the VRAM organization bit

A portable helper should conceptually do:

```text
row mode    = current_profile | 80h
column mode = current_profile & 7Fh
```

rather than hard-coding `80h` or `00h`.

For the monochrome configuration this normally means:

```text
column-centric = 02h
row-centric    = 82h
```

---

# 12. Current Reverse-Engineering Model

The current best model of these GAVDP registers is:

```text
                     CPU VRAM ACCESS
                           |
                         D068
                    bit 7 selects
                    /             \
             column-centric     row-centric


                    DISPLAY ORIGIN
                           |
                    +------+------+
                    |             |
                  C462           C663
             horizontal +      vertical line
             half select       within half
```

The CPU memory organization and display origin are separate hardware mechanisms.

That separation explains a number of previously confusing QX-11 behaviors and is now supported by both BIOS analysis and repeatable real-hardware experiments.

---

## Revision note

These findings should be treated as the reference behavior for future QX-11 graphics code.

If emulator behavior differs, software should continue to follow the real-hardware rules documented here.
