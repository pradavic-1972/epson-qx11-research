// license:BSD-3-Clause
#include "emu.h"
#include "epson_icrt.h"
#include "screen.h"

DEFINE_DEVICE_TYPE(EPSON_ICRT, epson_icrt_device, "epson_icrt", "Epson APX-ICRT (CGA-compatible)")

// -------------------------------------------------
// ROM: character generator
// If your tree already has a CGA font ROM in another device/romset, you can hook that instead.
// For now we define a local region; replace NO_DUMP with a real CRC/SHA1 if you add one.
// -------------------------------------------------
ROM_START(epson_icrt)
    ROM_REGION(0x2000, "chargen", 0)
    ROM_LOAD("icrt-chargen.bin", 0x0000, 0x2000, CRC(...) SHA1(...))
ROM_END

const tiny_rom_entry *epson_icrt_device::device_rom_region() const
{
	return ROM_NAME(epson_icrt);
}

epson_icrt_device::epson_icrt_device(const machine_config &mconfig, const char *tag, device_t *owner, u32 clock)
	: device_t(mconfig, EPSON_ICRT, tag, owner, clock)
	, device_video_interface(mconfig, *this)
	, m_screen(*this, ":screen")     // <--- existing machine screen (absolute tag)
	, m_crtc(*this, "crtc")
	, m_palette(*this, "palette")
	, m_chargen(*this, "chargen")
{
}

void epson_icrt_device::device_add_mconfig(machine_config &config)
{
	// DO NOT create a screen here.
	// We attach to the machine's existing ":screen".

	PALETTE(config, m_palette, palette_device::BLACK, 16);

	// HD46505 is MC6845-compatible for our purposes here.
	MC6845(config, m_crtc, XTAL(14'318'181) / 8);
	m_crtc->set_screen(m_screen);
	m_crtc->set_show_border_area(false);
	m_crtc->set_char_width(8);
	m_crtc->set_update_row_callback(FUNC(epson_icrt_device::crtc_update_row));
}

void epson_icrt_device::device_start()
{
	m_vram = std::make_unique<u8[]>(0x8000);
	std::fill_n(m_vram.get(), 0x8000, 0x00);

	save_pointer(NAME(m_vram), 0x8000);
	save_item(NAME(m_active));
	save_item(NAME(m_crtc_index));
	save_item(NAME(m_crtc_addr));
	save_item(NAME(m_mode));
	save_item(NAME(m_color));
	save_item(NAME(m_cntr));
	save_item(NAME(m_map));
	save_item(NAME(m_plantronics));
	save_item(NAME(m_palette_lut_2bpp));
    save_item(NAME(m_crtc_regs));
	save_item(NAME(m_update_row_type));
}

void epson_icrt_device::device_reset()
{
	m_active = false;
	m_crtc_index = 0;
	m_crtc_addr = 0;
	m_mode  = 0;
	m_color = 0;
	m_cntr  = 0;
	m_map   = 0;
	m_plantronics = 0;
	std::fill_n(m_palette_lut_2bpp, std::size(m_palette_lut_2bpp), 0x00);
	std::fill_n(m_crtc_regs, std::size(m_crtc_regs), 0x00);
	update_palette_lut();
	update_cga_mode_control();
}

// -------------------------------------------------
// Address maps (host installs these)
// -------------------------------------------------

void epson_icrt_device::vram_map_color(address_map &map)
{
    map(0x0000, 0x7fff).rw(FUNC(epson_icrt_device::vram_color_r),
                           FUNC(epson_icrt_device::vram_color_w));
}

void epson_icrt_device::vram_map_mono(address_map &map)
{
    map(0x0000, 0x7fff).rw(FUNC(epson_icrt_device::vram_mono_r),
                           FUNC(epson_icrt_device::vram_mono_w));
}


