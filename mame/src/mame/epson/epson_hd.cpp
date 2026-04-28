// license:BSD-3-Clause
#include "emu.h"
#include "epson_hd.h"

#define LOG_HD 0
#if LOG_HD
#define HDLOG(...) logerror(__VA_ARGS__)
#else
#define HDLOG(...) do {} while (0)
#endif

DEFINE_DEVICE_TYPE(EPSON_HD, epson_hd_device, "epson_hd", "Epson QX-11 HD-10 host protocol device")

epson_hd_device::epson_hd_device(const machine_config &mconfig, const char *tag, device_t *owner, u32 clock)
	: device_t(mconfig, EPSON_HD, tag, owner, clock)
	, device_image_interface(mconfig, *this)
{
}

void epson_hd_device::device_start()
{
	save_item(NAME(m_phase));
	save_item(NAME(m_probe_pending));
	save_item(NAME(m_prefix));
	save_item(NAME(m_armed));

	save_item(NAME(m_cmd));
	save_item(NAME(m_cmd_pos));

	save_item(NAME(m_op));
	save_item(NAME(m_addr));
	save_item(NAME(m_count));
	save_item(NAME(m_magic));

	save_item(NAME(m_r0));
	save_item(NAME(m_r1));

	save_item(NAME(m_need_post_ack));
	save_item(NAME(m_after_ack_phase));

	save_item(NAME(m_param_left));
	save_item(NAME(m_param_pos));
	save_item(NAME(m_param_buf));

	save_item(NAME(m_stream_mode));
	save_item(NAME(m_stream_total));
	save_item(NAME(m_stream_pos));

	save_item(NAME(m_image));
    save_item(NAME(m_dirty));
}

void epson_hd_device::device_stop()
{
    flush_image();
}

void epson_hd_device::flush_image()
{
    if (!m_dirty)
        return;
    if (m_image.empty())
        return;
    if (!is_loaded() || !is_writeable())
        return;

    // rewind + write whole file (simple and robust)
    fseek(0, SEEK_SET);
    const u32 put = fwrite(m_image.data(), u32(m_image.size()));
    if (put != m_image.size())
        HDLOG("[epson_hd] WARN: short write while flushing image\n");
    else
        m_dirty = false;
}

void epson_hd_device::device_reset()
{
	m_phase = PH_WAIT_PREFIX;

	m_probe_pending = false;
	m_prefix = 0x00;
	m_armed  = false;

	std::fill(m_cmd.begin(), m_cmd.end(), 0);
	m_cmd_pos = 0;

	m_op = 0;
	m_addr = 0;
	m_count = 0;
	m_magic = 0;

	m_r0 = 0;
	m_r1 = 0;

	m_need_post_ack = false;
	m_after_ack_phase = PH_RES_R0;

	m_param_left = 0;
	m_param_pos = 0;
	std::fill(m_param_buf.begin(), m_param_buf.end(), 0);

	m_stream_mode = SM_NONE;
	m_stream_total = 0;
	m_stream_pos = 0;

    m_dirty = false;
}

std::pair<std::error_condition, std::string> epson_hd_device::call_load()
{
	// Load entire raw file into memory
	const u64 sz = length();
	if (sz == 0)
	{
		m_image.clear();
		return { std::error_condition(), std::string() };
	}

	if (sz > (128ull * 1024ull * 1024ull))
		return { std::make_error_condition(std::errc::file_too_large), "Image too large for raw loader (limit 128MB)" };

	m_image.resize(size_t(sz));
	const u32 got = fread(m_image.data(), u32(m_image.size()));
	if (got != m_image.size())
		return { std::make_error_condition(std::errc::io_error), "Short read while loading raw image" };

	HDLOG("[epson_hd] loaded raw image: %llu bytes\n", (unsigned long long)sz);
	return { std::error_condition(), std::string() };
}

