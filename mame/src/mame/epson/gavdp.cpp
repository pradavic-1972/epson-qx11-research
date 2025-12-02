// license:BSD-3-Clause
// Epson QX-11 GAVDP — Gate Array Video Data Path / Processor
// Mode 7: column-centric 1bpp with 0x200 column stride and 0x100 bottom-half offset.

#include "emu.h"
#include "gavdp.h"

DEFINE_DEVICE_TYPE(EPSON_GAVDP, epson_gavdp_device, "epson_gavdp", "Epson QX-11 GAVDP (Video Processor)")

epson_gavdp_device::epson_gavdp_device(const machine_config& mconfig, const char* tag, device_t* owner, u32 clock)
    : device_t(mconfig, EPSON_GAVDP, tag, owner, clock)
    , device_video_interface(mconfig, *this)
    , m_screen(*this, "screen")
    , m_palette(*this, "palette")
{
}

void epson_gavdp_device::device_start()
{
    // Allocate full VRAM window: 128 columns * 0x200 stride = 0x10000 bytes
    const u32 bytes = u32(m_char_cols) * m_col_stride;
    m_cols = std::make_unique<u8[]>(bytes);
    std::fill_n(m_cols.get(), bytes, 0x00);

    // Default attributes: all cells normal white-on-black
    m_attr.fill(0x07);
    m_latched_attr    = 0x07;
    m_machine_profile = 0x02;
    m_color_mode      = false;
    m_c663_scroll     = 0;

    // Save-state
    save_pointer(NAME(m_cols), bytes);
    save_item(NAME(m_window_base));
    save_item(NAME(m_vis_w));
    save_item(NAME(m_vis_h));
    save_item(NAME(m_split));
    save_item(NAME(m_col_stride));
    save_item(NAME(m_bottom_off));
    save_item(NAME(m_char_cols));
    save_item(NAME(m_logical_w));
    save_item(NAME(m_logical_h));
    save_item(NAME(m_last_maxx));
    save_item(NAME(m_last_maxy));
    save_item(NAME(m_c663_scroll));
    save_item(NAME(m_attr));
    save_item(NAME(m_latched_attr));
    save_item(NAME(m_machine_profile));
    save_item(NAME(m_color_mode));
}

void epson_gavdp_device::device_reset()
{
    // Leave VRAM as-is; BIOS will reinitialize, but keep attributes reasonable
    m_latched_attr = 0x07;
    m_c663_scroll  = 0;
    update_color_profile_from_ga();
}

void epson_gavdp_device::palette_init(palette_device &palette)
{
    // 8-color RGB palette (3-bit RGB: R,G,B)
    // Index: (R<<2)|(G<<1)|B
    palette.set_pen_color(0, rgb_t(0x00, 0x00, 0x00)); // 0: black
    palette.set_pen_color(1, rgb_t(0x00, 0x00, 0xFF)); // 1: blue
    palette.set_pen_color(2, rgb_t(0x00, 0xFF, 0x00)); // 2: green
    palette.set_pen_color(3, rgb_t(0x00, 0xFF, 0xFF)); // 3: cyan
    palette.set_pen_color(4, rgb_t(0xFF, 0x00, 0x00)); // 4: red
    palette.set_pen_color(5, rgb_t(0xFF, 0x00, 0xFF)); // 5: magenta
    palette.set_pen_color(6, rgb_t(0xFF, 0xFF, 0x00)); // 6: yellow
    palette.set_pen_color(7, rgb_t(0xFF, 0xFF, 0xFF)); // 7: white
}

void epson_gavdp_device::device_add_mconfig(machine_config &config)
{
    SCREEN(config, m_screen, SCREEN_TYPE_RASTER);
    m_screen->set_raw(12'000'000, 800, 0, 640, 525, 0, 400);
    m_screen->set_screen_update(FUNC(epson_gavdp_device::screen_update));
    m_screen->set_palette(m_palette);

    PALETTE(config, m_palette, FUNC(epson_gavdp_device::palette_init), 8);
}

