# Epson QX-11 — Interrupt Vectors (Grouped and Annotated)

> Source: IVT dump (vectors 00h–BFh).  
> BIOS base: F107h segment.  
> Notes:  
> - `F107:0112` → **Beep/Halt** stub (BIOS beeps and halts).  
> - `F107:0422` / `F107:0423` → **IRET** stub (returns immediately).  
> - The QX-11 has **no 8259 PIC**; all hardware IRQs share **INT 71h**, multiplexed via GA status port 0x0E.

---

## 🧩 Implemented BIOS/DOS Interrupts

| INT | Address | Description |
|:---:|:---|:---|
| 00h | `EBA9:2A46` | CPU divide error handler. |
| 05h | `F107:2673` | Print-screen / bounds check. |
| 10h | `F107:0620` | **Video BIOS services.** |
| 11h | `F107:042A` | **Equipment list.** |
| 12h | `F107:0435` | **Base-memory size.** |
| 13h | `F107:3396` | **Disk services (INT 13h).** |
| 14h | `F107:3D41` | **Serial services (INT 14h).** |
| 15h | `F107:45D1` | **System services (INT 15h).** |
| 16h | `F107:1CB6` | **Keyboard (INT 16h).** |
| 17h | `F107:44E6` | **Printer (INT 17h).** |
| 18h | `F107:4657` | ROM BASIC / fallback. |
| 19h | `F107:0440` | **Bootstrap loader.** |
| 1Ah | `F107:38F1` | **RTC / Time-of-Day.** |
| 1Bh | `F107:21E0` | **Ctrl-Break handler.** |
| 1Eh | `F042:0B5D` | Diskette parameter table pointer. |
| 1Fh | `F656:15B8` | Graphics character table pointer. |
| 70h | `F107:0500` | Stub placeholder. |
| **71h** | `F107:37CD` | **Gate-Array shared interrupt (timer/FDC/etc.).** |
| 75h | `F107:1D32` | 8087/aux stub (not used). |
| 77h | `F107:3BF5` | BIOS dispatcher entry. |
| 79h | `F107:3BBF` | BIOS dispatcher entry. |
| 7Ch | `F107:3BDA` | BIOS dispatcher entry. |

---

## ⚙️ IBM PC Hardware IRQs (Not Implemented in QX-11)

| INT | Address | Original IBM PC Function | Status in QX-11 |
|:---:|:---|:---|:---|
| 08h | `F107:0112` | Timer (IRQ0) | Beep/Halt stub |
| 09h | `F107:0112` | Keyboard (IRQ1) | Beep/Halt stub |
| 0Ah | `F107:0112` | IRQ2 cascade | Beep/Halt stub |
| 0Bh | `F107:0112` | COM2 (IRQ3) | Beep/Halt stub |
| 0Ch | `F107:0112` | COM1 (IRQ4) | Beep/Halt stub |
| 0Dh | `F107:0112` | LPT2 (IRQ5) | Beep/Halt stub |
| 0Eh | `F107:0112` | FDC (IRQ6) | Beep/Halt stub |
| 0Fh | `F107:0112` | LPT1 (IRQ7) | Beep/Halt stub |

> In the QX-11, **INT 71h** replaces all these; it handles timer, FDC, and other GA events via port 0x0E.

---

## 🔔 Interrupts Using Beep/Halt Stub (`F107:0112`)

| INT Range | Example | Description |
|:---|:---|:---|
| 08h–0Fh | `08h → F107:0112` | All PC hardware IRQ placeholders. |
| 1Dh | `F107:0112` | Video parameter table pointer. |
| 30h–6Fh | Various | Rare/uncommon; unused BIOS placeholders. |
| 80h–BFh | Various | Unused vectors mapped to halt stub. |

---

## 🔁 Interrupts Using IRET Stub (`F107:0422` / `F107:0423`)

| INT | Address | Description |
|:---:|:---|:---|
| 01h | `F107:0422` | Single-step / debug return. |
| 02h | `F107:0422` | NMI return. |
| 03h | `F107:0422` | Breakpoint return. |
| 04h | `F107:0422` | Overflow return. |
| 06h | `F107:0422` | Invalid opcode return. |
| 07h | `F107:0422` | Coprocessor-not-available return. |
| 1Ch | `F107:0422` | **INT 1Ch user hook (default IRET).** |
| 72h | `F107:0423` | Tiny IRET stub. |
| 73h–7Fh | `F107:0422` | Misc. unused slots. |

---

## 🧭 Summary

- **INT 71h @ F107:37CD** – the only maskable hardware interrupt.  
  GA routes timer, floppy, and possibly serial events here; BIOS reads **port 0x0E** to identify and acknowledge the source.  
- **INT 08h–0Fh** – IBM PC IRQ vectors, unused; all map to beep/halt stub.  
- **INT 1Ah/1Ch** – Time-of-day and user tick implemented.  
- **INT 1Dh/1Eh/1Fh** – BIOS data pointers.  
- **Most other vectors** → IRET or halt stub.

---

© Research: Reverse-engineered from Epson QX‑11 BIOS ROM and IVT dump.
