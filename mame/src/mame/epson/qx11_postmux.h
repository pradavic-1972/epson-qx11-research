// license:BSD-3-Clause
// Epson QX-11 “POST/handshake mux” (ports 0x80, 0x81, 0x82) - minimal stub
#ifndef MAME_EPSON_QX11_POSTMUX_H
#define MAME_EPSON_QX11_POSTMUX_H

#pragma once

#include "emu.h"

// Public device type (declare here, define in the .cpp)
DECLARE_DEVICE_TYPE(QX11_POSTMUX, qx11_postmux_device)

class qx11_postmux_device : public device_t
{
public:
	// construction
	qx11_postmux_device(const machine_config &mconfig, const char *tag, device_t *owner, u32 clock = 0);

	// I/O handlers you’ll map to 0x80..0x82
	u8  port80_r();               // status/echo (rarely read, but keep it)
	void port80_w(u8 data);       // POST/handshake data burst

	u8  port81_r();               // “status” nibble that BIOS polls
	void port81_w(u8 data);       // handshake control

	u8  port82_r();               // optional aux/mask
	void port82_w(u8 data);       // optional aux/mask

protected:
	// device_t
	virtual void device_start() override;
	virtual void device_reset() override;

private:
	// very small model of what the ROM does:
	//  - 0x81 is a polled status/handshake register
	//  - 0x80 receives a tiny 6-byte burst when 0x81&(0x1f)==0x0d
	//  - after the burst completes we present 0x0c on 0x81 (per your logs)
	u8  m_p80_last = 0x00;
	u8  m_p81_stat = 0x01;    // start with bit0 set so the poll loop sees "present"
	u8  m_p82_last = 0x00;

	u8  m_seq_expected = 0;   // how many bytes still expected for the 6-byte POST burst
	u8  m_seq_buf[6]{};       // capture (for logging/inspection if needed)
};

#endif // MAME_EPSON_QX11_POSTMUX_H
