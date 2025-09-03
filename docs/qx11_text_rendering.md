# Epson QX‑11 — Text Rendering in VRAM @ 0x9000

> How the BIOS draws 80×25 text using an 8×8 font on the 48 KiB VRAM window.

## TL;DR
- Text is drawn into the 48 KiB VRAM window starting at segment **0x9000**.
- The BIOS sets **ES = 0x9010** and draws the page starting at **ES:0x0100**.
- One character = **8×8** pixels at **1 bpp**, fetched from a ROM font (**8 bytes per glyph**).
- Address for byte of scanline *i* of char at column *x*, row *y*:

```
addr = base + y*640 + i*80 + x
(base = ES:0x0100 with ES=0x9010)
```

- Strides:
  - Next character (same row): **+1** byte
  - Next glyph scanline: **+80** bytes
  - Same column, next text row: **+640** bytes
- Full screen (80×25): **2,000 chars × 8 B = 16,000 B (0x3E80)** of pixel data.

---

## VRAM layout (48 KiB at 0x9000)
```
Segment 0x9000:  0x0000–0x3FFF  (Bank A, 16 KiB)
                  0x4000–0x7FFF  (Bank B, 16 KiB)
                  0x8000–0xBFFF  (Bank C, 16 KiB)

Text page uses Bank A like this:
  0x0000–0x00FF  : small header/work area
  0x0100–0x3F7F  : 640×200 bitmap for 80×25 text (8×8 font)
  0x3F80–0x3FFF  : slack
```
- Bank B and Bank C are available for paging/graphics (e.g., 640×400@1bpp = 32 KiB across both banks, or a second 640×200 page for double‑buffering).

---

## Character metrics & glyph source
- **Cell size:** 8×8 pixels, **1 bit per pixel** (bit7 = leftmost pixel).
- **Glyph bytes:** 8 bytes per character code. For character `ch`, the byte for scanline `i` lives at:

```
font_addr = font_base + ch*8 + i   (i = 0..7)
```

The BIOS copies each of these 8 bytes into the VRAM page using the addressing formula below.

---

## Addressing & spacing (the important part)
Let `(x, y)` be the character column and row (0‑based), and `i` be the scanline within the 8‑pixel glyph (`0..7`).

- **Base for the text page:** `ES=0x9010`, `offset=0x0100`.
- **Byte address for scanline `i` of char `(x,y)`:**

```
addr = base + y*640 + i*80 + x
```

### Practical distances
- Next character in same row → `+1` byte
- Next scanline of same glyph → `+80` bytes
- Same column, next character row → `+640` bytes

This layout interleaves the whole row **per scanline** (80 bytes per scanline × 8 scanlines = 640 bytes per text row).

---

## Worked example
**Write ASCII 'A' at (x=10, y=5):**

- Row start from base = `y*640 + x = 5*640 + 10 = 3210`
- For `i = 0..7`, write glyph byte `g[i]` to: `base + 3210 + i*80`

---

## Minimal pseudo‑code
```c
// ES already set to 0x9010; base = 0x0100
void putchar_xy(uint8_t ch, uint8_t x, uint8_t y) {
    const uint16_t base = 0x0100;            // ES:base is framebuffer
    const uint16_t row_stride = 640;         // bytes per character row (80*8)
    const uint8_t  scan_stride = 80;         // bytes per scanline

    const uint8_t* glyph = rom_font + ch*8;  // 8 bytes, bit7 = leftmost pixel

    uint16_t off = base + y*row_stride + x;  // start at scanline 0
    for (uint8_t i = 0; i < 8; i++) {
        *(uint8_t far*)(off + i*scan_stride) = glyph[i];
    }
}
```

