// license:BSD-3-Clause
// Epson QX-11 GAVDP (Video Processor / Gate Array)

#include "emu.h"
#include "gavdp.h"

DEFINE_DEVICE_TYPE(EPSON_GAVDP, gavdp_device, "epson_gavdp", "Epson QX-11 GAVDP")

// ============================================================================
//  Construction
// ============================================================================

gavdp_device::gavdp_device(const machine_config &mconfig, const char *tag, device_t *owner, u32 clock)
	: device_t(mconfig, EPSON_GAVDP, tag, owner, clock)
	, device_video_interface(mconfig, *this)
	, m_screen(*this, "screen")
{
}

// ============================================================================
//  device_t
// ============================================================================

void gavdp_device::device_start()
{
	// Full GAVDP VRAM window
	m_vram.resize(VRAM_WINDOW_SIZE);
	std::fill(m_vram.begin(), m_vram.end(), 0);

	save_item(NAME(m_vram));
	save_item(NAME(m_vram_base));
	save_item(NAME(m_color_mode));
	save_item(NAME(m_visible_width));
	save_item(NAME(m_visible_height));
	save_item(NAME(m_visible_cols));

	// State for CLS/scroll detection
	save_item(NAME(m_d068_last));
	save_item(NAME(m_clear_scroll_mode));
	save_item(NAME(m_scroll_mode));

	// Erase tracking
	save_item(NAME(m_erase_tracking));
	save_item(NAME(m_erase_min));
	save_item(NAME(m_erase_max));
	save_item(NAME(m_erase_count));
	save_item(NAME(m_erase_min_low));
	save_item(NAME(m_erase_max_low));

	// Scroll clear logging
	save_item(NAME(m_col_used));
	save_item(NAME(m_col_min_idx));
	save_item(NAME(m_col_max_idx));
	save_item(NAME(m_reg_c663));
	save_item(NAME(m_reg_c462));

	init_palette();

	// Default: hi-res mono 640x400
	m_color_mode     = false;
	m_visible_cols   = 80;
	m_visible_width  = 640;
	m_visible_height = 400;

	m_cpu_space          = nullptr;
	m_d068_last          = 0x00;
	m_clear_scroll_mode  = false;
	m_scroll_mode        = false;

	m_erase_tracking = false;
	m_erase_min      = 0;
	m_erase_max      = 0;
	m_erase_count    = 0;
	m_erase_min_low  = 0xff;
	m_erase_max_low  = 0x00;

	for (int col = 0; col < VRAM_COLS; ++col)
	{
		m_col_used[col]    = 0;
		m_col_min_idx[col] = 0xffff;
		m_col_max_idx[col] = 0x0000;
	}

	m_reg_c663 = 0;
	m_reg_c462 = 0;
}

void gavdp_device::device_reset()
{
	// BIOS will rewrite D068; geometry is re-sampled each frame.
}

void gavdp_device::device_add_mconfig(machine_config &config)
{
	SCREEN(config, m_screen, SCREEN_TYPE_RASTER);

	// Nominal timing; visible area adjusted at runtime.
	m_screen->set_raw(14'318'180, 912, 0, 640, 449, 0, 400);
	m_screen->set_screen_update(*this, FUNC(gavdp_device::screen_update));
}

// ============================================================================
//  Public API
// ============================================================================

void gavdp_device::install_vram_window(address_space &space, u32 base)
{
	m_cpu_space = &space;
	m_vram_base = base;

	space.install_readwrite_handler(
		base,
		base + VRAM_WINDOW_SIZE - 1,
		read8sm_delegate(*this, FUNC(gavdp_device::vram_r)),
		write8sm_delegate(*this, FUNC(gavdp_device::vram_w)));
}

u8 gavdp_device::vram_r(offs_t offset)
{
	if (offset < VRAM_WINDOW_SIZE)
		return m_vram[offset];
	return 0xff;
}

