# Epson QX‑11 ("Abacus" / QC‑11) — MAME Driver README

> Initial public draft: **2025‑09‑28**

This document explains the background, architecture, status, and developer notes for the **qx11.cpp** MAME driver. It captures the reverse‑engineering work we’ve done so far to emulate the Epson **QX‑11** (aka *Abacus* in Venezuela; *QC‑11* in Japan), an 8088‑based MS‑DOS 2.11 machine with several Epson‑specific gate arrays.

---

## Quick links

- **Driver file**: `src/mame/epson/qx11.cpp`
- **Machine shortname** (proposed): `qx11`
- **ROMs**: Epson MS‑DOS 2.11 system ROM (M25140CA / M25141CA), plus character ROM
- **Target CPU**: Intel 8088

> Tip: run with `-debug` while iterating:  
> `mame qx11 -debug -log -window -nomax -skip_gameinfo`

---

## Hardware background (what we know)

- **CPU**: 8088
- **System ROM**: MS‑DOS 2.11 in ROM; Epson part numbers **M25140CA** / **M25141CA** (27256 DIP images).  
- **Gate Arrays**: Multiple custom Epson chips (e.g., floppy, video/console, I/O). These mediate access to RTC, CRTC, serial, and other subsystems via paging/command windows.
- **Floppy**: uPD765‑compatible FDC; TEAC SMD‑125 3.5" drives (Epson formats 360 KB). Bus rate **250 kbps**.
- **Video**: Native graphics on motherboard, likely NEC µPD7220–family–like behavior for hi‑res modes. Confirmed game(s) used **640×400** and **320×200** modes. VRAM observed: **48 KB** (0x8000–0x9FFF), with text framebuffer use around **0x9000**.
- **Sound**: TI **SN76489AN** PSG exposed at a single I/O port.
- **RTC**: Hitachi **HD146818P** physically present; access proxied by gate array.
- **I/O**: Two joystick ports, audio out with volume knob, ROM cartridge slot.

---

## Emulation architecture

### Gate‑array command/status handshake
- **Ports 0x000C / 0x000D** act as **GA_CMD / GA_STATUS**.  
  - **0x0C**: write page/command; **0x0C** read: response byte.  
  - **0x0D**: status bits: `bit0=Input‑ready`, `bit1=Output‑ready`.  
  - BIOS handshake pattern: wait for 0x0D.bit0 → `OUT 0x0C,<page>` → poll 0x0D.bit1 (with timeout) → optionally `IN 0x0C` to consume response.
- **Known GA “pages”** (selector values written to 0x0C):
  - **0x80**: *Console/CRTC window*. Maps ports **0x04=index**, **0x05=data** for GA/CRTC regs. BIOS routine also touches BDA keyboard flags.

> Note: The **RTC (HD146818P)** is **not** paged via the GA; its ports **0x10 (index)** and **0x11 (data)** are dedicated and always active.

### Floppy subsystem (uPD765)
- **I/O map**:
  - **0x12 = MSR** (Main Status Register)  
  - **0x13 = DATA FIFO** (read/write)  
  - **0x0F = DOR‑like** (drive/motor/control).  
    - **A:** select → `OUT 0x0F, 0x04`; **B:** select → `OUT 0x0F, 0x08`; both followed by `OUT 0x0F, 0x00`.
- **Drive‑present probe via 0x0E**: During floppy reads the BIOS **polls port 0x0E**. When the selected drive is **A:** it expects **0x01**; for **B:** it expects **0x02**. This appears to be a **disk‑inserted / drive‑ready indicator** exposed by the GA.
- **Bus rate**: 250 kbps.  
- **Observed command sequences** (from BIOS during boot/read):
  - `SPECIFY 03 DF 03`
  - `SENSE DRIVE STATUS (SDS) 04 00 → ST3 = 38h` (ready, track0, double‑sided)
  - `RECALIBRATE 07 00` then `SENSE INTERRUPT STATUS 08 → 20h 00h` (seek end, PCN=0)