void epson_icrt_device::io_map(address_map &map)
{
	// CRTC: 3B4/3B5 and 3D4/3D5
	map(0x3b4, 0x3b4).w(FUNC(epson_icrt_device::crtc_addr_w));
	map(0x3b5, 0x3b5).rw(FUNC(epson_icrt_device::crtc_data_r), FUNC(epson_icrt_device::crtc_data_w));
	map(0x3d4, 0x3d4).w(FUNC(epson_icrt_device::crtc_addr_w));
	map(0x3d5, 0x3d5).rw(FUNC(epson_icrt_device::crtc_data_r), FUNC(epson_icrt_device::crtc_data_w));

	// Mode: 3B8 / 3D8
	map(0x3b8, 0x3b8).w(FUNC(epson_icrt_device::mode_w));
	map(0x3d8, 0x3d8).w(FUNC(epson_icrt_device::mode_w));

	// Color: 3B9 / 3D9
	map(0x3b9, 0x3b9).w(FUNC(epson_icrt_device::color_w));
	map(0x3d9, 0x3d9).w(FUNC(epson_icrt_device::color_w));

	// Status: 3BA / 3DA
	map(0x3ba, 0x3ba).r(FUNC(epson_icrt_device::status_r));
	map(0x3da, 0x3da).r(FUNC(epson_icrt_device::status_r));

	// Plantronics COLORPLUS extension control
	map(0x3bd, 0x3bd).rw(FUNC(epson_icrt_device::plantronics_r), FUNC(epson_icrt_device::plantronics_w));
	map(0x3dd, 0x3dd).rw(FUNC(epson_icrt_device::plantronics_r), FUNC(epson_icrt_device::plantronics_w));

	// CNTR: 03CE
	map(0x3ce, 0x3ce).rw(FUNC(epson_icrt_device::cntr_r), FUNC(epson_icrt_device::cntr_w));

	// MAP: 03CF
	map(0x3cf, 0x3cf).rw(FUNC(epson_icrt_device::map_r), FUNC(epson_icrt_device::map_w));
}

void epson_icrt_device::io_map_mono(address_map &map)
{
	// CRTC: 3B4/3B5 and 3D4/3D5
	map(0x4, 0x4).w(FUNC(epson_icrt_device::crtc_addr_w));
	map(0x5, 0x5).rw(FUNC(epson_icrt_device::crtc_data_r), FUNC(epson_icrt_device::crtc_data_w));
	

	// Mode: 3B8 / 3D8
	map(0x8, 0x8).w(FUNC(epson_icrt_device::mode_w));
	
	// Color: 3B9 / 3D9
	map(0x9, 0x9).w(FUNC(epson_icrt_device::color_w));
	
	// Status: 3BA / 3DA
	map(0xa, 0xa).r(FUNC(epson_icrt_device::status_r));

	// Plantronics COLORPLUS extension control (3BD/3DD mirrored through host window)
	map(0xd, 0xd).rw(FUNC(epson_icrt_device::plantronics_r), FUNC(epson_icrt_device::plantronics_w));

	// CNTR: 03CE
	map(0xe, 0xe).rw(FUNC(epson_icrt_device::cntr_r), FUNC(epson_icrt_device::cntr_w));

	// MAP: 03CF
	map(0xf, 0xf).rw(FUNC(epson_icrt_device::map_r), FUNC(epson_icrt_device::map_w));
}
// -------------------------------------------------
// VRAM
// -------------------------------------------------

bool epson_icrt_device::vram_aperture_enabled(bool mono_window) const
{
	if (!BIT(m_map, 7))
		return false;

	return BIT(m_map, mono_window ? 5 : 6);
}

offs_t epson_icrt_device::translate_cpu_vram_offset(offs_t offset) const
{
	offs_t const raw = offset & 0x7fff;

	if (!is_graphics())
		return raw;

	if (vram_32k())
		return raw;

	return (raw & 0x3fff) | (vram_upper_bank() ? 0x4000 : 0x0000);
}

u8 epson_icrt_device::vram_color_r(offs_t off)
{
	if (!vram_aperture_enabled(false))
		return 0xff;

	return m_vram[translate_cpu_vram_offset(off)];
}

void epson_icrt_device::vram_color_w(offs_t off, u8 data)
{
	if (!vram_aperture_enabled(false))
		return;

	m_active = true;
	m_vram[translate_cpu_vram_offset(off)] = data;
}

u8 epson_icrt_device::vram_mono_r(offs_t off)
{
	if (!vram_aperture_enabled(true))
		return 0xff;

	return m_vram[translate_cpu_vram_offset(off)];
}

void epson_icrt_device::vram_mono_w(offs_t off, u8 data) 
{
	if (!vram_aperture_enabled(true))
		return;

	m_active = true;
	m_vram[translate_cpu_vram_offset(off)] = data;
}

// -------------------------------------------------
// I/O handlers
// -------------------------------------------------

void epson_icrt_device::crtc_addr_w(u8 data)
 {
    m_crtc_index = data & 0x1f;
	m_crtc->address_w(m_crtc_index);

}

