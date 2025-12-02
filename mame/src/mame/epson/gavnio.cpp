// license:BSD-3-Clause
// Epson QX-11 GAVNIO – keyboard/floppy I/O gate array

#include "emu.h"
#include "gavnio.h"
#include "gafddc.h"

DEFINE_DEVICE_TYPE(EPSON_GAVNIO, epson_gavnio_device, "epson_gavnio", "Epson QX-11 GAVNIO Gate Array")

//-------------------------------------------------
//  construction
//-------------------------------------------------

epson_gavnio_device::epson_gavnio_device(
        const machine_config &mconfig,
        const char *tag,
        device_t *owner,
        u32 clock)
    : device_t(mconfig, EPSON_GAVNIO, tag, owner, clock)
    , m_irq_to_gavnit(*this)
    , m_kbd_rxd(*this)
    , m_kbd_clk(*this)
{
}

//-------------------------------------------------
//  device_start / reset
//-------------------------------------------------

void epson_gavnio_device::device_start()
{
    // Keyboard serial bit clock
    m_bitclk_timer = timer_alloc(FUNC(epson_gavnio_device::bitclk_cb), this);

    // Save state
    save_item(NAME(m_kbd_txd_level));
    save_item(NAME(m_clk_level));

    save_item(NAME(m_rx_state));
    save_item(NAME(m_rx_shift));
    save_item(NAME(m_rx_bitcount));
    save_item(NAME(m_rx_skip));

    save_item(NAME(m_rx_fifo));
    save_item(NAME(m_rx_head));
    save_item(NAME(m_rx_tail));
    save_item(NAME(m_rx_count));

    save_item(NAME(m_status_sticky));
    save_item(NAME(m_irq_level));

    // TX side
    //save_item(NAME(m_tx_state));
    save_item(NAME(m_tx_shift));
    save_item(NAME(m_tx_bits_remaining));
    save_item(NAME(m_tx_parity_acc));
    save_item(NAME(m_tx_active));
}

void epson_gavnio_device::device_reset()
{
    // RX line levels
    m_kbd_txd_level = 1;
    m_clk_level     = 1;   // idle high

    // RX state
    m_rx_state      = RX_IDLE;
    m_rx_shift      = 0;
    m_rx_bitcount   = 0;
    m_rx_skip       = 0;

    m_rx_head       = 0;
    m_rx_tail       = 0;
    m_rx_count      = 0;

    m_status_sticky = 0;
    m_irq_level     = 0;

    // --- TX reset ---
    m_tx_state          = tx_state::IDLE;
    m_tx_shift          = 0;
    m_tx_bits_remaining = 0;
    m_tx_parity_acc     = 0;
    m_tx_active         = false;

    // Make sure keyboard RX line is idle-high (mark).
    m_kbd_rxd(1);
    m_post_ready = false;

    // Start the keyboard clock – 1200 bps, two phases per bit (high+low).
    const int bitclk_hz = KBD_BAUD * KBD_TICKS_PER_BIT;
    attotime period = attotime::from_hz(bitclk_hz);
    m_bitclk_timer->adjust(period, 0, period);

    recompute_status();
    update_irq_line();
}

//-------------------------------------------------
//  TX host -> keyboard
//-------------------------------------------------

void epson_gavnio_device::start_tx_frame(u8 data)
{
    // Set up state machine for one frame: start + 8 data + parity + stop
    m_tx_state          = tx_state::START;
    m_tx_shift          = data;
    m_tx_bits_remaining = 8;

    // Odd parity: start accumulator at 1 and XOR all data bits.
    m_tx_parity_acc     = 1;
    m_tx_active         = true;

    // Drive start bit immediately (line low), clock will run as usual.
    m_kbd_rxd(0);

    //logerror("GAVNIO: start TX frame %02X\n", data);
}

void epson_gavnio_device::handle_tx_bit()
{
    if (!m_tx_active)
        return;

    switch (m_tx_state)
    {
    case tx_state::START:
        // We already drove the start bit low in start_tx_frame().
        // Just move to DATA on the first sampling edge.
        m_tx_state = tx_state::DATA;
        break;

    case tx_state::DATA:
    {
        // Send least-significant bit first.
        int bit = m_tx_shift & 1;
        m_tx_shift >>= 1;

        // Update odd-parity accumulator
        if (bit)
            m_tx_parity_acc ^= 1;

        m_kbd_rxd(bit ? 1 : 0);

        if (--m_tx_bits_remaining == 0)
            m_tx_state = tx_state::PARITY;
        break;
    }

    case tx_state::PARITY:
    {
        // With accumulator starting at 1 and XORing all '1' bits,
        // the accumulator itself is the odd-parity output bit.
        int parity_bit = (m_tx_parity_acc & 1);
        m_kbd_rxd(parity_bit);
        m_tx_state = tx_state::STOP;
        break;
    }

    case tx_state::STOP:
        // Stop bit is a mark (line high).
        m_kbd_rxd(1);

        // Done with this frame.
        m_tx_state          = tx_state::IDLE;
        m_tx_active         = false;
        m_tx_bits_remaining = 0;
        break;

    case tx_state::IDLE:
    default:
        // Shouldn’t really get here while m_tx_active, but keep line high.
        m_kbd_rxd(1);
        m_tx_active = false;
        m_tx_state  = tx_state::IDLE;
        break;
    }
}