### 8086‑style sketch
```asm
; ES = 9010h, DI = 0100h at page base
; Inputs: AL = ch, DL = x, DH = y
putchar_xy:
    push bx
    push cx
    push si

    ; off = base + y*640 + x
    mov  bx, dx          ; BH=y, BL=x
    mov  si, 640         ; row stride
    mov  ch, 0           ; clear high for MUL
    mov  cl, bh          ; y
    mov  ax, si
    mul  cx              ; AX = y*640
    add  ax, 0100h       ; base
    add  ax, bx          ; + x
    mov  di, ax          ; DI = start offset for i=0

    ; SI points to glyph[0] = font_base + ch*8
    mov  si, font_base
    movzx bx, al         ; BX = ch
    shl  bx, 3           ; *8
    add  si, bx

    mov  cx, 8           ; 8 scanlines
.put_loop:
    mov  al, [si]        ; glyph[i]
    stosb                ; write byte to ES:DI
    add  di, 80-1        ; advance to next scanline (we already advanced +1)
    inc  si
    loop .put_loop

    pop si
    pop cx
    pop bx
    ret
```

---

## Troubleshooting / gotchas
- **“Every other row is missing”**: using `+160` between scanlines will skip alternate rows. The correct scanline stride is **+80**.
- Make sure **ES is 0x9010** and you start at **offset 0x0100**; the first 256 bytes are a small work/header area.

---

## How much memory does the page consume?
- Full 80×25 page: `2,000 chars × 8 B = 16,000 B (0x3E80)` of bitmap data.
- Including the 0x0100 header area, the Bank‑A footprint is ~**0x3F80 (16,256 B)**.

---


## Visual: glyph → VRAM mapping (inline SVG)