void epson_icrt_device::crtc_data_w(u8 data)
 { 
    // Shadow the written value so we can inspect R9, R12/13, etc.
	m_crtc_regs[m_crtc_index] = data;
	if (m_crtc_index == 0x01 || m_crtc_index == 0x06 || m_crtc_index == 0x09)
		logerror("ICRT CRTC R%u <= %02X (mode=%02X cntr=%02X map=%02X)\n", m_crtc_index, data, m_mode, m_cntr, m_map);
    m_crtc->register_w(data);
 }

u8 epson_icrt_device::crtc_data_r()
{
	// Data-port read. Also keep shadow in sync if you want (optional).
	const u8 v = m_crtc->register_r();
	// m_crtc_regs[m_crtc_index] = v; // optional
	return v;
}


void epson_icrt_device::mode_w(u8 data)
{
	m_mode = data;
	update_palette_lut();
	update_cga_mode_control();
	logerror("ICRT mode <= %02X (GR=%d HCH=%d HGR=%d BL=%d charw=%d)\n",
		m_mode, BIT(m_mode, 1), BIT(m_mode, 0), BIT(m_mode, 4), BIT(m_mode, 5),
		(m_update_row_type == ICRT_GFX_1BPP) ? 16 : 8);

    // bit 0 (HCH)  
    // bit 1 (GR)   : graphics/text (0=text,1=graphics)
    // bit 2        : alternate CGA 4-color palette select
    // bit 4 (HGR)  : hi-res graphics (1=hires)
    // bit 5 (BLEN) : blink enable
    
}

void epson_icrt_device::color_w(u8 data)
{
	m_color = data;
	update_palette_lut();
}

void epson_icrt_device::update_cga_mode_control()
{
	switch (m_mode & 0x3f)
	{
	case 0x08: case 0x09: case 0x0c: case 0x0d:
		m_crtc->set_hpixels_per_column(8);
		m_update_row_type = ICRT_TEXT_INTEN;
		break;
	case 0x0a: case 0x0b: case 0x0e: case 0x0f:
	case 0x2a: case 0x2b: case 0x2e: case 0x2f:
		m_crtc->set_hpixels_per_column(8);
		m_update_row_type = ICRT_GFX_2BPP;
		break;
	case 0x18: case 0x19: case 0x1c: case 0x1d:
		m_crtc->set_hpixels_per_column(8);
		m_update_row_type = ICRT_TEXT_INTEN_ALT;
		break;
	case 0x1a: case 0x1b: case 0x1e: case 0x1f:
	case 0x3a: case 0x3b: case 0x3e: case 0x3f:
		m_crtc->set_hpixels_per_column(16);
		m_update_row_type = ICRT_GFX_1BPP;
		break;
	case 0x28: case 0x29: case 0x2c: case 0x2d:
		m_crtc->set_hpixels_per_column(8);
		m_update_row_type = ICRT_TEXT_BLINK;
		break;
	case 0x38: case 0x39: case 0x3c: case 0x3d:
		m_crtc->set_hpixels_per_column(8);
		m_update_row_type = ICRT_TEXT_BLINK_ALT;
		break;
	default:
		m_crtc->set_hpixels_per_column(8);
		m_update_row_type = ICRT_TEXT_INTEN;
		break;
	}

	// Match CGA behavior: the low bit of the mode register switches the 6845 input clock.
	m_crtc->set_unscaled_clock((m_mode & 0x01) ? XTAL(14'318'181) / 8 : XTAL(14'318'181) / 16);
}

bool epson_icrt_device::row_type_is_graphics() const
{
	return (m_update_row_type == ICRT_GFX_1BPP) || (m_update_row_type == ICRT_GFX_2BPP);
}

bool epson_icrt_device::row_type_is_1bpp() const
{
	return m_update_row_type == ICRT_GFX_1BPP;
}

int epson_icrt_device::row_type_pixel_width() const
{
	return row_type_is_1bpp() ? 16 : 8;
}

u8 epson_icrt_device::cntr_r()
{
	return m_cntr;
}

