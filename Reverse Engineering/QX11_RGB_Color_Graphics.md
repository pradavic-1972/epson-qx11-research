# Epson QX-11 RGB Color Graphics and Three-Plane Rendering

This page documents the current reverse-engineered understanding of how the Epson QX-11 stores color graphics, combines its three video planes, and produces its RGB output.

> **Status:** Work in progress.  
> The VRAM plane assignments and visible color combinations have been verified on real QX-11 hardware. The exact transistor/resistor network used by the video-output stage has not yet been completely traced, so electrical-level descriptions are identified separately from confirmed logical behavior.

---

## 1. Overview

In its color graphics modes, the QX-11 uses **three independent one-bit bitmap planes**:

| Plane | CPU-visible region | Color contribution |
|---|---:|---|
| Blue | `8000h` plane/bank | Blue |
| Red | `8008h` plane/bank | Red |
| Green | `9000h` plane/bank | Green |

Each plane stores one binary decision for every displayed pixel:

- `0` = that primary color is absent
- `1` = that primary color is present

The display hardware reads corresponding bits from the red, green, and blue planes at the same time. Those three bits form a three-bit color number:

```text
Color = (Blue × 1) + (Red × 2) + (Green × 4)
```

Using the QX-11 plane order found during testing:

```text
bit 2 = Green
bit 1 = Red
bit 0 = Blue
```

This produces the standard eight-color digital RGB palette.

---

## 2. The Eight RGB Combinations

| Green | Red | Blue | Binary | Result |
|---:|---:|---:|---:|---|
| 0 | 0 | 0 | `000` | Black |
| 0 | 0 | 1 | `001` | Blue |
| 0 | 1 | 0 | `010` | Red |
| 0 | 1 | 1 | `011` | Magenta |
| 1 | 0 | 0 | `100` | Green |
| 1 | 0 | 1 | `101` | Cyan |
| 1 | 1 | 0 | `110` | Yellow |
| 1 | 1 | 1 | `111` | White |

The important point is that cyan, magenta, yellow, and white are **not stored in separate memory areas**. They are created by enabling more than one primary-color plane for the same pixel.

For example:

```text
Blue plane bit  = 1
Red plane bit   = 1
Green plane bit = 0
```

The monitor receives red and blue simultaneously, producing **magenta**.

---

## 3. How the QX-11 “Mixes” the Colors

The QX-11 does not appear to mix color values in software. Software writes independent monochrome masks into the three color planes.

The display hardware then performs the equivalent of this operation continuously for every pixel:

```text
R_OUT = red_plane_pixel
G_OUT = green_plane_pixel
B_OUT = blue_plane_pixel
```

Conceptually:

```text
             Red VRAM bit  ───────────────► Red output
Pixel clock  Green VRAM bit ──────────────► Green output
selects      Blue VRAM bit ───────────────► Blue output
same pixel
position
```

The monitor performs the optical addition of the three primaries. The computer therefore does not need a stored numeric value for yellow, cyan, magenta, or white.

### Logical mixing versus electrical mixing

There are two separate stages:

1. **Logical combination**  
   The GAVDP/video circuitry fetches one bit from each plane for the same pixel.

2. **Electrical output stage**  
   The three binary color states are driven onto the physical red, green, and blue output lines through the ICRT video card circuitry.

The logical behavior is confirmed. The exact voltage levels, output impedance, and complete resistor/transistor path should still be measured or traced before describing the connector as electrically compatible with a particular TTL-RGB standard.

---

## 4. Confirmed QX-11 Video Connector Signals

The currently traced nine-pin inline video connector includes:

| Pin | Signal |
|---:|---|
| 1 | +12 V |
| 2 | Approximately 14.318 MHz clock; not connected through the known 8-pin DIN cable |
| 3 | Blue |
| 4 | Ground |
| 5 | Red |
| 6 | Green |
| 7 | Horizontal sync |
| 8 | Vertical sync |
| 9 | Not yet documented here |

This is a **separate-sync RGB interface**: the color channels are carried independently, and horizontal and vertical synchronization are also separate.

The RGB outputs traced on the ICRT card ultimately originate in the video-output section associated with the GAIBVD circuitry. For example, the red path has been traced from GAIBVD pin 34 through the card circuitry to the external connector.

---

## 5. Plane Organization

### 5.1 A plane is a monochrome image

Each QX-11 color plane can be viewed independently as a black-and-white bitmap.

For a given screen location:

```text
Blue plane:  00010000
Red plane:   00010000
Green plane: 00000000
```

The set bit occurs at the same pixel in the blue and red planes, so that pixel appears magenta.

A useful debugging method is to fill only one plane:

