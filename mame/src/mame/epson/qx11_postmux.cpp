// license:BSD-3-Clause
#include "emu.h"
#include "qx11_postmux.h"

// DEFINE the device type (pairs with DECLARE in the header)
DEFINE_DEVICE_TYPE(QX11_POSTMUX, qx11_postmux_device, "qx11_postmux", "Epson QX-11 POST/Handshake Mux")

qx11_postmux_device::qx11_postmux_device(const machine_config &mconfig, const char *tag, device_t *owner, u32 clock)
	: device_t(mconfig, QX11_POSTMUX, tag, owner, clock)
{
}

void qx11_postmux_device::device_start()
{
	save_item(NAME(m_p80_last));
	save_item(NAME(m_p81_stat));
	save_item(NAME(m_p82_last));
	save_item(NAME(m_seq_expected));
	save_item(NAME(m_seq_buf));
}

void qx11_postmux_device::device_reset()
{
	m_p80_last    = 0x00;
	m_p81_stat    = 0x01;   // matches your first “in 81h -> 01” observations
	m_p82_last    = 0x00;
	m_seq_expected = 0;
	std::fill(std::begin(m_seq_buf), std::end(m_seq_buf), 0x00);
}

/* ----- port 0x80 --------------------------------------------------------- */

u8 qx11_postmux_device::port80_r()
{
	// Rare in your traces; keep simple: echo last write (common POST-port debug behaviour)
	return m_p80_last;
}

void qx11_postmux_device::port80_w(u8 data)
{
	m_p80_last = data;

	// The ROM writes a 6-byte burst when (port81 & 0x1f) == 0x0d; bytes are e0,00,00,00,00,45 in your logs.
	// We emulate the handshake:
	if (m_seq_expected == 0)
	{
		// Start of a burst: if 0x81 low 5 bits are 0x0d, arm for 6 bytes
		if ( (m_p81_stat & 0x1f) == 0x0d )
		{
			m_seq_expected = 6;
		}
	}

	if (m_seq_expected)
	{
		const u8 idx = 6 - m_seq_expected;
		m_seq_buf[idx] = data;
		m_seq_expected--;

		// When the burst completes, ROM expects 0x81 to show 0x0c (per your “stuck read 0x0C” trace)
		if (m_seq_expected == 0)
		{
			// Clear bit0 and present 0x0c on low 5 bits; keep any upper bits intact.
			m_p81_stat = (m_p81_stat & 0xe0) | 0x0c;
		}
	}

	// Optional: log the sequence for debugging
	// if (!machine().side_effects_disabled()) logerror("POSTMUX: port80 <= %02x (seq_left=%d)\n", data, m_seq_expected);
}

/* ----- port 0x81 --------------------------------------------------------- */

u8 qx11_postmux_device::port81_r()
{
	// BIOS polls this heavily; just return the current status nibble
	// Your traces show transitions 0x01 -> 0x0d -> 0x0c during the handshake.
	return m_p81_stat;
}

void qx11_postmux_device::port81_w(u8 data)
{
	// The ROM first writes 0x01, then checks (read & 1) and compares low 5 bits to 0x0d.
	// Treat any write as “set current status bits”; keep it permissive.
	m_p81_stat = data;

	// If the low 5 bits are 0x0d, the ROM will soon send the 6-byte burst to port 0x80.
	// Arm the sequence intake right away so we accept the burst starting at the next port80 writes.
	if ( (m_p81_stat & 0x1f) == 0x0d )
	{
		m_seq_expected = 6;
	}
	else if ( (m_p81_stat & 0x1f) == 0x1f )
	{
		// Another pattern the ROM checks (0x1f) — nothing special to do, just let it pass.
	}
}

/* ----- port 0x82 --------------------------------------------------------- */

u8 qx11_postmux_device::port82_r()
{
	// Nothing firm from traces — just expose last written value.
	return m_p82_last;
}

void qx11_postmux_device::port82_w(u8 data)
{
	m_p82_last = data;
	// In your logs BIOS wrote 0x01 here before the handshake; we just latch it.
}
