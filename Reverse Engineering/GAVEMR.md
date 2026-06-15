# Epson QX-11 GAVEMR Gate Array and DRAM Configuration Research

## Overview

The Epson QX-11 / QC-11 uses several custom Epson gate arrays to implement functions normally handled by multiple standard support chips in contemporary IBM PC systems.

One of the most important of these devices is the **GAVEMR** memory gate array.

Based on hardware tracing, reverse engineering, oscilloscope analysis, and real hardware experiments, the GAVEMR appears to be responsible for:

* DRAM control
* DRAM refresh generation
* ROM decoding
* Memory timing
* Bus arbitration
* Wait-state generation
* Memory configuration

The GAVEMR is likely functionally related to the **GAPNMD** gate array used in the Epson PX-4 portable computer.

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

This confirms the GAVEMR participates directly in:

* memory decoding
* memory timing
* system memory arbitration

---

# Data Bus Connections

The GAVEMR is also connected directly to the CPU data bus.

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

| GAVEMR Pin | DRAM Function |
| ---------- | ------------- |
| 21         | DRAM address  |
| 22         | DRAM address  |
| 23         | DRAM address  |

This confirms the GAVEMR performs multiplexed DRAM addressing internally.

---

# Clock Input

The system crystal oscillator feeds directly into the GAVEMR.

```text id="y7swyo"
14.7456 MHz Crystal
        ↓
TC40H004 Oscillator/Inverter
        ↓
GAVEMR Pin 35
```

The GAVEMR likely derives all DRAM timing and refresh timing from this master clock source.

---

# ROM Control

The GAVEMR directly controls ROM selection.

| GAVEMR Pin | Destination |
| ---------- | ----------- |
| 1          | ROMI /OE    |
| 2          | ROMI /CE    |
| 3          | ROMID /CE   |

Additional observation:

* ROMID /OE is permanently tied to GND.

This confirms the GAVEMR performs the ROM address decoding internally.

---

# ROM Configuration Jumpers

Three jumpers located near the GAVEMR configure [ROM size support](rom_expansion.md).

| Jumper | Function        |
| ------ | --------------- |
| J1     | ROMID 16K / 32K |
| J2     | ROMI 16K / 32K  |
| J3     | ROMI 32K / 64K  |

These jumpers reroute ROM address lines and allow the motherboard to support multiple ROM sizes.

---

# DRAM Configuration Jumpers

A second set of jumpers near the GAVEMR appears to configure the installed DRAM type [PICTURE](photos/DRAM_TYPE.jpg).

This discovery was made during testing of a QX-11 system populated with:

```text id="ez1g8z"
16 × 50256 / 41256-class DRAM chips
```

The installed memory capacity was physically:

```text id="95ey4j"
512 KB
```

---

# Observed Behavior

Two jumper configurations were tested.

## Position A

When the jumper was placed in Position A:

```text id="9j6kuy"
System reports 128 KB RAM
```

---

## Position B

When the jumper was placed in Position B:

```text id="s4mjlwm"
System reports 512 KB RAM
```

No DRAM chips were changed during testing.

Only the jumper position was modified.

This strongly indicates the jumper changes the memory controller configuration inside the GAVEMR itself.

---

# Installed DRAM Type

The installed DRAMs are compatible with:

| DRAM Family | Organization |
| ----------- | ------------ |
| 41256       | 256K × 1     |
| HM50256     | 256K × 1     |
| TMS4256     | 256K × 1     |

Total memory calculation:

```text id="6wluq5"
16 × 256K bits
= 4096K bits
= 512 KB
```

which matches the detected RAM in Position B.

---

# Probable DRAM Support Modes

The observed behavior strongly suggests the motherboard was designed to support two different DRAM generations.

| Jumper Position | DRAM Type | Total RAM |
|---|---|
| Position A | 4164 / 64K×1 | 128 KB |
| Position B | 41256 / 256K×1 | 512 KB |

This was a very common upgrade strategy in mid-1980s computer systems.

---

# Why 4164 DRAM Makes Sense

If Position A configures the system for:

```text id="4rcsht"
16 × 64K × 1 DRAMs
```

then total RAM becomes:

```text id="jcyh7y"
16 × 64K bits
= 1024K bits
= 128 KB
```

which exactly matches the observed POST memory count.

This is currently the strongest evidence that:

* Position A selects 64K DRAM mode
* Position B selects 256K DRAM mode

inside the GAVEMR.

---

# What the Jumpers Likely Change

The jumpers probably alter several internal GAVEMR behaviors simultaneously.

Possible changes include:

* row address width
* column address width
* refresh row count
* DRAM multiplexing geometry
* memory bank decoding
* POST memory sizing logic

---

# Address Geometry Differences

## 4164 DRAM

Typical geometry:

```text id="9qyb7o"
7-bit row
7-bit column
128 refresh rows
```

---

## 41256 DRAM

Typical geometry:

```text id="viy5m4"
8-bit row
8-bit column
256 refresh rows
```

The jumper likely informs the GAVEMR:

* how many row bits to generate
* how many refresh rows exist
* how high memory addresses should be decoded

---

# DRAM Refresh

The GAVEMR almost certainly generates DRAM refresh internally.

Evidence includes:

* dedicated RAS/CAS outputs
* direct master clock input
* absence of discrete DRAM controller ICs
* multiplexed DRAM addressing

Possible refresh methods:

* distributed refresh
* burst refresh
* CAS-before-RAS refresh

Future oscilloscope analysis of:

* RAS
* CAS
* CPU READY

should reveal the exact implementation.

---

# Real Hardware Repair Discovery

One major hardware fault was traced directly to the GAVEMR ROM decode path.

## Failure

Broken connection:

```text id="m1l27i"
GAVEMR → ROMID /CE
```

Result:

```text id="v6w4fd"
System would not boot
```

---

# Temporary Hardware Repair

A workaround was implemented using:

* 74LS00 NAND gates
* existing ROMI control signals

This recreated the missing ROM enable logic and restored successful boot operation.

This confirmed the GAVEMR directly generates ROM chip-enable signals.

---

# Comparison to IBM PC Architecture

The GAVEMR appears to replace the functionality normally handled by several discrete IBM PC support chips.

Approximate equivalents:

| IBM PC Function      | GAVEMR     |
| -------------------- | ---------- |
| Clock support logic  | Integrated |
| DRAM controller      | Integrated |
| Refresh generator    | Integrated |
| Address decode logic | Integrated |
| Wait-state logic     | Integrated |

This highly integrated design reduced component count and gave Epson substantial flexibility in system configuration.

---

# Current Best Theory

The current evidence strongly suggests the GAVEMR is the central memory-management device of the QX-11 architecture.

It likely coordinates:

* CPU memory access
* DRAM timing
* DRAM refresh
* ROM mapping
* wait-state insertion
* memory configuration
* bank decoding

without relying on standard Intel support chipsets.

The DRAM jumpers appear to configure the internal operating mode of the GAVEMR itself, allowing the same motherboard design to support both:

* 64K DRAM systems
* 256K DRAM systems

using only jumper changes.

---

# Remaining Unknowns

Several aspects remain unresolved:

* exact jumper-to-pin mapping
* full refresh timing implementation
* CPU wait-state generation
* memory arbitration behavior
* exact bank decode logic
* possible support for additional DRAM densities

Further reverse engineering and oscilloscope analysis will be required.
