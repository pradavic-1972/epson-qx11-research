// license:BSD-3-Clause
// Epson QX-11 GAVDP (Video Processor / Gate Array)

#ifndef MAME_EPSON_GAVDP_H
#define MAME_EPSON_GAVDP_H

#pragma once

#include "emupal.h"
#include "screen.h"
#include "device.h"

// ============================================================================
//  Device type
// ============================================================================

DECLARE_DEVICE_TYPE(EPSON_GAVDP, gavdp_device)

// ============================================================================
//  GAVDP device
// ============================================================================
//
//  - Column-centric VRAM
//  - Per-column layout (512 bytes):
//        0x0000–0x00C7 : visible rows 0–199  (top half)
//        0x00C8–0x00FF : gap (unused)
//        0x0100–0x01C7 : visible rows 200–399 (bottom half, mono only)
//        0x01C8–0x01FF : gap (unused)
//  - Monochrome: 640×400 uses both halves
//  - Color:      640×200 uses only 0x0000–0x00C7 (top half), bottom is 0
//  - C663 is a vertical scroll index (pixels), applied as a simple ring:
//        mono : (y + C663) % 400
//        color: (y + C663) % 200
//  - 8D068 (machine profile):
//        0x02 → mono 640×400
//        0x07 → color 640×200
//        bit7 is used as a clear/scroll engine flag.
//  - 8D269 (attribute) is used only in color mode as a global fg/bg color.
//

class gavdp_device :
	public device_t,
	public device_video_interface
{
public:
	// --------------------------------------------------------------------
	//  Construction
	// --------------------------------------------------------------------
	gavdp_device(const machine_config &mconfig, const char *tag, device_t *owner, u32 clock);

	// Map GAVDP window into the main CPU address space at `base`.
	// This installs a full 64 KiB segment (0x0000–0xFFFF) backed by m_vram.
	void install_vram_window(address_space &space, u32 base);

	// Raw VRAM access (for debugging / logs)
	u8  vram_r(offs_t offset);
	void vram_w(offs_t offset, u8 data);

	// Screen update callback
	u32 screen_update(screen_device &screen, bitmap_rgb32 &bitmap, const rectangle &cliprect);

protected:
	// device_t
	virtual void device_start() override;
	virtual void device_reset() override;
	virtual void device_add_mconfig(machine_config &config) override;

private:
	// --------------------------------------------------------------------
	//  Internal constants / layout
	// --------------------------------------------------------------------

	// Bitmap plane: 80 columns × 0x200 bytes = 0xA000, but we leave some headroom.
	static constexpr int VRAM_COLS           = 80;
	static constexpr int VRAM_BYTES_PER_COL  = 0x200;
	static constexpr int VRAM_PLANE_SIZE     = VRAM_COLS * VRAM_BYTES_PER_COL; // 0xA000

	// CPU-visible GAVDP window: full 64 KiB segment (0x0000–0xFFFF)
	static constexpr int VRAM_WINDOW_SIZE    = 0x10000;

	// GAVDP "register" mirrors in VRAM
	static constexpr offs_t REG_C060_OFFSET  = 0x0C060;
	static constexpr offs_t REG_C261_OFFSET  = 0x0C261;
	static constexpr offs_t REG_C462_OFFSET  = 0x0C462;
	static constexpr offs_t REG_C663_OFFSET  = 0x0C663;
	static constexpr offs_t REG_D068_OFFSET  = 0x0D068;
	static constexpr offs_t REG_D269_OFFSET  = 0x0D269;
	static constexpr offs_t REG_D46A_OFFSET  = 0x0D46A;
	static constexpr offs_t REG_C864_OFFSET  = 0x0C864;
	static constexpr offs_t REG_CA65_OFFSET  = 0x0CA65;
	static constexpr offs_t REG_CC66_OFFSET  = 0x0CC66;
	static constexpr offs_t REG_CE67_OFFSET  = 0x0CE67;

	// --------------------------------------------------------------------
	//  Subdevices
	// --------------------------------------------------------------------

	// The GAVDP owns its own screen.
	required_device<screen_device> m_screen;

	// --------------------------------------------------------------------
	//  VRAM and mapping
	// --------------------------------------------------------------------

	// Full 64 KiB GAVDP window as seen by the CPU (0x0000–0xFFFF).
	// Bitmap data lives in [0x0000..0xBFFF]. The rest (0xC000–0xFFFF)
	// is used by BIOS as control/mirror area (e.g., 0xD068, 0xD269).
	std::vector<u8> m_vram;

	// Base address where the window is installed in the CPU program space.
	u32             m_vram_base = 0;
	address_space  *m_cpu_space = nullptr;

	// --------------------------------------------------------------------
	//  Video state mirrors
	// --------------------------------------------------------------------

	bool m_color_mode        = false; // false: mono 640×400, true: color 640×200
	bool m_scroll_mode       = false; // true: this clear pass is a scroll (C663 written)
	bool m_clear_scroll_mode = false; // true: D068 bit7 is set (clear/scroll engine active)
	bool m_app_clear         = false; // (unused right now, reserved)

	int  m_visible_height    = 400;   // scanlines visible: 400 or 200
	int  m_visible_cols      = 80;    // always 80 logical character columns
	int  m_visible_width     = 640;   // m_visible_cols * 8

	int  m_d068_last         = 0;     // last value written to D068 (profile/engine)

	// Erase tracking (while D068 bit7 is set)
	bool m_erase_tracking    = false;
	u32  m_erase_min         = 0;     // smallest offset zeroed (unused in current heuristic)
	u32  m_erase_max         = 0;     // largest offset zeroed (unused)
	u32  m_erase_count       = 0;     // how many zero writes this pass
	u8   m_erase_min_low     = 0xff;  // min (offset & 0xFF) (unused)
	u8   m_erase_max_low     = 0x00;  // max (offset & 0xFF) (unused)

	// Scroll clear logging: per-column band info
	u8   m_col_used[VRAM_COLS];       // 1 if this column saw any zero writes in this pass
	u16  m_col_min_idx[VRAM_COLS];    // min idx (0..0x1FF) zeroed in this col
	u16  m_col_max_idx[VRAM_COLS];    // max idx (0..0x1FF) zeroed in this col

	// Snapshots of scroll-related regs for logging
	u8   m_reg_c663 = 0;              // last written C663
	u8   m_reg_c462 = 0;              // last written C462

	// 8-color RGB palette for color mode
	rgb_t m_palette[8];

	// --------------------------------------------------------------------
	//  Helpers
	// --------------------------------------------------------------------

	void init_palette();

	// Read machine profile (D068) and decide:
	//  - mono vs color
	//  - 640×400 vs 640×200
	void update_geometry_from_profile();

	// Address helpers
	inline u8  vram_byte(u32 offset) const;
	inline u8 &vram_byte_ref(u32 offset);

	// Core rendering entry
	void render_framebuffer(bitmap_rgb32 &bitmap, const rectangle &cliprect);

	// Mode-specific rendering
	void render_mode_mono(bitmap_rgb32 &bitmap, const rectangle &cliprect);
	void render_mode_color(bitmap_rgb32 &bitmap, const rectangle &cliprect);

	// CLS helper
	void clear_text_vram();
	void clear_scroll_bottom_band_for_columns();
	void clear_window_from_ga();      

};

#endif // MAME_EPSON_GAVDP_H