std::pair<std::error_condition, std::string> epson_hd_device::call_create(s32 format_type, util::option_resolution *format_options)
{
	(void)format_type;
	(void)format_options;

	// If user "creates" an image, just initialize it to 10MB unless overridden by UI.
	const u64 default_size = 10ull * 1024ull * 1024ull;
	m_image.assign(size_t(default_size), 0x00);

	const u32 put = fwrite(m_image.data(), u32(m_image.size()));
	if (put != m_image.size())
		return { std::make_error_condition(std::errc::io_error), "Short write while creating raw image" };

	HDLOG("[epson_hd] created raw image: %llu bytes\n", (unsigned long long)default_size);
	return { std::error_condition(), std::string() };
}

void epson_hd_device::call_unload()
{
	// Best effort flush-back if the image is writable and we have data.
	if (!m_image.empty() && is_writeable())
	{
		// rewind to start
		fseek(0, SEEK_SET);

		const u32 put = fwrite(m_image.data(), u32(m_image.size()));
		if (put != m_image.size())
			HDLOG("[epson_hd] WARN: short write on unload\n");
	}

    flush_image();
	m_image.clear();
}

void epson_hd_device::ensure_image_min_size(u64 bytes)
{
	if (m_image.size() < bytes)
		m_image.resize(size_t(bytes), 0x00);
}

// NEW: final results phase entry (don’t abort/reset yet!)
void epson_hd_device::enter_final_results()
{
	// After data transfer completes, BIOS expects:
	//   IN 81h -> 0x0F, then IN 80h reads R0
	//   IN 81h -> 0x1F, then IN 80h reads R1
	// Only then do we abort/reset in PH_RES_R1 handling.
	m_stream_mode  = SM_NONE;
	m_stream_total = 0;
	m_stream_pos   = 0;
	m_phase = PH_RES_R0;
}

void epson_hd_device::abort_all()
{
	m_phase = PH_WAIT_PREFIX;

	m_armed = false;
	m_prefix = 0x00;

	m_cmd_pos = 0;
	std::fill(m_cmd.begin(), m_cmd.end(), 0);

	m_need_post_ack = false;
	m_after_ack_phase = PH_RES_R0;

	m_param_left = 0;
	m_param_pos = 0;
	std::fill(m_param_buf.begin(), m_param_buf.end(), 0);

	m_stream_mode = SM_NONE;
	m_stream_total = 0;
	m_stream_pos = 0;
}

void epson_hd_device::start_command_transaction(u8 prefix)
{
	// Start-of-command is authoritative: drop stale state.
	m_prefix = prefix;
	m_armed = true;

	m_cmd_pos = 0;
	std::fill(m_cmd.begin(), m_cmd.end(), 0);

	m_need_post_ack = false;
	m_after_ack_phase = PH_RES_R0;

	m_param_left = 0;
	m_param_pos = 0;
	std::fill(m_param_buf.begin(), m_param_buf.end(), 0);

	m_stream_mode = SM_NONE;
	m_stream_total = 0;
	m_stream_pos = 0;

	m_phase = PH_REQ_FRAME;
}

//
// PORT 81 — STATUS (read)
//
u8 epson_hd_device::port81_r()
{
	// Probe reply: OUT81 then immediate IN81 should return 00
	if (m_probe_pending)
	{
		m_probe_pending = false;
		return 0x00;
	}

	// Not in a transaction -> 00
	if (m_phase == PH_WAIT_PREFIX || m_phase == PH_WAIT_STROBE || m_phase == PH_IDLE)
		return 0x00;

	// One-shot post-frame ACK: bit0 must be 0 exactly once
	if (m_need_post_ack)
	{
		m_need_post_ack = false;
		m_phase = m_after_ack_phase;
		return 0x00;
	}

	switch (m_phase)
	{
	case PH_REQ_FRAME:   return 0x0D;
	case PH_RECV_FRAME:  return 0x00;

	case PH_PARAM_TX:
		// “ready to accept param byte” (low5==9, bit0==1)
		return 0x09;

	case PH_RES_R0:      return 0x0F;
	case PH_RES_R1:      return 0x1F;

	case PH_STREAM_READ:
		// READ data phase: BIOS polls for 0x05 after shifting (0x0B -> 0x05)
		return (m_stream_pos < m_stream_total) ? 0x0b : 0x00;

	case PH_STREAM_WRITE:
		// WRITE data phase: BIOS polls for 0x09 before each OUT 80h
		return (m_stream_pos < m_stream_total) ? 0x09 : 0x00;

    case PH_STREAM_0F:
		// WRITE data phase: BIOS polls for 0x09 before each OUT 80h
		return (m_stream_pos < m_stream_total) ? 0x09 : 0x00;

	default:
		return 0x00;
	}
}