```text
Blue only  -> blue pattern
Red only   -> red pattern
Green only -> green pattern
```

Then combine two or three fills to verify the mixed colors.

### 5.2 The addressing is not IBM-style linear scan-line memory

Real-hardware testing shows that QX-11 bitmap VRAM is **column-major**, rather than the conventional row-major organization expected by most IBM PC software.

In a simple row-major framebuffer, adjacent addresses normally progress horizontally:

```text
address + 1 -> next group of pixels to the right
```

In the QX-11’s native organization, address progression is tied more strongly to vertical or column-oriented display sequencing. This is one reason that IBM CGA and Hercules rendering routines cannot simply redirect segment `B800h` or `B000h` writes to QX-11 VRAM.

Software ports must transform coordinates or copy a conventional framebuffer through a QX-specific renderer.

### 5.3 Known color-mode plane selection

Reverse engineering of QX-11 mode 2 established:

```text
8000h = Blue plane
8008h = Red plane
9000h = Green plane
```

The unusual `8000h` versus `8008h` distinction indicates that at least part of the plane selection is controlled by the QX-11’s memory/video banking logic, not merely by three ordinary contiguous 16 KiB CPU address ranges.

The labels above describe the effective CPU-visible selections observed during testing. They should not yet be interpreted as a complete physical DRAM address map.

---

## 6. Drawing a Pixel

At the logical level, drawing a color pixel requires changing the corresponding bit in one, two, or all three planes.

Assume:

```text
mask = bit selecting pixel X within the target byte
offset = QX-specific address calculated from X and Y
```

Then:

```text
Blue  = color AND 1
Red   = color AND 2
Green = color AND 4
```

Pseudocode:

```c
void qx_put_pixel(int x, int y, unsigned color)
{
    unsigned offset = qx_column_major_offset(x, y);
    unsigned char mask = qx_pixel_mask(x);

    select_blue_plane();
    update_bit(offset, mask, color & 0x01);

    select_red_plane();
    update_bit(offset, mask, color & 0x02);

    select_green_plane();
    update_bit(offset, mask, color & 0x04);
}
```

The same principle applies to bytes, characters, sprites, and full-screen images: generate three monochrome masks and write each mask to its matching plane.

---

## 7. Converting Packed RGB Data into QX-11 Planes

Suppose a source image stores one three-bit color number per pixel:

```text
0 = black
1 = blue
2 = red
3 = magenta
4 = green
5 = cyan
6 = yellow
7 = white
```

For every group of eight pixels, construct three output bytes:

```c
blue_byte  = 0;
red_byte   = 0;
green_byte = 0;

for (int pixel = 0; pixel < 8; pixel++) {
    unsigned c = source[pixel];
    unsigned mask = 0x80 >> pixel;

    if (c & 0x01) blue_byte  |= mask;
    if (c & 0x02) red_byte   |= mask;
    if (c & 0x04) green_byte |= mask;
}
```

The bytes then go to the corresponding QX-11 planes at the same QX-specific screen offset.

This operation is usually called **planar conversion**, **bit-plane separation**, or **chunky-to-planar conversion**.

---

## 8. Why Planar Graphics Were Attractive

Three one-bit planes require:

```text
width × height × 3 bits
```

For a 640 × 200 image:

```text
640 × 200 × 3 / 8 = 48,000 bytes
```

That is almost exactly 48 KiB, a common and practical amount of dedicated video memory in early-1980s Japanese computers.

Planar storage also offers several useful operations:

- Clear or replace one primary color without rewriting the other two.
- Produce colored overlays by writing only selected planes.
- Perform monochrome logical operations independently on red, green, and blue.
- Reuse one-bit drawing hardware for each primary.
- Feed three parallel one-bit shift-register paths directly into digital RGB outputs.

The cost is that changing a general eight-color pixel may require up to three separate memory operations.

---

## 9. Comparison with Contemporary Systems

## 9.1 Fujitsu FM-7

The FM-7 is one of the closest conceptual matches to the QX-11.

It provides:

- 640 × 200 graphics
- Eight simultaneous digital RGB colors
- 48 KiB of video RAM
- Separate blue, red, and green bit planes

The FM-7’s 48 KiB VRAM capacity follows directly from three 16 KiB monochrome planes:

```text
640 × 200 / 8 = 16,000 bytes per plane
16,000 × 3 = 48,000 bytes
```

Like the QX-11, a pixel’s final color is formed by combining corresponding bits from the three planes.

The major architectural difference is access. The FM-7 uses a second 6809 processor as a video/sub-CPU, and normal graphics access is mediated by that subsystem. The QX-11 instead integrates display control into Epson gate-array logic and exposes its video memory through unusual CPU-visible windows and plane-selection behavior.

