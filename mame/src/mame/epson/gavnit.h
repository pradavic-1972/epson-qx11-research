// license:BSD-3-Clause
// Epson QX-11 GAVNIT — Event / Interrupt / Timer gate array

#pragma once

#include "device.h"
#include "devcb.h"

class epson_gavnit_device : public device_t
{
public:
    epson_gavnit_device(const machine_config &mconfig, const char *tag, device_t *owner, u32 clock = 0);

    // ----- Timer compare window (ports 00h / 01h) -----
    // These are already used on your QX-11 driver.
    u8  port0_r();                 // read compare LSB
    u8  port1_r();                 // read compare MSB
    void port0_w(u8 data);         // write compare LSB (re-arm)
    void port1_w(u8 data);         // write compare MSB (re-arm)

    // ----- Interrupt mask/control (ports 04h / 05h) -----
    // QX-11 BIOS writes AX to port 4 (16-bit OUT 4,AX).
    // We treat port 04h low byte as "enable bits" for the 8 interrupt lines:
    //   bit = 1 -> IRQ source enabled
    //   bit = 0 -> IRQ source masked
    //
    // Internally we translate: IMR = ~enable_lo (classic 8259-style IMR).
    u8  intmask_lo_r();            // port 04h
    u8  intmask_hi_r();            // port 05h
    void intmask_lo_w(u8 data);    // port 04h
    void intmask_hi_w(u8 data);    // port 05h

    // ----- Interrupt fabric -----
    // Wire this to the CPU INTR line:
    //   m_gavnit->intr_cb().set_inputline(m_maincpu, INPUT_LINE_IRQ0);
    auto intr_cb() { return m_intr_cb.bind(); }

    // Called during INTA: returns the vector for the highest-priority pending line
    int  inta_cb(int irqline = 0);

    // External sources (timer, keyboard, RTC, etc.) call this to set/clear a line (0..15)
    void irq_request(int line, bool state);

    // Convenience wrapper for the keyboard line (line 1 → INT 75h).
    // Edge-triggered: only rising edges create a pending request.
    void keyboard_irq_w(int state);

    // Optional: set per-line vectors (defaults: line0=0x71 timer, line1=0x75 keyboard)
    void set_line_vector(int line, u8 vector);

    // Optional tuning for the internal timer
    void set_fractional_prescale(unsigned num, unsigned den);  // default 5/96
    void set_default_step(u16 step);                           // default 0x0600

    void fdc_intrq_w(int state);
    void rtc_irq_w(int state);

protected:
    void device_start() override;
    void device_reset() override;

private:
    // ---- timer model (00h/01h = compare/deadline latch) ----
    void recalc_base_rate();           // base_hz = clock() * num / den
    void schedule_next_event();        // next IRQ after (step / base_hz)
    void timer_fired();                // raise timer request
    TIMER_CALLBACK_MEMBER(irq_timer_cb);

    // ---- simple interrupt controller ----
    void update_intr_line();           // assert INTR if (IRR & ~IMR) != 0
    int  highest_pending() const;      // 0..15 or -1

    // timer/compare state
    u16 m_compare       = 0x0000;
    u16 m_last_written  = 0x0000;
    u16 m_step          = 0x0600;      // Δ between deadlines
    u16 m_default_step  = 0x0600;

    // fractional prescale (default 5/96): 14.7456 MHz -> 768 kHz.
    // With the default 0x0600 step, this yields the measured 500 Hz INTR rate.
    unsigned m_ps_num   = 5;
    unsigned m_ps_den   = 96;
    double   m_base_hz  = 768'000.0;

    // interrupt bitmaps
    u16 m_irr = 0x0000;                // pending (set by sources)
    u16 m_imr = 0x0000;                // mask: 1 = masked, 0 = enabled
    u16 m_isr = 0x0000;                // in-service (not heavily used yet)

    // mask latches as seen from ports 04h/05h
    u8 m_mask_lo = 0xFF;               // what port 04h reads back
    u8 m_mask_hi = 0xFF;               // what port 05h reads back

    // vectors per line
    u8 m_vector[16] = { 0 };

    // timer + CPU line
    emu_timer *      m_irq_timer     = nullptr;
    devcb_write_line m_intr_cb;

    // keyboard line last level for edge detection
    bool m_kb_last_level = false;

    //upd765 Interrupt
    int m_fdc_intrq = 0;
};

DECLARE_DEVICE_TYPE(EPSON_GAVNIT, epson_gavnit_device)
