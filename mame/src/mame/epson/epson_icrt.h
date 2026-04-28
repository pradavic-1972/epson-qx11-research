// license:BSD-3-Clause
#pragma once

#include "video/mc6845.h"
#include "emupal.h"

class epson_icrt_device : public device_t, public device_video_interface
{
public:
	epson_icrt_device(const machine_config &mconfig, const char *tag, device_t *owner, u32 clock = 0);

	// Host maps these into CPU spaces
	void io_map(address_map &map);
    void io_map_mono(address_map &map);
    void vram_map_color(address_map &map);
    void vram_map_mono(address_map &map);

	// Host screen calls this (or host driver calls it from its own screen_update)
	u32 screen_update(screen_device &screen, bitmap_rgb32 &bitmap, const rectangle &cliprect);

	// Optional: expose registers for debug / mode switching decisions
	u8 mode_reg()  const { return m_mode; }
	u8 color_reg() const { return m_color; }
	u8 cntr_reg()  const { return m_cntr; }
	u8 map_reg()   const { return m_map; }
	u8 plantronics_reg() const { return m_plantronics; }
    bool active()  const { return m_active; }

protected:
	// device_t
	virtual void device_start() override;
	virtual void device_reset() override;
	virtual void device_add_mconfig(machine_config &config) override;
	virtual const tiny_rom_entry *device_rom_region() const override;

private:
	// --- VRAM ---
	bool vram_aperture_enabled(bool mono_window) const;
	offs_t translate_cpu_vram_offset(offs_t offset) const;
	u8  vram_mono_r(offs_t offset);
	void vram_mono_w(offs_t offset, u8 data);
    u8  vram_color_r(offs_t offset);
	void vram_color_w(offs_t offset, u8 data);

	// --- I/O ---
	u8  status_r();
	u8  cntr_r();
	void cntr_w(u8 data);
	u8  map_r();
	void map_w(u8 data);
	u8  plantronics_r();
	void plantronics_w(u8 data);
	void mode_w(u8 data);
	void color_w(u8 data);
	void update_palette_lut();
	void update_cga_mode_control();
	bool row_type_is_graphics() const;
	bool row_type_is_1bpp() const;
	int row_type_pixel_width() const;

	void crtc_addr_w(u8 data);
	u8   crtc_data_r();
	void crtc_data_w(u8 data);
    bool m_active = false;

    u8 m_crtc_index = 0;
    u8 m_crtc_regs[0x20] = {};


	// Rendering callback from MC6845
	MC6845_UPDATE_ROW(crtc_update_row);

	enum update_row_type : int
	{
		ICRT_TEXT_INTEN = 0,
		ICRT_TEXT_INTEN_ALT,
		ICRT_TEXT_BLINK,
		ICRT_TEXT_BLINK_ALT,
		ICRT_GFX_1BPP,
		ICRT_GFX_2BPP
	};

	// Mode helpers (CGA-ish)
	bool is_graphics() const      { return BIT(m_mode, 1); }  // GR
	bool high_res_monitor() const { return BIT(m_mode, 0); }  // HCH
	
	bool is_hires_gfx() const     { return BIT(m_mode, 4); }  // HGR
	bool video_enable() const     { return BIT(m_mode, 3); }
	bool blink_enable() const     { return BIT(m_mode, 5); }  // BLEN
	bool plantronics_lores() const { return BIT(m_plantronics, 4); }
	bool plantronics_hires() const { return BIT(m_plantronics, 5); }
	bool plantronics_planes_swapped() const { return BIT(m_plantronics, 6); }

	// CNTR (03CEh)
	bool vram_32k() const         { return BIT(m_cntr, 7); }
	bool vram_upper_bank() const  { return BIT(m_cntr, 6); }
	bool g200() const             { return BIT(m_cntr, 5); }  // 200 vs 400 behavior (we treat as 200 active here)
	bool char_8x8() const         { return BIT(m_cntr, 4); }  // 8x8 vs 8x16
	bool underline_enable() const { return BIT(m_cntr, 2); }  // ENU
    enum font_sel_t { FONT_8x16_7x12, FONT_8x8_7x7, FONT_8x8_5x7 };
    font_sel_t font_sel;
    u8 glyph_row_icrt(u8 ch, u8 ra, font_sel_t sel, u8 r9) const;

    int vram_vm() const;

private:
	// IMPORTANT: This is an absolute-tag reference to the machine's existing screen
	// (your QX-11 driver already defines it). We don't create a screen in this device.
	required_device<screen_device>  m_screen;
	required_device<mc6845_device>  m_crtc;
	required_device<palette_device> m_palette;

	// Character generator (CGA ROM compatible is fine as a starting point)
	required_region_ptr<u8> m_chargen;

	std::unique_ptr<u8[]> m_vram; // 32K max

	u16 m_crtc_addr = 0;
	u8  m_mode  = 0;
	u8  m_color = 0;
	u8  m_cntr  = 0;
	u8  m_map   = 0;
	u8  m_plantronics = 0;
	u8  m_palette_lut_2bpp[4] = {};
	int m_update_row_type = ICRT_TEXT_INTEN;
};

DECLARE_DEVICE_TYPE(EPSON_ICRT, epson_icrt_device)