<!-- The SVG below is embedded directly so it renders on GitHub Pages and Markdown viewers that allow inline SVG. -->
<div style="max-width: 960px; overflow-x: auto;">
<svg xmlns="http://www.w3.org/2000/svg" width="732" height="352" viewBox="0 0 732 352"><text x="20" y="24" font-family="monospace" font-size="16" text-anchor="start" font-weight="bold">QX-11 8×8 glyph → VRAM mapping (text page @ ES=0x9010, off=0x0100)</text><text x="20" y="44" font-family="monospace" font-size="14" text-anchor="start" font-weight="normal">addr = base + y*640 + i*80 + x   (x=col, y=row, i=scanline 0..7)</text><text x="172.0" y="52" font-family="monospace" font-size="12" text-anchor="middle" font-weight="normal">b7</text><text x="196.0" y="52" font-family="monospace" font-size="12" text-anchor="middle" font-weight="normal">b6</text><text x="220.0" y="52" font-family="monospace" font-size="12" text-anchor="middle" font-weight="normal">b5</text><text x="244.0" y="52" font-family="monospace" font-size="12" text-anchor="middle" font-weight="normal">b4</text><text x="268.0" y="52" font-family="monospace" font-size="12" text-anchor="middle" font-weight="normal">b3</text><text x="292.0" y="52" font-family="monospace" font-size="12" text-anchor="middle" font-weight="normal">b2</text><text x="316.0" y="52" font-family="monospace" font-size="12" text-anchor="middle" font-weight="normal">b1</text><text x="340.0" y="52" font-family="monospace" font-size="12" text-anchor="middle" font-weight="normal">b0</text><text x="150" y="76.08" font-family="monospace" font-size="12" text-anchor="end" font-weight="normal">i=0</text><rect x="160" y="60" width="24" height="24" stroke="black" stroke-width="1" fill="white"/><rect x="184" y="60" width="24" height="24" stroke="black" stroke-width="1" fill="white"/><rect x="208" y="60" width="24" height="24" stroke="black" stroke-width="1" fill="white"/><rect x="232" y="60" width="24" height="24" stroke="black" stroke-width="1" fill="black"/><rect x="256" y="60" width="24" height="24" stroke="black" stroke-width="1" fill="black"/><rect x="280" y="60" width="24" height="24" stroke="black" stroke-width="1" fill="white"/><rect x="304" y="60" width="24" height="24" stroke="black" stroke-width="1" fill="white"/><rect x="328" y="60" width="24" height="24" stroke="black" stroke-width="1" fill="white"/><text x="150" y="100.08" font-family="monospace" font-size="12" text-anchor="end" font-weight="normal">i=1</text><rect x="160" y="84" width="24" height="24" stroke="black" stroke-width="1" fill="white"/><rect x="184" y="84" width="24" height="24" stroke="black" stroke-width="1" fill="white"/><rect x="208" y="84" width="24" height="24" stroke="black" stroke-width="1" fill="black"/><rect x="232" y="84" width="24" height="24" stroke="black" stroke-width="1" fill="white"/><rect x="256" y="84" width="24" height="24" stroke="black" stroke-width="1" fill="white"/><rect x="280" y="84" width="24" height="24" stroke="black" stroke-width="1" fill="black"/><rect x="304" y="84" width="24" height="24" stroke="black" stroke-width="1" fill="white"/><rect x="328" y="84" width="24" height="24" stroke="black" stroke-width="1" fill="white"/><text x="150" y="124.08" font-family="monospace" font-size="12" text-anchor="end" font-weight="normal">i=2</text><rect x="160" y="108" width="24" height="24" stroke="black" stroke-width="1" fill="white"/><rect x="184" y="108" width="24" height="24" stroke="black" stroke-width="1" fill="black"/><rect x="208" y="108" width="24" height="24" stroke="black" stroke-width="1" fill="white"/><rect x="232" y="108" width="24" height="24" stroke="black" stroke-width="1" fill="white"/><rect x="256" y="108" width="24" height="24" stroke="black" stroke-width="1" fill="white"/><rect x="280" y="108" width="24" height="24" stroke="black" stroke-width="1" fill="white"/><rect x="304" y="108" width="24" height="24" stroke="black" stroke-width="1" fill="black"/><rect x="328" y="108" width="24" height="24" stroke="black" stroke-width="1" fill="white"/><text x="150" y="148.08" font-family="monospace" font-size="12" text-anchor="end" font-weight="normal">i=3</text><rect x="160" y="132" width="24" height="24" stroke="black" stroke-width="1" fill="white"/><rect x="184" y="132" width="24" height="24" stroke="black" stroke-width="1" fill="black"/><rect x="208" y="132" width="24" height="24" stroke="black" stroke-width="1" fill="white"/><rect x="232" y="132" width="24" height="24" stroke="black" stroke-width="1" fill="white"/><rect x="256" y="132" width="24" height="24" stroke="black" stroke-width="1" fill="white"/><rect x="280" y="132" width="24" height="24" stroke="black" stroke-width="1" fill="white"/><rect x="304" y="132" width="24" height="24" stroke="black" stroke-width="1" fill="black"/><rect x="328" y="132" width="24" height="24" stroke="black" stroke-width="1" fill="white"/><text x="150" y="172.08" font-family="monospace" font-size="12" text-anchor="end" font-weight="normal">i=4</text><rect x="160" y="156" width="24" height="24" stroke="black" stroke-width="1" fill="white"/><rect x="184" y="156" width="24" height="24" stroke="black" stroke-width="1" fill="black"/><rect x="208" y="156" width="24" height="24" stroke="black" stroke-width="1" fill="black"/><rect x="232" y="156" width="24" height="24" stroke="black" stroke-width="1" fill="black"/><rect x="256" y="156" width="24" height="24" stroke="black" stroke-width="1" fill="black"/><rect x="280" y="156" width="24" height="24" stroke="black" stroke-width="1" fill="black"/><rect x="304" y="156" width="24" height="24" stroke="black" stroke-width="1" fill="black"/><rect x="328" y="156" width="24" height="24" stroke="black" stroke-width="1" fill="white"/><text x="150" y="196.08" font-family="monospace" font-size="12" text-anchor="end" font-weight="normal">i=5</text><rect x="160" y="180" width="24" height="24" stroke="black" stroke-width="1" fill="white"/><rect x="184" y="180" width="24" height="24" stroke="black" stroke-width="1" fill="black"/><rect x="208" y="180" width="24" height="24" stroke="black" stroke-width="1" fill="white"/><rect x="232" y="180" width="24" height="24" stroke="black" stroke-width="1" fill="white"/><rect x="256" y="180" width="24" height="24" stroke="black" stroke-width="1" fill="white"/><rect x="280" y="180" width="24" height="24" stroke="black" stroke-width="1" fill="white"/><rect x="304" y="180" width="24" height="24" stroke="black" stroke-width="1" fill="black"/><rect x="328" y="180" width="24" height="24" stroke="black" stroke-width="1" fill="white"/><text x="150" y="220.08" font-family="monospace" font-size="12" text-anchor="end" font-weight="normal">i=6</text><rect x="160" y="204" width="24" height="24" stroke="black" stroke-width="1" fill="white"/><rect x="184" y="204" width="24" height="24" stroke="black" stroke-width="1" fill="black"/><rect x="208" y="204" width="24" height="24" stroke="black" stroke-width="1" fill="white"/><rect x="232" y="204" width="24" height="24" stroke="black" stroke-width="1" fill="white"/><rect x="256" y="204" width="24" height="24" stroke="black" stroke-width="1" fill="white"/><rect x="280" y="204" width="24" height="24" stroke="black" stroke-width="1" fill="white"/><rect x="304" y="204" width="24" height="24" stroke="black" stroke-width="1" fill="black"/><rect x="328" y="204" width="24" height="24" stroke="black" stroke-width="1" fill="white"/><text x="150" y="244.08" font-family="monospace" font-size="12" text-anchor="end" font-weight="normal">i=7</text><rect x="160" y="228" width="24" height="24" stroke="black" stroke-width="1" fill="white"/><rect x="184" y="228" width="24" height="24" stroke="black" stroke-width="1" fill="black"/><rect x="208" y="228" width="24" height="24" stroke="black" stroke-width="1" fill="white"/><rect x="232" y="228" width="24" height="24" stroke="black" stroke-width="1" fill="white"/><rect x="256" y="228" width="24" height="24" stroke="black" stroke-width="1" fill="white"/><rect x="280" y="228" width="24" height="24" stroke="black" stroke-width="1" fill="white"/><rect x="304" y="228" width="24" height="24" stroke="black" stroke-width="1" fill="black"/><rect x="328" y="228" width="24" height="24" stroke="black" stroke-width="1" fill="white"/><rect x="392" y="60" width="48" height="192" stroke="black" stroke-width="1" fill="white"/><text x="416.0" y="48" font-family="monospace" font-size="12" text-anchor="middle" font-weight="normal">VRAM bytes</text><rect x="392" y="60" width="48" height="24" stroke="black" stroke-width="1" fill="white"/><text x="416.0" y="75.6" font-family="monospace" font-size="11" text-anchor="middle" font-weight="normal">+ i*80  (i=0)</text><line x1="352" y1="72.0" x2="392" y2="72.0" stroke="black" stroke-width="1" marker-end="url(#arrow)"/><rect x="392" y="84" width="48" height="24" stroke="black" stroke-width="1" fill="white"/><text x="416.0" y="99.6" font-family="monospace" font-size="11" text-anchor="middle" font-weight="normal">+ i*80  (i=1)</text><line x1="352" y1="96.0" x2="392" y2="96.0" stroke="black" stroke-width="1" marker-end="url(#arrow)"/><rect x="392" y="108" width="48" height="24" stroke="black" stroke-width="1" fill="white"/><text x="416.0" y="123.6" font-family="monospace" font-size="11" text-anchor="middle" font-weight="normal">+ i*80  (i=2)</text><line x1="352" y1="120.0" x2="392" y2="120.0" stroke="black" stroke-width="1" marker-end="url(#arrow)"/><rect x="392" y="132" width="48" height="24" stroke="black" stroke-width="1" fill="white"/><text x="416.0" y="147.6" font-family="monospace" font-size="11" text-anchor="middle" font-weight="normal">+ i*80  (i=3)</text><line x1="352" y1="144.0" x2="392" y2="144.0" stroke="black" stroke-width="1" marker-end="url(#arrow)"/><rect x="392" y="156" width="48" height="24" stroke="black" stroke-width="1" fill="white"/><text x="416.0" y="171.6" font-family="monospace" font-size="11" text-anchor="middle" font-weight="normal">+ i*80  (i=4)</text><line x1="352" y1="168.0" x2="392" y2="168.0" stroke="black" stroke-width="1" marker-end="url(#arrow)"/><rect x="392" y="180" width="48" height="24" stroke="black" stroke-width="1" fill="white"/><text x="416.0" y="195.6" font-family="monospace" font-size="11" text-anchor="middle" font-weight="normal">+ i*80  (i=5)</text><line x1="352" y1="192.0" x2="392" y2="192.0" stroke="black" stroke-width="1" marker-end="url(#arrow)"/><rect x="392" y="204" width="48" height="24" stroke="black" stroke-width="1" fill="white"/><text x="416.0" y="219.6" font-family="monospace" font-size="11" text-anchor="middle" font-weight="normal">+ i*80  (i=6)</text><line x1="352" y1="216.0" x2="392" y2="216.0" stroke="black" stroke-width="1" marker-end="url(#arrow)"/><rect x="392" y="228" width="48" height="24" stroke="black" stroke-width="1" fill="white"/><text x="416.0" y="243.6" font-family="monospace" font-size="11" text-anchor="middle" font-weight="normal">+ i*80  (i=7)</text><line x1="352" y1="240.0" x2="392" y2="240.0" stroke="black" stroke-width="1" marker-end="url(#arrow)"/>
<defs>
  <marker id="arrow" markerWidth="6" markerHeight="6" refX="5" refY="3" orient="auto">
    <path d="M0,0 L6,3 L0,6 Z" fill="black" />
  </marker>
