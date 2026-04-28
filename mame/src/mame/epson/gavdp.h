// license:BSD-3-Clause
// Epson QX-11 GAVDP (Video Processor / Gate Array)
// Alias-window model:
//
//  - Driver installs TWO 0x10000 apertures:
//        install_vram_window(space, 0x80000);
//        install_vram_window(space, 0x90000);
//
//  - These are NOT two independent framebuffers in Mode 7.
//    They are two *views* into the same canonical, column-centric VRAM layout:
//
//      Canonical per-column storage is 0x200 bytes (512) per column:
//        idx 0x000..0x0C7 : top 200 scanlines
//        idx 0x100..0x1C7 : bottom 200 scanlines
//
//    Conceptually:
//      8000:yyyy addresses idx 0x000.. (top half) when yyyy is 0..199
//      8000:0100-style column-major addresses provide the bottom half.
//      In 400-line mono, 9000 column-major accesses are an offscreen
//      scratch/page area used for save-under operations.  In 200-line mono,
//      9010:0000 is the visible 200-line page base.
//      In clear/scroll mode, 9000 remains the row-major bottom-half view for
//      400-line mono; 9008-biased row-major writes address the same visible
//      200-line page as 9010-biased column-major writes in 200-line mono.
//
//  - BIOS uses two bitmap addressing styles:
//      * regular mode (D068 bit 7 clear): column-major bitmap writes
//          offset = (xbyte<<9) | idx9
//          one byte is 8 horizontal pixels; offset + 1 advances vertically.
//      * clear/scroll mode (D068 bit 7 set): row-major bitmap writes
//          offset = (y<<8) | xbyte
//          one byte is 8 horizontal pixels; offset + 1 advances horizontally.
//        The BIOS mode-set clear loop uses ES=9008, which reaches the 9000
//        aperture with xbyte biased by +0x80.  That path is accepted only as
//        a mode-set clear alias; regular clear/scroll writes remain xbyte 0..79.
//
//  - Clear/scroll mode does not make a single write represent an 8x16 text cell.
//    Text rows are a BIOS/software convention; the GAVDP VRAM contract remains
//    bitmap bytes plus a row-major address transform.
//

#pragma once

#include "screen.h"
#include "emupal.h"
#include <array>
#include <vector>

