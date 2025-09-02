# Epson QX‑11 Firmware Mapping, Interrupt Vectors, and BIOS Handlers

## Introduction

The Epson QX‑11 is a Japanese 8088‑based computer (also marketed as the Abacus/QC‑11). Unlike the IBM PC, it ships with **MS‑DOS 2.11 directly in ROM** alongside a custom machine BIOS. This allows the system to boot and provide DOS functionality instantly without relying on floppy disks.

The firmware is split into two main 32 KiB regions:


- **Machine BIOS (QX‑11 BIOS):**

  - Address: **F0000h–F7FFFh** (mapped from `EPSON_ABACUS_M25140CA.BIN`)

  - Mirror: **F8000h–FFFFFh** (mapped from `EPSON_ABACUS_M25141CA.BIN`)

  - Provides POST, hardware interrupt handlers (keyboard, video, disk, etc.).


- **ROM‑DOS BIOS + MS‑DOS kernel:**

  - Address: **E0000h–E7FFFh**

  - Mirror: **E8000h–EFFFFh**

  - Provides DOS system calls (INT 20h, INT 21h, etc.).


This design makes the QX‑11 behave like a PC with both BIOS and DOS fused into firmware chips.

## Interrupt Vector Table (IVT)

At physical address **0000:0000 → 0000:03FF** lies the **Interrupt Vector Table**. This is a 1 KiB table with 256 entries, one for each interrupt. Each entry contains a 16‑bit offset and 16‑bit segment pointing to the handler.


The table below was extracted from a live running QX‑11 machine under emulation. Physical addresses were computed as `(segment << 4) + offset`, and mapped into the corresponding ROM region/file.