- **Data‑phase termination**: When BIOS signals the end of the requested byte count, it writes **0x10 to port 0x0F**. In the driver we route this to the FDC’s **`tc_line_w(1)`** (Terminal Count) to advance to the **result phase**. This change fixed the hanging/timeout and allowed successful reads, directory listings, and program loads.
- **Vendor path on 0x12/0x13**: We have proven that ports **0x12 (MSR)** and **0x13 (DATA)** are **dedicated to the uPD765**. There is **no GA muxing** of these ports away from the 765 in the QX‑11. Earlier traces showing ASCII-like values (e.g., `"EPSON"`) were due to **disk content** during normal reads, not gate‑array redirection.

### Video subsystem
- **Native mode VRAM layout**: In native QX‑11 mode the machine **writes graphics to 0x8000–0x8FFF** and **renders text from buffers at 0x9000–0x9FFF** (total VRAM ≈48 KB). We’ve consistently observed screen changes tied to writes in these regions during boots, DIR output, and test programs.
- Text currently appears in the upper portion of the screen; scrolling is still imperfect.
- Known issue: after extensive text scrolling, a **CLS** may blank the screen; repeated CR/LF can make the prompt reappear. This suggests we need to refine the **text framebuffer blit/scroll path** and GA/CRTC registers for start address/row compare.

#### How we deduced text & graphics rendering
1. **Targeted VRAM pokes**: Using the MAME debugger and MS‑DOS `DEBUG`, we wrote repeating patterns into **0x8000–0x9FFF** and mapped which regions caused **pixel‑level (graphics)** vs **character‑cell (text)** changes.  
2. **Character write sweep**: We wrote ASCII codes (e.g., `0x41 'A'`) sequentially into the **0x9000** area and measured on‑screen spacing to infer **per‑character stride** and row/column mapping.  
3. **Glyph cross‑check**: We dumped the QX‑11 **character ROM** and verified that the bitmaps consumed by the text renderer matched the glyphs we saw on screen.  
4. **Mode sanity checks**: Test apps toggling between **640×400** and **320×200** showed that 0x8000 activity affects pixel graphics in both modes, while 0x9000 activity affects the text layer.

---

## I/O port map (current working set)

| Port | Role | Notes |
|---:|---|---|
| 0x04 | GA/CRTC index | Selected when GA page 0x80 active. Also touched by serial setup sequence. |
| 0x05 | GA/CRTC data | — |
| 0x07 | Serial config (via GA) | Baud/parity/data/stop encoded in one byte. |
| 0x08 | GA sub‑selector | Used by serial setup (0x08→0x0B wrap). |
| 0x0C | **GA_CMD** | Write page/command; read response. |
| 0x0D | **GA_STATUS** | bit0=IN ready; bit1=OUT ready. |
| 0x0E | GA status (secondary) / **Disk‑present flags** | BIOS polls during floppy reads: expects **0x01** for A:, **0x02** for B:. Also seen as 0xFF during POST. |
| 0x0F | **DOR‑like / control** | Drive select (A=0x04, B=0x08); **0x10** used as TC signal to FDC. |
| 0x10 | **RTC index** | Dedicated RTC port (no GA page). |
| 0x11 | **RTC data** | — |
| 0x12 | **FDC MSR** | Main Status Register. |
| 0x13 | **FDC DATA** | FIFO (read/write). |
| 0x14 | **SN76489AN** | PSG data/latch. |

> Note: Ports 0x12/0x13 are dedicated to the uPD765 (no GA mux).

---

## Build & run

1. Place ROMs (system + charset) in the QX‑11 set directory:
   - `M25140CA` / `M25141CA` 27256 images (e.g., `MBM27256@DIP28_EPSON_ABACUS_M25140CA.BIN`).
2. Build MAME as usual. Ensure the driver is compiled (`qx11.cpp` added to `src/mame/epson/`).
3. Launch:
   ```bash
   mame qx11 -debug -log -window -nomax -skip_gameinfo \
     -flop1 path/to/disk.img
   ```

### Debugging tips
- Break on port access (example, FDC):
  - `bp iowrite,12,1` / `bp ioread,12,1` (MSR)
  - `bp iowrite,13,1` / `bp ioread,13,1` (DATA)
  - `bp iowrite,0f,1` (DOR‑like/TC)
- Log the **result phase** bytes after READ/FORMAT to diagnose ST0/ST1/ST2.
- If data phase stalls, verify that the write of **0x10 to 0x0F** calls `tc_line_w(1)` and returns to `0` afterwards.

