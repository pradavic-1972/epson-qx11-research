// license:BSD-3-Clause
// Epson QX-11 GAVDP (Video Processor / Gate Array) - alias-window model

#include "emu.h"
#include "gavdp.h"

#include <algorithm>
#include <cstdlib>

DEFINE_DEVICE_TYPE(EPSON_GAVDP, gavdp_device, "epson_gavdp", "Epson QX-11 GAVDP")

namespace {

bool gavdp_trace_enabled()
{
	static const bool enabled = std::getenv("QX11_GAVDP_TRACE") != nullptr;
	return enabled;
}

const char *gavdp_reg_name(offs_t off)
{
	switch (off)
	{
	case 0x0c060: return "C060";
	case 0x0c261: return "C261";
	case 0x0c462: return "C462";
	case 0x0c663: return "C663";
	case 0x0d068: return "D068";
	case 0x0d269: return "D269";
	default: return nullptr;
	}
}

}

gavdp_device::gavdp_device(const machine_config &mconfig, const char *tag, device_t *owner, u32 clock)
	: device_t(mconfig, EPSON_GAVDP, tag, owner, clock)
	, device_video_interface(mconfig, *this)
	, m_screen(*this, "^screen")
{
}

void gavdp_device::set_screen_tag(const char *tag)
{
	m_screen.set_tag(tag);
}

void gavdp_device::device_start()
{
	m_vram.assign(VRAM_CANON_SIZE, 0x00);
	m_hidden_vram.assign(VRAM_CANON_SIZE, 0x00);
	for (auto &plane : m_color_plane)
		plane.assign(VRAM_CANON_SIZE, 0x00);
	m_mmio.assign(VRAM_WINDOW_SIZE, 0x00);
	std::fill(m_color_attr.begin(), m_color_attr.end(), 0x07);

	// Simple 3-bit RGB palette
	m_palette[0] = rgb_t(0x00, 0x00, 0x00);
	m_palette[1] = rgb_t(0x00, 0x00, 0xff);
	m_palette[2] = rgb_t(0x00, 0xff, 0x00);
	m_palette[3] = rgb_t(0x00, 0xff, 0xff);
	m_palette[4] = rgb_t(0xff, 0x00, 0x00);
	m_palette[5] = rgb_t(0xff, 0x00, 0xff);
	m_palette[6] = rgb_t(0xff, 0xff, 0x00);
	m_palette[7] = rgb_t(0xff, 0xff, 0xff);

	save_pointer(NAME(&m_vram[0]), VRAM_CANON_SIZE);
	save_pointer(NAME(&m_hidden_vram[0]), VRAM_CANON_SIZE);
	save_pointer(NAME(&m_color_plane[0][0]), VRAM_CANON_SIZE);
	save_pointer(NAME(&m_color_plane[1][0]), VRAM_CANON_SIZE);
	save_pointer(NAME(&m_color_plane[2][0]), VRAM_CANON_SIZE);
	save_pointer(NAME(&m_mmio[0]), VRAM_WINDOW_SIZE);

	save_item(NAME(m_color_mode));
	save_item(NAME(m_visible_height));
	save_item(NAME(m_visible_cols));
	save_item(NAME(m_visible_width));

	save_item(NAME(m_d068_last));
	save_item(NAME(m_reg_c663));
	save_item(NAME(m_reg_c462));
	save_item(NAME(m_reg_c261));
	save_item(NAME(m_color_attr));

	update_geometry_from_profile();
}

void gavdp_device::device_reset()
{
	std::fill(m_vram.begin(), m_vram.end(), 0x00);
	std::fill(m_hidden_vram.begin(), m_hidden_vram.end(), 0x00);
	for (auto &plane : m_color_plane)
		std::fill(plane.begin(), plane.end(), 0x00);
	std::fill(m_mmio.begin(), m_mmio.end(), 0x00);
	std::fill(m_color_attr.begin(), m_color_attr.end(), 0x07);

	m_color_mode     = false;
	m_visible_height = 400;
	m_visible_cols   = 80;
	m_visible_width  = 640;

	m_d068_last = 0x00;
	m_reg_c663  = 0x00;
	m_reg_c462  = 0x00;
	m_reg_c261  = 0x00;
	m_trace_clear_active = false;
	m_trace_clear_count = 0;
	m_trace_clear_reject_count = 0;
	m_trace_clear_zero_count = 0;
	m_trace_clear_ff_count = 0;
	m_trace_clear_min_x = 0;
	m_trace_clear_max_x = 0;
	m_trace_clear_min_y = 0;
	m_trace_clear_max_y = 0;
	m_trace_clear_min_off = 0;
	m_trace_clear_max_off = 0;
	m_trace_clear_windows = 0;
	m_trace_clear_reject_min_off = 0;
	m_trace_clear_reject_max_off = 0;
	m_trace_clear_reject_samples = 0;
	m_trace_vram_write_count = 0;
	m_trace_vram_last_segment = 0xffffffff;
	m_trace_vram_read_count = 0;
	m_trace_vram_last_read_segment = 0xffffffff;

	update_geometry_from_profile();
}