| INT | Segment:Offset | Physical | Region | ROM file | File offset |
|---:|---|---|---|---|---|
| 00h | EBA9:2A46 | EE4D6h | DOS_HIGH |  | 0x64D6 |
| 01h | F107:0422 | F1492h | BIOS_LOW | EPSON_ABACUS_M25140CA.BIN | 0x1492 |
| 02h | F107:0422 | F1492h | BIOS_LOW | EPSON_ABACUS_M25140CA.BIN | 0x1492 |
| 03h | F107:0422 | F1492h | BIOS_LOW | EPSON_ABACUS_M25140CA.BIN | 0x1492 |
| 04h | F107:0422 | F1492h | BIOS_LOW | EPSON_ABACUS_M25140CA.BIN | 0x1492 |
| 05h | F107:2673 | F36E3h | BIOS_LOW | EPSON_ABACUS_M25140CA.BIN | 0x36E3 |
| 06h | F107:0422 | F1492h | BIOS_LOW | EPSON_ABACUS_M25140CA.BIN | 0x1492 |
| 07h | F107:0422 | F1492h | BIOS_LOW | EPSON_ABACUS_M25140CA.BIN | 0x1492 |
| 08h | F107:0112 | F1182h | BIOS_LOW | EPSON_ABACUS_M25140CA.BIN | 0x1182 |
| 09h | F107:0112 | F1182h | BIOS_LOW | EPSON_ABACUS_M25140CA.BIN | 0x1182 |
| 0Ah | F107:0112 | F1182h | BIOS_LOW | EPSON_ABACUS_M25140CA.BIN | 0x1182 |
| 0Bh | F107:0112 | F1182h | BIOS_LOW | EPSON_ABACUS_M25140CA.BIN | 0x1182 |
| 0Ch | F107:0112 | F1182h | BIOS_LOW | EPSON_ABACUS_M25140CA.BIN | 0x1182 |
| 0Dh | F107:0112 | F1182h | BIOS_LOW | EPSON_ABACUS_M25140CA.BIN | 0x1182 |
| 0Eh | F107:0112 | F1182h | BIOS_LOW | EPSON_ABACUS_M25140CA.BIN | 0x1182 |
| 0Fh | F107:0112 | F1182h | BIOS_LOW | EPSON_ABACUS_M25140CA.BIN | 0x1182 |
| 10h | F107:0620 | F1690h | BIOS_LOW | EPSON_ABACUS_M25140CA.BIN | 0x1690 |
| 11h | F107:042A | F149Ah | BIOS_LOW | EPSON_ABACUS_M25140CA.BIN | 0x149A |
| 12h | F107:0435 | F14A5h | BIOS_LOW | EPSON_ABACUS_M25140CA.BIN | 0x14A5 |
| 13h | F107:3396 | F4406h | BIOS_LOW | EPSON_ABACUS_M25140CA.BIN | 0x4406 |
| 14h | F107:3D41 | F4DB1h | BIOS_LOW | EPSON_ABACUS_M25140CA.BIN | 0x4DB1 |
| 15h | F107:45D1 | F5641h | BIOS_LOW | EPSON_ABACUS_M25140CA.BIN | 0x5641 |
| 16h | F107:1CB6 | F2D26h | BIOS_LOW | EPSON_ABACUS_M25140CA.BIN | 0x2D26 |
| 17h | F107:44E6 | F5556h | BIOS_LOW | EPSON_ABACUS_M25140CA.BIN | 0x5556 |
| 18h | F107:4657 | F56C7h | BIOS_LOW | EPSON_ABACUS_M25140CA.BIN | 0x56C7 |
| 19h | F107:0440 | F14B0h | BIOS_LOW | EPSON_ABACUS_M25140CA.BIN | 0x14B0 |
| 1Ah | F107:38F1 | F4961h | BIOS_LOW | EPSON_ABACUS_M25140CA.BIN | 0x4961 |
| 1Bh | F107:21E0 | F3250h | BIOS_LOW | EPSON_ABACUS_M25140CA.BIN | 0x3250 |
| 1Ch | F107:0422 | F1492h | BIOS_LOW | EPSON_ABACUS_M25140CA.BIN | 0x1492 |
| 1Dh | F107:0112 | F1182h | BIOS_LOW | EPSON_ABACUS_M25140CA.BIN | 0x1182 |
| 1Eh | F042:0B5D | F0F7Dh | BIOS_LOW | EPSON_ABACUS_M25140CA.BIN | 0x0F7D |
| 1Fh | F656:15B8 | F7B18h | BIOS_LOW | EPSON_ABACUS_M25140CA.BIN | 0x7B18 |
| 20h | EBA9:035C | EBDECh | DOS_HIGH |  | 0x3DEC |
| 21h | EBA9:0360 | EBDF0h | DOS_HIGH |  | 0x3DF0 |
| 22h | 0395:028B | 03BDBh |  |  |  |
| 23h | 0395:01BD | 03B0Dh |  |  |  |
| 24h | 0395:04C0 | 03E10h |  |  |  |
| 25h | EBA9:05C5 | EC055h | DOS_HIGH |  | 0x4055 |
| 26h | EBA9:060C | EC09Ch | DOS_HIGH |  | 0x409C |
| 27h | EBA9:3277 | EED07h | DOS_HIGH |  | 0x6D07 |
| 28h | EBA9:0370 | EBE00h | DOS_HIGH |  | 0x3E00 |
| 29h | F042:0099 | F04B9h | BIOS_LOW | EPSON_ABACUS_M25140CA.BIN | 0x04B9 |
| 2Ah | 0000:0000 | 00000h |  |  |  |
| 2Bh | 0000:0000 | 00000h |  |  |  |
| 2Ch | 0000:0000 | 00000h |  |  |  |
| 2Dh | 0000:0000 | 00000h |  |  |  |
| 2Eh | 0395:025A | 03BAAh |  |  |  |
| 2Fh | 0000:0000 | 00000h |  |  |  |
| 30h | A903:71EA | B021Ah |  |  |  |
| 31h | F107:01EB | F125Bh | BIOS_LOW | EPSON_ABACUS_M25140CA.BIN | 0x125B |
| 32h | F107:0112 | F1182h | BIOS_LOW | EPSON_ABACUS_M25140CA.BIN | 0x1182 |
| 33h | F107:0112 | F1182h | BIOS_LOW | EPSON_ABACUS_M25140CA.BIN | 0x1182 |
| 34h | F107:0112 | F1182h | BIOS_LOW | EPSON_ABACUS_M25140CA.BIN | 0x1182 |
| 35h | F107:0112 | F1182h | BIOS_LOW | EPSON_ABACUS_M25140CA.BIN | 0x1182 |
| 36h | F107:0112 | F1182h | BIOS_LOW | EPSON_ABACUS_M25140CA.BIN | 0x1182 |
| 37h | F107:0112 | F1182h | BIOS_LOW | EPSON_ABACUS_M25140CA.BIN | 0x1182 |
| 38h | F107:0112 | F1182h | BIOS_LOW | EPSON_ABACUS_M25140CA.BIN | 0x1182 |
| 39h | F107:0112 | F1182h | BIOS_LOW | EPSON_ABACUS_M25140CA.BIN | 0x1182 |
| 3Ah | F107:0112 | F1182h | BIOS_LOW | EPSON_ABACUS_M25140CA.BIN | 0x1182 |
| 3Bh | F107:0112 | F1182h | BIOS_LOW | EPSON_ABACUS_M25140CA.BIN | 0x1182 |
| 3Ch | F107:0112 | F1182h | BIOS_LOW | EPSON_ABACUS_M25140CA.BIN | 0x1182 |
| 3Dh | F107:0112 | F1182h | BIOS_LOW | EPSON_ABACUS_M25140CA.BIN | 0x1182 |
| 3Eh | F107:0112 | F1182h | BIOS_LOW | EPSON_ABACUS_M25140CA.BIN | 0x1182 |
| 3Fh | F107:0112 | F1182h | BIOS_LOW | EPSON_ABACUS_M25140CA.BIN | 0x1182 |
| 40h | F107:2776 | F37E6h | BIOS_LOW | EPSON_ABACUS_M25140CA.BIN | 0x37E6 |
| 41h | 0000:1BD5 | 01BD5h |  |  |  |
| 42h | F107:0112 | F1182h | BIOS_LOW | EPSON_ABACUS_M25140CA.BIN | 0x1182 |
| 43h | F107:0112 | F1182h | BIOS_LOW | EPSON_ABACUS_M25140CA.BIN | 0x1182 |
| 44h | F656:11B8 | F7718h | BIOS_LOW | EPSON_ABACUS_M25140CA.BIN | 0x7718 |
| 45h | F107:0112 | F1182h | BIOS_LOW | EPSON_ABACUS_M25140CA.BIN | 0x1182 |
| 46h | F107:0112 | F1182h | BIOS_LOW | EPSON_ABACUS_M25140CA.BIN | 0x1182 |
| 47h | F107:0112 | F1182h | BIOS_LOW | EPSON_ABACUS_M25140CA.BIN | 0x1182 |
| 48h | F107:0112 | F1182h | BIOS_LOW | EPSON_ABACUS_M25140CA.BIN | 0x1182 |
| 49h | F107:0112 | F1182h | BIOS_LOW | EPSON_ABACUS_M25140CA.BIN | 0x1182 |
| 4Ah | F107:0112 | F1182h | BIOS_LOW | EPSON_ABACUS_M25140CA.BIN | 0x1182 |
| 4Bh | F107:0112 | F1182h | BIOS_LOW | EPSON_ABACUS_M25140CA.BIN | 0x1182 |
| 4Ch | F107:0112 | F1182h | BIOS_LOW | EPSON_ABACUS_M25140CA.BIN | 0x1182 |
| 4Dh | F107:0112 | F1182h | BIOS_LOW | EPSON_ABACUS_M25140CA.BIN | 0x1182 |
| 4Eh | F107:0112 | F1182h | BIOS_LOW | EPSON_ABACUS_M25140CA.BIN | 0x1182 |
| 4Fh | F107:0112 | F1182h | BIOS_LOW | EPSON_ABACUS_M25140CA.BIN | 0x1182 |
| 50h | F107:0112 | F1182h | BIOS_LOW | EPSON_ABACUS_M25140CA.BIN | 0x1182 |
| 51h | F107:0112 | F1182h | BIOS_LOW | EPSON_ABACUS_M25140CA.BIN | 0x1182 |
| 52h | F107:0112 | F1182h | BIOS_LOW | EPSON_ABACUS_M25140CA.BIN | 0x1182 |
| 53h | F107:0112 | F1182h | BIOS_LOW | EPSON_ABACUS_M25140CA.BIN | 0x1182 |
| 54h | F107:0112 | F1182h | BIOS_LOW | EPSON_ABACUS_M25140CA.BIN | 0x1182 |
| 55h | F107:0112 | F1182h | BIOS_LOW | EPSON_ABACUS_M25140CA.BIN | 0x1182 |
| 56h | F107:0112 | F1182h | BIOS_LOW | EPSON_ABACUS_M25140CA.BIN | 0x1182 |
| 57h | F107:0112 | F1182h | BIOS_LOW | EPSON_ABACUS_M25140CA.BIN | 0x1182 |
| 58h | F107:0112 | F1182h | BIOS_LOW | EPSON_ABACUS_M25140CA.BIN | 0x1182 |
| 59h | F107:0112 | F1182h | BIOS_LOW | EPSON_ABACUS_M25140CA.BIN | 0x1182 |
| 5Ah | F107:0112 | F1182h | BIOS_LOW | EPSON_ABACUS_M25140CA.BIN | 0x1182 |
| 5Bh | F107:0112 | F1182h | BIOS_LOW | EPSON_ABACUS_M25140CA.BIN | 0x1182 |
| 5Ch | F107:0112 | F1182h | BIOS_LOW | EPSON_ABACUS_M25140CA.BIN | 0x1182 |
| 5Dh | F107:0112 | F1182h | BIOS_LOW | EPSON_ABACUS_M25140CA.BIN | 0x1182 |
| 5Eh | F107:0112 | F1182h | BIOS_LOW | EPSON_ABACUS_M25140CA.BIN | 0x1182 |
| 5Fh | F107:0112 | F1182h | BIOS_LOW | EPSON_ABACUS_M25140CA.BIN | 0x1182 |
| 60h | F107:0112 | F1182h | BIOS_LOW | EPSON_ABACUS_M25140CA.BIN | 0x1182 |
| 61h | F107:0112 | F1182h | BIOS_LOW | EPSON_ABACUS_M25140CA.BIN | 0x1182 |
| 62h | F107:0112 | F1182h | BIOS_LOW | EPSON_ABACUS_M25140CA.BIN | 0x1182 |
| 63h | F107:0112 | F1182h | BIOS_LOW | EPSON_ABACUS_M25140CA.BIN | 0x1182 |
| 64h | F107:0112 | F1182h | BIOS_LOW | EPSON_ABACUS_M25140CA.BIN | 0x1182 |
| 65h | F107:0112 | F1182h | BIOS_LOW | EPSON_ABACUS_M25140CA.BIN | 0x1182 |
| 66h | F107:0112 | F1182h | BIOS_LOW | EPSON_ABACUS_M25140CA.BIN | 0x1182 |
| 67h | F107:0112 | F1182h | BIOS_LOW | EPSON_ABACUS_M25140CA.BIN | 0x1182 |
| 68h | F107:0112 | F1182h | BIOS_LOW | EPSON_ABACUS_M25140CA.BIN | 0x1182 |
| 69h | F107:0112 | F1182h | BIOS_LOW | EPSON_ABACUS_M25140CA.BIN | 0x1182 |
| 6Ah | F107:0112 | F1182h | BIOS_LOW | EPSON_ABACUS_M25140CA.BIN | 0x1182 |
| 6Bh | F107:0112 | F1182h | BIOS_LOW | EPSON_ABACUS_M25140CA.BIN | 0x1182 |
| 6Ch | F107:0112 | F1182h | BIOS_LOW | EPSON_ABACUS_M25140CA.BIN | 0x1182 |
| 6Dh | F107:0112 | F1182h | BIOS_LOW | EPSON_ABACUS_M25140CA.BIN | 0x1182 |
| 6Eh | F107:0112 | F1182h | BIOS_LOW | EPSON_ABACUS_M25140CA.BIN | 0x1182 |
| 6Fh | F107:0112 | F1182h | BIOS_LOW | EPSON_ABACUS_M25140CA.BIN | 0x1182 |
| 70h | F107:0500 | F1570h | BIOS_LOW | EPSON_ABACUS_M25140CA.BIN | 0x1570 |
| 71h | F107:37CD | F483Dh | BIOS_LOW | EPSON_ABACUS_M25140CA.BIN | 0x483D |
| 72h | F107:0423 | F1493h | BIOS_LOW | EPSON_ABACUS_M25140CA.BIN | 0x1493 |
| 73h | F107:0422 | F1492h | BIOS_LOW | EPSON_ABACUS_M25140CA.BIN | 0x1492 |
| 74h | F107:0422 | F1492h | BIOS_LOW | EPSON_ABACUS_M25140CA.BIN | 0x1492 |
| 75h | F107:1D32 | F2DA2h | BIOS_LOW | EPSON_ABACUS_M25140CA.BIN | 0x2DA2 |
| 76h | F107:0422 | F1492h | BIOS_LOW | EPSON_ABACUS_M25140CA.BIN | 0x1492 |
| 77h | F107:3BF5 | F4C65h | BIOS_LOW | EPSON_ABACUS_M25140CA.BIN | 0x4C65 |
| 78h | F107:0422 | F1492h | BIOS_LOW | EPSON_ABACUS_M25140CA.BIN | 0x1492 |
| 79h | F107:3BBF | F4C2Fh | BIOS_LOW | EPSON_ABACUS_M25140CA.BIN | 0x4C2F |
| 7Ah | F107:0422 | F1492h | BIOS_LOW | EPSON_ABACUS_M25140CA.BIN | 0x1492 |
| 7Bh | F107:0422 | F1492h | BIOS_LOW | EPSON_ABACUS_M25140CA.BIN | 0x1492 |
| 7Ch | F107:3BDA | F4C4Ah | BIOS_LOW | EPSON_ABACUS_M25140CA.BIN | 0x4C4A |
| 7Dh | F107:0422 | F1492h | BIOS_LOW | EPSON_ABACUS_M25140CA.BIN | 0x1492 |
| 7Eh | F107:0422 | F1492h | BIOS_LOW | EPSON_ABACUS_M25140CA.BIN | 0x1492 |
| 7Fh | F107:0422 | F1492h | BIOS_LOW | EPSON_ABACUS_M25140CA.BIN | 0x1492 |
| 80h | 0000:0000 | 00000h |  |  |  |
| 81h | 0000:0000 | 00000h |  |  |  |
| 82h | 0000:0000 | 00000h |  |  |  |
| 83h | 0000:0000 | 00000h |  |  |  |
| 84h | 0000:0000 | 00000h |  |  |  |
| 85h | 0000:0000 | 00000h |  |  |  |
| 86h | 0000:0000 | 00000h |  |  |  |
| 87h | 0000:0000 | 00000h |  |  |  |
| 88h | 0000:0000 | 00000h |  |  |  |
| 89h | 0000:0000 | 00000h |  |  |  |
| 8Ah | 0000:0000 | 00000h |  |  |  |
| 8Bh | 0000:0000 | 00000h |  |  |  |
| 8Ch | 0000:0000 | 00000h |  |  |  |
| 8Dh | 0000:0000 | 00000h |  |  |  |
| 8Eh | 0000:0000 | 00000h |  |  |  |
| 8Fh | 0000:0000 | 00000h |  |  |  |
| 90h | 0000:0000 | 00000h |  |  |  |
| 91h | 0000:0000 | 00000h |  |  |  |
| 92h | 0000:0000 | 00000h |  |  |  |
| 93h | 0000:0000 | 00000h |  |  |  |
| 94h | 0000:0000 | 00000h |  |  |  |
| 95h | 0000:0000 | 00000h |  |  |  |
| 96h | 0000:0000 | 00000h |  |  |  |
| 97h | 0000:0000 | 00000h |  |  |  |
| 98h | 0000:0000 | 00000h |  |  |  |
| 99h | 0000:0000 | 00000h |  |  |  |
| 9Ah | 0000:0000 | 00000h |  |  |  |
| 9Bh | 0000:0000 | 00000h |  |  |  |
| 9Ch | 0000:0000 | 00000h |  |  |  |
| 9Dh | 0000:0000 | 00000h |  |  |  |
| 9Eh | 0000:0000 | 00000h |  |  |  |
| 9Fh | 0000:0000 | 00000h |  |  |  |
| A0h | 0000:0000 | 00000h |  |  |  |
| A1h | 0000:0000 | 00000h |  |  |  |
| A2h | 0000:0000 | 00000h |  |  |  |
| A3h | 0000:0000 | 00000h |  |  |  |
| A4h | 0000:0000 | 00000h |  |  |  |
| A5h | 0000:0000 | 00000h |  |  |  |
| A6h | 0000:0000 | 00000h |  |  |  |
| A7h | 0000:0000 | 00000h |  |  |  |
| A8h | 0000:0000 | 00000h |  |  |  |
| A9h | 0000:0000 | 00000h |  |  |  |
| AAh | 0000:0000 | 00000h |  |  |  |
| ABh | 0000:0000 | 00000h |  |  |  |
| ACh | 0000:0000 | 00000h |  |  |  |
| ADh | 0000:0000 | 00000h |  |  |  |
| AEh | 0000:0000 | 00000h |  |  |  |
| AFh | 0000:0000 | 00000h |  |  |  |
| B0h | 0000:0000 | 00000h |  |  |  |
| B1h | 0000:0000 | 00000h |  |  |  |
| B2h | 0000:0000 | 00000h |  |  |  |
| B3h | 0000:0000 | 00000h |  |  |  |
| B4h | 0000:0000 | 00000h |  |  |  |
| B5h | 0000:0000 | 00000h |  |  |  |
| B6h | 0000:0000 | 00000h |  |  |  |
| B7h | 0000:0000 | 00000h |  |  |  |
| B8h | 0000:0000 | 00000h |  |  |  |
| B9h | 0000:0000 | 00000h |  |  |  |
| BAh | 0000:0000 | 00000h |  |  |  |
| BBh | 0000:0000 | 00000h |  |  |  |
| BCh | 0000:0000 | 00000h |  |  |  |
| BDh | 0000:0000 | 00000h |  |  |  |
| BEh | 0000:0000 | 00000h |  |  |  |
| BFh | 0000:0000 | 00000h |  |  |  |
| C0h | 0000:0000 | 00000h |  |  |  |
| C1h | 0000:0000 | 00000h |  |  |  |
| C2h | 0000:0000 | 00000h |  |  |  |
| C3h | 0000:0000 | 00000h |  |  |  |
| C4h | 0000:0000 | 00000h |  |  |  |
| C5h | 0000:0000 | 00000h |  |  |  |
| C6h | 0000:0000 | 00000h |  |  |  |
| C7h | 0000:0000 | 00000h |  |  |  |
| C8h | 0000:0000 | 00000h |  |  |  |
| C9h | 0000:0000 | 00000h |  |  |  |
| CAh | 0000:0000 | 00000h |  |  |  |
| CBh | 0000:0000 | 00000h |  |  |  |
| CCh | 0000:0000 | 00000h |  |  |  |
| CDh | 0000:0000 | 00000h |  |  |  |
| CEh | 0000:0000 | 00000h |  |  |  |
| CFh | 0000:0000 | 00000h |  |  |  |
| D0h | 0000:0000 | 00000h |  |  |  |
| D1h | 0000:0000 | 00000h |  |  |  |
| D2h | 0000:0000 | 00000h |  |  |  |
| D3h | 0000:0000 | 00000h |  |  |  |
| D4h | 0000:0000 | 00000h |  |  |  |
| D5h | 0000:0000 | 00000h |  |  |  |
| D6h | 0000:0000 | 00000h |  |  |  |
| D7h | 0000:0000 | 00000h |  |  |  |
| D8h | 0000:0000 | 00000h |  |  |  |
| D9h | 0000:0000 | 00000h |  |  |  |
| DAh | 0000:0000 | 00000h |  |  |  |
| DBh | 0000:0000 | 00000h |  |  |  |
| DCh | 0000:0000 | 00000h |  |  |  |
| DDh | 0000:0000 | 00000h |  |  |  |
| DEh | 0000:0000 | 00000h |  |  |  |
| DFh | 0000:0000 | 00000h |  |  |  |
| E0h | 0000:0000 | 00000h |  |  |  |
| E1h | 0000:0000 | 00000h |  |  |  |
| E2h | 0000:0000 | 00000h |  |  |  |
| E3h | 0000:0000 | 00000h |  |  |  |
| E4h | 0000:0000 | 00000h |  |  |  |
| E5h | 0000:0000 | 00000h |  |  |  |
| E6h | 0000:0000 | 00000h |  |  |  |
| E7h | 0000:0000 | 00000h |  |  |  |
| E8h | 0000:0000 | 00000h |  |  |  |
| E9h | 0000:0000 | 00000h |  |  |  |
| EAh | 0000:0000 | 00000h |  |  |  |
| EBh | 0000:0000 | 00000h |  |  |  |
| ECh | 0000:0000 | 00000h |  |  |  |
| EDh | 0000:0000 | 00000h |  |  |  |
| EEh | 0000:0000 | 00000h |  |  |  |
| EFh | 0000:0000 | 00000h |  |  |  |
| F0h | 0000:0000 | 00000h |  |  |  |
| F1h | 0000:0000 | 00000h |  |  |  |
| F2h | 0000:0000 | 00000h |  |  |  |
| F3h | 0735:0000 | 07350h |  |  |  |
| F4h | 0732:0731 | 07A51h |  |  |  |
| F5h | 0730:0035 | 07335h |  |  |  |
| F6h | 0742:0730 | 07B50h |  |  |  |
| F7h | 0000:0030 | 00030h |  |  |  |
| F8h | 000C:27C6 | 02886h |  |  |  |
| F9h | 33E5:3639 | 37489h |  |  |  |
| FAh | 0000:C000 | 0C000h |  |  |  |
| FBh | 1D1C:1BF5 | 1EDB5h |  |  |  |
| FCh | 0001:0080 | 00090h |  |  |  |
| FDh | 3317:E000 | 41170h |  |  |  |
| FEh | F246:F107 | 101567h |  |  |  |
| FFh | 03E5:2775 | 065C5h |  |  |  |


