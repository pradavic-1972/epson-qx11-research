# Epson QX-11 Gate Arrays  
**Complete Technical Documentation + Diagrams**

The Epson QX-11 computer is built around **five custom gate arrays** (GAs) that replace the discrete logic found in IBM PCs. These chips implement keyboard I/O, video, timers, floppy control, memory refresh, and interrupt routing.

Only **four of these GAs are fully or partially understood**; the fifth is still mysterious.

This file documents everything known so far, including interaction diagrams, VRAM diagrams, timer logic, and I/O maps.

---

# 0. Table of Contents
1. Overview  
2. List of Gate Arrays  
3. [GAVNIO](gavnio.md) – I/O & Keyboard Gate Array  
4. [GAVNIT](gavnit.md) – Interrupt & Host Timer Gate Array  
5. GAFDDC – Floppy Drive Control Gate Array  
6. [GAVDP](gavdp.md) – Video Display Processor Gate Array  
7. [GAVEMR](gavemr.md) – RAM/ROM Memory control  
8. Complete System Interaction Diagram  
9. Summary  

---

# 1. Overview

The QX-11 uses the following **five gate arrays**:

| Gate Array | Main Role |
|------------|-----------|
| **GAVNIO** | I/O command interface + keyboard serial engine |
| **GAVNIT** | Interrupt controller + 50 Hz timer |
| **GAFDDC** | Floppy drive control + TC signaling |
| **GAVDP** | Video processor (VRAM → raster) |
| **GAVNMR** | Memory refresh logic (suspected) |

These devices create a unified architecture that is *not IBM compatible*.

---

# 2. List of Gate Arrays (with brief descriptions)

| GA | Description |
|----|-------------|
| **GAVNIO** | CPU I/O interface, keyboard deserializer, command/status controller |
| **GAVNIT** | Interrupt aggregator, system timer engine |
| **GAFDDC** | Floppy drive select, drive-ready, TC toggle |
| **GAVDP** | Custom video processor: column-based VRAM, Mode 7, RGB mode |
| **GAVNMR** | Memory refresh logic (not required for emulation) |

---

# 3. GAVNIO  
## I/O Interface + Keyboard Serial Engine

### Responsibilities
- Exposes two key I/O ports used by the BIOS:
  - **0x0C** – command/data
  - **0x0D** – status  
- Implements the **1200 bps synchronous keyboard protocol**  
- Does bit-shifting to assemble serial keycodes  
- Passes finished bytes to GAVNIT → raises **INT 75h**

### I/O Ports
| Port | Function |
|------|----------|
| **0x0C** | Command/Data register |
| **0x0D** | Status register |

### Keyboard Protocol
```
Host drives clock → Keyboard sends:
START → 8 data bits (LSB first) → ODD PARITY → STOP
```

Diagram — Keyboard → GAVNIO → GAVNIT:

```
     Keyboard TXD ----> [ Shift Register ] ----> Completed Byte
     Host CLK   ----> [ GAVNIO Clocking ] ----> To GAVNIT interrupt logic
```

When a byte completes → GAVNIT raises **INT 75h**.

GAVNIO **does not handle paging** for video or RTC. All such devices use fixed ports.

---

# 4. GAVNIT  
## Interrupt Controller + 50 Hz Timer

### Responsibilities
- Timer interrupt → **INT 71h**
- Keyboard interrupt → **INT 75h**
- Shutdown event → **INT 70h**
- FDC interrupt latching (uPD765 INTRQ)
- Timer compare register (deadline-based timer)

### I/O Ports
| Port | Direction | Function |
|------|-----------|----------|
| **0x00** | R/W | Timer deadline LSB |
| **0x01** | R/W | Timer deadline MSB |
| **0x04** | R/W | Interrupt latch (read) / mask/control (write – hypothesis) |
| **0x05** | W   | Additional IRQ mask (hypothesis) |

---

## Deadline Timer Diagram (INT 71h engine)

```
[ CPU reads deadline from 0x00/0x01 ]
             ↓
[ CPU adds delta (usually 0x0600) ]
             ↓
[ CPU writes new deadline ]
             ↓
GAVNIT compares host-clock counter to deadline
             ↓
When reached → INT 71h
```

The timer **must be re-armed** every tick (BIOS responsibility).

---

## Interrupt Flow Diagram

```
                ┌──────────────────┐
  Keyboard Byte →│ INT 75h Handler │
                └──────────────────┘
                        ▲
                        │
         ┌──────────────┴──────────────┐
         │                              │
   FDC INTRQ                        Timer Reached
         │                              │
         ▼                              ▼
      [GAVNIT] ------------------→ Raises INT 71/75/70
         │
         ▼
       8088
```

---

# 5. GAFDDC  
## Floppy Drive Control + Terminal Count (TC)

### Responsibilities
- Drive A/B selection  
- Drive ready status  
- Toggles uPD765 **Terminal Count** (TC)  
- Cooperates with RTC square-wave (expected motor-off behavior; TBD)

### Ports
| Port | Function |
|------|----------|
| **0x0E** | Drive ready (01h = A, 02h = B) |
| **0x0F** | Drive select + **TC toggle** |

### Behavior
| Value | Meaning |
|--------|----------|
| 0x04 | Select drive A |
| 0x08 | Select drive B |
| 0x00 | Deselect drive |
| **0x10** | Toggle FDC Terminal Count |

### Sequence Diagram

```
BIOS OUT 0x0F, 0x04 → select A
BIOS issues FDC command
BIOS OUT 0x0F, 0x10 → toggle TC  (end-of-operation)
BIOS OUT 0x0F, 0x00 → deselect
```