</defs>
<text x="460" y="64" font-family="monospace" font-size="13" text-anchor="start" font-weight="normal">Strides:</text><text x="460" y="82" font-family="monospace" font-size="13" text-anchor="start" font-weight="normal">• next char in row        → +1 byte</text><text x="460" y="100" font-family="monospace" font-size="13" text-anchor="start" font-weight="normal">• next glyph scanline     → +80 bytes</text><text x="460" y="118" font-family="monospace" font-size="13" text-anchor="start" font-weight="normal">• next text row (y+1)     → +640 bytes</text><text x="460" y="136" font-family="monospace" font-size="13" text-anchor="start" font-weight="normal"></text><text x="460" y="154" font-family="monospace" font-size="13" text-anchor="start" font-weight="normal">Full page (80×25 chars):</text><text x="460" y="172" font-family="monospace" font-size="13" text-anchor="start" font-weight="normal">  2,000 chars × 8 B = 16,000 B (0x3E80)</text><text x="460" y="190" font-family="monospace" font-size="13" text-anchor="start" font-weight="normal"></text><text x="460" y="208" font-family="monospace" font-size="13" text-anchor="start" font-weight="normal">Example shown: glyph 'A' (illustrative)</text><text x="20" y="282" font-family="monospace" font-size="13" text-anchor="start" font-weight="normal">Base for text page:  ES=0x9010, offset=0x0100 (physical ≈ 0x90100)</text><text x="20" y="300" font-family="monospace" font-size="13" text-anchor="start" font-weight="normal">Byte for char (x,y), scanline i:  base + y*640 + i*80 + x</text><text x="20" y="318" font-family="monospace" font-size="13" text-anchor="start" font-weight="normal">Glyph bytes from ROM font:  addr = font_base + ch*8 + i  (i=0..7)</text></svg>
</div>


## Notes on the extra VRAM (the other 32 KiB)
- Bank B and Bank C (two × 16 KiB) can hold:
  - one **640×400@1bpp** page across both banks (32 KiB), or
  - additional **640×200** pages for paging/double‑buffering, or
  - multiple lower‑res pages (e.g., 320×200@1bpp is 8 KiB).

---

## License
You can include this page under **CC BY‑SA 4.0** or **MIT**; pick whichever matches the rest of the repo.