// -------------------------------------------------
// Window installation
// -------------------------------------------------

void gavdp_device::install_vram_window(address_space &space, u32 base)
{
	if (base == 0x80000)
	{
		space.install_readwrite_handler(
			base,
			base + VRAM_WINDOW_SIZE - 1,
			read8sm_delegate(*this, FUNC(gavdp_device::win_r_8000)),
			write8sm_delegate(*this, FUNC(gavdp_device::win_w_8000)));
	}
	else if (base == 0x90000)
	{
		space.install_readwrite_handler(
			base,
			base + VRAM_WINDOW_SIZE - 1,
			read8sm_delegate(*this, FUNC(gavdp_device::win_r_9000)),
			write8sm_delegate(*this, FUNC(gavdp_device::win_w_9000)));
	}
	else
	{
		// default to 8000 view
		space.install_readwrite_handler(
			base,
			base + VRAM_WINDOW_SIZE - 1,
			read8sm_delegate(*this, FUNC(gavdp_device::win_r_8000)),
			write8sm_delegate(*this, FUNC(gavdp_device::win_w_8000)));
	}
}

u8  gavdp_device::win_r_8000(offs_t offset) { return win_r(false, offset); }
void gavdp_device::win_w_8000(offs_t offset, u8 data) { win_w(false, offset, data); }

u8  gavdp_device::win_r_9000(offs_t offset) { return win_r(true, offset); }
void gavdp_device::win_w_9000(offs_t offset, u8 data) { win_w(true, offset, data); }

// -------------------------------------------------
// Decode helpers
// -------------------------------------------------

inline bool gavdp_device::color_attr_index_from_off(u32 off, u32 &idx) const
{
	const u32 col = off / VRAM_CANON_BYTES_PER_COL;
	if (col >= 80)
		return false;

	const u32 in_col = off - col * VRAM_CANON_BYTES_PER_COL;

	if (in_col < 0x0100u || in_col >= 0x0100u + 200u)
		return false;

	const u32 canon_y = in_col - 0x0100u;   // 0..199
	const u32 yblock  = canon_y >> 3;       // 0..24

	idx = yblock * 80u + col;               // 0..1999
	return true;
}


bool gavdp_device::decode_col_major(offs_t offset, u32 &xbyte, u32 &idx9) const
{
	// offset = (xbyte<<9) | idx9
	xbyte = (u32)((offset >> 9) & 0x7f);
	idx9  = (u32)(offset & 0x1ff);

	if (xbyte >= (u32)VRAM_COLS)
		return false;

	// Canonical halves are top 0..0x0c7 and bottom 0x100..0x1c7.
	if (idx9 > 0x1c7)
		return false;

	return true;
}

bool gavdp_device::decode_row_major(bool is_9000, offs_t offset, u32 &xbyte, u32 &canon_y) const
{
	offs_t decode_offset = offset;
	if (is_9000 && m_visible_height == 200)
	{
		const u32 raw_x = (u32)(decode_offset & 0xff);
		if (raw_x >= 0x80u && raw_x < 0x80u + (u32)VRAM_COLS)
			decode_offset -= 0x80;
		else if (decode_offset >= 0x100)
			decode_offset -= 0x100;
		else
			return false;
	}

	xbyte = (u32)(decode_offset & 0xff);
	const u32 y = (u32)((decode_offset >> 8) & 0xff);

	if (xbyte >= (u32)VRAM_COLS)
		return false;
	if (y >= 200u)
		return false;

	canon_y = (is_9000 && m_visible_height != 200) ? (200u + y) : y;
	return true;
}

bool gavdp_device::decode_mode_set_clear_alias(bool is_9000, offs_t offset, u32 &xbyte, u32 &y) const
{
	if (!is_9000)
		return false;

	const u32 raw_x = (u32)(offset & 0xff);
	if (raw_x < 0x80u || raw_x >= 0x80u + (u32)VRAM_COLS)
		return false;

	y = (u32)((offset >> 8) & 0xff);
	if (y >= 200u)
		return false;

	xbyte = raw_x - 0x80u;
	return true;
}

// -------------------------------------------------
// MMIO helpers
// -------------------------------------------------

inline u8 gavdp_device::reg_read(offs_t off) const
{
	if ((u32)off < (u32)m_mmio.size())
		return m_mmio[off];
	return 0xff;
}