**Similarity:** Extremely high at the color-representation level.

---

## 9.2 NEC PC-8801

Early PC-8801 graphics modes also used three RGB bit planes to provide 640 × 200 graphics in eight colors.

As on the QX-11:

```text
pixel color = blue bit + red bit + green bit
```

The PC-8801 family later added more capable palette and graphics modes, but the original eight-color mode belongs to the same Japanese planar-RGB design tradition.

A practical difference is that the PC-8801 became a major game platform, so software often contains highly optimized routines for writing or logically combining its planes. The QX-11 appears to have used a related color concept but a less conventional memory layout and a much smaller software ecosystem.

**Similarity:** High for the original digital eight-color modes.

---

## 9.3 NEC PC-9801

Early PC-9801 graphics hardware also used separate graphics planes. The original digital-color organization is commonly described in terms of blue, red, and green planes, with later models adding a fourth plane and increasingly sophisticated graphics controllers and palettes.

The PC-9801 is particularly relevant because it is, like the QX-11:

- An x86-family business computer
- Designed around Japanese-market display requirements
- Not IBM PC video-compatible despite using a related CPU architecture
- Built around dedicated text and graphics display mechanisms

The PC-9801 eventually developed hardware-assisted planar operations, including GRCG and later EGC functions. No equivalent QX-11 accelerator has yet been identified; the QX-11’s GAVDP does, however, provide display-origin, scrolling, and layout controls that go beyond a simple passive framebuffer.

**Similarity:** High in general architecture, though the PC-9801 graphics system evolved much further.

---

## 9.4 Sharp X1

The Sharp X1 also belongs to the Japanese digital-RGB generation. Its early models supported 640 × 200 graphics and an eight-color RGB display system, with video memory made directly available to software on configurations equipped with graphics VRAM.

The X1 is notable for tightly integrating computer graphics with television and video features. Although its software-visible details differ from the QX-11, its use of digital RGB and an eight-color primary-combination palette reflects the same design environment.

**Similarity:** Moderate to high at the output and palette level; memory-control details differ.

---

## 9.5 IBM Color Graphics Adapter

IBM CGA also outputs digital red, green, and blue, but adds an **intensity** signal:

```text
R + G + B + I
```

That gives a nominal 16-color RGBI palette.

However, standard CGA graphics memory is not organized as three independent full-screen color planes:

- 320 × 200 graphics normally stores packed two-bit pixels and displays four colors from restricted palettes.
- 640 × 200 graphics stores one bit per pixel and is normally two-color.
- Sixteen-color graphics is not available as a normal 320 × 200 packed bitmap mode.

Therefore, even though both interfaces use digital RGB concepts, CGA software cannot be adapted to the QX-11 merely by changing a segment address.

| Feature | QX-11 | IBM CGA |
|---|---|---|
| Primary graphics model | Three one-bit planes | Packed 2-bpp or monochrome |
| Normal simultaneous graphics colors | 8 | 4 at 320 × 200; 2 at 640 × 200 |
| RGB intensity line | No confirmed intensity channel | Yes |
| Typical graphics VRAM | Approximately 48 KiB for three-plane screen | 16 KiB |
| Native memory layout | QX-specific column-major | Interleaved scan-line layout |
| Direct software compatibility | None | IBM PC standard |

**Similarity:** Low at the framebuffer level, despite both using digital RGB output.

---

## 9.6 MSX1

MSX1 systems generally use the Texas Instruments TMS9918-family video display processor.

The MSX1 approach is fundamentally different:

- Video memory is accessed through VDP I/O ports rather than as three CPU-visible RGB planes.
- Graphics are largely pattern/tile based.
- Color values are indices into a fixed VDP palette.
- In the common high-resolution pattern mode, each eight-pixel line segment normally has foreground and background color attributes rather than an independent three-bit color value for every pixel.

The VDP internally generates RGB or composite video, but software does not normally manipulate red, green, and blue plane masks.

**Similarity:** Low. Both can display multiple colors, but the memory model and rendering process are very different.

---

## 10. Summary Table

| System | Era | Typical eight-color method | Memory representation | QX-11 similarity |
|---|---:|---|---|---|
| Epson QX-11 | Early 1980s | Three digital RGB primaries | Three one-bit planes; QX-specific mapping | — |
| Fujitsu FM-7 | 1982 | Three digital RGB primaries | Three one-bit planes, 48 KiB VRAM | Very high |
| NEC PC-8801 | 1981 onward | Three digital RGB primaries | Planar graphics in original color modes | High |
| NEC PC-9801 | 1982 onward | Planar digital color | Multiple graphics planes; later accelerators | High |
| Sharp X1 | 1982 onward | Digital RGB combinations | Dedicated graphics VRAM, model-dependent | Moderate/high |
| IBM CGA | 1981 | RGB plus intensity | Packed or monochrome graphics | Low |
| MSX1 | 1983 onward | Indexed VDP palette | Pattern, color, and name tables | Low |