void epson_icrt_device::cntr_w(u8 data)
{
	m_cntr = data;
	logerror("ICRT cntr <= %02X (CM/EX=%d A/B=%d G400/G200=%d)\n",
		m_cntr, BIT(m_cntr, 7), BIT(m_cntr, 6), BIT(m_cntr, 5));
    // bit 3 
    // bit 4 
    
    /* 
    7x12 font (8x16 matrix area): 03CE bit 4 = 0, bit 3 is disregarded, and R9 = OF At the CG, A12 = 0, A11 = RA3, and 4K bytes CG ROM (0000-OFFF) are used. When a character matrix of more than 8 dots
    vertically is selected, the dot pattern for each character is divided and stored in two locations
    0000-07FF for the upper 8 dots, 0800-OFFF for the lower dots.

    7x7 font (8x8 matrix area): 03CE bit 4 = 1, bit 3 = 0, and R9 = 07. At the CG. A12 = 1, A11 = 1. and 2K
    bytes CG ROM (1800-1FFF) are used.
    
    5x7 font (8x8 matrix area): 3CE bit4 = 1, bit 3 = 1, and R9 = 07. At the CG, A12 = 1.A11 = 0, and 2K bytes CG ROM (1000-17FF) are used.
    */

    // bit 7 (CM/EX)  : 0 = 16KB , 1 = 32K VRAM enable
    // bit 6 (A/B)    : VRAM bank select (0=lower 0000-3fff,1=upper 4000-7fff)
    // bit 5 (G200)   : 200/400 mode select 
    //0: With raster address R9 set to the maximum, 03, each display line is repeated,resulting in a 400 line display.
    //1: With raster address R9 set to 01, this produces a 200 line display. If a 400 line CRT is attached, the 200 lines will be compressed in the upper half of the screen.

/*  VMO: Lower 16K bytes VRAM (0000-3FFF), with R9 = 03, causing each line to be displayed twice for a 400line display
    VM1: Lower 16K bytes VRAM (0000-3FFF), with R9=01; each line is displayed once for a 200 line display
    VM2: Same as VMO, using the upper 16K bytes VRAM (4000-7FFF).
    VM3: Same as VM1, using the upper 16K bytes VRAM (4000-7FFF).
    VM4: Enables use of all 32K bytes VRAM by using 0000-3FFF for the even scan data and 4000-7FFF for the
    odd scans; R9 = 03, causing repeat scanning and a 400 line display.
    VM5: Same as VM4 but with R9= 01, resulting in a 200 line display.
    VM6: 0000-7FFF; R9=03 and R6 (vertical display height) =64. 32K bytes VRAM, 400 line display without repeat. Address space is split into 48K-byte blocks. The first scan uses raster data from the lowest
    address block, the second scan from the second block, the third scan from the third block, etc., and
    the cycle is repeated for subsequent scans. (Refer to Figure 2-87.) */

}

u8 epson_icrt_device::map_r()
{
	return m_map;
}

void epson_icrt_device::map_w(u8 data)
{
	m_map = data;
	logerror("ICRT map <= %02X (enable=%d color=%d mono=%d)\n",
		m_map, BIT(m_map, 7), BIT(m_map, 6), BIT(m_map, 5));
}

u8 epson_icrt_device::plantronics_r()
{
	return m_plantronics;
}

void epson_icrt_device::plantronics_w(u8 data)
{
	m_plantronics = data & 0x70;
}

void epson_icrt_device::update_palette_lut()
{
	// Match the standard CGA 2bpp color select behavior used by MAME's CGA device.
	if (m_mode & 0x10)
		m_palette_lut_2bpp[0] = 0;
	else
		m_palette_lut_2bpp[0] = m_color & 0x0f;

	if (m_mode & 0x04)
	{
		m_palette_lut_2bpp[1] = ((m_color & 0x10) >> 1) | 3;
		m_palette_lut_2bpp[2] = ((m_color & 0x10) >> 1) | 4;
		m_palette_lut_2bpp[3] = ((m_color & 0x10) >> 1) | 7;
	}
	else if (m_color & 0x20)
	{
		m_palette_lut_2bpp[1] = ((m_color & 0x10) >> 1) | 3;
		m_palette_lut_2bpp[2] = ((m_color & 0x10) >> 1) | 5;
		m_palette_lut_2bpp[3] = ((m_color & 0x10) >> 1) | 7;
	}
	else
	{
		m_palette_lut_2bpp[1] = ((m_color & 0x10) >> 1) | 2;
		m_palette_lut_2bpp[2] = ((m_color & 0x10) >> 1) | 4;
		m_palette_lut_2bpp[3] = ((m_color & 0x10) >> 1) | 6;
	}
}