inline void gavdp_device::reg_write(offs_t off, u8 data)
{
	const u8 old = reg_read(off);
	if (gavdp_trace_enabled())
	{
		if (const char *name = gavdp_reg_name(off))
		{
			if (old != data)
			{
				logerror("GAVDP REG %s %02x -> %02x (D068=%02x C060=%02x C663=%02x C462=%02x C261=%02x D269=%02x)\n",
						name, old, data,
						reg_read(REG_D068_OFFSET), reg_read(REG_C060_OFFSET), reg_read(REG_C663_OFFSET),
						reg_read(REG_C462_OFFSET), reg_read(REG_C261_OFFSET),
						reg_read(REG_D269_OFFSET));
			}
		}
	}

	if ((u32)off < (u32)m_mmio.size())
		m_mmio[off] = data;

	if (off == REG_D068_OFFSET)
		m_d068_last = data;
	else if (off == REG_C663_OFFSET)
		m_reg_c663 = data;
	else if (off == REG_C462_OFFSET)
		m_reg_c462 = data;
	else if (off == REG_C261_OFFSET)
		m_reg_c261 = data;
}

void gavdp_device::update_geometry_from_profile()
{
	const u8 prof_raw = reg_read(REG_D068_OFFSET);
	const u8 cols = reg_read(REG_C060_OFFSET);
	const u8 c261 = reg_read(REG_C261_OFFSET);
	const u8 prof     = prof_raw & 0x7f;

	bool new_color  = m_color_mode;
	int  new_height = m_visible_height;
	int  new_cols   = m_visible_cols;


	if (prof == 2)
	{
		new_color  = false;
		new_height = (c261 & 0x01) ? 200 : 400;
		new_cols   = (cols == 0x11) ? 40 : 80;
	}
	else if (prof == 7 || prof == 3 || prof == 5)
	{
		new_color  = true;
		new_height = 200;
		new_cols   = 80;
	}
	else
	{
		// safe default
		new_color  = false;
		new_height = 400;
		new_cols   = 80;
	}

	if (cols == 0x11)
		new_cols = 40;

	const int new_width = new_cols * 8;

	if (new_color != m_color_mode || new_height != m_visible_height || new_cols != m_visible_cols)
	{
		if (gavdp_trace_enabled())
		{
			logerror("GAVDP GEOMETRY %dx%d %s -> %dx%d %s (D068=%02x C060=%02x C261=%02x C663=%02x C462=%02x)\n",
					m_visible_width, m_visible_height, m_color_mode ? "color" : "mono",
					new_width, new_height, new_color ? "color" : "mono",
					prof_raw, cols, c261, reg_read(REG_C663_OFFSET), reg_read(REG_C462_OFFSET));
		}

		m_color_mode     = new_color;
		m_visible_height = new_height;
		m_visible_cols   = new_cols;
		m_visible_width  = new_width;
		m_trace_vram_write_count = 0;
		m_trace_vram_last_segment = 0xffffffff;
		m_trace_vram_read_count = 0;
		m_trace_vram_last_read_segment = 0xffffffff;

		m_screen->set_visible_area(0, m_visible_width - 1, 0, m_visible_height - 1);
	}

	m_d068_last = prof_raw;
}

int gavdp_device::effective_scroll_px() const
{
	const u32 c663 = reg_read(REG_C663_OFFSET) & 0xff;
	const u32 c462 = reg_read(REG_C462_OFFSET) & 0xff;

	// C462 bit 7 selects the other 200-line half.  Its low seven bits are
	// the horizontal display start and are handled by horizontal_scroll_cols().
	return (c663 + ((c462 & 0x80) ? 200u : 0u)) % 400u;
}

u32 gavdp_device::horizontal_scroll_cols() const
{
	// The display-start granularity is one VRAM byte (eight pixels).  Real
	// hardware has an empirical discontinuity at 5f -> 60: that increment
	// advances four columns, after which single-column increments resume.
	u32 origin = reg_read(REG_C462_OFFSET) & 0x7f;
	if (origin >= 0x60)
		origin += 3;

	return origin % VRAM_COLS;
}

void gavdp_device::trace_clear_write(bool is_9000, offs_t offset, u8 data, u32 xbyte, u32 canon_y)
{
	if (!gavdp_trace_enabled())
		return;

	if (!m_trace_clear_active)
	{
		m_trace_clear_active = true;
		m_trace_clear_count = 0;
		m_trace_clear_reject_count = 0;
		m_trace_clear_zero_count = 0;
		m_trace_clear_ff_count = 0;
		m_trace_clear_min_x = xbyte;
		m_trace_clear_max_x = xbyte;
		m_trace_clear_min_y = canon_y;
		m_trace_clear_max_y = canon_y;
		m_trace_clear_min_off = offset;
		m_trace_clear_max_off = offset;
		m_trace_clear_windows = 0;
		m_trace_clear_reject_min_off = 0;
		m_trace_clear_reject_max_off = 0;
		m_trace_clear_reject_samples = 0;
		logerror("GAVDP CLEAR begin D068=%02x C663=%02x C462=%02x scroll_px=%d\n",
				reg_read(REG_D068_OFFSET), reg_read(REG_C663_OFFSET), reg_read(REG_C462_OFFSET),
				effective_scroll_px());
	}

	m_trace_clear_count++;
	if (data == 0x00)
		m_trace_clear_zero_count++;
	else if (data == 0xff)
		m_trace_clear_ff_count++;

	m_trace_clear_min_x = std::min(m_trace_clear_min_x, xbyte);
	m_trace_clear_max_x = std::max(m_trace_clear_max_x, xbyte);
	m_trace_clear_min_y = std::min(m_trace_clear_min_y, canon_y);
	m_trace_clear_max_y = std::max(m_trace_clear_max_y, canon_y);
	m_trace_clear_min_off = std::min(m_trace_clear_min_off, (u32)offset);
	m_trace_clear_max_off = std::max(m_trace_clear_max_off, (u32)offset);
	m_trace_clear_windows |= is_9000 ? 2u : 1u;
}