## Key Hardware Interrupts

The following BIOS interrupts handle low‑level hardware. Their entry points were resolved from the IVT and then matched back to the BIOS ROM files. Disassembly snippets are included to illustrate their structure.

### INT 05h

- **Purpose:** Print Screen or generic trap. On the IBM PC, INT 5h was tied to the Print Screen key. On the QX‑11 this is repurposed, but still present in the IVT.

- **Vector:** F107:2673 → physical F36E3h

- **ROM file:** EPSON_ABACUS_M25140CA.BIN, offset 0x36E3



### INT 09h

- **Purpose:** Keyboard hardware interrupt (IRQ1). Triggered when a key is pressed or released. On IBM PCs this reads port 60h from the 8042; on the QX‑11 it instead uses Epson gate array ports.

- **Vector:** F107:0112 → physical F1182h

- **ROM file:** EPSON_ABACUS_M25140CA.BIN, offset 0x1182


```
40 2b bf c3 2b f3 a4 e9 27 01 1e 56 57 bf d1 2d 04 30 aa e8 7d 15 aa 3c 0d 74 09 3c 25 75 f4 26 ...
```


### INT 10h

- **Purpose:** Video services. Provides cursor positioning, character/attribute writing, and screen functions.

- **Vector:** F107:0620 → physical F1690h