//
// PORT 81 — STATUS (write)
// OUT81/IN81 is probe/wakeup. Abort everything.
//
void epson_hd_device::port81_w(u8 data)
{
	(void)data;
	abort_all();
	m_probe_pending = true;
}

//
// PORT 82 — STROBE (write)
// out80(prefix) then out82(prefix) starts a command.
//
void epson_hd_device::port82_w(u8 data)
{
	if (m_phase != PH_WAIT_STROBE || !m_armed)
		return;

	if (data != m_prefix)
		return;

	start_command_transaction(m_prefix);
}

//
// PORT 80 — DATA (write)
//
void epson_hd_device::port80_w(u8 data)
{
	switch (m_phase)
	{
	case PH_WAIT_PREFIX:
		m_prefix = data;
		m_armed = true;
		m_phase = PH_WAIT_STROBE;
		break;

	case PH_REQ_FRAME:
		m_cmd_pos = 0;
		m_cmd[m_cmd_pos++] = data;
		m_phase = PH_RECV_FRAME;
		break;

	case PH_RECV_FRAME:
		if (m_cmd_pos < 6)
			m_cmd[m_cmd_pos++] = data;

		if (m_cmd_pos == 6)
		{
			decode_frame();
			begin_command();

			// BIOS does IN81 immediately after sending 6 bytes -> must see 00 once.
			m_need_post_ack = true;
		}
		break;

	case PH_PARAM_TX:
		// collect param bytes
		if (m_param_pos < u16(m_param_buf.size()))
			m_param_buf[m_param_pos] = data;
		m_param_pos++;

		if (m_param_left > 0)
			m_param_left--;

		if (m_param_left == 0)
		{
			// Param block done -> BIOS expects 0x0F/0x1F and reads results on port80
			m_phase = PH_RES_R0;
		}
		break;

	case PH_STREAM_WRITE:
		if (m_stream_pos < m_stream_total)
		{
			const u32 idx = m_stream_pos++;
			const u32 lba = m_addr + (idx / 512);
			const u32 off = (idx % 512);

			ensure_image_min_size(u64(lba + 1) * 512ull);
			write_media_byte(lba, off, data);

			// FIX: after last byte, do NOT abort/reset; go to final results phase
			if (m_stream_pos >= m_stream_total)
            {
                flush_image();
				enter_final_results();
		    }
		break;
        }
    case PH_STREAM_0F:
		if (m_stream_pos < m_stream_total)
		{
			//const u32 idx = m_stream_pos++;
			//const u32 lba = m_addr + (idx / 512);
			//const u32 off = (idx % 512);

			//ensure_image_min_size(u64(lba + 1) * 512ull);
			//write_media_byte(lba, off, data);

			// FIX: after last byte, do NOT abort/reset; go to final results phase
			if (m_stream_pos >= m_stream_total)
            {
                //flush_image();
				enter_final_results();
		    }
		break;
        }
	default:
		break;
	}
}

//
// PORT 80 — DATA (read)
//
u8 epson_hd_device::port80_r()
{
	u8 v = 0xFF;

	switch (m_phase)
	{
	case PH_RES_R0:
		v = m_r0;
		m_phase = PH_RES_R1;
		break;

	case PH_RES_R1:
		v = m_r1;
		abort_all(); // after both result bytes are consumed, we reset
		break;

	case PH_STREAM_READ:
		if (m_stream_pos < m_stream_total)
		{
			const u32 idx = m_stream_pos++;
			const u32 lba = m_addr + (idx / 512);
			const u32 off = (idx % 512);

			v = read_media_byte(lba, off);

			// FIX: after last byte, do NOT abort/reset; go to final results phase
			if (m_stream_pos >= m_stream_total)
				enter_final_results();
		}
		else
		{
			// Don’t wedge if BIOS reads past end; finalize.
			enter_final_results();
			v = 0x00;
		}
		break;

	default:
		v = 0xFF;
		break;
	}

	return v;
}

