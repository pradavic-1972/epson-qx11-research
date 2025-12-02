// license:BSD-3-Clause
// Epson QX-11 GAVDP — Gate Array Video Data Path / Processor
// Mode 7: column-centric 1bpp (8 horiz pixels per byte, MSB-first),
// per-column stride 0x200, bottom-half offset 0x100, split at 200 lines.

#pragma once

#include "device.h"
#include "screen.h"
#include "emupal.h"
#include <array>

class epson_gavdp_device : public device_t, public device_video_interface
{
public:
    // Full VRAM window we expose to the CPU (0x80000..0x8FFFF typically)
    static constexpr u32 VRAM_BYTES = 0x10000;

    // Default geometry
    static constexpr int  DEF_WIDTH  = 640;
    static constexpr int  DEF_HEIGHT = 400;
    static constexpr int  DEF_SPLIT  = 200;    // top 200, bottom 200

    // Column-centric layout
    static constexpr u32  DEF_COL_STRIDE   = 0x200; // bytes per 8-pixel character column
    static constexpr u32  DEF_BOTTOM_OFF   = 0x100; // bottom-half offset within column
    static constexpr int  DEF_CHAR_COLUMNS = 128;   // track up to 128 columns

    // Attribute grid (40/80 columns × up to 400/8 = 50 rows)
    static constexpr int  ATTR_ROWS  = 50;
    static constexpr int  ATTR_COLS  = 128;

    // Logical text rows we care about in mode 7 text
    static constexpr int  TEXT_ROWS  = 25;

    epson_gavdp_device(const machine_config& mconfig, const char* tag, device_t* owner, u32 clock = 0);

    // Install VRAM window at CPU physical base (e.g., 0x80000)
    void install_vram_window(address_space &space, offs_t base);

    // 8-bit handlers
    u8  vram_r(offs_t offset);
    void vram_w(offs_t offset, u8 data);

    // Video callback (bound from qx11.cpp)
    u32 screen_update(screen_device& screen, bitmap_rgb32& bitmap, const rectangle& cliprect);

protected:
    void device_add_mconfig(machine_config &config) override;
    void device_start() override;
    void device_reset() override;

private:
    void palette_init(palette_device &palette);
    u32  linear_index_from_rel(u32 rel) const;
    void render_mode7(bitmap_rgb32& bmp);
    void update_geometry_from_bios();
    void update_color_profile_from_ga();

    // Map VRAM offset → approximate screen Y (0..399), returns false if out of range
    bool rel_to_screen_y(u32 rel, int &y) const;

    // Read GA scroll index mirror at C663 (scanline offset)
    u8 get_scroll_scanlines() const;

    // Base address where VRAM window is installed
    offs_t m_window_base = 0;

    // Geometry / split
    int    m_vis_w = DEF_WIDTH;
    int    m_vis_h = DEF_HEIGHT;
    int    m_split = DEF_SPLIT;

    // Layout
    u32    m_col_stride = DEF_COL_STRIDE;   // 0x200
    u32    m_bottom_off = DEF_BOTTOM_OFF;   // 0x100
    int    m_char_cols  = DEF_CHAR_COLUMNS; // 128 columns tracked

    // Logical resolution reported by BIOS (BDA)
    int    m_logical_w = 640;
    int    m_logical_h = 400;

    u16    m_last_maxx = 0xffff;
    u16    m_last_maxy = 0xffff;

    // Scroll mirror (we still read actual value from VRAM at C663)
    u8     m_c663_scroll = 0;

    // Compact VRAM: [column][stride]
    std::unique_ptr<u8[]> m_cols;

    // Per-cell attribute memory: ATTR_ROWS x ATTR_COLS
    std::array<u8, ATTR_ROWS * ATTR_COLS> m_attr{};
    u8  m_latched_attr     = 0x07;   // last value written to 8D269 (GA control latch)
    u8  m_machine_profile  = 0x02;   // mirror of 8D068 (2=HR mono, 7=color RGB)
    bool m_color_mode      = false;  // true for color RGB monitor, false for HR mono

    required_device<screen_device>  m_screen;
    required_device<palette_device> m_palette;
};

DECLARE_DEVICE_TYPE(EPSON_GAVDP, epson_gavdp_device)