- **ROM file:** EPSON_ABACUS_M25140CA.BIN, offset 0x1690


```
8b 36 7e 2d 33 ff e8 11 10 ba e3 26 e8 c1 12 b4 36 8a 16 5c 00 cd 21 3d ff ff 74 c4 ba fa 26 e8 ...
```


### INT 13h

- **Purpose:** Disk services. Handles floppy disk reads/writes via the µPD765 FDC through Epson’s GAFDDC gate array.

- **Vector:** F107:3396 → physical F4406h

- **ROM file:** EPSON_ABACUS_M25140CA.BIN, offset 0x4406



### INT 16h

- **Purpose:** Keyboard services (polled). Provides higher‑level routines like 'wait for key' and 'get keystroke'. Built on top of INT 09h’s buffer.

- **Vector:** F107:1CB6 → physical F2D26h

- **ROM file:** EPSON_ABACUS_M25140CA.BIN, offset 0x2D26



## Conclusion

The QX‑11 BIOS follows many IBM PC conventions but with Epson‑specific mappings for I/O ports. The IVT shows clearly that standard INTs (09h, 10h, 13h, 16h) are provided, but the underlying code does not touch PC keyboard controller ports (0x60/0x64). Instead, these routines talk to hardware through Epson’s custom gate array logic. Mapping the IVT against the ROM files provides a roadmap for reverse engineering and MAME driver development.