// ============================================================================
//  Core VRAM write handler with CLS/scroll detection + scroll fix
// ============================================================================

void gavdp_device::vram_w(offs_t offset, u8 data)
{
	// ---------------- D068: profile + bit7 = clear/scroll engine ----------
	if (offset == REG_D068_OFFSET)
	{
		u8 old = m_d068_last;
		m_d068_last = data;

		bool old_clear = (old & 0x80) != 0;
		bool new_clear = (data & 0x80) != 0;

		// Rising edge: enter clear/scroll phase
		if (!old_clear && new_clear)
		{
			m_clear_scroll_mode = true;
			m_scroll_mode       = false;   // assume CLS until we see C663

			// start counting zeros for this pass
			m_erase_tracking = true;
			m_erase_count    = 0;
			m_erase_min      = 0;
			m_erase_max      = 0;
			m_erase_min_low  = 0xff;
			m_erase_max_low  = 0x00;

			// reset per-column tracking
			for (int col = 0; col < VRAM_COLS; ++col)
			{
				m_col_used[col]    = 0;
				m_col_min_idx[col] = 0xffff;
				m_col_max_idx[col] = 0x0000;
			}
		}

	if (old_clear && !new_clear)
{
	if (m_erase_tracking)
	{
		logerror("GAVDP: CLEAR pass end (scroll=%d) zeros=%u\n",
		         (int)m_scroll_mode, m_erase_count);

		if (m_scroll_mode)
		{
			// SCROLL CASE
			logerror("GAVDP: SCROLL C663=%02X C462=%02X zeros=%u\n",
			         m_reg_c663, m_reg_c462, m_erase_count);

			if (m_erase_count >= 1200 && m_erase_count <= 1600)
				clear_scroll_bottom_band_for_columns();

			for (int col = 0; col < VRAM_COLS; ++col)
			{
				if (!m_col_used[col])
					continue;

				logerror("GAVDP: SCROLL col=%02d idx=%03X..%03X\n",
				         col,
				         (unsigned)m_col_min_idx[col],
				         (unsigned)m_col_max_idx[col]);
			}
		}
		else
		{
			// NON-SCROLL: either full CLS or smaller window
			if (m_erase_count >= 31840)
			{
				// Full-screen CLS
				logerror("GAVDP: CLS heuristic (zeros=%u) → clear_text_vram()\n",
				         m_erase_count);
				clear_text_vram();
			}
			else
			{
				// *** WINDOW CLEAR ***
				logerror("GAVDP: WINDOW CLEAR zeros=%u (no CLS)\n",
				         m_erase_count);

				// For debugging: geometry summary
				int used_cols = 0;
				int first_col = -1;
				int last_col  = -1;
				for (int col = 0; col < VRAM_COLS; ++col)
				{
					if (!m_col_used[col])
						continue;

					if (first_col < 0)
						first_col = col;
					last_col = col;
					used_cols++;

					logerror("GAVDP: WINDOW col=%02d idx=%03X..%03X\n",
					         col,
					         (unsigned)m_col_min_idx[col],
					         (unsigned)m_col_max_idx[col]);
				}

				logerror("GAVDP: WINDOW summary cols=%d range=%02d..%02d zeros=%u\n",
				         used_cols, first_col, last_col, m_erase_count);

				// Perform a logical rectangular clear based on the GA's band info.
				clear_window_from_ga();
			}
		}
	}

	// reset flags for next pass
	m_clear_scroll_mode = false;
	m_scroll_mode       = false;
	m_erase_tracking    = false;
	m_erase_count       = 0;
}



		// store D068 itself
		if (offset < VRAM_WINDOW_SIZE)
			m_vram[offset] = data;

		logerror("GAVDP: D068 write @%05X = %02X (clear_scroll=%d, scroll=%d)\n",
		         (unsigned)offset, data,
		         (int)m_clear_scroll_mode, (int)m_scroll_mode);
		return;
	}

	// ---------------- C663: scroll index ------------------------------------
	if (offset == REG_C663_OFFSET)
	{
		m_reg_c663 = data; // track latest scroll index

		// Any C663 write during clear/scroll marks this pass as scroll
		if (m_clear_scroll_mode)
			m_scroll_mode = true;

		if (offset < VRAM_WINDOW_SIZE)
			m_vram[offset] = data;

		logerror("GAVDP: C663 write @%05X = %02X (clear_scroll=%d, scroll=%d)\n",
		         (unsigned)offset, data,
		         (int)m_clear_scroll_mode, (int)m_scroll_mode);
		return;
	}

	// ---------------- C462: scroll phase helper -----------------------------
	if (offset == REG_C462_OFFSET)
	{
		m_reg_c462 = data; // track latest phase/flag

		if (offset < VRAM_WINDOW_SIZE)
			m_vram[offset] = data;

		logerror("GAVDP: C462 write @%05X = %02X (clear_scroll=%d, scroll=%d)\n",
		         (unsigned)offset, data,
		         (int)m_clear_scroll_mode, (int)m_scroll_mode);
		return;
	}

	// ---------------- D269: attribute register ------------------------------
	if (offset == REG_D269_OFFSET)
	{
		if (offset < VRAM_WINDOW_SIZE)
			m_vram[offset] = data;

		logerror("GAVDP: D269 write @%05X = %02X\n", (unsigned)offset, data);
		return;
	}

	// ---------------- Other GAVDP regs: log + store -------------------------
	if (offset == REG_C060_OFFSET ||
	    offset == REG_C261_OFFSET ||
	    offset == REG_D46A_OFFSET ||
	    offset == REG_C864_OFFSET ||
	    offset == REG_CA65_OFFSET ||
	    offset == REG_CC66_OFFSET ||
	    offset == REG_CE67_OFFSET)
	{
		if (offset < VRAM_WINDOW_SIZE)
			m_vram[offset] = data;

		logerror("GAVDP: REG write @%05X = %02X\n", (unsigned)offset, data);
		return;
	}

	// ---------------- Default: normal VRAM write ----------------------------
if (offset < VRAM_WINDOW_SIZE)
{
	// Count and track zero writes only while clear/scroll is active
	if (m_clear_scroll_mode && m_erase_tracking && data == 0x00)
	{
		m_erase_count++;

		// Column and index within column (0..79, 0..0x1FF)
		u32 col = offset / VRAM_BYTES_PER_COL;
		u16 idx = offset % VRAM_BYTES_PER_COL;

		if (col < VRAM_COLS)
		{
			m_col_used[col] = 1;
			if (idx < m_col_min_idx[col])
				m_col_min_idx[col] = idx;
			if (idx > m_col_max_idx[col])
				m_col_max_idx[col] = idx;
		}

		u8 low = (u8)(offset & 0xff);
		if (m_erase_min == 0 && m_erase_count == 1)
			m_erase_min = offset;
		if (offset > m_erase_max)
			m_erase_max = offset;
		if (low < m_erase_min_low)
			m_erase_min_low = low;
		if (low > m_erase_max_low)
			m_erase_max_low = low;

		// IMPORTANT:
		// During any GA clear pass (scroll / window / CLS),
		// we DO NOT apply the zero writes directly.
		// We emulate the clear logically at the end of the pass.
		return;
	}

	// Normal write (non-zero or not in clear pass)
	m_vram[offset] = data;
}
}