void epson_gavdp_device::update_geometry_from_bios()
{
    cpu_device *cpu = machine().device<cpu_device>("maincpu");
    if (!cpu)
        return;

    address_space &space = cpu->space(AS_PROGRAM);

    u16 maxx = space.read_byte(0x0855) | (u16(space.read_byte(0x0856)) << 8);
    u16 maxy = space.read_byte(0x0857) | (u16(space.read_byte(0x0858)) << 8);

    if (maxx == m_last_maxx && maxy == m_last_maxy)
        return;

    m_last_maxx = maxx;
    m_last_maxy = maxy;

    u16 vis_maxx = std::min<u16>(maxx, DEF_WIDTH  - 1);  // 639
    u16 vis_maxy = std::min<u16>(maxy, DEF_HEIGHT - 1);  // 399

    m_logical_w = int(vis_maxx) + 1;
    m_logical_h = int(vis_maxy) + 1;

    m_screen->set_visible_area(0, vis_maxx, 0, vis_maxy);
}

// Read 8D068 ("machine profile") from VRAM mirror and decide mono vs color.
void epson_gavdp_device::update_color_profile_from_ga()
{
    const u32 idx_prof = linear_index_from_rel(0x0D068);
    if (idx_prof != ~0u)
        m_machine_profile = m_cols[idx_prof];

    // Empirically: 02 in HR mono, 07 in RGB color (ignore high bit).
    const u8 prof = m_machine_profile & 0x7F;
    m_color_mode = (prof == 0x07);   // true only for RGB color profiles
}

void epson_gavdp_device::install_vram_window(address_space &space, offs_t base)
{
    m_window_base = base;

    const offs_t start = base;
    const offs_t end   = base + VRAM_BYTES - 1;

    space.unmap_readwrite(start, end);

    space.install_readwrite_handler(
        start, end,
        read8sm_delegate(*this, FUNC(epson_gavdp_device::vram_r)),
        write8sm_delegate(*this, FUNC(epson_gavdp_device::vram_w)));
}

u32 epson_gavdp_device::linear_index_from_rel(u32 rel) const
{
    const u32 col = rel / m_col_stride;
    if (col >= u32(m_char_cols))
        return ~0u;

    const u32 off = rel % m_col_stride;
    return col * m_col_stride + off;
}

// Map VRAM-relative offset to approximate screen Y (0..399).
bool epson_gavdp_device::rel_to_screen_y(u32 rel, int &y) const
{
    const u32 column = rel / m_col_stride;
    if (column >= u32(m_char_cols))
        return false;

    const u32 offs   = rel % m_col_stride;
    const bool bottom = offs >= m_bottom_off;
    const u32 within_half = bottom ? (offs - m_bottom_off) : offs;

    const u32 crow  = within_half / 0x10;     // 16 bytes per text row per column
    const u32 scan  = within_half & 0x0F;     // 0..15 within that row

    int base_y = bottom ? m_split : 0;
    int yy     = int(crow * 16 + scan);

    y = base_y + yy;
    if (y < 0 || y >= DEF_HEIGHT)
        return false;

    return true;
}

u8 epson_gavdp_device::get_scroll_scanlines() const
{
    // GA scroll mirror at C663 in VRAM
    const u32 idx = linear_index_from_rel(0x0C663);
    if (idx == ~0u)
        return 0;

    return m_cols[idx];
}

u8 epson_gavdp_device::vram_r(offs_t offset)
{
    const u32 rel = u32(offset);
    const u32 idx = linear_index_from_rel(rel);
    if (idx == ~0u)
        return 0xFF;

    return m_cols[idx];
}

