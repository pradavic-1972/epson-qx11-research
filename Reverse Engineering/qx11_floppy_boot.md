# Epson QX-11 Floppy Boot Sector Requirements

This document summarizes the **exact conditions** under which the Epson **QX-11** BIOS considers a floppy disk *bootable*, based on reverse-engineering of the ROM BIOS.

Unlike IBM-PC compatibles, the QX-11 uses **vendor-specific validation logic** before executing the boot sector.

---

## BIOS Boot Validation Logic

When attempting to boot from floppy, the QX-11 BIOS:

1. Reads sector 0 into memory at **0000:7C00**
2. Performs a series of checks
3. If all checks pass, executes the boot sector via a **FAR CALL** to `0000:7C00`

If *any* check fails, the disk is skipped.

---

## Required Conditions for Boot Execution

### 1. First Opcode Must Be `E9` (Near JMP)

```asm
mov  al, [7C00]
and  al, 0FDh
cmp  al, 0E9h
```

- The first byte **must be `E9`**
- Short jumps (`EB xx 90`) are **not accepted**
- The jump offset is not validated

---

### 2. OEM String Must Be `"EPSON"`

```asm
cmpsb    ; CX = 5
```

- Bytes **7C03–7C07** must contain ASCII `"EPSON"`
- Only the first 5 bytes are checked
- Remaining OEM bytes are ignored

---

### 3. Boot Enable Bit (Offset 0x08)

```asm
test byte ptr [7C08], 20h
jnz  skip_boot
```

- **Bit 0x20 MUST be clear**
- If the bit is set, the BIOS refuses to boot the disk
- This bit is **QX-11-specific** and not part of FAT or DOS standards

---

## Boot Transfer Mechanism

If all checks pass, the BIOS executes:

```asm
call far 0:7C00
```

Key implications:

- The BIOS **does not JMP**, it **FAR CALLs**
- Boot sectors may safely terminate with `RETF`
- This explains why Epson-formatted disks often contain a `RETF` stub

---

## Epson Formatter Behavior

Disks formatted by the QX-11 often contain:

- A valid FAT12 BPB
- OEM string `"EPSON"`
- A near JMP to a stub containing only `RETF`

This allows the disk to:
- Pass BIOS validation
- Safely return to ROM if booted
- Become bootable later via `SYS`

---

## Booting Non-Epson MS-DOS Disks on QX-11

Any **360 KB FAT12 MS-DOS floppy** can be made bootable on the QX-11 by applying **three minimal patches**:

| Offset | Required Change |
|------|-----------------|
| 0x00 | Replace `EB xx 90` with `E9 xx xx` |
| 0x03–0x07 | Write `"EPSON"` |
| 0x08 | Clear bit `0x20` |

No other modifications are required.

The BIOS does **not** validate:
- BPB correctness
- FAT layout
- `55 AA` signature
- Boot loader origin (IBM / MS / FreeDOS)

Once execution reaches `0000:7C00`, the loader runs in a **fully standard 8088 DOS environment** using BIOS INT 13h.

---

## Disk Format Limitations

The following **will not boot**, regardless of patching:

- 720 KB (80-track) disks
- High-density media
- Non-FAT loaders using direct FDC access

The QX-11 supports **360 KB (DS/DD, 40-track)** floppies only.

---

## Summary

The QX-11 boot process is:

- **Strict before execution**
- **Completely standard after execution**

Once the Epson-specific gates are satisfied, the system behaves like a conventional MS-DOS machine.