// ============================================================================
//  Window helper: clear GA-defined rectangle (small menu/window erases)
// ============================================================================
//
// We use the GA's band info (m_col_used[], m_col_min_idx[], m_col_max_idx[])
// accumulated during a WINDOW CLEAR pass, but instead of just taking the
// outermost min/max (which pulls in noise), we:
//
//  1) Find the *longest contiguous run* of columns where m_col_used[col] == 1.
//  2) Compute vmin/vmax only over that run.
//  3) Clear a solid band for that run.
//
// This usually matches the actual menu window and avoids stray columns/rows
// that make the rectangle too big or slightly shifted.
//

void gavdp_device::clear_window_from_ga()
{
	if (m_vram.empty())
		return;

	// --- 1) Find the longest run of used columns ---
	int best_start = -1;
	int best_len   = 0;

	int col = 0;
	while (col < VRAM_COLS)
	{
		// skip unused columns
		while (col < VRAM_COLS && !m_col_used[col])
			col++;

		if (col >= VRAM_COLS)
			break;

		int run_start = col;
		int run_len   = 0;

		// count contiguous used columns
		while (col < VRAM_COLS && m_col_used[col])
		{
			run_len++;
			col++;
		}

		if (run_len > best_len)
		{
			best_len   = run_len;
			best_start = run_start;
		}
	}

	if (best_start < 0 || best_len <= 0)
	{
		logerror("GAVDP: clear_window_from_ga: no contiguous used columns, nothing to do\n");
		return;
	}

	int first_col = best_start;
	int last_col  = best_start + best_len - 1;

	// --- 2) Compute vertical band only over that run ---
	u16 vmin = 0x1FF;
	u16 vmax = 0x000;

	for (int c = first_col; c <= last_col; ++c)
	{
		if (!m_col_used[c])
			continue;

		if (m_col_min_idx[c] < vmin)
			vmin = m_col_min_idx[c];
		if (m_col_max_idx[c] > vmax)
			vmax = m_col_max_idx[c];
	}

	if (vmin > vmax)
	{
		logerror("GAVDP: clear_window_from_ga: invalid vmin/vmax (%03X..%03X)\n",
		         (unsigned)vmin, (unsigned)vmax);
		return;
	}

	// Clamp to our per-column VRAM range.
	if (vmax >= VRAM_BYTES_PER_COL)
		vmax = VRAM_BYTES_PER_COL - 1;

	int cleared_cols  = 0;
	int cleared_lines = vmax - vmin + 1;

	// --- 3) Clear the solid band within that run ---
	for (int c = first_col; c <= last_col; ++c)
	{
		if (!m_col_used[c])
			continue;

		++cleared_cols;
		u32 col_base = c * VRAM_BYTES_PER_COL;

		for (u16 idx = vmin; idx <= vmax; ++idx)
		{
			u32 offset = col_base + idx;
			if (offset < m_vram.size())
				m_vram[offset] = 0x00;
		}
	}

	logerror("GAVDP: Window band cleared cols=%d (%d..%d) idx=%03X..%03X (lines≈%d)\n",
	         cleared_cols, first_col, last_col,
	         (unsigned)vmin, (unsigned)vmax, cleared_lines);
}