void epson_gavdp_device::vram_w(offs_t offset, u8 data)
{
    const u32 rel = u32(offset);

    // GA control register mirror at 8D269 — treat as attribute latch
    if (rel == 0x0D269)
    {
        m_latched_attr = data;

        const u32 idx_attr = linear_index_from_rel(rel);
        if (idx_attr != ~0u)
            m_cols[idx_attr] = data;

        return;
    }

    // Machine profile mirror at 8D068 — update mono vs color state.
    if (rel == 0x0D068)
    {
        const u32 idx_prof = linear_index_from_rel(rel);
        if (idx_prof != ~0u)
            m_cols[idx_prof] = data;

        m_machine_profile = data;
        update_color_profile_from_ga();
        return;
    }

    // GA scroll mirror at C663
    if (rel == 0x0C663)
    {
        const u32 idx_scroll = linear_index_from_rel(rel);
        if (idx_scroll != ~0u)
            m_cols[idx_scroll] = data;

        m_c663_scroll = data;
        return;
    }

    const u32 idx = linear_index_from_rel(rel);
    if (idx == ~0u)
        return;

    // Write to VRAM
    m_cols[idx] = data;

    // --------------------------------------------------------------------
    // PROOF OF CONCEPT:
    // If BIOS writes to the *first column* of a text row (col 0, scan 0),
    // immediately clear that entire text row in VRAM (all columns, 16 scans).
    // --------------------------------------------------------------------
    {
        const u32 col      = rel / m_col_stride;            // 0..m_char_cols-1
        const u32 col_off  = rel % m_col_stride;            // 0..(m_col_stride-1)

        const bool bottom      = (col_off >= m_bottom_off); // top/bottom half
        const u32 within_half  = bottom ? (col_off - m_bottom_off) : col_off;

        const int crow = int(within_half >> 4);             // 16 bytes per text row
        const int scan = int(within_half & 0x0F);           // 0..15

        // Split 25 rows as 12 top + 13 bottom in mode 7 text
        constexpr int TOP_ROWS = 12;
        int logical_row = 0;
        if (!bottom)
            logical_row = crow;              // 0..11
        else
            logical_row = TOP_ROWS + crow;   // 12..24

        if (logical_row >= 0 && logical_row < TEXT_ROWS)
        {
            // "Column 1 in that row" → col 0, scan 0
            if (col == 0 && scan == 0)
            {
                const u32 tracked = u32(m_char_cols) * m_col_stride;
                const u32 half_base = bottom ? m_bottom_off : 0x000;
                const u32 row_base  = half_base + u32(crow) * 0x10u;

                // Zero this row across all columns and all 16 scanlines
                for (int c = 0; c < m_char_cols; ++c)
                {
                    const u32 col_base = u32(c) * m_col_stride;
                    for (int s = 0; s < 16; ++s)
                    {
                        const u32 a_off = row_base + u32(s);
                        const u32 li    = col_base + a_off;
                        if (li < tracked)
                            m_cols[li] = 0x00;
                    }
                }
            }
        }
    }

    // In HR mono mode we do NOT maintain a per-cell attribute plane;
    // BIOS performs highlight by manipulating glyph bits directly.
    if (!m_color_mode)
        return;

    // In color mode, treat attributes as 8-scanline cells.
    int y;
    if (!rel_to_screen_y(rel, y))
        return;

    const int attr_row = y / 8;   // 8-scanline tall attribute cells
    if (attr_row < 0 || attr_row >= ATTR_ROWS)
        return;

    // Column (x/8) is simply the VRAM column index.
    const int attr_col = int(rel / m_col_stride);
    if (attr_col < 0 || attr_col >= ATTR_COLS)
        return;

    const int i = attr_row * ATTR_COLS + attr_col;
    m_attr[i] = m_latched_attr;
}

u32 epson_gavdp_device::screen_update(screen_device& screen, bitmap_rgb32& bitmap, const rectangle& cliprect)
{
    update_geometry_from_bios();
    update_color_profile_from_ga();
    render_mode7(bitmap);
    return 0;
}