void gavdp_device::trace_clear_reject(bool is_9000, offs_t offset, u8 data)
{
	if (!gavdp_trace_enabled())
		return;

	if (!m_trace_clear_active)
	{
		m_trace_clear_active = true;
		m_trace_clear_count = 0;
		m_trace_clear_reject_count = 0;
		m_trace_clear_zero_count = 0;
		m_trace_clear_ff_count = 0;
		m_trace_clear_min_x = 0;
		m_trace_clear_max_x = 0;
		m_trace_clear_min_y = 0;
		m_trace_clear_max_y = 0;
		m_trace_clear_min_off = 0;
		m_trace_clear_max_off = 0;
		m_trace_clear_windows = 0;
		m_trace_clear_reject_min_off = (u32)offset;
		m_trace_clear_reject_max_off = (u32)offset;
		m_trace_clear_reject_samples = 0;
		logerror("GAVDP CLEAR begin D068=%02x C663=%02x C462=%02x scroll_px=%d\n",
				reg_read(REG_D068_OFFSET), reg_read(REG_C663_OFFSET), reg_read(REG_C462_OFFSET),
				effective_scroll_px());
	}

	m_trace_clear_reject_count++;
	if (m_trace_clear_reject_samples < 16)
	{
		logerror("GAVDP CLEAR reject sample off=%04x data=%02x window=%s raw_y=%02x raw_x=%02x\n",
				(u32)offset, data, is_9000 ? "9000" : "8000",
				(u32)((offset >> 8) & 0xff), (u32)(offset & 0xff));
		m_trace_clear_reject_samples++;
	}
	m_trace_clear_reject_min_off = std::min(m_trace_clear_reject_min_off, (u32)offset);
	m_trace_clear_reject_max_off = std::max(m_trace_clear_reject_max_off, (u32)offset);
	m_trace_clear_windows |= is_9000 ? 2u : 1u;
}

void gavdp_device::trace_flush_clear(const char *reason)
{
	if (!gavdp_trace_enabled() || !m_trace_clear_active)
		return;

	logerror("GAVDP CLEAR end reason=%s decoded=%llu rejected=%llu zero=%llu ff=%llu other=%llu x=%u..%u canon_y=%u..%u offsets=%04x..%04x reject_offsets=%04x..%04x windows=%s%s D068=%02x C663=%02x C462=%02x scroll_px=%d\n",
			reason,
			(unsigned long long)m_trace_clear_count,
			(unsigned long long)m_trace_clear_reject_count,
			(unsigned long long)m_trace_clear_zero_count,
			(unsigned long long)m_trace_clear_ff_count,
			(unsigned long long)(m_trace_clear_count - m_trace_clear_zero_count - m_trace_clear_ff_count),
			m_trace_clear_min_x, m_trace_clear_max_x,
			m_trace_clear_min_y, m_trace_clear_max_y,
			m_trace_clear_min_off, m_trace_clear_max_off,
			m_trace_clear_reject_min_off, m_trace_clear_reject_max_off,
			(m_trace_clear_windows & 1u) ? "8000" : "",
			(m_trace_clear_windows == 3u) ? "+9000" : ((m_trace_clear_windows & 2u) ? "9000" : ""),
			reg_read(REG_D068_OFFSET), reg_read(REG_C663_OFFSET), reg_read(REG_C462_OFFSET),
			effective_scroll_px());

	m_trace_clear_active = false;
}