// ============================================================================
//  CLS helper: clear text VRAM region for this mode
// ============================================================================

void gavdp_device::clear_text_vram()
{
	if (m_vram.empty())
		return;

	// This is your "full erase" pattern for mono text:
	// clear 0x80–0xCF in each 0x100-byte band, up to 0x8E80.
	for (u32 base = 0x0000; base <= 0xCBFF; base += 0x0100)
	{
		u32 start = base;
		u32 end   = base + 0x00FF; // 0x80..0xCF → 80 bytes

		if (start >= m_vram.size())
			break;

		if (end >= m_vram.size())
			end = m_vram.size() - 1;

		for (u32 off = start; off <= end; ++off)
			m_vram[off] = 0x00;
	}

	logerror("GAVDP: CLS emulated (cleared bands 0x0080–0x8ECF, step 0x100)\n");
}

// ============================================================================
//  Scroll helper: clear logical bottom row (16-pixel band) for touched columns
// ============================================================================

void gavdp_device::clear_scroll_bottom_band_for_columns()
{
	if (m_vram.empty())
		return;

	const int height       = m_visible_height;         // 400 (mono) or 200 (color)
	const int total_lines  = height;
	const int band_height  = 16;                       // one text row
	const int bottom_start = height - band_height;     // e.g. 384 for 400-line

	u8 scroll_px = vram_byte(REG_C663_OFFSET);

	int cleared_cols = 0;

	for (int col = 0; col < m_visible_cols && col < VRAM_COLS; ++col)
	{
		if (!m_col_used[col])
			continue;

		++cleared_cols;

		u32 col_base = col * VRAM_BYTES_PER_COL;

		for (int y = bottom_start; y < height; ++y)
		{
			int scrolled_y = y + scroll_px;
			while (scrolled_y >= total_lines)
				scrolled_y -= total_lines;

			int scan_index;
			if (!m_color_mode)
			{
				// mono 640x400: split 0..199 / 200..399 across 0x000/0x100 bands
				if (scrolled_y < 200)
					scan_index = scrolled_y;                 // 0x000..0x00C7
				else
					scan_index = 0x100 + (scrolled_y - 200); // 0x0100..0x01C7
			}
			else
			{
				// color 640x200: single 0x000..0x00C7 band
				scan_index = scrolled_y;
			}

			u32 offset = col_base + scan_index;
			if (offset < m_vram.size())
				m_vram[offset] = 0x00;
		}
	}

	logerror("GAVDP: Scroll bottom band cleared for %d columns (height=%d, scroll=%02X)\n",
	         cleared_cols, height, scroll_px);
}