class gavdp_device :
	public device_t,
	public device_video_interface
{
public:
	gavdp_device(const machine_config &mconfig, const char *tag, device_t *owner, u32 clock);

	// Install a 0x10000 window. The base selects which alias view is used (0x80000 vs 0x90000).
	void install_vram_window(address_space &space, u32 base);

	// If your machine config's screen isn't tagged "screen", override it (e.g. "^screen").
	void set_screen_tag(const char *tag);

	u32 screen_update(screen_device &screen, bitmap_rgb32 &bitmap, const rectangle &cliprect);

protected:
	virtual void device_start() override;
	virtual void device_reset() override;

private:
	// -------------------------------------------------
	// Layout
	// -------------------------------------------------
	static constexpr int  VRAM_COLS               = 80;     // 640/8
	static constexpr int  VRAM_BYTES_PER_COL      = 0x200;  // canonical stacked layout per column
	static constexpr u32  VRAM_WINDOW_SIZE        = 0x10000;
	static constexpr u32  VRAM_CANON_BYTES_PER_COL = 0x200; // canonical col stride
	static constexpr u32  VRAM_CANON_SIZE = VRAM_COLS * VRAM_CANON_BYTES_PER_COL; // 0xA000
	static constexpr offs_t VRAM_CANON_LIMIT = VRAM_CANON_SIZE;

	// Normal VRAM occupies 0x0000..0x9fff; clear/scroll row-major access is
	// decoded before the MMIO split so scanlines 192..199 remain reachable.
	static constexpr offs_t VRAM_MMIO_SPLIT       = 0x0C000;

	// MMIO offsets (within aperture)
	static constexpr offs_t REG_C060_OFFSET = 0x0C060;
	static constexpr offs_t REG_C261_OFFSET = 0x0C261;
	static constexpr offs_t REG_C462_OFFSET = 0x0C462;
	static constexpr offs_t REG_C663_OFFSET = 0x0C663;
	static constexpr offs_t REG_D068_OFFSET = 0x0D068;
	static constexpr offs_t REG_D269_OFFSET = 0x0D269;

	// -------------------------------------------------
	// Window handlers
	// -------------------------------------------------
	u8  win_r_8000(offs_t offset);
	void win_w_8000(offs_t offset, u8 data);

	u8  win_r_9000(offs_t offset);
	void win_w_9000(offs_t offset, u8 data);

	u8  win_r(bool is_9000, offs_t offset);
	void win_w(bool is_9000, offs_t offset, u8 data);

	inline bool color_attr_index_from_off(u32 off, u32 &idx) const;
	
	// -------------------------------------------------
	// Decode helpers
	// -------------------------------------------------
	// Column-major: offset = (xbyte<<9) | idx9  where idx9 can be 0..0x1C7
	bool decode_col_major(offs_t offset, u32 &xbyte, u32 &idx9) const;

	// Row-major: offset = (y<<8) | xbyte, y is 0..199; segment selects half.
	bool decode_row_major(bool is_9000, offs_t offset, u32 &xbyte, u32 &canon_y) const;

	// Mode-set clear alias: ES=9008 appears as 9000:(y<<8)|(0x80+x).
	bool decode_mode_set_clear_alias(bool is_9000, offs_t offset, u32 &xbyte, u32 &y) const;

	// -------------------------------------------------
	// MMIO helpers
	// -------------------------------------------------
	inline u8  reg_read(offs_t off) const;
	inline void reg_write(offs_t off, u8 data);
	void update_geometry_from_profile();

	// -------------------------------------------------
	// Rendering
	// -------------------------------------------------
	void render_mode_mono(bitmap_rgb32 &bitmap, const rectangle &cliprect);
	void render_mode_color(bitmap_rgb32 &bitmap, const rectangle &cliprect);
	int  effective_scroll_px() const;
	void trace_clear_write(bool is_9000, offs_t offset, u8 data, u32 xbyte, u32 canon_y);
	void trace_clear_reject(bool is_9000, offs_t offset, u8 data);
	void trace_flush_clear(const char *reason);
	void trace_vram_write(const char *mode, const char *target, bool is_9000, offs_t offset, offs_t decode_offset, u8 data, u32 xbyte, u32 y_or_idx, u32 canon_y);
	void trace_vram_read(const char *mode, const char *target, bool is_9000, offs_t offset, offs_t decode_offset, u8 data, u32 xbyte, u32 y_or_idx, u32 canon_y);

private:
	required_device<screen_device> m_screen;

	// Canonical stacked VRAM (mode 7): 80 cols * 0x200 bytes/col
	std::vector<u8> m_vram;

	// Normal-mode 9000 scratch page: preserves save-under accesses without
	// rendering them as visible bottom VRAM.
	std::vector<u8> m_hidden_vram;

	// Color mode has three 1bpp output planes.  BIOS text writes target
	// 9010:xxxx as a latch-expanded glyph stream, while direct plane helpers
	// use the 8010/9000/8000 segment trio.
	std::array<std::vector<u8>, 3> m_color_plane;

	// Backing for full 0x10000 aperture (registers/unused); shared across both windows
	std::vector<u8> m_mmio;

	std::array<u8,2000> m_color_attr;

	// Cached mode/geometry
	bool m_color_mode      = false;
	int  m_visible_height  = 400;
	int  m_visible_cols    = 80;
	int  m_visible_width   = 640;

	// Cached regs
	u8 m_d068_last = 0x00;
	u8 m_reg_c663  = 0x00;
	u8 m_reg_c462  = 0x00;
	u8 m_reg_c261  = 0x00;

	rgb_t m_palette[8];

	bool m_trace_clear_active = false;
	u64 m_trace_clear_count = 0;
	u64 m_trace_clear_reject_count = 0;
	u64 m_trace_clear_zero_count = 0;
	u64 m_trace_clear_ff_count = 0;
	u32 m_trace_clear_min_x = 0;
	u32 m_trace_clear_max_x = 0;
	u32 m_trace_clear_min_y = 0;
	u32 m_trace_clear_max_y = 0;
	u32 m_trace_clear_min_off = 0;
	u32 m_trace_clear_max_off = 0;
	u32 m_trace_clear_windows = 0;
	u32 m_trace_clear_reject_min_off = 0;
	u32 m_trace_clear_reject_max_off = 0;
	u32 m_trace_clear_reject_samples = 0;
	u32 m_trace_vram_write_count = 0;
	u32 m_trace_vram_last_segment = 0xffffffff;
	u32 m_trace_vram_read_count = 0;
	u32 m_trace_vram_last_read_segment = 0xffffffff;
};

DECLARE_DEVICE_TYPE(EPSON_GAVDP, gavdp_device)
