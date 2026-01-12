# Epson QX-11 (Abacus) GAVNIO Gate Array — Ports 0x0C / 0x0D / 0x0E / 0x0F

This document describes the **GAVNIO** I/O gate array used in the Epson QX‑11 (also known as the Abacus).
GAVNIO multiplexes several unrelated subsystems behind a small number of I/O ports, including:

- Keyboard interface (command / status handshake)
- Floppy drive selection, status reporting, and TC‑done signaling
- Joystick selection and input sampling (used by BIOS INT 15h AH=10h)
- Additional OEM I/O paths handled through the same gate array

This page focuses on the ports and bit‑level behavior that have been reverse‑engineered so far and confirmed
through BIOS disassembly and runtime observation.

---

## Overview of Relevant Ports

| Port | Direction | Purpose |
|-----:|----------|---------|
| 0x0C | Write / Read | GAVNIO command / data register (keyboard & OEM I/O) |
| 0x0D | Read | GAVNIO status register |
| 0x0E | Read | Multiplexed status input (floppy + joystick) |
| 0x0F | Write | Multiplexed control latch (floppy + joystick select) |

---

## Ports 0x0C / 0x0D — Command / Status Handshake

Ports **0x0C** and **0x0D** implement the standard GAVNIO command/status handshake.
They are used by the BIOS to communicate with subsystems such as the keyboard controller.

- **0x0C** — command / data register
- **0x0D** — status register

These ports are already documented elsewhere in this repository (keyboard FIFO behavior, IRQ generation,
and handshake protocol). They are mentioned here only for completeness, as the focus of this document
is on the newly clarified multiplexing on ports **0x0E** and **0x0F**.

---

## Port 0x0F — Control Latch (Write Only)

Port **0x0F** is a write‑only control latch inside GAVNIO.  
Different bits and values are interpreted by different downstream subsystems.

### Floppy‑Related Control Writes

The BIOS uses the following values when controlling the floppy subsystem:

| Value written | Meaning |
|---------------|--------|
| `0x04` | Select floppy drive **A:** |
| `0x08` | Select floppy drive **B:** |
| `0x10` | Assert **TC‑done** (Terminal Count) toward the uPD765 FDC path |
| `0x00` | Clear / deassert latch (commonly written immediately after the above) |

**Typical BIOS pattern:**

```
OUT 0x0F, 0x04   ; select drive A
OUT 0x0F, 0x00   ; clear
```

or

```
OUT 0x0F, 0x10   ; TC done
OUT 0x0F, 0x00   ; clear
```

### Joystick Selection Writes

Joystick selection is performed indirectly through **INT 15h AH=10h**.
The BIOS computes the value written to port 0x0F as `(AL << 5)`.

| Joystick | AL | Value written to 0x0F |
|----------|----|-----------------------|
| Joystick #1 | 0x00 | `0x00` |
| Joystick #2 | 0x01 | `0x20` |

So:
- `OUT 0x0F, 0x00` → select joystick #1
- `OUT 0x0F, 0x20` → select joystick #2

### Ambiguity of 0x00 Writes

The value `0x00` is used in **two different contexts**:

1. As a **clear/deassert** following floppy control writes
2. As the **joystick #1 select** value

Real BIOS code distinguishes these by context (INT 15h joystick service vs floppy routines).
An emulator should avoid treating every `0x00` write as a joystick select if it immediately follows
a floppy control operation.

---

## Port 0x0E — Multiplexed Status Input (Read Only)

Port **0x0E** returns a composite status byte.  
Different subsystems use **different, non‑overlapping bits** of this byte.

---

## Floppy Status Bits (Bits 0–1)

The BIOS expects port 0x0E to return **exactly one of the following values** when checking floppy status:

- `0x01` → Drive A selected / ready
- `0x02` → Drive B selected / ready

These are implemented using bits **0** and **1**:

| Bit | Mask | Meaning |
|-----|------|--------|
| 0 | `0x01` | Floppy drive A selected / ready |
| 1 | `0x02` | Floppy drive B selected / ready |

The BIOS uses this value as a gating condition; if the expected bit is not asserted,
floppy reads and writes may not proceed.

---

## Joystick Input Bits (Bits 3–7, Active‑Low)

Joystick input is returned on the **same port (0x0E)** after selecting joystick #1 or #2 via port 0x0F.

These bits are **active‑low**:
- Bit = 1 → released / idle
- Bit = 0 → direction or button pressed

| Bit | Mask | Meaning | Pressed condition |
|-----|------|--------|------------------|
| 3 | `0x08` | Right | `(value & 0x08) == 0` |
| 4 | `0x10` | Left | `(value & 0x10) == 0` |
| 5 | `0x20` | Down | `(value & 0x20) == 0` |
| 6 | `0x40` | Up | `(value & 0x40) == 0` |
| 7 | `0x80` | Button | `(value & 0x80) == 0` |

### Idle Value

When no joystick input is active, bits 3–7 should all read as 1:

```
(value & 0xF8) == 0xF8
```

### Bit 2

Bit 2 (`0x04`) appears to be unused or noisy in the joystick path.
BIOS joystick code explicitly masks it out (`AND FC`, then `AND F8`), so it should be treated as
**don’t care** for joystick decoding.

---

## Composite Port 0x0E Value

A single read from port 0x0E may safely combine both subsystems:

```
value = (floppy_status & 0x03) | (joystick_bits & 0xF8)
```

This works because:
- Floppy code only examines bits 0–1
- Joystick code masks off bits 0–2 and only examines bits 3–7

---

## Relationship to INT 15h AH=10h (Joystick)

The BIOS joystick service:

1. Writes joystick select (`0x00` or `0x20`) to port 0x0F
2. Reads port 0x0E repeatedly until two consecutive reads match
3. Returns the stable byte in `AL`

The returned value is the **raw composite byte** described above.
Callers then apply masking to interpret joystick directions and button state.

See `int15.md` for the full BIOS disassembly and INT 15h calling convention.