void epson_gavdp_device::render_mode7(bitmap_rgb32& bmp)
{
    const int W = std::min(m_logical_w, bmp.width());
    const int H = std::min(m_logical_h, bmp.height());

    const int cols    = std::min(m_char_cols, W / 8);
    const u32 tracked = u32(m_char_cols) * m_col_stride;

    // Use C663 as a *raw scanline offset* (no mod 25, no fancy math).
    const u8 scroll = get_scroll_scanlines();

    // We only ever show 25 text rows (25 * 16 = 400 scanlines).
    constexpr int SCANLINES_PERROW = 16;
    constexpr int TEXT_SCANLINES   = TEXT_ROWS * SCANLINES_PERROW; // 400

    // Clear output bitmap (background = black)
    bmp.fill(m_palette->pen(0));

    for (int y = 0; y < H; ++y)
    {
        u32 *dst = &bmp.pix(y);

        // Effective scanline from top of the text area:
        // C663 is the starting scanline, y is the on-screen line.
        int eff_y = int(scroll) + y;

        if (eff_y < 0 || eff_y >= TEXT_SCANLINES)
        {
            // Outside 25-row text window, just background
            u8 bg = 0;
            if (m_color_mode)
            {
                int attr_row = y / 8;
                if (attr_row < 0)          attr_row = 0;
                if (attr_row >= ATTR_ROWS) attr_row = ATTR_ROWS - 1;
                u8 attr0 = m_attr[attr_row * ATTR_COLS + 0];
                bg = (attr0 >> 4) & 0x07;
            }

            for (int x = 0; x < W; ++x)
                dst[x] = m_palette->pen(bg);

            continue;
        }

        // Decide if this effective scanline is in the top or bottom half
        const bool bottom = (eff_y >= m_split);
        const int  yy     = bottom ? (eff_y - m_split) : eff_y;

        // Text row index and scanline within that row in VRAM layout
        const int crow    = yy >> 4;        // 16 scanlines per text row
        const int scan    = yy & 0x0F;      // 0..15
        const u32 half    = bottom ? m_bottom_off : 0x000;

        // Map crow/half to logical 0..24 text row (for attribute lookup)
        constexpr int TOP_ROWS = 12;
        int logical_row = 0;
        if (!bottom)
            logical_row = crow;
        else
            logical_row = TOP_ROWS + crow;

        for (int c = 0; c < cols; ++c)
        {
            // Column-centric VRAM layout:
            //   - each text row uses 0x10 bytes per column,
            //   - 'scan' selects which byte inside the 16-byte row slot.
            const u32 addr_off = half + u32(crow) * 0x10u + u32(scan);
            const u32 lin      = u32(c) * m_col_stride + addr_off;

            u8 b = 0;
            if (lin < tracked)
                b = m_cols[lin];

            // Defaults for mono (HR)
            u8 fg = 7;
            u8 bg = 0;

            if (m_color_mode)
            {
                // In color text mode, attributes are per character-row,
                // using 8-scanline “cells”.
                int attr_row = y / 8;
                if (attr_row < 0)          attr_row = 0;
                if (attr_row >= ATTR_ROWS) attr_row = ATTR_ROWS - 1;

                const int attr_col = c;
                u8 attr = 0x07;
                if (attr_col >= 0 && attr_col < ATTR_COLS)
                    attr = m_attr[attr_row * ATTR_COLS + attr_col];

                fg =  attr       & 0x07;
                bg = (attr >> 4) & 0x07;
            }
            else
            {
                // HR mono: BIOS encodes highlight via glyph bits.
                fg = 7;
                bg = 0;
            }

            const int x0 = c * 8;
            const int x1 = std::min(x0 + 8, W);
            for (int x = x0; x < x1; ++x)
            {
                const int bit       = 7 - (x & 7);
                const u8  glyph_bit = (b >> bit) & 1;
                const u8  pen_index = glyph_bit ? fg : bg;
                dst[x] = m_palette->pen(pen_index);
            }
        }

        // Fill remainder of the line with background (take attr from column 0)
        u8 bg = 0;
        if (m_color_mode)
        {
            int attr_row = y / 8;
            if (attr_row < 0)          attr_row = 0;
            if (attr_row >= ATTR_ROWS) attr_row = ATTR_ROWS - 1;

            u8 attr0 = m_attr[attr_row * ATTR_COLS + 0];
            bg = (attr0 >> 4) & 0x07;
        }

        for (int x = cols * 8; x < W; ++x)
            dst[x] = m_palette->pen(bg);
    }
}
