# Epson QX‑11 ROMs — Summary & Boot Flow

This folder contains two ROM images dumped from an Epson **QX‑11** (a.k.a. Epson Abacus / QC‑11). Together they implement **ROM‑DOS 2.11** with the command shell and a BIOS/DOS‑kernel split across two chips.

---

## Files in this folder

### 1) `MBM27256@DIP28_EPSON_ABACUS_M25140CA.BIN` — 32 KB (27C256 class)
**Role:** ROM “disk” holding **`COMMAND.COM`** only (the DOS 2.11 command interpreter).  
- Verified single 8.3 directory entry: `COMMAND   COM` (payload starts at 0x0B40, length 14,832 bytes).  
- Extracted shell for convenience: `QX11_COMMAND_COM.bin` (same contents as above).

**Hashes:**  
- MD5: `8dc3064b355c1f762682d2e726f45607`  
- SHA1: `d9dbafd6cae98559a5dfdd2be28fde485f105149`  
- CRC32: `5F4C9367`

---

### 2) `MBM27256@DIP28_EPSON_ABACUS_M25141CA.BIN` — 64 KB (27C512 class)
**Role:** **Reset/POST + BIOS services + ROM‑DOS kernel/bootstraps.**  
- Hard‑coded boot artifacts include `\CONFIG.SYS`, `J:\COMMAND.COM`, and device aliases like `\DEV\NUL`.  
- The ROM installs a **ROM drive mapped to `J:`** and launches **`J:\COMMAND.COM`** from the first ROM.  
- CONFIG.SYS directives present (DOS 2.11 era): `BUFFERS`, `BREAK`, `SHELL`, `DEVICE`, `FILES`, `COUNTRY`.

**Hashes:**  
- MD5: `845040f6b2321559998efa5901304cc9`  
- SHA1: `737e9ff8bb78161704b463393b69afd3c5b5c007`  
- CRC32: `B0AC8134`

---
### ) `qx11_font_8x8.pbm`
**Role:** **This file is part of the QX-11 BIOS but I extracted for the purpose of this Documentation**  
- Character generator table. The QX-11 will look into this table when drawing a character on screen. It is an 8x8 font.  

---
## How the QX‑11 loads the OS (expected flow)

1. **Reset → POST/BIOS (M25141CA):**  
   The CPU vectors into the 64 KB ROM, which initializes hardware using Epson‑specific I/O ports (not IBM PC standard).

2. **Install ROM drive(s):**  
   The BIOS/ROM‑DOS kernel creates a **ROM drive at `J:`**. (Setup screens label `J:` as *“MS‑DOS OS ROM”*.)  
   It may also configure a **RAM disk at `I:`** (strings and Setup menu indicate this).

3. **Process `\CONFIG.SYS`:**  
   The kernel parses classic DOS 2.11 directives (e.g., `FILES`, `BUFFERS`, `DEVICE`, `SHELL`).

4. **Launch the shell:**  
   The kernel loads **`J:\COMMAND.COM`** from the 32 KB ROM (`M25140CA`) and hands control to it.  
   From here you’re in **MS‑DOS 2.11** command interpreter.

> **Note:** No `IO.SYS` / `MSDOS.SYS` files exist on this system. Their functionality is fused into `M25141CA` together with the BIOS.

---

## What is NOT in these ROMs

- **GW‑BASIC / BASICA:** not present.  
- **Extra DOS utilities or `.SYS` drivers:** not present (e.g., no `ICRTDRV.SYS`).  
- The 32 KB ROM is **not a mountable FAT filesystem**; it’s a minimal ROM structure that only carries `COMMAND.COM` for the kernel to copy/execute.

---

## Testing notes

- The extracted `QX11_COMMAND_COM.bin` runs fine as a secondary shell under **MS‑DOS / FreeDOS** (e.g., DOSEMU2 or DOSBox‑X), because it uses standard **INT 21h** calls.  
- The 64 KB BIOS ROM will **not** boot on a stock IBM‑PC emulator due to **Epson‑specific I/O** expectations.

---

## Useful artifacts

- `QX11_COMMAND_COM.bin` — the extracted DOS 2.11 shell (14,832 bytes).  
- `qx11_rom_file_refs_curated.csv` — curated list of file/path/device references with offsets (optional helper).

*All offsets above are file offsets unless otherwise noted. Prepared from the two supplied ROM dumps.*