// ============================================================================
//  Screen update
// ============================================================================

u32 gavdp_device::screen_update(screen_device &screen, bitmap_rgb32 &bitmap, const rectangle &cliprect)
{
	update_geometry_from_profile();
	render_framebuffer(bitmap, cliprect);
	return 0;
}

// ============================================================================
//  Helpers
// ============================================================================

void gavdp_device::init_palette()
{
	// Very simple 8-color RGB palette for now.
	m_palette[0] = rgb_t(0x00, 0x00, 0x00); // black
	m_palette[1] = rgb_t(0x00, 0x00, 0xff); // blue
	m_palette[2] = rgb_t(0x00, 0xff, 0x00); // green
	m_palette[3] = rgb_t(0x00, 0xff, 0xff); // cyan
	m_palette[4] = rgb_t(0xff, 0x00, 0x00); // red
	m_palette[5] = rgb_t(0xff, 0x00, 0xff); // magenta
	m_palette[6] = rgb_t(0xff, 0xff, 0x00); // yellow
	m_palette[7] = rgb_t(0xff, 0xff, 0xff); // white
}

inline u8 gavdp_device::vram_byte(u32 offset) const
{
	if (offset < m_vram.size())
		return m_vram[offset];
	return 0xff;
}

inline u8 &gavdp_device::vram_byte_ref(u32 offset)
{
	static u8 dummy = 0xff;
	if (offset < m_vram.size())
		return m_vram[offset];
	return dummy;
}

void gavdp_device::update_geometry_from_profile()
{
	u8 prof_raw = vram_byte(REG_D068_OFFSET);
	u8 prof     = prof_raw & 0x7f; // ignore bit7 (CLS/scroll) for geometry

	bool new_color  = m_color_mode;
	int  new_height = m_visible_height;

	if (prof == 2)      // hi-res mono 640x400
	{
		new_color  = false;
		new_height = 400;
	}
	else if (prof == 7) // color 640x200
	{
		new_color  = true;
		new_height = 200;
	}

	int new_cols  = 80;
	int new_width = new_cols * 8;

	if (new_color != m_color_mode ||
	    new_height != m_visible_height ||
	    new_cols != m_visible_cols)
	{
		m_color_mode     = new_color;
		m_visible_height = new_height;
		m_visible_cols   = new_cols;
		m_visible_width  = new_width;

		if (m_screen)
			m_screen->set_visible_area(0, m_visible_width - 1, 0, m_visible_height - 1);
	}
}