u8 epson_icrt_device::status_r()
{
	u8 v = 0x00;

    // Bit 7: vertical retrace (what your app is waiting on via JNS)
    if (m_screen->vblank())
        v |= 0x80;

    // Optional: keep “classic” bits too (harmless, helps other software)
    if (m_screen->vblank())
        v |= 0x08;      // bit 3 also indicates vblank for some code

    if (!m_screen->hblank() && !m_screen->vblank())
        v |= 0x01;      // bit 0 display-enable-ish

    return v;
}

u8 epson_icrt_device::glyph_row_icrt(u8 ch, u8 ra, font_sel_t sel, u8 r9) const
{
    // Clamp RA to programmed cell height (defensive)
    if (ra > r9)
        return 0x00;

    switch (sel)
    {
    case FONT_8x16_7x12:
        // Expect r9 == 0x0f, but don’t hard-fail if not.
        // 4K area 0000-0FFF, split into 0000-07FF (rows 0-7) and 0800-0FFF (rows 8-15)
        if (ra >= 16)
            return 0x00;
        return m_chargen[(ch * 8) + (ra & 7) + ((ra & 8) ? 0x800 : 0)];

    case FONT_8x8_7x7:
        // 2K area 1800-1FFF, 8 bytes per char
        if (ra >= 8)
            return 0x00;
        return m_chargen[0x1800 + (ch * 8) + ra];

    case FONT_8x8_5x7:
        // 2K area 1000-17FF, 8 bytes per char
        if (ra >= 8)
            return 0x00;
        return m_chargen[0x1000 + (ch * 8) + ra];
    }

    return 0x00;
}



// -------------------------------------------------
// Host-facing screen update
// -------------------------------------------------
u32 epson_icrt_device::screen_update(screen_device &screen, bitmap_rgb32 &bitmap, const rectangle &cliprect)
{
	bitmap.fill(m_palette->pen(0), cliprect);
	// We let the CRTC drive rendering using our update_row callback.
	return m_crtc->screen_update(screen, bitmap, cliprect);
}

// -------------------------------------------------
// Palette (simple CGA 16-color table)
// -------------------------------------------------
static const rgb_t s_cga16[16] =
{
	rgb_t(0x00,0x00,0x00), rgb_t(0x00,0x00,0xaa), rgb_t(0x00,0xaa,0x00), rgb_t(0x00,0xaa,0xaa),
	rgb_t(0xaa,0x00,0x00), rgb_t(0xaa,0x00,0xaa), rgb_t(0xaa,0x55,0x00), rgb_t(0xaa,0xaa,0xaa),
	rgb_t(0x55,0x55,0x55), rgb_t(0x55,0x55,0xff), rgb_t(0x55,0xff,0x55), rgb_t(0x55,0xff,0xff),
	rgb_t(0xff,0x55,0x55), rgb_t(0xff,0x55,0xff), rgb_t(0xff,0xff,0x55), rgb_t(0xff,0xff,0xff),
};

int epson_icrt_device::vram_vm() const
{
    const bool ex32 = BIT(m_cntr, 7); // CM/EX
    const bool ab   = BIT(m_cntr, 6); // A/B
    const bool g2   = BIT(m_cntr, 5); // G200
    const u8 r9 = m_crtc_regs[9] & 0x1f;
    const u8 r6 = m_crtc_regs[6];

    if (!ex32) {
        if (!ab) return g2 ? 1 : 0;  // VM0/VM1
        else     return g2 ? 3 : 2;  // VM2/VM3
    } else {
        // VM6 special case
        if (r9 == 0x03 && r6 == 0x40)
            return 6;
        return g2 ? 5 : 4;           // VM4/VM5
    }
}

