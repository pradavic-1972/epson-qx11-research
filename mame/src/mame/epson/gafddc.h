// license:BSD-3-Clause
// Epson QX-11 GAFDDC – Floppy gate array
//
// Sits between the uPD765 FDC and the TEAC drives.
// CPU never sees this directly – it talks to GAVNIO ports 0x0E/0x0F,
// and GAVNIO forwards those to this device.

#ifndef MAME_EPSON_GAFDDC_H
#define MAME_EPSON_GAFDDC_H

#pragma once

#include "device.h"
#include "machine/upd765.h"
#include "imagedev/floppy.h"
#include <string>

class epson_gafddc_device : public device_t
{
public:
    epson_gafddc_device(const machine_config &mconfig, const char *tag,
                        device_t *owner, u32 clock = 0);

    // Wiring from qx11_state / machine_config
    void set_fdc(upd765a_device &fdc) { m_fdc = &fdc; }
    void set_floppies(floppy_image_device *drive0, floppy_image_device *drive1)
    {
        m_floppy[0] = drive0;
        m_floppy[1] = drive1;
    }

    void set_floppy_tag(int index, const char *tag) { m_floppy_tag[index] = tag; }

    // Front side: called by GAVNIO for ports 0x0F and 0x0E respectively
    void control_w(u8 data);
    u8   status_r() const;
    

protected:
    virtual void device_start() override;
    virtual void device_reset() override;

private:
    // Helpers
    void select_drive(int sel);
    void motor_on_pulse();          // pulse → motor ON + (re)start hold timer
    void motor_timeout();           // called when hold timer expires

    // Motor hold timer: how long after the last pulse the drive stays enabled
    static constexpr int MOTOR_HOLD_MSEC = 2000; // tune as needed
    emu_timer *m_motor_hold_timer = nullptr;
    TIMER_CALLBACK_MEMBER(motor_hold_timer_expired);

    // Connected devices
    upd765a_device *m_fdc = nullptr;
    floppy_image_device *m_floppy[2]{};

    // Latched control/state
    u8   m_ctrl = 0x00;      // last byte written to 0x0F
    int  m_sel  = -1;        // 0 = A:, 1 = B:, -1 = none
    bool m_motor_on = false; // logical motor state
    bool m_ready[2]{ false, false };

       // Tags for the two floppy connectors
    std::string m_floppy_tag[2];
    // Resolved floppy devices
    // (resolved floppy pointers are stored in m_floppy above)

};

DECLARE_DEVICE_TYPE(EPSON_GAFDDC, epson_gafddc_device)

#endif // MAME_EPSON_GAFDDC_H
