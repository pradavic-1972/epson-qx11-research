# GAVNIT Interrupt Controller on the Epson QX-11

## Overview

The Epson QX-11 does **not** use the standard IBM PC interrupt architecture based on the Intel **8259 PIC** and **8253/8254 PIT**.  
Instead, interrupt routing, masking, and prioritization are handled by a custom Epson gate array referred to here as **GAVNIT**.

GAVNIT fulfills **two major roles**:

1. **Programmable Interrupt Controller (PIC)** – routing hardware interrupt sources to CPU interrupt vectors.
2. **System interrupt arbiter and mask controller** – managing interrupt priority, masking, and critical sections.

The QX-11 BIOS is explicitly written for this architecture and relies on **dynamic interrupt masking** rather than explicit End-Of-Interrupt (EOI) commands.

---

## Interrupt Vector Model (Key Difference vs IBM PC)

### IBM PC (8259 PIC)

| IRQ line | INT vector |
|--------:|------------|
| IRQ0 | INT 08h (timer) |
| IRQ1 | INT 09h (keyboard) |
| IRQ6 | INT 0Eh (floppy) |
| … | … |

The PC maps IRQ lines to **INT 08h–0Fh**.

---

### Epson QX-11 (GAVNIT)

The QX-11 maps hardware interrupts to **INT 70h–7Fh**.

The observed mapping rule is:

```
Interrupt vector = 0x70 + bit_index
```

Where `bit_index` is the bit position in a **16-bit interrupt mask register**.

---

## Interrupt Mask Register (Ports 0x04 / 0x05)

### Hardware Interface

Ports **0x04–0x05** form a single **16-bit interrupt mask latch**:

- **Port 0x04** → mask low byte  
- **Port 0x05** → mask high byte  

On the 8088, BIOS commonly uses:

```asm
OUT 04h, AX
```

Which writes:
- `AL → port 04h`
- `AH → port 05h`

### Mask Semantics

- **Bit = 1** → interrupt source enabled  
- **Bit = 0** → interrupt source masked  

Unlike an IBM PC, the BIOS does **not** issue an explicit EOI.  
Instead, it temporarily changes the mask during ISR execution to prevent re-entrancy and protect critical sections.

---

## Confirmed Interrupt Assignments

| Mask bit | INT vector | Source | Evidence |
|--------:|:----------:|--------|---------|
| 0 | INT 70h | Power-off / shutdown | INT 70 masks all interrupts (mask→0x0000) |
| 1 | INT 71h | System timer tick | Periodic BIOS ticker |
| 5 | INT 75h | Keyboard | Fires on keypress; ISR clears bit5 while running |
| 7 | INT 77h | Built-in serial | Control block uses ports 06h–08h |
| 9 | INT 79h | Internal modem (300 bps) | Control block uses port 19h |
| 10 | INT 7Ah | Floppy controller (uPD765) | uPD765 IRQ requires bit10 enabled |
| 12 | INT 7Ch | Optional serial interface | Control block uses ports 95h–96h |

Unused vectors (e.g. INT 76h, 78h, 7Ah/7Bh in some configs) may exist in the IVT but point to `IRET` stubs until a subsystem installs a handler.

---

## BIOS Masking Strategy (Instead of EOI)

### Boot-time mask example

After boot, the BIOS sets the mask in RAM at `0000:078B` to:

- `23 04` (little-endian) → `0x0423`

This enables mask bits: **0, 1, 5, 10**.

---

### Example: Keyboard Interrupt (INT 75h)

During INT 75 handling, BIOS changes the mask to:

- `03 04` → `0x0403` (bit5 cleared)

Effect:

- Keyboard interrupts are disabled while the ISR runs (prevents re-entrancy).
- Timer tick and other enabled sources can remain active.

The previous mask is restored before returning with `IRET`.

---

### Example: Timer Tick (INT 71h)

During certain critical sections (observed immediately before reading port `0x0E`), BIOS sets:

- `01 00` → `0x0001`

Effect:

- All interrupts are blocked except the highest priority source (bit0 / INT 70h).
- The previous mask (`0x0423`) is restored immediately after the critical I/O.

---

### Example: Power-Off (INT 70h)

INT 70h is confirmed to be the power-off/shutdown interrupt.  
While servicing INT 70h, BIOS sets:

- `00 00` → `0x0000`

Written to both ports 0x04 and 0x05 via a 16-bit `OUT 04h, AX`.

Effect:

- All maskable interrupts are disabled as the system enters shutdown.

---

## Role Compared to the IBM PC PIT

The QX-11 does not appear to use an 8253/8254 PIT. Instead:

- The periodic **system tick** is delivered as **INT 71h**.
- BIOS uses INT 71h similarly to IBM PC **IRQ0 / INT 08h**, but within the QX-11's **0x70-based** interrupt space.
- GAVNIT therefore covers functionality normally split across the PIT (periodic interrupt generation) and PIC (interrupt routing/masking).

---

## Conceptual Interrupt Delivery Model

A practical model for emulation and documentation is:

1. Hardware asserts a request (keyboard, serial RX-ready, FDC IRQ, etc.)
2. GAVNIT sets a **pending bit**
3. CPU IRQ line is asserted only if:

   ```
   (pending & mask) != 0
   ```

4. On interrupt acknowledge, the delivered vector is:

   ```
   INT = 0x70 + lowest_pending_bit_index
   ```

5. BIOS ISR may temporarily adjust the mask to:
   - block its own source (avoid re-entrancy)
   - block everything during critical sections
6. Pending bits clear when the source is serviced (e.g., serial byte drained, FDC interrupt condition cleared).

---

## Emulation Notes (MAME)

Minimum requirements for correct behavior:

- Model ports **0x04/0x05** as a **single 16-bit interrupt mask register**.
- Maintain a **pending bitfield** for interrupt sources.
- Assert the CPU IRQ line whenever `(pending & mask) != 0`.
- Do **not** clear the CPU IRQ line unconditionally after delivering a vector; instead, recompute eligibility after clearing one pending source.

This matches observed BIOS behavior and supports nested/critical-section masking patterns.

---

## Summary

Compared to an IBM PC, the QX-11 interrupt architecture differs in three critical ways:

1. Hardware IRQs map into **INT 70h–7Fh**, not INT 08h–0Fh.
2. A **16-bit mask register** at ports **0x04/0x05** controls interrupt delivery.
3. The BIOS uses **dynamic masking** instead of explicit EOIs.

These behaviors are directly observable in BIOS ISR prologues/epilogues and in live traces (INT 70 shutdown masking, INT 75 self-masking, INT 71 critical-section masking), and they inform a straightforward emulation model.