void gavdp_device::trace_vram_write(const char *mode, const char *target, bool is_9000, offs_t offset, offs_t decode_offset, u8 data, u32 xbyte, u32 y_or_idx, u32 canon_y)
{
	if (!gavdp_trace_enabled() || m_visible_height != 200)
		return;

	const u32 phys = (is_9000 ? 0x90000u : 0x80000u) + (u32)offset;
	const u32 seg = phys >> 4;
	const u32 off16 = phys & 0x0f;
	const bool log_sample = m_color_mode || (m_trace_vram_write_count < 512) || (seg != m_trace_vram_last_segment);

	if (log_sample)
	{
		logerror("GAVDP VRAMW #%u mode=%s target=%s win=%s raw=%04x equiv=%04x:%04x decode=%04x x=%02x yidx=%03x canon_y=%03x data=%02x D068=%02x C060=%02x C261=%02x C663=%02x C462=%02x D269=%02x\n",
				m_trace_vram_write_count, mode, target, is_9000 ? "9000" : "8000",
				(u32)offset, seg, off16, (u32)decode_offset, xbyte, y_or_idx, canon_y, data,
				reg_read(REG_D068_OFFSET), reg_read(REG_C060_OFFSET), reg_read(REG_C261_OFFSET),
				reg_read(REG_C663_OFFSET), reg_read(REG_C462_OFFSET), reg_read(REG_D269_OFFSET));
	}

	m_trace_vram_last_segment = seg;
	m_trace_vram_write_count++;
}

void gavdp_device::trace_vram_read(const char *mode, const char *target, bool is_9000, offs_t offset, offs_t decode_offset, u8 data, u32 xbyte, u32 y_or_idx, u32 canon_y)
{
	if (!gavdp_trace_enabled() || !m_color_mode || m_visible_height != 200)
		return;

	const u32 phys = (is_9000 ? 0x90000u : 0x80000u) + (u32)offset;
	const u32 seg = phys >> 4;
	const u32 off16 = phys & 0x0f;
	const bool log_sample = (m_trace_vram_read_count < 4096) || (seg != m_trace_vram_last_read_segment);

	if (log_sample)
	{
		logerror("GAVDP VRAMR #%u mode=%s target=%s win=%s raw=%04x equiv=%04x:%04x decode=%04x x=%02x yidx=%03x canon_y=%03x data=%02x D068=%02x C060=%02x C261=%02x C663=%02x C462=%02x D269=%02x\n",
				m_trace_vram_read_count, mode, target, is_9000 ? "9000" : "8000",
				(u32)offset, seg, off16, (u32)decode_offset, xbyte, y_or_idx, canon_y, data,
				reg_read(REG_D068_OFFSET), reg_read(REG_C060_OFFSET), reg_read(REG_C261_OFFSET),
				reg_read(REG_C663_OFFSET), reg_read(REG_C462_OFFSET), reg_read(REG_D269_OFFSET));
	}

	m_trace_vram_last_read_segment = seg;
	m_trace_vram_read_count++;
}

// -------------------------------------------------
// Read/write handlers
// -------------------------------------------------

