# Reverse Engineering (QX-11)

This folder collects notes, code snippets, and findings from our ongoing **reverse-engineering of the QX-11/QC-11 BIOS and native software**. The immediate focus is the **INT 10h video BIOS**: how it initializes modes, manages the QX-11’s **tri-plane text system**, and exposes OEM functions (AH=40h–4Fh) used by bundled applications.

> TL;DR: We’re figuring out how the QX-11 works by reading the ROM, tracing the dispatcher, and validating behavior with small test programs and emulator memory dumps.

---

## What’s here

- **BIOS INT 10h documentation**  
  A full walkthrough of the INT 10h handler ranges (`00h–10h` and `40h–4Fh`), including register contracts, control flow summaries, workspace variables, and notes on the tri-plane text layout.  
  👉 See **[INT10.md](./INT10.md)**

- **Analysis notes**  
  Addresses, linear conversions, and workspace maps (e.g., `[0000:0808]` mode block, plane segments at `[088E]/[0890]/[0892]`, cursor storage at `[0450]`…).

- **Snippets & test harnesses**  
  Minimal MASM/TASM programs to exercise specific calls (scroll, rect blit/fill, read/write cell, palette nibble R/W, etc.).

- **Emulator workflows**  
  Quick commands for dumping words/bytes at linear addresses, and tips for verifying planes/rows/stride in MAME.

---

## Why this matters

The QX-11’s text display isn’t the usual IBM “char+attr word” memory. It uses **separate planes** for:
- **Character**
- **Attribute high nibble/byte**
- **Attribute low nibble/byte**

The BIOS services (both standard and OEM) keep these planes in sync; understanding the helpers and workspace is key to writing correct tools and ports.

---

## Status

- ✅ INT 10h **AH=00h–10h** documented (mode set, cursor, TTY, pixel R/W, palette).  
- ✅ INT 10h **AH=40h–4Fh** documented (tri-plane rect ops, char map/profile/layout, cell R/W, GA nibble R/W, display-list helpers).  
- 🔬 Continuing to verify edge cases (page flipping, fast scroll path, graphics mode quirks).

---

## How we work

1. **Disassemble & label** the BIOS (focus on INT 10h dispatcher and jump table).
2. **Map workspace** in low RAM (`0000:`), name fields as they appear across calls.
3. **Write tiny tests** to compare expected vs. observed behavior.
4. **Cross-check in emulator** (linear address math, plane contents, CRTC/GA shadows).

---

## Contributing

- Open issues with function traces, diffs, or clarification requests.
- PRs welcome for:
  - New findings or verified corrections.
  - Additional test programs.
  - Better naming/structure for workspace fields.

---

## Folder layout (suggested)

