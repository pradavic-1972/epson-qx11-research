// license:BSD-3-Clause
// Epson QX-11 GAVNIT — Event / Interrupt / Timer gate array

#include "emu.h"
#include "gavnit.h"

DEFINE_DEVICE_TYPE(EPSON_GAVNIT, epson_gavnit_device, "epson_gavnit", "Epson QX-11 GAVNIT (Event/Interrupt/Timer)")

//-------------------------------------------------
//  ctor
//-------------------------------------------------

epson_gavnit_device::epson_gavnit_device(
        const machine_config &mconfig,
        const char *tag,
        device_t *owner,
        u32 clock)
    : device_t(mconfig, EPSON_GAVNIT, tag, owner, clock)
    , m_intr_cb(*this)
{
}

//-------------------------------------------------
//  device_start
//-------------------------------------------------

void epson_gavnit_device::device_start()
{
    save_item(NAME(m_compare));
    save_item(NAME(m_last_written));
    save_item(NAME(m_step));
    save_item(NAME(m_default_step));
    save_item(NAME(m_ps_num));
    save_item(NAME(m_ps_den));
    save_item(NAME(m_base_hz));
    save_item(NAME(m_irr));
    save_item(NAME(m_imr));
    save_item(NAME(m_isr));
    save_item(NAME(m_mask_lo));
    save_item(NAME(m_mask_hi));
    save_item(NAME(m_vector));
    save_item(NAME(m_kb_last_level));

    save_item(NAME(m_fdc_intrq));

    // default vectors: 0 = timer INT71h, 1 = keyboard INT75h
    m_vector[0] = 0x71;
    m_vector[1] = 0x75;
    for (int i = 2; i < 8; ++i)
        m_vector[i] = 0x70 + i;    // placeholders for now

    // default mask: everything enabled
    m_mask_lo = 0xFF;
    m_mask_hi = 0xFF;
    m_imr     = 0x00;              // 1 = masked, so 0 means all enabled

    recalc_base_rate();

    m_irq_timer = timer_alloc(FUNC(epson_gavnit_device::irq_timer_cb), this);
    schedule_next_event();
}

//-------------------------------------------------
//  device_reset
//-------------------------------------------------

void epson_gavnit_device::device_reset()
{
    m_compare       = 0x0000;
    m_last_written  = 0x0000;
    m_step          = m_default_step;

    // keep mask as configured by BIOS – don't clobber it on reset()
    m_irr           = 0x00;
    m_isr           = 0x00;
    m_kb_last_level = false;

    m_fdc_intrq = 0;

    update_intr_line();
    schedule_next_event();
}

//-------------------------------------------------
//  timer base rate
//-------------------------------------------------

void epson_gavnit_device::recalc_base_rate()
{
    if (!m_ps_den)
    {
        m_base_hz = 0.0;
        return;
    }

    m_base_hz = double(clock()) * double(m_ps_num) / double(m_ps_den);
}

//-------------------------------------------------
//  schedule_next_event
//-------------------------------------------------

void epson_gavnit_device::schedule_next_event()
{
    if (!m_irq_timer)
        return;

    if (m_base_hz <= 0.0 || m_step == 0)
    {
        m_irq_timer->enable(false);
        return;
    }

    const attotime dt = attotime::from_double(double(m_step) / m_base_hz);
    m_irq_timer->adjust(dt);
}

//-------------------------------------------------
//  timer_fired – periodic INT 71h request
//-------------------------------------------------

void epson_gavnit_device::timer_fired()
{
    // Line 0 is the periodic timer (INT 71h).
    m_irr |= 0x01;
    update_intr_line();

    // Move compare forward so the BIOS sees the current deadline
    m_compare = m_compare + m_step;

    schedule_next_event();
}

TIMER_CALLBACK_MEMBER(epson_gavnit_device::irq_timer_cb)
{
    timer_fired();
}

//-------------------------------------------------
//  interrupt controller core
//-------------------------------------------------

void epson_gavnit_device::update_intr_line()
{
    const bool any = (m_irr & ~m_imr) != 0;
    m_intr_cb(any ? 1 : 0);
}

int epson_gavnit_device::highest_pending() const
{
    u8 cand = (m_irr & ~m_imr);
    for (int i = 0; i < 8; ++i)
        if (cand & (1 << i))
            return i;
    return -1;
}