u8 gavdp_device::win_r(bool is_9000, offs_t offset)
{
	const bool clear_mode = (m_d068_last & 0x80) != 0;

	// In clear/scroll mode, row-major bitmap addressing takes priority over
	// the MMIO split so offsets 0xC000..0xC74F can still address scanlines
	// 192..199. Register offsets are protected by xbyte < 80.
	if (clear_mode)
	{
		if (m_color_mode)
		{
			offs_t decode_offset = offset;
			const u32 raw_x = (u32)(offset & 0xff);
			int plane = -1;

			if (is_9000)
			{
				// Color pixel/rectangle helpers use 9000:yyyy as one direct plane.
				plane = 1;
			}
			else if (raw_x >= 0x80u && raw_x < 0x80u + (u32)VRAM_COLS)
			{
				// 8008:yyyy reaches this aperture with the low byte biased by 0x80.
				decode_offset -= 0x80;
				plane = 2;
			}
			else
			{
				// 8000:yyyy is the third direct plane.
				plane = 0;
			}

			const u32 xbyte = (u32)(decode_offset & 0xff);
			const u32 y = (u32)((decode_offset >> 8) & 0xff);
			if (plane >= 0 && xbyte < (u32)VRAM_COLS && y < 200u)
			{
				const u32 off = xbyte * VRAM_CANON_BYTES_PER_COL + y;
				const u8 data = (off < m_color_plane[plane].size()) ? m_color_plane[plane][off] : 0x00;
				trace_vram_read("row", plane == 0 ? "color_plane_8000" : (plane == 1 ? "color_plane_9000" : "color_plane_8008"),
						is_9000, offset, decode_offset, data, xbyte, y, y);
				return data;
			}
		}

		u32 xbyte = 0, canon_y = 0;
		if (decode_row_major(is_9000, offset, xbyte, canon_y))
		{
			const u32 idx = (canon_y < 200u) ? canon_y : (0x100u + (canon_y - 200u));
			const u32 off = xbyte * VRAM_CANON_BYTES_PER_COL + idx;
			const u8 data = (off < m_vram.size()) ? m_vram[off] : 0x00;
			const bool use_9008_page = is_9000 && m_visible_height == 200
					&& ((offset & 0xff) >= 0x80) && ((offset & 0xff) < 0x80 + VRAM_COLS);
			offs_t decode_offset = offset;
			if (use_9008_page)
				decode_offset -= 0x80;
			else if (is_9000 && m_visible_height == 200 && decode_offset >= 0x100)
				decode_offset -= 0x100;
			trace_vram_read("row", use_9008_page ? "vram_9008_alias" : "vram", is_9000, offset, decode_offset, data, xbyte, idx, canon_y);
			return data;
		}
	}

	// MMIO region (register space)
	if (offset >= VRAM_MMIO_SPLIT)
		return reg_read(offset);

	// Normal mode: canonical column-major bitmap region (0x0000..0x9FFF)
	if (offset < VRAM_CANON_LIMIT)
	{
		if (m_color_mode)
		{
			const bool latch_9010 = is_9000 && offset >= 0x100;
			const bool plane_8010 = !is_9000 && offset >= 0x100;
			const offs_t decode_offset = (latch_9010 || plane_8010) ? (offset - 0x100) : offset;
			u32 xbyte = 0, idx9 = 0;
			if (!decode_col_major(decode_offset, xbyte, idx9))
				return 0x00;

			const u32 off = xbyte * VRAM_CANON_BYTES_PER_COL + idx9;
			if (latch_9010)
			{
				const u8 data = (off < m_vram.size()) ? m_vram[off] : 0x00;
				trace_vram_read("col", "color_latch_9010", is_9000, offset, decode_offset, data, xbyte, idx9, idx9);
				return data;
			}

			const u32 plane = plane_8010 ? 0 : (is_9000 ? 1 : 2);
			const u8 data = (off < m_color_plane[plane].size()) ? m_color_plane[plane][off] : 0x00;
			trace_vram_read("col", plane == 0 ? "color_plane_8010" : (plane == 1 ? "color_plane_9000" : "color_plane_8000"),
					is_9000, offset, decode_offset, data, xbyte, idx9, idx9);
			return data;
		}

		const bool visible_9010_200 = is_9000 && m_visible_height == 200 && offset >= 0x100;
		const offs_t decode_offset = visible_9010_200 ? (offset - 0x100) : offset;
		u32 xbyte = 0, idx9 = 0;
		if (!decode_col_major(decode_offset, xbyte, idx9))
			return 0x00;

		const u32 off = xbyte * VRAM_CANON_BYTES_PER_COL + idx9;
		if (is_9000 && !visible_9010_200)
		{
			const u8 data = (off < m_hidden_vram.size()) ? m_hidden_vram[off] : 0x00;
			trace_vram_read("col", "hidden_9000", is_9000, offset, decode_offset, data, xbyte, idx9, idx9);
			return data;
		}
		const u8 data = (off < m_vram.size()) ? m_vram[off] : 0x00;
		trace_vram_read("col", visible_9010_200 ? "vram_9010" : "vram", is_9000, offset, decode_offset, data, xbyte, idx9, idx9);
		return data;
	}

	// Fallback: treat as MMIO backing store
	return reg_read(offset);
}

