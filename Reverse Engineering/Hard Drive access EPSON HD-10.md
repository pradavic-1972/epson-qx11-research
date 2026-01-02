# Epson QX-11 Hard Disk Interface (HD-10)  
## Reverse-Engineering Notes and Protocol Description

This document describes the Epson QX-11 hard disk interface as implemented by the **HD-10 hard disk unit**, based on BIOS reverse-engineering, logic analysis, and a working MAME implementation.

The goal of this work was **not** to guess a protocol, but to observe what the QX-11 BIOS actually does and implement *only* what it expects.

---

## Executive Summary

* The Epson QX-11 hard disk interface is **not IDE, not Shugart, and not modern SCSI**
* It most closely matches a **SASI Class-0, host-driven protocol**
* Communication is done through **three I/O ports**:
  * **Port 80h** – Data
  * **Port 81h** – Status / Phase
  * **Port 82h** – Command strobe
* Commands are **6-byte Command Descriptor Blocks (CDBs)**
* Data transfer is **CPU-driven**, byte-by-byte
* No arbitration, no DMA, no interrupts
* The BIOS performs **strict phase checking** — incorrect status codes abort commands

This behavior aligns with **early SASI (pre-SCSI-1)** controllers such as those based on the WD1015.

---

## Why This Is SASI-Like (But Not Modern SCSI)

The protocol observed matches **SASI Class-0** characteristics:

| Feature | QX-11 HD-10 | SASI Class-0 |
|------|------------|-------------|
| Bus arbitration | ❌ No | ❌ No |
| Initiators | 1 | 1 |
| CDB length | 6 bytes | 6 bytes |
| DMA | ❌ No | ❌ Optional |
| Handshake | CPU polling | REQ/ACK |
| Command set | READ / WRITE / INIT | Same |

However:

* Signals are **latched and multiplexed** into ports
* There is **no exposed REQ/ACK line**
* Status bits are **encoded**, not direct wire states

Therefore, this is best described as:

> **A SASI-derived, Epson-specific host protocol**

---

## I/O Port Overview

### Port 80h — Data Port
* Bidirectional
* Used for:
  * Sending command bytes
  * Sending parameter blocks
  * Reading sector data
  * Writing sector data
  * Reading result bytes

---

### Port 81h — Status / Phase Port
Read and write semantics differ.

#### Read behavior
The BIOS polls this port heavily. Returned values encode the **current phase**.

| Value | Meaning |
|----|--------|
| `00h` | Idle / ACK / Probe response |
| `0Dh` | Ready to receive command frame |
| `09h` | Ready to receive parameter or write data |
| `0Bh` | Read data available |
| `0Fh` | Result byte 0 ready |
| `1Fh` | Result byte 1 ready |

> **Important:**  
> The BIOS often shifts the returned value right by one bit.  
> For example, `0Bh >> 1 = 05h`, which is what the BIOS compares against.

This is why returning **`0Bh` for READ** is required.

#### Write behavior
Writing *any value* to port 81h is interpreted as:

* **Abort current transaction**
* **Probe / wake-up sequence**

Immediately following this, an `IN 81h` must return `00h`.

---

### Port 82h — Command Strobe
This port finalizes command submission.

Sequence:
1. `OUT 80h, <prefix>`
2. `OUT 82h, <same prefix>`

This transitions the device into **command frame receive mode**.

---

## Command Lifecycle

### 1. Probe / Reset
OUT 81h, xx
IN 81h → 00h
Resets all internal state.
---
### 2. Command Start
OUT 80h, <prefix>
OUT 82h, <prefix>
---
### 3. Command Frame (6 bytes)
OUT 80h, OP
OUT 80h, A2
OUT 80h, A1
OUT 80h, A0
OUT 80h, COUNT
OUT 80h, MAGIC

Where:

* Address is **24-bit**
* COUNT = number of 512-byte sectors
* COUNT = 0 → 256 sectors (SASI convention)

---

### 4. Post-Frame ACK
Immediately after the 6th byte:
IN 81h → 00h (exactly once)

Failure to return `00h` here aborts the command.

---

## Implemented Commands

### READ (08h / E5h)

**Observed frame example**
08 00 00 00 01 45

**Behavior**
1. BIOS polls `IN 81h` until `0Bh` (→ `05h`)
2. BIOS performs 512 × COUNT reads from port 80h
3. No final `0F/1F` phase — data phase ends command

**Important**
* Returning `0Fh` or `1Fh` during READ **breaks the BIOS**
* READ must transition **directly** into data streaming

---

### WRITE (0Ah / E6h)

Same as READ, but reversed direction.

**Behavior**
1. BIOS polls `IN 81h` until `09h`
2. BIOS writes 512 × COUNT bytes to port 80h
3. After final byte, command ends

---

### INITIALIZE / RESET (0Ch)

**Observed behavior**
* After command frame, BIOS sends **8 parameter bytes**
* BIOS polls `IN 81h == 09h` before each byte
* Final phase includes result bytes

Example parameter tail observed:

**Behavior**
1. BIOS polls `IN 81h` until `0Bh` (→ `05h`)
2. BIOS performs 512 × COUNT reads from port 80h
3. No final `0F/1F` phase — data phase ends command

**Important**
* Returning `0Fh` or `1Fh` during READ **breaks the BIOS**
* READ must transition **directly** into data streaming

---

### WRITE (0Ah / E6h)

Same as READ, but reversed direction.

**Behavior**
1. BIOS polls `IN 81h` until `09h`
2. BIOS writes 512 × COUNT bytes to port 80h
3. After final byte, command ends

---

### INITIALIZE / RESET (0Ch)

**Observed behavior**
* After command frame, BIOS sends **8 parameter bytes**
* BIOS polls `IN 81h == 09h` before each byte
* Final phase includes result bytes

Example parameter tail observed:
... 80 00 80 0B


The meaning of these parameters is not yet fully decoded.

---

## Result Phase (0Fh / 1Fh)

Only used for commands that **explicitly expect results** (e.g., INIT).

Sequence:
IN 81h → 0Fh
IN 80h → R0

IN 81h → 1Fh
IN 80h → R1

READ and WRITE **must not** enter this phase.

---

## Key Reverse-Engineering Lessons

1. **There is no universal “end phase”**
   * Each command has its own termination behavior

2. **Returning the wrong status value immediately aborts commands**
   * BIOS is extremely strict

3. **READ/WRITE bypass result phases entirely**
   * Data streaming *is* the command completion

4. **Port 81h values are encoded, not literal**
   * Always consider BIOS bit-shifting

5. **This is not blind guessing**
   * Every implemented behavior corresponds to BIOS-observed sequences

---

## Current Implementation Status

✔ Commands decoded  
✔ Sector reads working  
✔ Sector writes functional in memory  
✔ Image-backed storage supported  
✔ BIOS boot sector validation passes  

Remaining work:
* Parameter block semantics for INIT
* Geometry reporting
* Error code mapping
* Optional multi-drive support

---

## Conclusion

The Epson QX-11 hard disk interface is a **clean, early-1980s SASI-derived design** optimized for a single drive and simple firmware.

Understanding it required:
* BIOS disassembly
* Cycle-accurate logging
* Strict phase modeling
* Rejecting modern SCSI assumptions

This document captures the **actual protocol**, not a guessed one.

---

*Victor Prada – QX-11 Reverse Engineering Project*