---

# 6. GAVDP  
## The Video Display Processor Gate Array

This is the most advanced chip in the QX-11.

### Major Responsibilities
- Maps CPU RAM → VRAM window  
- Generates pixel raster  
- Handles scroll offset, profiles, attributes  
- Implements column-centric VRAM addressing  
- Supports Mode 7 + 8-color RGB mode  
- Dynamically adjusts screen size based on BIOS memory values  

---

## 6.1 Video Modes

| Mode | Resolution | Color | Notes |
|------|------------|--------|-------|
| **Mode 7** | 640×400 | Monochrome | Primary firmware mode |
| **Color Mode** | 640×200 | 8 colors | Enabled via DIP switches |

---

## 6.2 Column-Major VRAM Design

Each column = **512 bytes (0x200)**:

```
Column N offset = N * 0x200
```

Vertical splitting:

```
Offset +0x000 → Row 0–199
Offset +0x100 → Row 200–399
```

### VRAM Diagram

```
VRAM (logical)
──────────────────────────────────────────────
| Col0 | Col1 | Col2 | … | ColN |
──────────────────────────────────────────────
| +0x000 → Top 200 lines per column         |
| +0x100 → Bottom 200 lines per column      |
──────────────────────────────────────────────
```

Rendering = reconstruct each row by reading **one byte from each column**.

---

## 6.3 VRAM Window > 48 KB

Physical VRAM = 48 KB  
Logical VRAM window = **larger**

Meaning:

- Additional memory around 0x8C000–0x8FFFF influences video  
- GAVDP decides which slice is used  
- Likely tied to the 11-register mode table  

---

## 6.4 The GAVDP 11-Register Mode Control Block

During any INT 10h mode switch, the BIOS copies an **11-byte configuration table** to RAM.

### Decoded Registers
| Address | Function |
|---------|----------|
| **0x8C663** | Vertical scroll offset |
| **0x8D068** | Video profile selector |
| **0x8D269** | Attribute byte |

### Remaining 8 Registers (TBD)
| Address |
|---------|
| 0x8C660 |
| 0x8C661 |
| 0x8C662 |
| 0x8C664 |
| 0x8C665 |
| 0x8D060 |
| 0x8D061 |
| 0x8D062 |

These likely cover:

- VRAM bank select  
- Address masks  
- Timing tweaks  
- Character cell geometry  

---

## 6.5 Attribute System

### Attribute Byte (0x8D269)

```
bit 0   : Foreground color LSB
bit 1   : Foreground color MID
bit 2   : Foreground color MSB  (→ 8 colors)
bit 3   : Background control
bit 4   : Underline
bit 5   : Inverse
bit 6   : Blink
bit 7   : Mode-dependent
```

In monochrome mode → color bits become styling only.

---

## 6.6 Auto-Adjusting Screen Resolution (40/80 Columns)

The BIOS stores max X/Y screen size in RAM.

When switching:

- **80 → 40 columns**, or  
- **40 → 80 columns**  

…the emulator automatically **resizes screen resolution** based on these values.

Diagram:

```
[BIOS writes new maxX/maxY] → [GAVDP renderer updates screen size]
```

---

## 6.7 GAVDP Known Issues

### 1. Scrolling Gap
Changing scroll index at **0x8C663** causes a moving gap.

Likely caused by:

- VRAM window not fully modeled  
- Column + row wrap-around rules  
- Unimplemented behavior around 48KB → larger VRAM window  

### 2. Missing Hardware Row-Clear
Real hardware clears rows automatically when writing column 1.

This behavior is not yet reproduced.

---

# 7. GAVNMR  
## Memory Refresh / RAM Timing Gate Array  
(*Unknown, not needed for emulation*)

### Likely Responsibilities
- DRAM refresh sequencing  
- Address multiplexing  
- Extended bus timing for VRAM stability  
- Power management during HALT/reset  

No I/O ports mapped. BIOS does not interact with it directly.

Because DRAM refresh is emulated by MAME’s RAM core, **GAVNMR is not required**.

---

# 8. Full System Interaction Diagram

```
                      ┌─────────────┐
  Keyboard TXD  ----> │   GAVNIO    │
  Keyboard CLK  ----> │ (I/O + KBD) │
                      └──────┬──────┘
                             │
                      Completed Byte
                             │
                             ▼
                      ┌─────────────┐
        RTC  -------> │   GAVNIT    │ <------ FDC INTRQ
 (tick source?)       │ (IRQ+Timer) │
                      └──────┬──────┘
                             │
                 INT 75 / INT 71 / INT 70
                             │
                             ▼
                          8088 CPU
                             │
     ┌───────────────────────┼────────────────────────┐
     ▼                       ▼                        ▼
┌──────────┐          ┌──────────┐             ┌──────────┐
│  GAFDDC  │          │  GAVDP   │             │ GAVNMR   │
│(Floppy)  │          │ (Video)  │             │ (Refresh)│
└──────────┘          └──────────┘             └──────────┘
     │                      │
 Drive Select          VRAM → Raster
 TC Toggle
```

---

# 9. Summary

The Epson QX-11 relies heavily on these five gate arrays to implement all I/O, video, and timing functions.  
Four of them (GAVNIO, GAVNIT, GAFDDC, GAVDP) are now understood well enough for accurate emulation.

The last remaining GA (GAVNMR) appears to be purely for memory refresh and is not needed for a working system.

The **GAVDP** and **GAVNIT** continue to be active areas of reverse engineering as we decode more of their internal logic, register interactions, and timing systems.

---