void gavdp_device::win_w(bool is_9000, offs_t offset, u8 data)
{
	const bool clear_mode = (m_d068_last & 0x80) != 0;
	auto color_latch_expand = [this] (u32 off, u8 data)
	{
		if (off >= m_vram.size())
			return;

		m_vram[off] = data;

		const u8 attr = reg_read(REG_D269_OFFSET) & 0x77;
		const u8 fg = attr & 0x07;
		const u8 bg = (attr >> 4) & 0x07;
		const u8 inv = data ^ 0xff;

		for (u32 plane = 0; plane < 3; plane++)
		{
			u8 expanded = 0x00;
			if (BIT(fg, plane))
				expanded |= data;
			if (BIT(bg, plane))
				expanded |= inv;
			m_color_plane[plane][off] = expanded;
		}
	};

	if ((reg_read(REG_D068_OFFSET) & 0x7f) == 7)
	{
		u32 idx;
		if (color_attr_index_from_off(offset, idx))
			m_color_attr[idx] = reg_read(REG_D269_OFFSET) & 0x77;
	}

	if (clear_mode)
	{
		if (m_color_mode)
		{
			offs_t decode_offset = offset;
			const u32 raw_x = (u32)(offset & 0xff);
			int plane = -1;

			if (is_9000)
			{
				plane = 1;
			}
			else if (raw_x >= 0x80u && raw_x < 0x80u + (u32)VRAM_COLS)
			{
				decode_offset -= 0x80;
				plane = 2;
			}
			else
			{
				plane = 0;
			}

			const u32 xbyte = (u32)(decode_offset & 0xff);
			const u32 y = (u32)((decode_offset >> 8) & 0xff);
			if (plane >= 0 && xbyte < (u32)VRAM_COLS && y < 200u)
			{
				const u32 off = xbyte * VRAM_CANON_BYTES_PER_COL + y;
				trace_clear_write(is_9000, offset, data, xbyte, y);
				trace_vram_write("row", plane == 0 ? "color_plane_8000" : (plane == 1 ? "color_plane_9000" : "color_plane_8008"),
						is_9000, offset, decode_offset, data, xbyte, y, y);
				if (off < m_color_plane[plane].size())
					m_color_plane[plane][off] = data;
				return;
			}
		}

		u32 xbyte = 0, canon_y = 0;
		if (decode_row_major(is_9000, offset, xbyte, canon_y))
		{
			trace_clear_write(is_9000, offset, data, xbyte, canon_y);
			const u32 idx = (canon_y < 200u) ? canon_y : (0x100u + (canon_y - 200u));
			const u32 off = xbyte * VRAM_CANON_BYTES_PER_COL + idx;
			const bool use_9008_page = is_9000 && m_visible_height == 200
					&& ((offset & 0xff) >= 0x80) && ((offset & 0xff) < 0x80 + VRAM_COLS);
			offs_t decode_offset = offset;
			if (use_9008_page)
				decode_offset -= 0x80;
			else if (is_9000 && m_visible_height == 200 && decode_offset >= 0x100)
				decode_offset -= 0x100;
			trace_vram_write("row", use_9008_page ? "vram_9008_alias" : "vram", is_9000, offset, decode_offset, data, xbyte, idx, canon_y);
			if (off < m_vram.size())
				m_vram[off] = data;
			if (m_color_mode)
				color_latch_expand(off, data);
			return;
		}

		u32 y = 0;
		if (decode_mode_set_clear_alias(is_9000, offset, xbyte, y))
		{
			trace_clear_write(is_9000, offset, data, xbyte, y);
			trace_clear_write(is_9000, offset, data, xbyte, 200u + y);
			const u32 top_off = xbyte * VRAM_CANON_BYTES_PER_COL + y;
			const u32 bottom_off = xbyte * VRAM_CANON_BYTES_PER_COL + 0x100u + y;
			trace_vram_write("alias", "mode_set_alias", is_9000, offset, offset - 0x80, data, xbyte, y, y);
			if (top_off < m_vram.size())
				m_vram[top_off] = data;
			if (bottom_off < m_vram.size())
				m_vram[bottom_off] = data;
			if (m_color_mode)
			{
				color_latch_expand(top_off, data);
				color_latch_expand(bottom_off, data);
			}
			return;
		}

		trace_clear_reject(is_9000, offset, data);
	}


	// MMIO region (register space)
	if (offset >= VRAM_MMIO_SPLIT)
	{
		if (offset == REG_D068_OFFSET && (data & 0x80) == 0)
			trace_flush_clear("D068 clear bit dropped");
		reg_write(offset, data);
		if (offset == REG_D068_OFFSET || offset == REG_C060_OFFSET || offset == REG_C261_OFFSET)
			update_geometry_from_profile();
		return;
	}

	// Normal mode: canonical column-major bitmap region (0x0000..0x9FFF)
	if (offset < VRAM_CANON_LIMIT)
	{
		if (m_color_mode)
		{
			const bool latch_9010 = is_9000 && offset >= 0x100;
			const bool plane_8010 = !is_9000 && offset >= 0x100;
			const offs_t decode_offset = (latch_9010 || plane_8010) ? (offset - 0x100) : offset;
			u32 xbyte = 0, idx9 = 0;
			if (!decode_col_major(decode_offset, xbyte, idx9))
				return;

			const u32 off = xbyte * VRAM_CANON_BYTES_PER_COL + idx9;
			if (latch_9010)
			{
				trace_vram_write("col", "color_latch_9010", is_9000, offset, decode_offset, data, xbyte, idx9, idx9);
				color_latch_expand(off, data);
				return;
			}

			const u32 plane = plane_8010 ? 0 : (is_9000 ? 1 : 2);
			trace_vram_write("col", plane == 0 ? "color_plane_8010" : (plane == 1 ? "color_plane_9000" : "color_plane_8000"),
					is_9000, offset, decode_offset, data, xbyte, idx9, idx9);
			if (off < m_color_plane[plane].size())
				m_color_plane[plane][off] = data;
			return;
		}

		const bool visible_9010_200 = is_9000 && m_visible_height == 200 && offset >= 0x100;
		const offs_t decode_offset = visible_9010_200 ? (offset - 0x100) : offset;
		u32 xbyte = 0, idx9 = 0;
		if (!decode_col_major(decode_offset, xbyte, idx9))
			return;

		const u32 off = xbyte * VRAM_CANON_BYTES_PER_COL + idx9;
		if (is_9000 && !visible_9010_200)
		{
			trace_vram_write("col", "hidden_9000", is_9000, offset, decode_offset, data, xbyte, idx9, idx9);
			if (off < m_hidden_vram.size())
				m_hidden_vram[off] = data;
			return;
		}
		trace_vram_write("col", visible_9010_200 ? "vram_9010" : "vram", is_9000, offset, decode_offset, data, xbyte, idx9, idx9);
		if (off < m_vram.size())
			m_vram[off] = data;
		return;
	}

	// Fallback: MMIO backing store
	if (offset == REG_D068_OFFSET && (data & 0x80) == 0)
		trace_flush_clear("D068 clear bit dropped");
	reg_write(offset, data);
	if (offset == REG_D068_OFFSET || offset == REG_C060_OFFSET || offset == REG_C261_OFFSET)
		update_geometry_from_profile();
		
}