// -------------------------------------------------
// MC6845 row renderer
// -------------------------------------------------
MC6845_UPDATE_ROW(epson_icrt_device::crtc_update_row)
{
	// Palette (CGA-ish 16-color) – safe to set each row
	for (int i = 0; i < 16; i++)
		m_palette->set_pen_color(i, s_cga16[i]);

	// If video disabled, blank the visible row area
	if (!video_enable() || !de)
	{
		for (int x = 0; x < x_count * row_type_pixel_width(); x++)
			bitmap.pix(y, x) = m_palette->pen(0);
		return;
	}

	// Blink phase (used for attribute blink + cursor blink)
	const bool blink_phase = BIT(m_screen->frame_number() >> 4, 0);

	// ------------------------------------------------------------
	// TEXT MODE
	// ------------------------------------------------------------
	if (!row_type_is_graphics())
	{
		const u8 r9 = m_crtc_regs[9] & 0x1f;   // 0x0f for 8x16, 0x07 for 8x8
        const u8 cntr = m_cntr;               // latched from 03CE writes
        const u8 b3 = BIT(cntr, 3);
        const u8 b4 = BIT(cntr, 4);

        if ((b4 == 1) && ( r9 == 0x07)) {
            font_sel = b3 ? FONT_8x8_7x7 : FONT_8x8_5x7;
            logerror("ICRT text mode: 8x8 font selected (b4=1, b3=%d, r9=%02X)\n", b3, r9);
            }
        if ((b4 == 0) && (r9 == 0x0F )){
            font_sel = FONT_8x16_7x12;            // bit3 disregarded
            logerror("ICRT text mode: 8x16 font selected (b4=0, r9=%02X)\n", r9);
            }
        
// Optional sanity: if CRTC programmed "wrong", you can either trust cntr or trust R9.
// I recommend: trust cntr for ROM base, but clamp glyph rows by R9.

		// Cursor parameters from CRTC regs
		const u8 cur_start = m_crtc_regs[0x0a] & 0x1f;
		const u8 cur_end   = m_crtc_regs[0x0b] & 0x1f;
		const bool cur_dis = BIT(m_crtc_regs[0x0a], 5);

		for (int col = 0; col < x_count; col++)
		{
			const u16 cell = (ma + col) & 0x3fff;
			const u32 addr = (cell * 2) & 0x7fff;

			const bool cursor_here = (cursor_x >= 0) && (col == cursor_x);

			const u8 ch   = m_vram[addr + 0]; // even = char
			const u8 attr = m_vram[addr + 1]; // odd  = attr
            

			u8 fg = attr & 0x0f;
			u8 bg = (attr >> 4) & 0x07;

			bool bg_intensity = false;
			bool do_blink = false;

			if (blink_enable())
				do_blink = BIT(attr, 7);
			else
				bg_intensity = BIT(attr, 7);

			if (bg_intensity)
				bg |= 0x08;

			// Underline rule (still best-effort; keep as-is for now)
			const bool underline =
				underline_enable() &&
				((attr & 0x07) == 0x01);

			u8 glyph = glyph_row_icrt(ch, ra, font_sel, r9); // your glyph_row() should implement Epson ROM selection

			// Underline overlay
			if (underline)
			{
				// NOTE: This is a guess; if you later confirm ENU semantics, adjust.
				const int ul_row = r9;  // typical underline at last scanline of cell
				if ((ra & 0x0f) == ul_row)
					glyph = 0xff;
			}

			// Cursor overlay (invert scanlines between start/end)
			if (cursor_here && !cur_dis)
			{
				const bool cursor_on = !blink_phase; // blink cursor
				if (cursor_on && ra >= cur_start && ra <= cur_end)
					glyph ^= 0xff;
			}

			// Apply blink by suppressing foreground during blink phase
			u8 effective_fg = fg;
			if (do_blink && blink_phase)
				effective_fg = bg;

			const int xpix = col * 8;
			for (int b = 0; b < 8; b++)
			{
				// For icrt-chargen.bin you reported MSB-left works (7-b)
				const bool on = BIT(glyph, 7 - b);
				bitmap.pix(y, xpix + b) = m_palette->pen(on ? effective_fg : bg);
			}
		}
		return;
	}

	// ------------------------------------------------------------
	// GRAPHICS MODE (Epson ICRT VM0–VM5 implemented; VM6 stubbed)
	// ------------------------------------------------------------

	if (plantronics_lores() || plantronics_hires())
	{
		const u32 bytes_per_scan = (u32)x_count;
		auto const plantronics_offs = [bytes_per_scan](int sy, u32 col) -> u32
		{
			return ((((u32)sy >> 1) * bytes_per_scan) + col + ((sy & 1) ? 0x2000 : 0x0000)) & 0x7fff;
		};

		auto const plantronics_color = [this](u8 pix2) -> u8
		{
			return m_palette_lut_2bpp[pix2 & 0x03];
		};

		if (plantronics_lores())
		{
			for (u32 col = 0; col < bytes_per_scan; col++)
			{
				const u32 offs = plantronics_offs(y, col);
				u8 plane01 = plantronics_planes_swapped() ? m_vram[offs | 0x4000] : m_vram[offs];
				u8 plane23 = plantronics_planes_swapped() ? m_vram[offs] : m_vram[offs | 0x4000];
				const int xpix = (int)col * 4;

				for (int pixel = 3; pixel >= 0; pixel--)
				{
					const u8 color =
							((plane01 & 0x03) << 1) |
							((plane23 & 0x02) >> 1) |
							((plane23 & 0x01) << 3);
					bitmap.pix(y, xpix + pixel) = m_palette->pen(color & 0x0f);
					plane01 >>= 2;
					plane23 >>= 2;
				}
			}
			return;
		}

		if (plantronics_hires())
		{
			for (u32 col = 0; col < bytes_per_scan; col++)
			{
				const u32 offs = plantronics_offs(y, col);
				u8 plane0 = plantronics_planes_swapped() ? m_vram[offs] : m_vram[offs | 0x4000];
				u8 plane1 = plantronics_planes_swapped() ? m_vram[offs | 0x4000] : m_vram[offs];
				u8 pixels_hi = 0;
				u8 pixels_lo = 0;

				for (int bit = 3; bit >= 0; bit--)
				{
					pixels_hi = (pixels_hi << 1) | BIT(plane0, 7);
					pixels_hi = (pixels_hi << 1) | BIT(plane1, 7);
					pixels_lo = (pixels_lo << 1) | BIT(plane0, 3);
					pixels_lo = (pixels_lo << 1) | BIT(plane1, 3);
					plane0 <<= 1;
					plane1 <<= 1;
				}

				const int xpix = (int)col * 8;
				bitmap.pix(y, xpix + 0) = m_palette->pen(plantronics_color((pixels_hi >> 6) & 0x03));
				bitmap.pix(y, xpix + 1) = m_palette->pen(plantronics_color((pixels_hi >> 4) & 0x03));
				bitmap.pix(y, xpix + 2) = m_palette->pen(plantronics_color((pixels_hi >> 2) & 0x03));
				bitmap.pix(y, xpix + 3) = m_palette->pen(plantronics_color((pixels_hi >> 0) & 0x03));
				bitmap.pix(y, xpix + 4) = m_palette->pen(plantronics_color((pixels_lo >> 6) & 0x03));
				bitmap.pix(y, xpix + 5) = m_palette->pen(plantronics_color((pixels_lo >> 4) & 0x03));
				bitmap.pix(y, xpix + 6) = m_palette->pen(plantronics_color((pixels_lo >> 2) & 0x03));
				bitmap.pix(y, xpix + 7) = m_palette->pen(plantronics_color((pixels_lo >> 0) & 0x03));
			}
			return;
		}
	}

	// Determine VRAM mode VM0–VM6 from CNTR bits 7..5 (+ R9/R6 for VM6)
	const bool ex32 = BIT(m_cntr, 7); // CM/EX
	const bool ab   = BIT(m_cntr, 6); // A/B
	const bool g2   = BIT(m_cntr, 5); // G400/G200 (1=200, 0=repeat/400 behavior)
	const u8 r9     = m_crtc_regs[9] & 0x1f;
	const u8 r6     = m_crtc_regs[6];
	const u32 words_per_scan = (u32)x_count;

	int vm = -1;
	if (!ex32)
	{
		// 16K window: V0/V1 (lower) or V2/V3 (upper)
		if (!ab) vm = g2 ? 1 : 0;
		else     vm = g2 ? 3 : 2;
	}
	else
	{
		// 32K: V4/V5, with VM6 special case (per manual: R9=03 and R6=64)
		if (r9 == 0x03 && r6 == 0x40)
			vm = 6;
		else
			vm = g2 ? 5 : 4;
	}

	// Follow CGA-style rendering: MA selects the row base, RA selects the scanline bank.
	// Epson repeat/400-line modes use R9=03 to display each CGA scanline twice:
	// ra 0/1 = even bank, ra 2/3 = odd bank.  Using ra&1 here creates a shifted
	// even/odd/even/odd ghost around pixels instead of true vertical repetition.
	const int line_parity = (!g2 && r9 == 0x03) ? ((ra >> 1) & 1) : (ra & 1);

	// Optional: if in a 200-line mode on a 400-line CRT, doc says image is in upper half.
	// If you want that behavior, uncomment:
	//
	// if (g2) {
	//     if (y >= 200) {
	//         for (int x = 0; x < x_count * 8; x++)
	//             bitmap.pix(y, x) = m_palette->pen(0);
	//         return;
	//     }
	// }

	auto lowres_color = [&](u8 pix2) -> u8
	{
		return m_palette_lut_2bpp[pix2 & 0x03];
	};

	// Epson monochrome-style 1bpp graphics use a green foreground.
	const u8 hires_fg = 0x0a;
	const u8 hires_bg = 0;

	// HCH selects the 1bpp high-resolution path even when HGR is clear.
	const bool hires = row_type_is_1bpp();

	// Helper to compute the first byte of the 2-byte fetch for VM0–VM5.
	auto vram_offs_vm0_5 = [&](int vm_mode, int row_ma, int line_parity, u32 col) -> u32
	{
		u32 offs = 0;
		const u32 pair = (((u32)(row_ma + (int)col) << 1) & 0x3fff);

		switch (vm_mode)
		{
			// VM0/VM1: lower 16K (0000-3FFF), even in 0000-1FFF, odd in 2000-3FFF
			case 0:
			case 1:
				offs = (pair & 0x1fff) | (line_parity ? 0x2000 : 0x0000);
				break;

			// VM2/VM3: upper 16K (4000-7FFF), even in 4000-5FFF, odd in 6000-7FFF
			case 2:
			case 3:
				offs = 0x4000 | (pair & 0x1fff) | (line_parity ? 0x2000 : 0x0000);
				break;

			// VM4/VM5: full 32K, even in 0000-3FFF, odd in 4000-7FFF
			case 4:
			case 5:
				offs = (pair & 0x3fff) | (line_parity ? 0x4000 : 0x0000);
				break;

			default:
				offs = 0;
				break;
		}

		return offs & 0x7fff;
	};

	// VM6 still needs the Figure 2-87 block-cycling layout. Until then, keep the
	// addressing CGA-like and only vary the bank decode.
	auto vram_offs = [&](int vm_mode, int row_ma, int line_parity, u32 col) -> u32
	{
		if (vm_mode == 6)
		{
			// TODO: implement true VM6 block-cycling mapping from the manual.
			// Temporary fallback: treat like VM4 (even/odd 32K split)
			const u32 pair = (((u32)(row_ma + (int)col) << 1) & 0x3fff);
			return (pair | (line_parity ? 0x4000 : 0x0000)) & 0x7fff;
		}

		return vram_offs_vm0_5(vm_mode, row_ma, line_parity, col);
	};

	// Render scanline
	if (!hires)
	{
		// CGA-style 2bpp packed graphics: 8 pixels per MC6845 access (2 bytes).
		for (u32 col = 0; col < words_per_scan; col++)
		{
			const int row_ma = ma;
			const u32 offs = vram_offs(vm, row_ma, line_parity, col);
			u8 data  = m_vram[offs];

			const int xpix = (int)col * 8;
			bitmap.pix(y, xpix + 0) = m_palette->pen(lowres_color((data >> 6) & 3));
			bitmap.pix(y, xpix + 1) = m_palette->pen(lowres_color((data >> 4) & 3));
			bitmap.pix(y, xpix + 2) = m_palette->pen(lowres_color((data >> 2) & 3));
			bitmap.pix(y, xpix + 3) = m_palette->pen(lowres_color((data >> 0) & 3));

			data = m_vram[(offs + 1) & 0x7fff];
			bitmap.pix(y, xpix + 4) = m_palette->pen(lowres_color((data >> 6) & 3));
			bitmap.pix(y, xpix + 5) = m_palette->pen(lowres_color((data >> 4) & 3));
			bitmap.pix(y, xpix + 6) = m_palette->pen(lowres_color((data >> 2) & 3));
			bitmap.pix(y, xpix + 7) = m_palette->pen(lowres_color((data >> 0) & 3));
		}
	}
	else
	{
		// CGA-style 1bpp packed graphics: 16 pixels per MC6845 access (2 bytes).
		for (u32 col = 0; col < words_per_scan; col++)
		{
			const int row_ma = ma;
			const u32 offs = vram_offs(vm, row_ma, line_parity, col);
			u8 data  = m_vram[offs];

			const int xpix = (int)col * 16;
			for (int b = 0; b < 8; b++)
			{
				const bool on = BIT(data, 7 - b);
				bitmap.pix(y, xpix + b) = m_palette->pen(on ? hires_fg : hires_bg);
			}

			data = m_vram[(offs + 1) & 0x7fff];
			for (int b = 0; b < 8; b++)
			{
				const bool on = BIT(data, 7 - b);
				bitmap.pix(y, xpix + 8 + b) = m_palette->pen(on ? hires_fg : hires_bg);
			}
		}
	}
}
