# Epson QX-11 ROM Configuration Jumpers and ROMI Expansion

## Overview

During reverse engineering of the Epson QX-11 motherboard, a group of three configuration jumpers was identified near the GAVNMR memory gate array. These jumpers control the ROM capacity expected by the system for the ROMI and ROMID devices.

The export version of the Epson QX-11 normally contains two 32 KB ROM devices:

| ROM | Address Range | Typical Size | Contents |
|------|------|------|------|
| ROMI | E0000h-E7FFFh | 32 KB | MS-DOS ROM |
| ROMID | F0000h-F7FFFh | 32 KB | BIOS |

Investigation of the jumper settings revealed that the motherboard supports multiple ROM configurations.

## Jumper Configuration

Three jumpers were identified. Each jumper provides two selectable positions, labeled **A** and **B**.

### J2 – ROMID Size Selection

This jumper controls the expected size of the BIOS ROM (ROMID).

| Setting | ROMID Size |
|----------|----------|
| Position A | 16 KB |
| Position B | 32 KB |

### J1 – ROMI Size Selection (32 KB / 16 KB)

This jumper controls one aspect of the DOS ROM configuration.

| Setting | ROMI Size |
|----------|----------|
| Position A | 16 KB |
| Position B | 32 KB |

### J3 – ROMI Size Selection (32 KB / 64 KB)

This jumper allows expansion of ROMI beyond the standard configuration.

| Setting | ROMI Size |
|----------|----------|
| Position A | 32 KB |
| Position B | 64 KB |

## ROMI Expansion Experiment

The discovery of Jumper 3 made it possible to replace the original 32 KB ROMI device with a 64 KB EPROM.

By configuring the motherboard for a 64 KB ROMI and installing a larger EPROM, additional software could be stored in ROM while preserving normal system operation.

The original ROMI image already contains COMMAND.COM. The expanded ROM image retains the original ROM contents and adds several useful DOS utilities that would otherwise require a floppy disk.

The following utilities were added to the ROM image:

- FORMAT.COM
- MODE.COM
- FILINK

As a result, the system now provides:

- COMMAND.COM from the original Epson ROM image.
- FORMAT.COM for initializing floppy disks.
- MODE.COM for serial port configuration.
- FILINK for transferring files over a serial connection.

This significantly improves the usability of a restored QX-11, especially when no original system disks are available.

## Practical Benefits

A machine equipped with the expanded ROM can:

- Boot directly into DOS using the original ROM-resident COMMAND.COM.
- Format floppy disks using FORMAT.COM.
- Configure serial communications using MODE.COM.
- Transfer files using FILINK.
- Operate without requiring a ROM cartridge.

This is particularly valuable for systems where original software media is unavailable.

## Japanese QC-11 ROM Capacity Question

Documentation for the Japanese QC-11 variant references a machine equipped with **128 KB of ROM**.

The jumper investigation described above confirms support for:

- 16 KB ROM devices
- 32 KB ROM devices
- 64 KB ROMI devices

However, no jumper configuration has yet been identified that allows ROMID to be expanded from 32 KB to 64 KB.

As a result, the mechanism used by the Japanese 128 KB ROM configuration remains unknown.

Possible explanations include:

- A motherboard revision not yet examined.
- Additional jumper locations elsewhere on the motherboard.
- A different GAVNMR configuration.
- A custom ROM mapping arrangement used only on Japanese systems.

Further investigation is required to determine how the 128 KB ROM configuration was implemented.

## Future Work

Additional reverse engineering should focus on:

1. Identifying any undocumented ROM configuration jumpers.
2. Determining how the Japanese QC-11 implements its reported 128 KB ROM configuration.
3. Understanding the exact role of GAVNMR in ROM size selection and address decoding.
4. Mapping all jumper combinations and documenting their effects.

## Photographs

### ROM Configuration Jumpers

<img width="2252" height="4000" alt="20260520_192505" src="https://github.com/user-attachments/assets/23100a06-9a0c-4e27-8e99-ecf57d1ac6b8" />


### Expanded ROMI Device

*Insert photograph showing the 64 KB ROMI EPROM installed in the system.*

### Modified ROM Image

*Insert screenshot or binary layout of the expanded ROM image containing FORMAT.COM, MODE.COM and FILINK.*