void epson_hd_device::decode_frame()
{
	m_op    = m_cmd[0];
	m_addr  = (u32(m_cmd[1]) << 16) | (u32(m_cmd[2]) << 8) | u32(m_cmd[3]);
	m_count = m_cmd[4];
	m_magic = m_cmd[5];

	// class-0 convention: count==0 => 256
	if (m_count == 0)
		m_count = 256;

	HDLOG("[epson_hd] cmd %02X %02X %02X %02X %02X %02X  op=%02X addr=%06X cnt=%u magic=%02X\n",
		m_cmd[0], m_cmd[1], m_cmd[2], m_cmd[3], m_cmd[4], m_cmd[5],
		m_op, unsigned(m_addr), unsigned(m_count), unsigned(m_magic));
}

void epson_hd_device::begin_command()
{
	// defaults
	m_stream_mode = SM_NONE;
	m_stream_total = 0;
	m_stream_pos = 0;

	m_r0 = 0x00;
	m_r1 = 0x00;

	// default after-ack goes to results
	m_after_ack_phase = PH_RES_R0;

	switch (m_op)
	{
	case 0x08:
	case 0xE5:
		start_read_stream();
		finish_ok();
		// READ: go directly to stream after the one-shot ACK
		m_after_ack_phase = PH_STREAM_READ;
		break;

	case 0x0A:
    case 0xE6:
		start_write_stream();
		finish_ok();
		// WRITE: go directly to stream after the one-shot ACK
		m_after_ack_phase = PH_STREAM_WRITE;
		break;

	case 0x0C:
		// Initialize/Reset: after post-ack, BIOS expects STATUS==0x09 and pushes 8 bytes
		finish_ok();
		m_param_left = 8;
		m_param_pos  = 0;
		std::fill(m_param_buf.begin(), m_param_buf.end(), 0);
		m_after_ack_phase = PH_PARAM_TX;
		break;

    case 0x0F:
        start_write_stream();
        finish_ok();
        m_after_ack_phase = PH_STREAM_0F;
        break;

	default:
		finish_err(0x01);
		m_after_ack_phase = PH_RES_R0;
		break;
	}
}

void epson_hd_device::finish_ok()
{
	m_r0 = 0x00;
	m_r1 = 0x00;
}

void epson_hd_device::finish_err(u8 err)
{
	m_r0 = err;
	m_r1 = 0x00;
	m_stream_mode = SM_NONE;
	m_stream_total = 0;
	m_stream_pos = 0;
}

void epson_hd_device::start_read_stream()
{
	m_stream_mode  = SM_READ;
	m_stream_total = u32(m_count) * 512u;
	m_stream_pos   = 0;
}

void epson_hd_device::start_write_stream()
{
	m_stream_mode  = SM_WRITE;
	m_stream_total = u32(m_count) * 512u;
	m_stream_pos   = 0;
}

u8 epson_hd_device::read_media_byte(u32 lba, u32 off) const
{
	const u64 idx = u64(lba) * 512ull + u64(off);

	if (!m_image.empty() && idx < m_image.size())
		return m_image[size_t(idx)];

	// fallback synthetic content if no image loaded
	if (lba == 0)
	{
		if (off == 0) return 0xE9;
		if (off == 3) return 'E';
		if (off == 4) return 'P';
		if (off == 5) return 'S';
		if (off == 6) return 'O';
		if (off == 7) return 'N';
		return 0x00;
	}

	return 0x00;
}

void epson_hd_device::write_media_byte(u32 lba, u32 off, u8 data)
{
	if (m_image.empty())
		return;

	const u64 idx = u64(lba) * 512ull + u64(off);
	if (idx < m_image.size())
		{
        m_image[size_t(idx)] = data;
        m_dirty = true;
    }
}