//-------------------------------------------------
//  timer – drive keyboard clock & sample TXD
//-------------------------------------------------

TIMER_CALLBACK_MEMBER(epson_gavnio_device::bitclk_cb)
{
    bit_clock_tick();
}

void epson_gavnio_device::bit_clock_tick()
{
    // Toggle keyboard clock every tick.
    m_clk_level = !m_clk_level;

    // Drive the keyboard port clock line.
    m_kbd_clk(m_clk_level);

    // The keyboard samples TXD on a given edge; we sample RX on the other.
    // Here we choose to sample on the falling edge (clk==0).
    if (!m_clk_level)
    {
        rx_sample_bit(m_kbd_txd_level ? 1 : 0);
        handle_tx_bit();
    }
}

//-------------------------------------------------
//  RX state machine
//-------------------------------------------------

void epson_gavnio_device::rx_sample_bit(int bit)
{
    switch (m_rx_state)
    {
    case RX_IDLE:
        // Waiting for start bit (0) while clock is going low.
        if (!bit)
        {
            m_rx_state    = RX_DATA;
            m_rx_shift    = 0;
            m_rx_bitcount = 0;
            m_rx_skip     = 0;
            // logerror("GAVNIO: RX start bit detected\n");
        }
        break;

    case RX_DATA:
        // 8 data bits, LSB first.
        m_rx_shift |= (bit << m_rx_bitcount);
        m_rx_bitcount++;

        if (m_rx_bitcount >= 8)
        {
            // Push the assembled byte to the FIFO.
            push_rx_byte(m_rx_shift);
            // Now skip parity + stop (2 bits) and return to idle.
            m_rx_state = RX_SKIP;
            m_rx_skip  = 2;
            // logerror("GAVNIO: RX byte=%02X (rx_count=%d)\n", m_rx_shift, m_rx_count);
        }
        break;

    case RX_SKIP:
        // Skip parity and stop bits; after that, look for next start bit.
        if (m_rx_skip > 0)
        {
            m_rx_skip--;
            if (m_rx_skip == 0)
            {
                m_rx_state = RX_IDLE;
            }
        }
        break;

    default:
        m_rx_state = RX_IDLE;
        break;
    }

    recompute_status();
    update_irq_line();
}

void epson_gavnio_device::push_rx_byte(u8 data)
{
    if (m_rx_count >= RX_FIFO_SIZE)
    {
        // Overflow – drop this byte and set sticky flag.
        m_status_sticky |= STAT_OVERRUN;
        logerror("GAVNIO: RX overflow, dropped=%02X\n", data);
        return;
    }

    m_rx_fifo[m_rx_head] = data;
    m_rx_head = (m_rx_head + 1) % RX_FIFO_SIZE;
    m_rx_count++;

    // logerror("GAVNIO: RX push %02X (count=%d)\n", data, m_rx_count);
}

u8 epson_gavnio_device::pop_rx_byte()
{
    if (m_rx_count == 0)
        return 0x00;

    u8 data = m_rx_fifo[m_rx_tail];
    m_rx_tail = (m_rx_tail + 1) % RX_FIFO_SIZE;
    m_rx_count--;

    // logerror("GAVNIO: RX pop %02X (count=%d)\n", data, m_rx_count);
    return data;
}

//-------------------------------------------------
//  status computation / IRQ
//-------------------------------------------------

void epson_gavnio_device::recompute_status()
{
    // Live bits (non-sticky) recomputed on every change.
    u8 stat = 0;

    // TX ready reflects whether we’re in the middle of a host→kbd frame.
    if (!m_tx_active)
        stat |= STAT_TX_READY;

    if (m_rx_count > 0)
        stat |= STAT_RX_READY;

    // Sticky bits (parity, overrun) are ORed in separately.
    stat |= (m_status_sticky & (STAT_PARITY_ERR | STAT_OVERRUN));

    // We don't store 'stat' directly; status_r() recomputes it from live +
    // sticky fields, mirroring this logic. recompute_status() is mainly here
    // so update_irq_line() sees the latest RX-count derived flags.
}

