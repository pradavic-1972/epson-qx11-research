// license:BSD-3-Clause
// Epson QX-11 GAVNIO – Keyboard/Floppy I/O Gate Array
// - Drives keyboard serial clock (host → keyboard)
// - Deserialises keyboard bit stream (keyboard → host)
// - Exposes ports 0x0C (data) and 0x0D (status) for keyboard
// - Forwards 0x0E/0x0F to the floppy gate array (GAFDDC)
// - Raises INT 75h via GAVNIT when keyboard data is available

#ifndef MAME_EPSON_GAVNIO_H
#define MAME_EPSON_GAVNIO_H

#pragma once

#include "device.h"
#include "devcb.h"

class emu_timer;

class epson_gafddc_device;

class epson_gavnio_device : public device_t
{
public:
    epson_gavnio_device(const machine_config &mconfig, const char *tag, device_t *owner, u32 clock = 0);

    // I/O visible to the CPU
    // 0x0C – keyboard data
    u8  data_r();          // IN  AL,0Ch
    void data_w(u8 data);  // OUT 0Ch,AL (host→keyboard commands)

    // 0x0D – keyboard status
    u8  status_r();        // IN  AL,0Dh
    void status_w(u8 data); // OUT 0Dh,AL (write-1-to-clear sticky bits)

    // 0x0E – floppy status (via GAFDDC)
    u8  floppy_status_r();     // IN  AL,0Eh

    // 0x0F – floppy control (via GAFDDC)
    void floppy_control_w(u8 data); // OUT 0Fh,AL

    // Connect our IRQ output to GAVNIT (line mapped to INT 75h)
    auto irq_to_gavnit() { return m_irq_to_gavnit.bind(); }

    // Bit-serial interface to the QX-10/QX-11 keyboard port:
    //  - kbd_txd_w is called by the keyboard port when the keyboard drives TXD
    //  - kbd_rxd_cb / kbd_clk_cb are used by the machine config to wire our
    //    RXD/CLK outputs into the keyboard port device.
    void kbd_txd_w(int state);
    auto kbd_rxd_cb() { return m_kbd_rxd.bind(); }
    auto kbd_clk_cb() { return m_kbd_clk.bind(); }

    // Wire up the floppy gate array
    void set_gafddc(epson_gafddc_device *gafddc) { m_gafddc = gafddc; }

protected:
    virtual void device_start() override;
    virtual void device_reset() override;

    // Timer: drives the keyboard clock line and samples TXD
    TIMER_CALLBACK_MEMBER(bitclk_cb);

private:
    // ----- constants -----
    // Keyboard line: 1200 bps, 11-bit frame (1 start, 8 data, parity, stop).
    static constexpr int KBD_BAUD          = 1200;
    static constexpr int KBD_TICKS_PER_BIT = 2;     // host transitions per bit (high + low)

    // Give the FIFO a bit more headroom so we don't stall if INTs are
    // masked for a while (e.g. during floppy I/O).
    static constexpr int RX_FIFO_SIZE      = 64;

    // Status bits exposed on 0x0D
    static constexpr u8 STAT_TX_READY   = 0x01; // host can write a command (0 when TX busy)
    static constexpr u8 STAT_RX_READY   = 0x02; // at least one byte in RX FIFO
    static constexpr u8 STAT_ATTENTION  = 0x04; // unused for now
    static constexpr u8 STAT_PARITY_ERR = 0x08; // sticky (not currently used)
    static constexpr u8 STAT_OVERRUN    = 0x10; // sticky

    // RX state machine
    static constexpr u8 RX_IDLE = 0;
    static constexpr u8 RX_DATA = 1;
    static constexpr u8 RX_SKIP = 2;  // skip parity + stop bits

    // --- TX from host -> keyboard ---
    // 1200 bps, start + 8 data bits (LSB first) + odd parity + stop
    enum class tx_state : u8
    {
        IDLE = 0,
        START,
        DATA,
        PARITY,
        STOP
    };

    // ----- helpers -----
    void bit_clock_tick();        // called from timer – toggles CLK and samples TXD
    void rx_sample_bit(int bit);  // one serial bit from keyboard
    void push_rx_byte(u8 data);   // push byte into RX FIFO (may drop on overflow)
    u8   pop_rx_byte();           // pop byte from RX FIFO (returns 0 if empty)
    void recompute_status();      // recompute live status bits
    void update_irq_line();       // raise/lower IRQ toward GAVNIT

    void start_tx_frame(u8 data); // begin one host→kbd frame
    void handle_tx_bit();         // advance host→kbd TX state machine one bit time

    // ----- timers -----
    emu_timer *m_bitclk_timer = nullptr;

    // ----- callbacks -----
    devcb_write_line m_irq_to_gavnit;
    devcb_write_line m_kbd_rxd;
    devcb_write_line m_kbd_clk;

    // ----- attached devices -----
    epson_gafddc_device *m_gafddc = nullptr;

    // ----- keyboard serial input (from keyboard TXD) -----
    int  m_kbd_txd_level = 1; // idle = 1
    int  m_clk_level     = 1; // idle high as per doc (“clock goes down” for bit)

    // ----- RX state machine -----
    u8   m_rx_state      = RX_IDLE;
    u8   m_rx_shift      = 0;
    u8   m_rx_bitcount   = 0;
    u8   m_rx_skip       = 0;     // how many bits left to skip (parity + stop)

    // ----- FIFO for bytes presented to the host -----
    u8 m_rx_fifo[RX_FIFO_SIZE]{};
    u8 m_rx_head    = 0;
    u8 m_rx_tail    = 0;
    u8 m_rx_count   = 0;

    // ----- sticky / computed status -----
    u8  m_status_sticky = 0; // PARITY_ERR / OVERRUN
    int m_irq_level     = 0; // cached level sent to GAVNIT

    // ----- TX host -> keyboard state -----
    tx_state m_tx_state          = tx_state::IDLE;
    u8       m_tx_shift          = 0x00;
    int      m_tx_bits_remaining = 0;
    u8       m_tx_parity_acc     = 0;   // running parity accumulator
    bool     m_tx_active         = false;   // true while we’re in a frame
    bool     m_post_ready   = false;
    int      m_post_countdown = 255;
};

DECLARE_DEVICE_TYPE(EPSON_GAVNIO, epson_gavnio_device)

#endif // MAME_EPSON_GAVNIO_H
