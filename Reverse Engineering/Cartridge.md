# Epson QX-11 ROM Cartridge Boot & Filesystem Mechanism (Confirmed)

This document summarizes **confirmed, tested behavior** of the Epson QX-11 ROM cartridge mechanism.
All items below have been validated experimentally.

The findings show that the QX-11 cartridge system is capable of:
- executing code during boot
- exposing a DOS filesystem
- participating in CONFIG.SYS / AUTOEXEC.BAT processing
- deferring disk-based drivers
- and very likely **bootstrapping an alternate operating system**

---

## 1. ROM Mapping

- Cartridge ROM is memory-mapped by the BIOS.
- Observed mappings:
  - **0xC0000** → cartridge filesystem appears as **drive L:**
  - **0xA0000** → cartridge filesystem appears as **drive K:**
- BIOS scans cartridges during POST.

---

## 2. Cartridge Header (offset 0x00)

### Required signature

| Offset | Size | Value |
|------:|-----:|------|
| 0x00 | WORD | **E5 56** (`56E5h`) |

Without this signature, the BIOS ignores the cartridge.

---

## 3. Execution Control (offset 0x08)

| Offset | Size | Meaning |
|------:|-----:|--------|
| 0x08 | BYTE | Execution / validation flags |

### Confirmed behavior

- When **bit 0x80 is set** (e.g. value `0xC0`):
  - The BIOS treats the cartridge as **executable**
  - Control is transferred to **offset `0x20`** in the cartridge

Execution occurs **after the IVT, INT 10h, INT 13h, and DOS infrastructure are already active**.

---

## 4. Segment Validation (offset 0x0B)

| Offset | Size | Meaning |
|------:|-----:|--------|
| 0x0B | BYTE | Expected load segment (high byte) |

- Must match the segment where the cartridge is mapped:
  - `0xC0000` → `0x0B = C0`
  - `0xA0000` → `0x0B = A0`
- If the value does not match:
  - the cartridge is recognized 
  
---

## 5. Filesystem Enable (offset 0x0C)

| Offset | Size | Meaning |
|------:|-----:|--------|
| 0x0C | BYTE | Filesystem indicator |

- **`0x04`** → cartridge contains a **DOS-accessible filesystem**
- Other values do **not** mount a filesystem

---

## 6. Volume / Module Name (offset 0x10)

| Value | Meaning |
|------|--------|
| `SYSTEM` | ROM-resident MS-DOS / COMMAND.COM storage (drive **J:**) |
| `FOREIGN` | ROM cartridge providing drivers or services |

---

## 7. Driver Deferral (FOREIGN cartridge)

QX-11 disk-supplied device drivers implement a ROM detection mechanism:

- If a cartridge with volume name **`FOREIGN`** is mapped at **0xC0000**
- The disk driver **does not load**
- The driver reports that the device is available in the ROM cartridge

This confirms Epson designed cartridges to **replace disk drivers cleanly**.

---

## 8. ROM Filesystem Layout

When `offset 0x0C = 0x04`, the cartridge exposes a filesystem.

### Filesystem start
- **Offset `0x40`** from the start of the cartridge

### Geometry (confirmed)

| Parameter | Value |
|---------|------|
| Bytes per sector | **32 bytes** |
| Sectors per cluster | **32** |
| Cluster size | **1024 bytes (1 KB)** |
| FAT type | FAT12-style |
| FAT copies | 1 |

---

## 9. Filesystem Structure

```
0x40  Boot sector / BPB (32 bytes)
0x60  FAT (packed FAT12)
...   Root directory (32 bytes per entry)
...   Data area (cluster-based)
```

- Standard DOS 8.3 directory entries
- DOS packed date/time supported
- Accessible via standard DOS APIs

---

## 10. DOS Boot Integration (CONFIRMED)

The cartridge filesystem is fully integrated into the DOS boot process.

### Confirmed behavior
- **CONFIG.SYS stored in the cartridge is read and executed**
- Cartridge participates in normal DOS boot probing
- Cartridge is treated as a valid DOS drive during boot

Given this, **AUTOEXEC.BAT stored in the cartridge will also be executed**.

---

## 11. Drive Letters

| Cartridge mapping | Drive |
|------------------|------|
| 0xC0000 | **L:** |
| 0xA0000 | **K:** |
| SYSTEM ROM DOS | **J:** |

---

## 12. Executable Cartridge Summary

To create an executable cartridge:

- `0x00 = E5 56`
- `0x08` with execution enabled (working value: `0xC0`)
- `0x0B` = mapped segment high byte
- Entry code at **offset `0x20`**

Execution begins at:

```
<segment>:0020
```

---

## 13. Implication: Alternate OS Booting

Because:
- cartridge code executes during boot
- cartridge can override drivers
- cartridge participates in CONFIG.SYS
- and cartridge can load arbitrary code

**This mechanism is very likely capable of bootstrapping an operating system other than the built-in MS-DOS 2.11**, such as:
- another DOS version
- FreeDOS kernel
- or a custom BIOS-compatible OS

Testing this is the next step.

---

## 14. Conclusion

The Epson QX-11 ROM cartridge system is a **BIOS-managed bootstrap mechanism**, not a simple ROM disk.

It supports:
- executable ROM modules
- ROM-resident DOS filesystems
- driver replacement
- full DOS boot integration

This makes the QX-11 one of the few early IBM-PC-compatible systems with a **designed-in ROM OS boot path**.
