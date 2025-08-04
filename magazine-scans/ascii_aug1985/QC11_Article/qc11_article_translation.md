# ✍️ Translation: Epson QC-11 Article (ASCII Magazine, August 1985)

## Overview

This article, originally published in ASCII Magazine Vol. 9, Issue 8 (August 1985), covers the Epson QC-11, a Japanese business computer based on the 8088-2 CPU, designed with MS-DOS in ROM and a focus on Japanese text input and compact design.

---

## Key Highlights

### 🧠 OS in ROM – “Switch-On MS-DOS”

The QC-11 boots MS-DOS Ver 2.11 directly from ROM without requiring a floppy disk. Even the command interpreter (`command.com`) is built into ROM, eliminating common boot errors and saving disk space. This makes the system immediately usable with no need to load the OS from external media.

---

### 🈶 Japanese Language Features

The QC-11 supports Japanese kana-kanji conversion at the OS level. It includes a kanji dictionary ROM, enabling fast conversion without disk access. Optional dictionaries with technical terms are available. Input methods include:
- Kana-to-kanji conversion
- Radical, stroke count, and JIS-code input
- Touch-typing support and JIS layout

---

### 🔤 Font and Printing Support

The QC-11 provides bitmapped font rendering, allowing even non-kanji printers to output Japanese characters when using ESC/P09-81-compatible Epson printers. Japanese characters are embedded in ROM for high-speed access.

---

### 🧩 Compact Design

- Body size: 320×300×80mm
- Two keyboard options: compact (81 keys) and full (107 keys with numeric keypad)
- Two display options: 5-inch or 12-inch green monochrome CRTs
- Standard RGB output available via DIP switch

---

### ⚙️ Hardware Specs

- **CPU**: 8088-2 @ 4.92MHz
- **RAM**: 256KB (expandable to 512KB)
- **VRAM**: 48KB
- **Graphics**: 640x400 and 640x200 (8-color RGB or mono)
- **Japanese Fonts**: JIS Level 1 (2965 chars), Level 2 optional
- **Storage**: Two internal 3.5" floppy drives (720KB each)
- **I/O**: Parallel, RS-232C, ROM cartridge, joystick, audio out

---

### 🛠️ Utilities and Expandability

- Includes Japanese GW-BASIC and MS-DOS utilities
- Configuration settings stored in CMOS RAM
- RAM disk feature available (uses part of RAM for high-speed storage)
- Built-in RS-232C terminal software (TERM, FLINK)
- Optional mouse and ROM cartridges expand functionality

---

### 🧪 Performance Notes

- Display performance is relatively slow, especially in GW-BASIC scrolling
- High character rendering overhead due to bitmapped graphics
- 8088 performance is balanced for office use but limited for heavy Japanese processing
- Quiet fanless design using CMOS chips to reduce heat

---

### 🧱 Custom Chip Design

Five custom ICs surround the CPU for memory, floppy, and video control. Estimated to replace 30–40 TTL chips (6000–7000 gates). These ICs contribute to the compactness and reliability of the system.

---

### 🔌 Future Support and Peripherals

- Optional QC Mouse supported over RS-232C (mouse driver in ROM)
- ROM cartridge slot enables specialized applications
- Support planned for HDDs and 3.5" floppy expansion
- Limited support for 5" HD and 8" drives may hinder adoption in larger offices

---

### 📦 Included Software and Applications

- Japanese word processor (e.g. TERA)
- Spreadsheet: SuperCalc 3 (Innovative Software)
- Database: TIMES (Sorcim) with data exchange capabilities

---

## 🧾 Final Thoughts

While understated, the QC-11 is a technically thoughtful machine. It offers real value to users familiar with MS-DOS and Japanese computing needs. Its ROM-based design, expandability, and integrated tools position it as a promising office solution in a market dominated by BASIC-based systems.

---

📄 Original article: [`QC11-ARTICLE_.pdf`](QC11-ARTICLE_.pdf)  
📰 Source: ASCII Magazine, August 1985  