// -------------------------------------------------
// Rendering
// -------------------------------------------------

void gavdp_device::render_mode_mono(bitmap_rgb32 &bitmap, const rectangle &cliprect)
{
	const int width  = m_visible_width;
	const int height = m_visible_height;

	if (m_visible_cols <= 0)
		return;

	const u32 scroll_mod = (m_visible_height == 200) ? 200u : 400u;
	const u32 scroll_base = (u32)effective_scroll_px() % scroll_mod;
	const u32 horizontal_base = (m_visible_cols == VRAM_COLS && height == 400) ? horizontal_scroll_cols() : 0;

	for (int y = cliprect.min_y; y <= cliprect.max_y && y < height; ++y)
	{
		const u32 canon_y = ((u32)y + scroll_base) % scroll_mod;

		// Canonical stacked mapping
		const u32 scan_index = (canon_y < 200u) ? canon_y : (0x0100u + (canon_y - 200u));

		for (int x = cliprect.min_x; x <= cliprect.max_x && x < width; ++x)
		{
			const int display_col = x >> 3;
			const int col = (display_col + int(horizontal_base)) % m_visible_cols;
			if (col < 0 || col >= m_visible_cols)
			{
				bitmap.pix(y, x) = rgb_t::black();
				continue;
			}

			const int bit = 7 - (x & 7);
			const u32 col_base = (u32)col * VRAM_CANON_BYTES_PER_COL;
			const u32 off = col_base + scan_index;

			const u8 b = (off < m_vram.size()) ? m_vram[off] : 0x00;
			const bool on = ((b >> bit) & 1) != 0;

			bitmap.pix(y, x) = on ? rgb_t(0x00, 0xff, 0x00) : rgb_t(0x00, 0x00, 0x00);
		}
	}
}

void gavdp_device::render_mode_color(bitmap_rgb32 &bitmap, const rectangle &cliprect)
{
	const int width  = m_visible_width;
	const int height = m_visible_height;

	if (m_visible_cols <= 0)
		return;

	const u32 scroll_base = (u32)effective_scroll_px() % 200u;
	if (gavdp_trace_enabled())
	{
		static u32 last_color_scroll = 0xffffffff;
		static u32 color_frame_count = 0;
		if (last_color_scroll != scroll_base || color_frame_count < 8)
		{
			logerror("GAVDP COLOR frame=%u scroll_base=%u visible=%dx%d D068=%02x C060=%02x C261=%02x C663=%02x C462=%02x D269=%02x\n",
					color_frame_count, scroll_base, width, height,
					reg_read(REG_D068_OFFSET), reg_read(REG_C060_OFFSET), reg_read(REG_C261_OFFSET),
					reg_read(REG_C663_OFFSET), reg_read(REG_C462_OFFSET), reg_read(REG_D269_OFFSET));
			last_color_scroll = scroll_base;
		}
		color_frame_count++;
	}

	for (int y = cliprect.min_y; y <= cliprect.max_y && y < height; ++y)
	{
		const u32 canon_y = ((u32)y + scroll_base) % 200u;

		const u32 scan_index = canon_y;

		for (int x = cliprect.min_x; x <= cliprect.max_x && x < width; ++x)
		{
			const int col = x >> 3;
			if (col < 0 || col >= m_visible_cols)
			{
				bitmap.pix(y, x) = rgb_t::black();
				continue;
			}

			const int bit = 7 - (x & 7);
			const u32 col_base = (u32)col * VRAM_CANON_BYTES_PER_COL;
			const u32 off = col_base + scan_index;

			u8 color = 0;
			for (u32 plane = 0; plane < 3; plane++)
			{
				const u8 b = (off < m_color_plane[plane].size()) ? m_color_plane[plane][off] : 0x00;
				if (BIT(b, bit))
					color |= 1 << plane;
			}

			bitmap.pix(y, x) = m_palette[color & 0x07];
		}
	}
}



u32 gavdp_device::screen_update(screen_device &screen, bitmap_rgb32 &bitmap, const rectangle &cliprect)
{
	if (reg_read(REG_D068_OFFSET) != m_d068_last)
		update_geometry_from_profile();
	if ((m_d068_last & 0x80) == 0)
		trace_flush_clear("screen update normal mode");

	if (m_color_mode)
		render_mode_color(bitmap, cliprect);
	else
		render_mode_mono(bitmap, cliprect);

	return 0;
}