int epson_gavnit_device::inta_cb(int)
{
    int line = highest_pending();
    if (line < 0)
    {
        logerror("GAVNIT: spurious INTA, no pending\n");
        return 0xFF;
    }

    m_irr &= ~(1 << line);
    m_isr |=  (1 << line);
    update_intr_line();

    logerror("GAVNIT: INTA line=%d vector=%02X IRR=%02X ISR=%02X IMR=%02X\n",
             line, m_vector[line], m_irr, m_isr, m_imr);

    return m_vector[line];
}

void epson_gavnit_device::irq_request(int line, bool state)
{
    if (line < 0 || line > 7)
        return;

    if (state)
        m_irr |=  (1 << line);
    else
        m_irr &= ~(1 << line);

    update_intr_line();
}

// Edge-triggered keyboard line (line 1 → INT 75h)
void epson_gavnit_device::keyboard_irq_w(int state)
{
    const bool level = state != 0;
    logerror("GAVNIT: keyboard_irq_w level=%d last=%d IRR=%02X IMR=%02X\n",
             level, m_kb_last_level, m_irr, m_imr);

    if (level && !m_kb_last_level)
    {
        irq_request(1, true);
        logerror("GAVNIT: keyboard IRQ edge → IRR=%02X\n", m_irr);
    }

    m_kb_last_level = level;
}

void epson_gavnit_device::set_line_vector(int line, u8 vector)
{
    if (line < 0 || line > 7)
        return;
    m_vector[line] = vector;
}

//-------------------------------------------------
//  I/O: timer compare (ports 00h / 01h)
//-------------------------------------------------

u8 epson_gavnit_device::port0_r()
{
    return u8(m_compare & 0x00FF);
}

u8 epson_gavnit_device::port1_r()
{
    return u8((m_compare >> 8) & 0x00FF);
}

void epson_gavnit_device::port0_w(u8 data)
{
    m_last_written = m_compare;
    m_compare = (m_compare & 0xFF00) | data;
    const u16 new_step = u16(m_compare - m_last_written);
    if (new_step)
        m_step = new_step;
    schedule_next_event();
}

void epson_gavnit_device::port1_w(u8 data)
{
    m_last_written = m_compare;
    m_compare = (m_compare & 0x00FF) | (u16(data) << 8);
    const u16 new_step = u16(m_compare - m_last_written);
    if (new_step)
        m_step = new_step;
    schedule_next_event();
}

//-------------------------------------------------
//  I/O: interrupt mask (ports 04h / 05h)
//-------------------------------------------------

u8 epson_gavnit_device::intmask_lo_r()
{
        // Add FDC “command complete” / interrupt bit:
    if (m_fdc_intrq)
        m_mask_lo |= 0x10;  // bit 4 = FDC INTRQ

    return m_mask_lo ;
}

u8 epson_gavnit_device::intmask_hi_r()
{
    return m_mask_hi;
}

void epson_gavnit_device::intmask_lo_w(u8 data)
{
    // BIOS writes AX to port 4. Low byte is "enable bits".
    // 1 = enabled, 0 = masked. Internally: IMR = ~enable_lo.
    m_mask_lo = data;
    m_imr     = ~data;

    logerror("GAVNIT: intmask_lo_w data=%02X -> IMR=%02X\n", data, m_imr);
    update_intr_line();
}

void epson_gavnit_device::intmask_hi_w(u8 data)
{
    // High byte is latched for completeness; currently unused
    m_mask_hi = data;
    logerror("GAVNIT: intmask_hi_w data=%02X\n", data);
}

// FDC Interrupt /// 
// FDC INTRQ callback
void epson_gavnit_device::fdc_intrq_w(int state)
{
    m_fdc_intrq = state ? 1 : 0;
    logerror("GAVNIT: FDC INTRQ -> %d\n", m_fdc_intrq);

    // If GAVNIT ORs sources to generate INT 71, you might do:
    // recompute_interrupts();
}

//-------------------------------------------------
//  tuning helpers
//-------------------------------------------------

void epson_gavnit_device::set_fractional_prescale(unsigned num, unsigned den)
{
    m_ps_num = num ? num : 1;
    m_ps_den = den ? den : 1;
    recalc_base_rate();
    schedule_next_event();
}

void epson_gavnit_device::set_default_step(u16 step)
{
    m_default_step = step ? step : 0x0600;
}