---

## 11. Implications for QX-11 Software Ports

### CGA ports

A CGA image must be decoded from packed two-bit pixels or monochrome data and separated into QX red, green, and blue masks.

CGA palette colors must also be mapped to the QX-11’s eight non-intensity colors.

### Hercules ports

Hercules is monochrome. The same one-bit source image can be copied into:

- one QX plane for a pure primary color,
- two planes for cyan, magenta, or yellow,
- all three planes for white.

The remaining difficulty is transforming the Hercules framebuffer’s row/interleave organization into the QX-11’s column-major organization.

### Native QX-11 software

Native drawing code should ideally:

1. Calculate the QX-specific byte offset and bit mask.
2. Group drawing operations by plane.
3. Avoid repeatedly switching planes for individual pixels.
4. Convert images into planar form ahead of time.
5. Use byte-wide masks and logical operations whenever possible.

---

## 12. Open Questions

The following details still require hardware tracing or controlled experiments:

- Exact electrical voltage levels of red, green, and blue.
- Output impedance of each color channel.
- Whether the external RGB signals are strict TTL levels or resistor-shaped levels intended for the Epson monitor.
- Complete role of the GAIBVD output circuitry.
- Exact function of connector pin 9.
- Whether any undocumented mode provides intensity or palette control.
- Complete relationship between the `8000h`, `8008h`, and `9000h` CPU-visible selections and the six physical VRAM DRAM devices.
- Whether color-plane writes can be enabled simultaneously for accelerated fills.
- Whether GAVDP logical-operation hardware exists but has not yet been identified.

---

## 13. Suggested Hardware Tests

1. Display solid black, blue, red, green, cyan, magenta, yellow, and white screens.
2. Measure each RGB output relative to ground for all eight combinations.
3. Compare unloaded voltage with the voltage connected to the original monitor.
4. Trace each channel from the connector back through resistors, transistors, and GAIBVD pins.
5. Capture RGB timing relative to the approximately 14.318 MHz connector clock.
6. Verify whether color edges change only on one phase or division of that clock.
7. Test writes to identical offsets in `8000h`, `8008h`, and `9000h`.
8. Photograph each single-plane and combined-plane test for the repository.

---

## 14. References

### QX-11 primary research

- Real-hardware measurements, connector tracing, BIOS analysis, VRAM tests, and driver-porting experiments from the Epson QX-11 reverse-engineering project:
  - <https://github.com/pradavic-1972/epson-qx11-research>

### Contemporary-system references

- NEC PC-8801FA/MA Programmer’s Guide, screen modes and graphics organization:  
  <https://andresdepedro.com/retro/pc88/PC-8801FA_MA_programmersguide.pdf>

- Fujitsu FM-7 technical-document index and hardware notes, including 48 KiB video RAM and 640 × 200 graphics:  
  <https://github.com/0cjs/sedoc/blob/main/8bit/fm7/fm-7.md>

- Fujitsu FM-7 programming notes showing separate blue and red VRAM regions and planar graphics access:  
  <https://www.chibiakumas.com/6809/fm7.php>

- NEC PC-9801 memory-map notes identifying graphics planes:  
  <https://radioc.web.fc2.com/column/pc98bas/pc98memmap_en.htm>

- MSX2 Technical Handbook, VDP screen modes, color tables, packed-pixel modes, palettes, and scrolling:  
  <https://konamiman.github.io/MSX2-Technical-Handbook/md/Chapter4a.html>

- IBM CGA overview and references to the IBM CGA technical documentation:  
  <https://en.wikipedia.org/wiki/Color_Graphics_Adapter>

---

## 15. Current Working Model

The current best model of QX-11 color rendering is:

```text
                    ┌─────────────────┐
Blue VRAM bit ─────►│                 │────► Blue output
Red VRAM bit  ─────►│ GAVDP / ICRT    │────► Red output
Green VRAM bit ────►│ video pipeline  │────► Green output
                    │                 │────► HSync
Display timing ────►│                 │────► VSync
                    └─────────────────┘
```

For every pixel position, the three plane bits are presented simultaneously. The resulting combination directly selects one of eight additive RGB colors.

This makes the QX-11 a member of the early-1980s **three-plane digital RGB** family, much closer in concept to the Fujitsu FM-7 and early NEC Japanese computers than to IBM CGA or MSX video hardware.
