# GAVDP – Epson QX-11 Gate Array Video Display Processor  
**Technical Reference & Reverse-Engineering Notes**

The **GAVDP** (Gate Array Video Display Processor) is the custom Epson chip responsible for all video output on the **Epson QX-11**.  
It is *not* IBM CGA/MDA compatible — it uses its own timing, VRAM format, attribute rules, and control registers.

This document provides a complete description of everything currently known about the GAVDP, how the BIOS programs it, which memory locations it uses, how VRAM is organized, and what remains to be reverse-engineered.

---

# 1. Key Features of the GAVDP

- Supports two major display modes:
  - **Mode 7 – 640×400 monochrome**
  - **Color Mode – 640×200, 8 colors**
- VRAM is **column-oriented**, not row-oriented (unique to QX-series)
- Physical VRAM: **48 KB**, but **logical window is larger**
- Uses an **11-register control block** stored in system RAM  
- Responds to DIP switches for:
  - RGB vs Monochrome monitor  
  - 40 vs 80 columns  
- Rendering resolution dynamically adjusts based on memory-stored max X/Y
- GAVDP handles color attributes, inverse, blink, underline, etc.

---

# 2. Video Modes

## 2.1 Mode 7 – 640×400 Monochrome
Epson high-resolution mode used by the BIOS and built-in utilities.

- 640 pixels × 400 lines  
- 1-bit per pixel  
- 48 KB VRAM accessed in a non-linear pattern  
- Primary mode for text and graphics on the QX-11

## 2.2 640×200 Color Mode (8 Colors)
Enabled when DIP switches 7–8 specify **RGB** monitor.

- 640×200 resolution  
- Color comes from an attribute byte (3-bit foreground color)  
- Background color support depends on mode  
- Blink, inverse, underline supported

---

# 3. Column-Centric VRAM Architecture  
(*The most important hardware-accurate detail*)

The QX-11 stores VRAM by **columns**, not rows — a design inherited from the QX-10 and other Epson word processors.

### Layout  
Each column = **512 bytes (0x200)**:

