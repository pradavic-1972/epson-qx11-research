// license:BSD-3-Clause
#include "emu.h"
#include "gafddc.h"

DEFINE_DEVICE_TYPE(EPSON_GAFDDC, epson_gafddc_device, "epson_gafddc", "Epson QX-11 GAFDDC Gate Array")

epson_gafddc_device::epson_gafddc_device(
        const machine_config &mconfig,
        const char *tag,
        device_t *owner,
        u32 clock)
    : device_t(mconfig, EPSON_GAFDDC, tag, owner, clock)
{
}


void epson_gafddc_device::device_start()
{
     m_motor_hold_timer = timer_alloc(FUNC(epson_gafddc_device::motor_hold_timer_expired), this);

    // Resolve floppy devices from tags
    for (int i = 0; i < 2; i++)
    {
        m_floppy[i] = nullptr;

        if (!m_floppy_tag[i].empty())
        {
            // owner() here is the QX-11 state device that owns both GAFDDC and the connectors
            auto *conn = owner()->subdevice<floppy_connector>(m_floppy_tag[i]);
            if (conn)
                m_floppy[i] = conn->get_device();
        }
    }

    save_item(NAME(m_ctrl));
    save_item(NAME(m_sel));
    save_item(NAME(m_motor_on));
    save_item(NAME(m_ready));
}

void epson_gafddc_device::device_reset()
{
    m_ctrl      = 0x00;
    m_sel       = -1;
    m_motor_on  = false;
    m_ready[0]  = false;
    m_ready[1]  = false;

    if (m_fdc)
        m_fdc->set_floppy(nullptr);

    m_motor_hold_timer->adjust(attotime::never);
}

// Timer callback: motor hold expired → turn everything off
TIMER_CALLBACK_MEMBER(epson_gafddc_device::motor_hold_timer_expired)
{
    motor_timeout();
}

void epson_gafddc_device::motor_timeout()
{
    if (!m_motor_on)
        return;

    logerror("GAFDDC: motor timeout, disabling drive\n");

    m_motor_on = false;

    if (m_sel >= 0 && m_sel < 2) {
    
    m_floppy[m_sel]->mon_w(1);
    
        m_ready[m_sel] = false;
    }
    m_sel = -1;

    if (m_fdc)
        
        m_fdc->set_floppy(nullptr);
        
}

void epson_gafddc_device::select_drive(int sel)
{
    if (sel == m_sel)
        return;

    m_sel = sel;

    floppy_image_device *flop = nullptr;
    if (m_sel >= 0 && m_sel < 2) {
        flop = m_floppy[m_sel];
       
    }
        

    if (m_fdc) {
        logerror("GAFDDC: Selecting drive - m_fdc->set_floppy\n");
       
        m_fdc->set_floppy(flop);
        m_fdc->set_rate(250000); // 250 kHz
        m_fdc->set_ready_line_connected(true);
        m_fdc->set_select_lines_connected(false);
    }
        //flop->mon_w(0);

    logerror("GAFDDC: select_drive -> %d (%c:)\n",
             m_sel, (m_sel < 0) ? '-' : (m_sel ? 'B' : 'A'));
             
}

// Called when we see a “kick” (04 or 08) on port 0x0F
void epson_gafddc_device::motor_on_pulse()
{
    // Motor is logically ON as long as the hold timer is running.
    m_motor_on = true;

    // Restart hold timer from now.
    m_motor_hold_timer->adjust(attotime::from_msec(MOTOR_HOLD_MSEC));

    if (m_sel >= 0 && m_sel < 2)
    {
        floppy_image_device *flop = m_floppy[m_sel];
        if (flop)
        {
            // Turn the motor ON for the selected drive.
            // (On PC-style drives, MON=0 = motor on; this matches your note.)
            flop->mon_w(0);
            logerror("GAFDDC: Device tag %c\n", flop->tag());

            // Only ever mark the drive ready if there's actually an image mounted.
            // Depending on your MAME version, you may need to tweak this check:
            //  - exists()
            //  - get_image() != nullptr
            //  - is_inserted()
            bool has_image = false;

            // Example pattern – adjust to your local API:
            if (flop)
                has_image = true;

            m_ready[m_sel] = has_image;

            logerror("GAFDDC: motor pulse, drive %c: motor=ON, image=%d, ready=%d (hold=%dms)\n",
                     m_sel ? 'B' : 'A', has_image ? 1 : 0, m_ready[m_sel] ? 1 : 0, MOTOR_HOLD_MSEC);
        }
        else
        {
            // No attached device for this slot
            m_ready[m_sel] = false;
            logerror("GAFDDC: motor pulse, but drive %c has no device attached\n",
                     m_sel ? 'B' : 'A');
        }
    }
    else
    {
        logerror("GAFDDC: motor pulse but no drive selected\n");
    }
}

// Port 0x0F – control (pulse semantics)
void epson_gafddc_device::control_w(u8 data)
{
  if (!machine().side_effects_disabled())
        logerror("GAFDDC: control_w <- %02X\n", data);

    m_ctrl = data;

    // QX-11 observation:
    //  - BIOS writes 0x04 (A:) then 0x00
    //  - BIOS writes 0x08 (B:) then 0x00
    //
    // We interpret 0x04 / 0x08 as *pulses*:
    //  - select the drive
    //  - motor on
    //  - restart motor hold timer
    int new_sel = -1;

    if (data & 0x04)
        new_sel = 0;      // drive A pulse
    else if (data & 0x08)
        new_sel = 1;      // drive B pulse

    if (new_sel != -1)
    {
        select_drive(new_sel);
        motor_on_pulse();
    }

    // Bit 4 (0x10) pulses the FDC TC (terminal count) line.
    // BIOS uses this to tell the 765 that a multi-sector command or
    // scan/format operation should terminate.
    if (data & 0x10)
    {
        if (m_fdc)
        {
            logerror("GAFDDC: TC pulse (0x10)\n");
            m_fdc->tc_w(1);
            m_fdc->tc_w(0);
        }
    }

    // Writes of 0x00 (the trailing half of the 0x04/0x08 pulse) do NOT
    // immediately disable the drive; motor_timeout() will fire when
    // MOTOR_HOLD_MSEC has elapsed since the last pulse.
}

// Port 0x0E – status
u8 epson_gafddc_device::status_r() const
{
    u8 result = 0x00;

    // QX-11 BIOS expects:
    //  bit0 = A: ready, bit1 = B: ready
    if (m_ready[0])
        result |= 0x01;
    if (m_ready[1])
        result |= 0x02;

    //logerror("GAFDDC: status_r -> %02X (readyA=%d readyB=%d motor=%d sel=%d)\n",
    //         result, m_ready[0], m_ready[1], m_motor_on, m_sel);
    return result;
}
