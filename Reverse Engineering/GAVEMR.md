# Epson QX-11 GAVEMR Gate Array Documentation

## Overview

The **GAVEMR** is one of the main custom gate arrays used in the Epson QX-11 / QC-11 computer system. Based on hardware tracing, reverse engineering, and real hardware behavior, the GAVEMR appears to be responsible for:

* DRAM control
* DRAM refresh generation
* ROM decoding
* Memory timing
* Bus arbitration
* Wait-state generation
* Memory configuration

The GAVEMR is likely equivalent in function to the **GAPNMD** gate array used in the Epson PX-4.

---

# Known Part Numbers

| System        | Gate Array      | Part Number |
| ------------- | --------------- | ----------- |
| QX-11 / QC-11 | GAVEMR / GAVNMR | E01038EA    |
| PX-4          | GAPNMD          | E01035EA    |

---

# Hardware Connections

## CPU Address Bus Inputs

The GAVEMR directly monitors the 8088 CPU address bus.

| 8088 Signal | GAVEMR Pin |
| ----------- | ---------- |
| A14         | 74         |
| A13         | 75         |
| A12         | 76         |
| A11         | 77         |
| A10         | 78         |
| A9          | 79         |
| A8          | 80         |
| A16/S3      | 68         |
| A17/S4      | 69         |
| A18/S5      | 70         |
| A19/S6      | 71         |
| ALE         | 57         |

This confirms the GAVEMR participates directly in memory decoding and timing.

---

# Data Bus Connections

The GAVEMR is also connected to the CPU data bus.

| GAVEMR Pin | Function |
| ---------- | -------- |
| 4–11       | D0–D7    |

---

# DRAM Control Signals

The GAVEMR generates the DRAM timing signals.

| GAVEMR Pin | Function |
| ---------- | -------- |
| 26         | WE       |
| 27         | RAS      |
| 28         | CAS      |

Additional traced connections:

| GAVEMR Pin | DRAM Pin     |
| ---------- | ------------ |
| 21         | DRAM address |
| 22         | DRAM address |
| 23         | DRAM address |

This confirms the GAVEMR performs multiplexed DRAM addressing.

---

# Clock Input

The system crystal oscillator feeds directly into the GAVEMR.

```text
14.7456 MHz Crystal
        ↓
TC40H004 Oscillator/Inverter
        ↓
GAVEMR Pin 35
```

The GAVEMR likely derives internal memory timing from this master clock.

---

# ROM Control

The GAVEMR directly controls ROM chip selection.

| GAVEMR Pin | Destination |
| ---------- | ----------- |
| 1          | ROMI /OE    |
| 2          | ROMI /CE    |
| 3          | ROMID /CE   |

Additional observation:

* ROMID /OE is permanently tied to GND.

This indicates the GAVEMR performs the ROM address decoding internally.

---

# ROM Configuration Jumpers

Three jumpers near the GAVEMR configure ROM size support.

| Jumper | Function        |
| ------ | --------------- |
| J1     | ROMID 16K / 32K |
| J2     | ROMI 16K / 32K  |
| J3     | ROMI 32K / 64K  |

The jumpers reroute ROM address lines, allowing multiple [ROM sizes](rom_expansion.md) to be installed.

---

# DRAM Configuration

The QX-11 motherboard supports multiple DRAM configurations.

Observed behavior:

* 512 KB installed RAM
* Jumper Position A → system reports 128 KB
* Jumper Position B → system reports 512 KB

Installed DRAMs:

* 16 × 50256 / 4256-class DRAM chips

This suggests the GAVEMR supports multiple DRAM organization modes.

---

# DRAM Refresh

The GAVEMR almost certainly generates DRAM refresh cycles internally.

Evidence:

* Dedicated RAS/CAS outputs
* No separate DRAM controller IC present
* Direct master clock input
* Multiplexed DRAM addressing logic

The refresh mechanism has not yet been fully characterized.

Possible refresh methods:

* Distributed refresh
* Burst refresh
* CAS-before-RAS refresh

Future oscilloscope analysis of DRAM RAS/CAS timing should confirm the implementation.

---

# Real Hardware Repair Discovery

One major hardware failure was traced directly to the GAVEMR ROM decode path.

## Failure

Broken connection:

```text
GAVEMR → ROMID /CE
```

Result:

* System would not boot.

## Temporary Hardware Repair

A workaround was implemented using:

* 74LS00 NAND gates
* Existing ROMI control signals

This recreated the missing ROM chip enable logic and restored successful system boot.

This confirmed the GAVEMR is directly responsible for ROM decode control.

---

# Suspected Internal Responsibilities

The GAVEMR likely combines the functionality of several standard IBM PC support chips into a single Epson custom gate array.

Probable functions include:

* DRAM controller
* DRAM refresh generator
* Memory address decoder
* Wait-state generator
* ROM mapper
* Bus arbitration
* Video memory timing coordination

---

# Comparison to IBM PC Architecture

The GAVEMR appears to replace functions normally handled by several discrete IBM PC support chips.

Approximate equivalents:

| IBM PC Function      | GAVEMR     |
| -------------------- | ---------- |
| 8284 clock support   | Integrated |
| DRAM controller      | Integrated |
| Refresh generator    | Integrated |
| Address decode logic | Integrated |
| Wait-state logic     | Integrated |

---

# Outstanding Unknowns

Several aspects of the GAVEMR remain unresolved:

* Exact DRAM refresh timing
* CPU wait-state generation
* Memory arbitration behavior
* Video/CPU memory contention
* Internal clock division
* Full memory map decode behavior

Further reverse engineering and oscilloscope analysis are required.

---

# Current Understanding

The GAVEMR is likely the central memory-management device of the Epson QX-11 architecture and one of the most important custom ICs in the system.

It coordinates:

* CPU memory access
* DRAM timing
* ROM selection
* refresh generation
* system memory configuration

without relying on standard Intel support chipsets.

This highly integrated design reduced component count and allowed Epson to implement a custom memory architecture around the 8088 CPU.
