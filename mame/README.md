# Epson QX-11 – MAME Driver Development Summary

This project recreates the Epson **QX-11** hardware inside **MAME**, including **four of its five custom gate arrays**:

- **GAVNIO** – I/O gate array  
- **GAVNIT** – Interrupt & Timer gate array  
- **GAFDDC** – Floppy Drive Control gate array  
- **GAVDP** – Video Display Processor gate array  

The only gate array not modeled:

- **GAVNMR** – Believed to perform **DRAM refresh / memory timing** and not required for functional emulation.

This driver includes working video, keyboard, floppy, timer, RTC, sound, DIP switch logic, and correct interrupt behavior.

---

# Gate Arrays Implemented

## ✔ GAVNIO – I/O Gate Array

Provides the BIOS-facing **command/status interface** and handles the **serial keyboard protocol**.

### Responsibilities (confirmed)
- Shift-in logic for the 1200-bps synchronous serial keyboard  
- Data/command interface via ports **0x0C / 0x0D**  
- Sends completed keyboard bytes to GAVNIT  

### Ports
- **0x0C** – GAVNIO command/data  
- **0x0D** – GAVNIO status  

GAVNIO does **not** provide paging for video, RTC, or CRTC; those appear at fixed ports.

---

## ✔ GAVNIT – Interrupt & Timer Gate Array

Central interrupt controller and periodic timer engine.

### Interrupts Raised
- **INT 71h** – 50 Hz system timer tick  
- **INT 75h** – keyboard byte ready  
- **INT 70h** – shutdown / power-off  

### Ports (confirmed + working theory)
- **0x04** – Interrupt latch (read) / IRQ mask or control (write – hypothesis)  
- **0x05** – Additional interrupt/peripheral mask (hypothesis)  

### Timer Deadline Mechanism (Ports 0x00 / 0x01)

The QX-11 uses a **16-bit deadline/compare timer**:

- **0x00** – LSB  
- **0x01** – MSB  

#### How INT 71h works
1. BIOS reads the current deadline from ports 0x00/0x01.  
2. BIOS adds a fixed offset (e.g., +0x0600).  
3. BIOS writes the new deadline to ports 0x00/0x01.  
4. BIOS updates tick counters and returns.  

The tim