// ============================================================================
//  Rendering – common
// ============================================================================

void gavdp_device::render_framebuffer(bitmap_rgb32 &bitmap, const rectangle &cliprect)
{
	bitmap.fill(rgb_t::black(), cliprect);

	if (m_color_mode)
		render_mode_color(bitmap, cliprect);
	else
		render_mode_mono(bitmap, cliprect);
}

// ============================================================================
//  Rendering – mono (640x400, simple pixel scroll with C663)
// ============================================================================

void gavdp_device::render_mode_mono(bitmap_rgb32 &bitmap, const rectangle &cliprect)
{
	const int width  = m_visible_width;   // 640
	const int height = m_visible_height;  // 400

	if (m_visible_cols <= 0)
		return;

	u8  c663         = vram_byte(REG_C663_OFFSET);
	int scroll_px    = int(c663);
	const int total_lines = 400;

	for (int y = cliprect.min_y; y <= cliprect.max_y && y < height; ++y)
	{
		int scrolled_y = y + scroll_px;
		while (scrolled_y >= total_lines)
			scrolled_y -= total_lines;

		int scan_index;
		if (scrolled_y < 200)
			scan_index = scrolled_y;                 // 0x000..0x00C7
		else
			scan_index = 0x100 + (scrolled_y - 200); // 0x0100..0x01C7

		for (int x = cliprect.min_x; x <= cliprect.max_x && x < width; ++x)
		{
			int col = x >> 3; // 0..79
			if (col < 0 || col >= m_visible_cols)
			{
				bitmap.pix(y, x) = rgb_t::black();
				continue;
			}

			int bit = 7 - (x & 7);

			u32 col_base = col * VRAM_BYTES_PER_COL; // 0x200 per column
			u32 offset   = col_base + scan_index;

			bool on = false;
			if (offset < VRAM_PLANE_SIZE)
			{
				u8 b = vram_byte(offset);
				on   = (b >> bit) & 0x01;
			}

			rgb_t color = on ? rgb_t(0xff, 0xff, 0xff) : rgb_t(0x00, 0x00, 0x00);
			bitmap.pix(y, x) = color;
		}
	}
}

// ============================================================================
//  Rendering – color (unchanged 640x200)
// ============================================================================

void gavdp_device::render_mode_color(bitmap_rgb32 &bitmap, const rectangle &cliprect)
{
	const int width  = m_visible_width;   // 640
	const int height = m_visible_height;  // 200

	if (m_visible_cols <= 0)
		return;

	u8 attr = vram_byte(REG_D269_OFFSET) & 0x77;
	u8 fg   = attr & 0x07;
	u8 bg   = (attr >> 4) & 0x07;

	u8  c663      = vram_byte(REG_C663_OFFSET);
	int scroll_px = int(c663);
	const int total_lines = 200;

	for (int y = cliprect.min_y; y <= cliprect.max_y && y < height; ++y)
	{
		int scrolled_y = y + scroll_px;
		while (scrolled_y >= total_lines)
			scrolled_y -= total_lines;

		int scan_index = scrolled_y; // 0x000..0x00C7

		for (int x = cliprect.min_x; x <= cliprect.max_x && x < width; ++x)
		{
			int col = x >> 3;
			if (col < 0 || col >= m_visible_cols)
			{
				bitmap.pix(y, x) = m_palette[bg];
				continue;
			}

			int bit = 7 - (x & 7);

			u32 col_base = col * VRAM_BYTES_PER_COL;
			u32 offset   = col_base + scan_index;

			bool on = false;
			if (offset < VRAM_PLANE_SIZE)
			{
				u8 b = vram_byte(offset);
				on   = (b >> bit) & 0x01;
			}

			rgb_t color = on ? m_palette[fg] : m_palette[bg];
			bitmap.pix(y, x) = color;
		}
	}
}