void epson_gavnio_device::update_irq_line()
{
    // INT 75h is raised whenever RX_READY is set.
    const u8 stat = status_r();
    const int new_irq = (stat & STAT_RX_READY) ? 1 : 0;

    if (!m_post_ready)
        logerror("m_post_countdown = %02X, Post ready = %01A\n", m_post_countdown,m_post_ready);
    
        if ((new_irq != m_irq_level) & (m_post_ready == true))
    {
        m_irq_level = new_irq;
        m_irq_to_gavnit(m_irq_level);
        // logerror("GAVNIO: IRQ -> %d\n", m_irq_level);
        logerror("%s: IRQ level=%d  rx_count=%d  sticky=%02X, Post ready=%02x\n",
        tag(), new_irq, m_rx_count, m_status_sticky, m_post_ready);
    }

    //m_post_countdown--;
    //if (m_post_countdown == 0) 
    //        m_post_ready = true;
}

//-------------------------------------------------
//  CPU-visible ports 0x0C / 0x0D
//-------------------------------------------------

u8 epson_gavnio_device::data_r()
{
    // Host reading RX FIFO.
    const u8 data = pop_rx_byte();

    recompute_status();
    update_irq_line();
    

    logerror("GAVNIO: data_r -> %02X (rx_count=%d)\n", data, m_rx_count);
    return data;
}

void epson_gavnio_device::data_w(u8 data)
{
    // Host -> keyboard command (e.g., E0, 80, etc.)
    logerror("GAVNIO: data_w <- %02X (start host->kbd TX)\n", data);

    // If a frame is still in flight, be defensive: drop the new byte.
    // With TX_READY now reflecting m_tx_active, the BIOS *should* poll
    // bit 0 of port 0x0D and avoid this.
    

    if (m_tx_active) 
    {
        logerror("GAVNIO: TX busy, dropping byte %02X\n", data);
        return;
    }

     if (data == 0xC0 || data == 0xC1)
    {
        logerror("%s: GA command %02X (NOT forwarded to keyboard)\n", tag(), data);
        // later we can treat these as GA/FDD commands, but for now just ignore
        return;
    }

    if (data == 0xE0) {
        m_post_ready=true;
        push_rx_byte(0x00);
        push_rx_byte(0x00);
        push_rx_byte(0x00);
        
    }
    start_tx_frame(data);

    // TX status changed, so update status/IRQ view.
    recompute_status();
    update_irq_line();
    
}

u8 epson_gavnio_device::status_r()
{
    // Rebuild the status from live + sticky bits.
    u8 stat = 0;

    if (!m_tx_active)
        stat |= STAT_TX_READY;

    if (m_rx_count > 0)
        stat |= STAT_RX_READY;

    stat |= (m_status_sticky & (STAT_PARITY_ERR | STAT_OVERRUN));

    //logerror("GAVNIO: status_r -> %02X (rx_count=%d sticky=%02X)\n",
    //         stat, m_rx_count, m_status_sticky);

    return stat;
}

void epson_gavnio_device::status_w(u8 data)
{
    // Write-1-to-clear for sticky error bits (parity / overrun).
    if (data & STAT_PARITY_ERR)
        m_status_sticky &= ~STAT_PARITY_ERR;
    if (data & STAT_OVERRUN)
        m_status_sticky &= ~STAT_OVERRUN;

    recompute_status();
    update_irq_line();

    logerror("GAVNIO: status_w <- %02X (sticky now=%02X)\n",
             data, m_status_sticky);
}

//-------------------------------------------------
//  Floppy ports (0x0E/0x0F) – forwarded to GAFDDC
//-------------------------------------------------

u8 epson_gavnio_device::floppy_status_r()
{
    u8 result = 0xff;

    if (m_gafddc)
        result = m_gafddc->status_r();

    //logerror("GAVNIO: floppy_status_r -> %02X\n", result);
    return result;
}

void epson_gavnio_device::floppy_control_w(u8 data)
{
    if (!machine().side_effects_disabled())
        logerror("GAVNIO: floppy_control_w <- %02X\n", data);

    if (m_gafddc)
        m_gafddc->control_w(data);
}

//-------------------------------------------------
//  Keyboard port connections
//-------------------------------------------------

void epson_gavnio_device::kbd_txd_w(int state)
{
    // Keyboard is driving TXD toward the host.
    m_kbd_txd_level = (state != 0);
    //logerror("GAVNIO: kbd_txd_w=%d\n", m_kbd_txd_level);
}
