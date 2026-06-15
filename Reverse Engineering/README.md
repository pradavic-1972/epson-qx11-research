# Epson QX-11 Reverse Engineering Project

This section of the repository contains documentation, hardware analysis, reverse engineering notes, and experimental findings related to the Epson QX-11 / QC-11 computer system.

The goal of this project is to preserve technical knowledge about the QX-11 architecture and document the internal operation of the machine's custom Epson hardware.

The information here comes from:

* real hardware analysis
* oscilloscope measurements
* logic analyzer captures
* ROM disassembly
* PCB tracing
* hardware repairs
* MAME driver development
* experimentation on original systems

---

# System Overview

The Epson QX-11 (Japanese model QC-11) is an 8088-based business computer featuring a highly customized architecture built around several Epson proprietary gate arrays.

Unlike a standard IBM PC design, the QX-11 integrates many hardware functions into custom Epson ICs responsible for:

* memory management
* video generation
* floppy disk control
* interrupt handling
* serial communication
* ROM decoding
* DRAM refresh

---

# Reverse Engineering Articles

## Memory and DRAM Controller

### `GAVEMR.md`

Research and reverse engineering notes for the Epson GAVEMR memory gate array.

Topics include:

* DRAM timing
* DRAM refresh
* ROM decoding
* memory configuration jumpers
* 64K vs 256K DRAM support
* ROM size jumpers
* hardware repair discoveries
* clock input tracing
* suspected internal architecture

---

## Video Hardware

### `GAVDP.md`

Reverse engineering documentation for the GAVDP video gate array.

Topics include:

* video register mapping
* VRAM organization
* 640×400 graphics mode
* hardware scrolling
* display origin registers
* bitmap enable behavior
* column-oriented VRAM layout
* display mode experimentation
* real hardware register observations

---

## Cartridge System

### `Cartridge.md`

Documentation of the QX-11 cartridge system and ROM expansion architecture.

Topics include:

* cartridge memory mapping
* BIOS cartridge detection
* ROM filesystem structure
* address decoding
* bank switching possibilities
* ROM expansion experiments

---

## Hard Drive Interface

### `Hard Drive access EPSON HD-10.md`

Analysis of the Epson HD-10 hard drive subsystem and communication interface.

Topics include:

* external hard drive architecture
* controller communication
* WD controller behavior
* QX-11 interface protocol
* reverse engineering observations
* emulator development ideas

---

## Interrupt Vector Table

### `IVT.md`

Documentation and analysis of the Epson QX-11 Interrupt Vector Table.

Topics include:

* BIOS interrupt mapping
* custom Epson interrupt handlers
* hardware IRQ assignments
* interrupt-driven device behavior
* reverse engineered BIOS vectors

---

# Additional Research Areas

Additional folders and documents may include:

* ROM disassembly notes
* BIOS analysis
* floppy controller behavior
* keyboard protocol research
* expansion bus analysis
* RGB video experiments
* serial port reverse engineering
* memory maps
* oscilloscope captures
* logic analyzer traces

---

# Important Hardware Discoveries

Some major findings from this project include:

* Recovery and repair of a non-booting QX-11 motherboard
* Discovery of ROM size configuration jumpers
* Identification of DRAM type configuration jumpers
* Mapping of GAVEMR DRAM control signals
* Reverse engineering of GAVDP display registers
* Discovery of VRAM scrolling/origin behavior
* Confirmation of separate ROMI and ROMID decode logic
* Analysis of floppy controller communication
* Real hardware validation against MAME emulation

---

# Hardware Used During Research

The reverse engineering work has been performed using:

* original Epson QX-11 hardware
* oscilloscope analysis
* logic analyzers
* TL866II EPROM programmer
* ROM extraction and disassembly
* MAME source modifications
* custom hardware adapters

---

# Project Goals

The long-term goals of this project include:

* preserving technical information about the QX-11
* documenting Epson proprietary hardware
* improving emulation accuracy
* developing recovery tools
* enabling hardware repairs
* creating expansion hardware
* understanding undocumented system behavior

---

# Repository

Main repository:

```text id="8d2gbf"
https://github.com/pradavic-1972/epson-qx11-research
```

---

# Disclaimer

This documentation is based on reverse engineering and experimentation performed on real hardware.

Some conclusions remain theoretical and may evolve as additional discoveries are made.

Contributions, corrections, and additional hardware information are welcome.