---

## Current status

✅ **Boots to DOS** from ROM; directory listings and program loads working after **TC line** hookup.

⚠️ **Text scrolling bug**: long scrolls may blank the screen; CLS may black out until further CR/LF. Needs CRTC/GA start‑addr handling and VRAM copy refinement.

⚠️ **FDC GA‑mux**: Ports 0x12/0x13 may sometimes be diverted by GA. We currently tie them directly to the uPD765; need a selectable mux that can surface vendor signatures and/or GA behaviors when enabled.

⚠️ **Interrupt routing**: INTRQ observed; precise GA‑mediated IRQ line and masking not fully documented.


---

## Recent breakthroughs (highlights)

- **Terminal Count (TC) hookup** on `0x0F ← 0x10` write: unblocks READ, enabling `DIR` and program execution from floppy.
- **Result‑phase parsing** verified: ST3 `0x38` from SDS indicates drive ready/track0/double‑sided as expected.
- **Serial config path** reproduced from SETUP.EXE: pure write‑only sequence across 0x08/0x07/0x08/0x04/0x05.
- **RTC ports dedicated**: 0x10/0x11 are exclusive to the HD146818P; no GA paging required (ensure BCD/24h handling).

---

## To‑do / roadmap

- **CRTC/GA**: Implement correct scroll/start‑address and row compare to fix text scrolling & CLS.
- **FDC**: Add GA mux behavior for ports 0x12/0x13; model non‑DMA transfer timing more faithfully; verify INTRQ/DRQ behavior under heavy I/O.
- **IRQ plumbing**: Document and emulate how GA routes 765 interrupts to the CPU.
- **Keyboard**: Improve scancode/ASCII path and input callbacks; audit input ports.
- **Sound**: Confirm SN76489AN clock and verify tone frequencies match BIOS INT 15h beeps.
- **Cartridge/ROM slot**: Model if needed for kanji/extra ROM.

---

## Developer reference (notes we’ve captured)

- **BIOS I/O sequences** we’ve observed (POST & disk): SPECIFY, SDS, RECAL, SIS; no `READ DATA (06h)` in some early captures; later traces confirm full data/result phases once TC is asserted.
- **Drive select** writes: A: `0x04`, B: `0x08` to 0x0F, then `0x00`.
- **Text framebuffer**: Writes around 0x9000; character glyphs fetched from the QX‑11 ROM; total VRAM 48 KB (0x8000–0x9FFF). Earlier write‑ups include per‑character stride/spacing experiments.
- **Serial**: GA‑mediated; pure write configuration path via 0x08/0x07/0x08/0x04/0x05.
- **RTC**: HD146818P on ports 0x10/0x11 (dedicated); keep BCD and DOW in range 1–7.
- **Vendor signature**: Occasional ASCII‑like bytes were traced to image content on disk track 0; ports 0x12/0x13 remain dedicated to the 765.

- **0x0E read behavior**: During a disk read attempt, BIOS reads **0x0E** and expects **0x01** when A: is selected, **0x02** when B: is selected — likely a GA‑exposed **media‑present** indication.

---

## Contributing & testing

- Please keep logs focused: share the **latest** capture only when requesting analysis.
- When reporting floppy issues, include:  
  MSR samples (0x12), FIFO bytes (0x13), any 0x0F writes (esp. 0x10), and GA activity (0x04/0x0C/0x0D/0x0E).
- For video, note when the screen blanks (after which command), and whether multiple CR/LF restore the prompt.

---

## License

Unless otherwise noted, this driver and documentation are released under the **MIT License**.

---

## Acknowledgements

- Reverse‑engineering, testing, and logs by the project author and community collaborators.  
- MAME team & documentation for the uPD765 and device frameworks.
- **AI‑assisted development**: A significant portion of research synthesis, draft code, and documentation was produced with AI assistance. This **accelerated development** and helped iterate quickly on hypotheses, device hookups (e.g., TC on 0x0F→`tc_line_w`), and documentation. All code was reviewed and tested by the project author before inclusion.

---

*If you’re reading this in the Git repository, this README belongs in the `src/mame/epson/` folder alongside `qx11.cpp`. Feel free to open issues/PRs with traces, photos, or ROM details to help nail the remaining unknowns.*

