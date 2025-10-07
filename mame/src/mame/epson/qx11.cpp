// license:BSD-3-Clause
// Epson QX-11 (skeleton) — 512 KiB max RAM

#include "emu.h"
#include "cpu/i86/i86.h"
#include "machine/ram.h"

// CGA Card
#include "bus/isa/isa.h"
#include "bus/isa/isa_cards.h"     // card lists (pc_isa8_cards)
#include "bus/isa/cga.h"
#include "bus/isa/ega.h"  
#include "video/pc_vga.h"  
//#include "bus/epson_qx/keyboard/matrix_qx11.h"
//

// Floppy disk support 
#include "machine/upd765.h"
#include "imagedev/floppy.h"
#include "formats/pc_dsk.h"


#include "machine/pic8259.h" // Place holder, not sure if there's a PIC8259 compatible chip inside the GAVNIT


#include "screen.h"
#include "emupal.h"
#include "device.h"
#include "logmacro.h" // <-- This header defines logerror
#include "emucore.h"
#include "emumem.h"
#include <deque>
#include <vector>
#include <stdio.h>
#include <fstream>
#include <cstdint>
#include <array>

#include "qx11_postmux.h"
#include "sound/sn76496.h"
#include "speaker.h"


// Add typedef for u8 if not already defined
typedef uint8_t u8;

// Keyboard
#include "machine/keyboard.h"  // We use a generic keyboard, but will try to implement the QX10 Keyboard

// Real time Clock HD146818P
#include "machine/mc146818.h"

// fd20 floppy drive emulation. // The QX11 will support up to 4 external floppy drives. EPSON FD15, FD20 and PX10 are supported
#include "fd20_epsp.h"

// Serial Port 
#define LOG_SERIAL   (1U << 2)

#include "bus/isa/ega.h"

/*
class qx11_isa8_cga_device : public isa8_cga_device
{
public:
    qx11_isa8_cga_device(const machine_config &mconfig, const char *tag, device_t *owner, u32 clock)
        : isa8_cga_device(mconfig, tag, owner, clock) {}

    void set_screen_tag(const char *tag) { m_screen.set_tag(tag); }

    // Try rgb32 first; if it doesn't compile, switch to the ind16 overload below.
    u32 public_screen_update(screen_device &screen, bitmap_rgb32 &bmp, const rectangle &clip)
    { return isa8_cga_device::screen_update(screen, bmp, clip); }

  

    // If your tree wants indexed-16 instead, use this and comment the rgb32 one:
    // u32 public_screen_update(screen_device &screen, bitmap_ind16 &bmp, const rectangle &clip)
    // { return isa8_cga_device::screen_update(screen, bmp, clip); }
};

DEFINE_DEVICE_TYPE(QX11_ISA8_CGA, qx11_isa8_cga_device, "qx11_cga", "QX-11 CGA (public update)")

*/


class qx11_state : public driver_device
{
public:
    qx11_state(const machine_config &mconfig, device_type type, const char *tag)
        : driver_device(mconfig, type, tag)
        , m_maincpu(*this, "maincpu")
        , m_ram(*this, "ram")
        
        , m_pic_s(*this, "pic8259")
        , m_screen(*this, "screen")
        //, m_palette(*this, "palette")
        , m_vram8000(*this, "vram8000")
        , m_vram9000(*this, "vram9000") 
        , m_textbuffer(*this, "textbuffer")  
        , m_kbd(*this, "kbd")
        , m_rtc(*this, "rtc")
        , m_fdc(*this, "upd765")
        , m_floppy(*this, "upd765:%u", 0U)
        , m_postmux(*this, "postmux")    
        , m_psg(*this, "sn76489")  
        , m_isabus(*this, "isa8")
        , m_cga(*this, "isa1:cga_mc1502")
      //  , m_epkbd(*this,"keyboard_device")
        //, m_vga(*this,"vga")
      

        
  
    {}

    std::unique_ptr<fd20_epsp> m_fd20;
    void qx11(machine_config &config);
    ioport_constructor device_input_ports() const override;

    // generic keyboard (already in your config)
    void kbd_put(u8 ascii);
    void bios_kbd_push(u8 ascii, u8 scan); // BDA ring writer

    // change handlers for non-ASCII keys
    DECLARE_INPUT_CHANGED_MEMBER(key_up_changed);
    DECLARE_INPUT_CHANGED_MEMBER(key_down_changed);
    DECLARE_INPUT_CHANGED_MEMBER(key_left_changed);
    DECLARE_INPUT_CHANGED_MEMBER(key_right_changed);
    DECLARE_INPUT_CHANGED_MEMBER(key_f9_changed);


    protected:
    // ✅ Declare these exactly like this
    virtual void machine_start() override;
    virtual void machine_reset() override;
    u32 screen_update_qx11(screen_device &screen, bitmap_rgb32 &bmp, const rectangle &clip);

private:
// --- BEGIN: QX-11 PC-compatible keyboard helpers ---

    // enqueue one INT 16h "word" (AL=ascii, AH=scancode) into BDA ring buffer
    void bios_kbd_enqueue(u8 ascii, u8 sc);
    // update BDA shift flags at 0040:0017 (mask is bits to set/clear)
    void set_shift_flags(u8 mask, bool pressed);

    // MAME input change handlers (bind in INPUT_PORTS below)
    INPUT_CHANGED_MEMBER(key_makebreak_changed);  // param = Set-1 scancode
    INPUT_CHANGED_MEMBER(mod_changed);            // param = mask bit to set/clear



    // Optional: ASCII -> Set-1 scancode for printables (US layout, minimal)
    static u8 ascii_to_set1(u8 ch);
// --- END: QX-11 PC-compatible keyboard helpers ---

    void mem_map(address_map &map);
    void io_map(address_map &map);
    
    void pallete_init(palette_device &palette) const;
 
    // TAP INT 10h 
    // qx11.cpp (inside qx11_state private:)
    memory_passthrough_handler m_int10_tap{};

    // INT 10h taps
    memory_passthrough_handler m_int10_vec_tap{};
    memory_passthrough_handler m_int10_entry_tap{};

    void mirror_cell_from_shadow(offs_t shadow_word_addr);

             // 8 scanlines per glyph

// --- Shadow text buffer: 80*25*2 bytes (char,attr) at 0000:0B05 (physical 0x0000B05) ---
static constexpr offs_t SHADOW_BASE  = 0x0000B05;
//static constexpr offs_t SHADOW_BASE  = 0x00b800;
static constexpr offs_t SHADOW_END   = SHADOW_BASE + 80*25*2 - 1; // inclusive

// --- Text bitmap plane the QX-11 scans (you already render this) ---
static constexpr u32 TXT_PHYS    = 0x9000u << 4;   // 0x90000 physical
static constexpr u32 TXT_BASEOFF = 0x0100u;        // first visible text scanline
static constexpr u32 COL_STRIDE  = 0x0200u;        // 512 bytes per character column

// --- BIOS ROM font (8x8), 256 glyphs x 8 bytes (you dumped at 0xF6560) ---
static constexpr u32 FONT_PHYS_BASE = 0x00F6560u;
static constexpr int FONT_HEIGHT    = 8;

void draw_text_cell_from_rom(int row, int col, u8 ch);
void maybe_refresh_text_from_rom();
inline void draw_text_cell_from_extfont(int row, int col, u8 ch);


    int m_expect = 0;   // how many params to collect for current command
    int m_resleft = 0;  // expected result bytes


    static constexpr u32 INT10_ENTRY = 0xF0000 + 0x1690; // F107:1690h -> phys F1690h
    //void clear_text_page(u8 fill = 0x00);

    std::deque<u8> m_kbd_fifo;        // reply bytes waiting to be read
    bool m_dev_ready = true;          // status bit0: ready to accept command
 
    u8 status7e_r();
    //u8  status12_r();
    u8 status81_r();
    void status81_w(u8 data);

    
    // Low I/O logger
    u8  io_low_r(offs_t port);
    void io_low_w(offs_t port, u8 data);

    u8  crtc_index_r();       // optional
    void crtc_index_w(u8 data);
    u8  crtc_data_r();        // optional
    void crtc_data_w(u8 data);

    u8  m_crtc_index = 0x00;
    u8  m_crtc_regs[32]{};    // simple register file to log values

    u8 m_14_seq_idx = 0;
    u8 m_status7e = 0xFF;

    // Kwyboar Related
    
    // keyboard plumbing
    //void kbd_put(u8 ascii);
    u8   kb_status_r();
    u8   kb_data_r();
    void kb_data_w(u8 data);     // if firmware echoes/commands (often NOP)

    // helpers
    u8   ascii_to_qx(u8 a);
 

    // FIFO and state
    std::deque<u8> m_kb_fifo;
    u8             m_kb_status = 0x00;

    IRQ_CALLBACK_MEMBER( inta_call );

    // Keyboar related 
    

    required_device<i8088_cpu_device> m_maincpu;

    required_device<ram_device>       m_ram;
    
    required_device<pic8259_device>   m_pic_s;
    required_device<screen_device>   m_screen;
    //optional_device<palette_device> m_palette;

    required_device<qx11_postmux_device> m_postmux;  // add to your state
    required_device<isa8_device>        m_isabus;
    required_device<isa8_cga_mc1502_device> m_cga;
    //required_device<vga_device> m_vga;
    //optional_device<bus::epson_qx::keyboard::keyboard_port_device> m_epkbd;
    u8 io12_counter = 0;

    // Frame Buffer to draw characters
    required_shared_ptr<u8> m_vram9000;
    required_shared_ptr<u8> m_vram8000;

    required_shared_ptr<u8> m_textbuffer;

    // Keyboard
    required_device<generic_keyboard_device> m_kbd;
    
    // RTC Real time clock
    required_device<mc146818_device> m_rtc;

    required_device<upd765a_device>     m_fdc;
    required_device_array<floppy_connector, 2> m_floppy;
    //optional_device<floppy_connector>   m_floppy0;
    //optional_device<floppy_connector>   m_floppy1;  
    //optional_device<floppy_connector>   m_floppy2;
    //optional_device<floppy_connector>   m_floppy3;   // if you want a second drive

    optional_device<sn76489a_device> m_psg;  // sound device

    u8 D_status = 2;

    u8 status0C_r();
    u8 status0D_r();
    void status0D_w(u8 data);

    // QX-11 BIOS keyboard ring buffer (from your INT16 analysis)
    static constexpr u16 KBD_HEAD_PTR = 0x20E9;  // head (read) pointer (DS=0)
    static constexpr u16 KBD_TAIL_PTR = 0x20EB;  // tail (write) pointer (DS=0)
    static constexpr u16 KBD_BUF_START = 0x20ED; // first entry
// TODO: confirm exact end from sub_F2D95; 16 entries * 4 bytes is a sane default:
    static constexpr u16 KBD_BUF_END   = KBD_BUF_START + 16 * 4; // one past last
    void kbd_push_ascii(u8 ascii, u8 scancode );

    // Keep a handle so we can remove/replace the tap cleanly
    memory_passthrough_handler m_io_tap;
    memory_passthrough_handler m_shadow_tap;

    void clear_full_text_bitmap();
    void clear_text_cell_bitmap(int row, int col);
    void refresh_text_from_extfont_if_dirty();

    u8 m_latched_dor = 0x00;

    // --- INT 10h polling (no taps) ---
emu_timer* m_int10_poll_timer = nullptr;
u32        m_int10_entry_phys = 0;   // cached (seg<<4)+off from IVT[10h]
u32        m_last_pc          = ~0U; // de-dup logging
u64        m_last_cycles       = 0;

void clear_text_page(u8 fill = 0x00);

// logical text buffer -> bitmap rasterizer
void rasterize_text_cells_to_bitmap();

// choose your font (8×8, 256 glyphs). Point this at your ROM font at machine_start().
const u8* m_font8x8 = nullptr;

// origin/stride your existing renderer uses
u32 m_vram_display_origin = 0x00100;  // matches your current base
static constexpr u32 k_col_stride      = 0x0200;  // bytes between columns
void clear_bitmap_where_cells_are_space();

// Tap to watch logical text buffer writes (low RAM)
memory_passthrough_handler m_textbuf_tap{};

// Optional: per-cell dirty tracking (80x25)
std::array<u8, 80*25> m_cell_dirty{};   // 0/1 flags

// Optional: simple write counter for rate-limited logging
u64 m_textbuf_write_count = 0;

// Helper to rasterize one cell into the bitmap (uses your base/stride)
void rasterize_one_cell_from_textbuf(u32 cell_index);
// BIOS page pointer (kept in sync with [0000:0104/0106])
u16 m_bios_page_off = 0;   // offset (e.g., 0x0B05)
u16 m_bios_page_seg = 0;   // segment (e.g., 0x9000)

static constexpr int  COLS        = 80;
static constexpr int  ROWS        = 25;
void sync_from_bios_page_pointer();
void rasterize_textbuffer_to_bitmap();
void rasterize_textbuffer_highlight_only();

void activate_cga_output();
void activate_native_output();
void cga_seen_w(offs_t, u8);

void qx11_palette_init(palette_device &palette) const;
//u8 ascii_to_set1(u8 ch);
//void set_shift_flags(u8 mask, bool pressed);
//void bios_kbd_enqueue(u8 ascii, u8 sc);


///// SERIAL PORT (COM1) /////

// ===== Serial/GA control (observed on ports 0x08/0x07, and BRG family at 0x04/0x05:index 0x23) =====
u8  m_ser_idx = 0;        // index written to 0x08
u8  m_ser_mode = 0x94;    // last mode byte written to 0x07 when idx==0x08 (default 600,N,8,1)
u8  m_brg_idx = 0;        // index written to 0x04
u8  m_brg_23  = 0x04;     // last BRG/timeout “family” code written with idx==0x23 (seen 0x04)

// Decoded, current serial line config (for later UART wiring)
int m_ser_baud = 9600;
int m_ser_data_bits = 8;
int m_ser_stop_bits = 1;
enum { PAR_NONE, PAR_ODD, PAR_EVEN, PAR_MARKSPACE } m_ser_parity = PAR_NONE;

// ===== CMOS/RTC window (ports 0x10/0x11) to persist “Save permanent” =====
u8  m_rtc_index = 0;
u8  m_cmos[128]{};

// ====== helpers ======
struct ser_cfg {
    int baud;
    int databits;
    int stopbits;
    int parity; // PAR_NONE, PAR_ODD, PAR_EVEN, PAR_MARKSPACE

};

static ser_cfg decode_serial_mode(u8 m);
void apply_serial_cfg(const ser_cfg &cfg);

// ====== I/O handlers ======
void ser_idx_w(u8 data);  // port 0x08
void ser_dat_w(u8 data);  // port 0x07
void brg_idx_w(u8 data);  // port 0x04
void brg_dat_w(u8 data);  // port 0x05
u8 brg_idx_r();        // optional: return last index written


inline bool ga_rtc_window() const { return m_ga_page == 0xE0; }

// ----- GA I/O handlers -----
void ga_cmd_w(u8 data);     // 0x0C
u8   ga_status_r();         // 0x0D

// ----- RTC windowed proxy handlers (via GA page 0xE0) -----
void ga_rtc_index_w(u8 data);   // 0x10 (index/address)
u8   ga_rtc_index_r();          // optional: return last index (or 0xFF)
void ga_rtc_data_w(u8 data);    // 0x11 (data)
u8   ga_rtc_data_r();           // 0x11 (data)



inline void ga_set_ready()   { m_ga_status = 0x03; m_ga_resp = 0xFF; }  // ready/latched
inline void ga_set_busy()    { m_ga_status = 0x01; m_ga_resp = 0x00; }  // input-ready only

u8 m_ga_page   = 0x00;
u8 m_ga_status = 0x01;  // bit0=1 (input-ready), bit1=0
u8 m_ga_resp   = 0xFF;  // last response byte

inline void ga_set_in_ready()  { m_ga_status |=  0x01; }
inline void ga_clr_in_ready()  { m_ga_status &= ~0x01; }
inline void ga_set_out_ready() { m_ga_status |=  0x02; }
inline void ga_clr_out_ready() { m_ga_status &= ~0x02; }

u8 ga_cmd_r();
void ga_status_w(u8 data);

// Simple policy: page 0xE0 = RTC window; otherwise CRTC window
inline bool rtc_window() const { return m_ga_page == 0xE0; }

u8  io10_r();  void io10_w(u8 data);  // index
u8  io11_r();  void io11_w(u8 data);  // data

// optional: keep last RTC index for readback
u8  m_rtc_index_latch = 0;


//// possible upd765 ... ports 12 and 13 /////
u8 m_p12_status = 0x80;  // start TX-ready only: 0b10xxxxxx  -> 0x80
u8 m_p13_in     = 0x00;  // next byte BIOS will read from 0x13
u8 m_p13_out    = 0x00;  // last byte BIOS wrote to 0x13
bool m_resp_pending = false;
u16 m_resp_delay   = 0; 

void ga_video_w(u8 data);
void ga_p13_w(u8 data);
u8 ga_p13_r();
u8 status12_r();

/// port 81 
// --- members (private:) ---
u8   m_p81_latched = 0x00;
u8   m_p81_status  = 0x02;   // bit1 set => ready
u8   m_p81_delay   = 0;      // small poll delay before bit1 rises

pic8259_device*  m_pic = nullptr;

void dma_p81_w(u8 data);
u8 dma_p81_r();

bool cmos_initialized = false;

// INT 08 Timer

emu_timer* m_tick = nullptr;
void tick_cb(int param);   // <- signature must be exactly void(int)
void bios_tick_once();
bool post_ready = false;

// int 08 timer ends


// --- GA-DMA registers (captured from the 6-byte payload) ---
u32 m_dma_addr = 0;
u16 m_dma_len  = 0;    // raw value as sent (we’ll treat it as count = val)
u8  m_dma_mode = 0;    // direction/channel bits (we only use direction for now)

// handshake
u8  m_dma_status = 0x01;  // bit0 = ready (1 = ready for command)
u8  m_dma_cmd    = 0x00;
int m_dma_needed = 0;     // expecting 6 bytes after a “program DMA” command

// transfer bookkeeping
u16 m_dma_pos = 0;        // how many bytes have been moved this op
bool m_dma_active = false;

void ga_dma_cmd_w(u8 data);
u8 ga_dma_status_r();
void ga_dma_data_w(u8 data);


void fdc_drq_w(int state);

void fdc_intrq_w(int state);
u8 m_dor = 0x00;
u8 m_dir = 0x00;

floppy_image_device* current_floppy_from_dor();
void fdc_dor_w(u8 data);
bool m_fdc_irq = false;
u8 fdc_dir_r();

void fdc_fifo_w(u8 data);
u8 fdc_fifo_r();
u8 fdc_msr_r();


std::array<u8, 32> m_cmdbuf{};

int m_cmdlen  = 0;              // how many bytes currently in m_cmdbuf

/// port 92 & 93 
void port92_w (u8 data);
void port93_w (u8 data);
u8 port92_r ();
u8 port93_r ();
u8 p13_in_r();
void p13_out_w(u8 data);
bool drive_has_disk(int drv);
void clear_tc(s32);


void floppy_motor_w(uint8_t state);
floppy_image_device* m_cur_flop = nullptr;  // our own tracking
//u8 m_dor = 0;

bool m_ser_pending = false;
u8   m_ser_byte    = 0x06; // the one-shot byte we'll present on 06h
int m_ser_prime = 8;

floppy_image_device* get_floppy_by_index(int idx);

u8 m_selected = 0;

    u8  ser_data_r()  
   {
      // Only drain a byte if the shim actually has one.
    // If BIOS reads when none is available, return 0x00 (harmless).
    uint8_t v = 0x00;
    if (m_fd20->has_tx())
        v = m_fd20->dev_data_read();

    logerror("SER: read data %02X (q=%zu)\n", v, m_fd20->debug_tx_size());
    return v; 
}
    
    void ser_data_w(u8 v)
    {
                 m_fd20->host_data_write(v);
        logerror("SER: write data %02X\n", v);

    }


    u8  ser_status_r()   
    {
     // 0x60 = “link OK, TX empty” baseline we observed on the real machine.
    // bit0 = 1 when a byte is available on port 6 (device->host).
    const bool rx_ready = m_fd20->has_tx();
    const uint8_t status = 0x60  |  0x20 | (rx_ready ? 0x01 : 0x00);

    logerror("SER: read status (raw=%02X) [rx_ready=%d q=%zu]\n",
             status, rx_ready ? 1 : 0, m_fd20->debug_tx_size());

    return status;

         
    }
    
    void ser_param_w(u8 v)
    {
        logerror("SER: write param %02X\n", v);
               m_fd20->host_param_write(v); 
    }
    
    void ser_cfg_w(u8 v) 
    {
            m_fd20->reset();

            if (v == 0x0B) m_ser_prime = 4;   // after commit, present ready+byte again
    }

};


//void qx11_state::ser_cfg_w(u8 data) { /* accept and ignore; BIOS writes 08/13/0B etc. */ }

// Port 0x82: command/index
void qx11_state::ga_dma_cmd_w(u8 data)
{
    m_dma_cmd = data;

    // For now, treat any command as "program DMA" and return status-code 0x0D, ready=1.
    // BIOS checks (in 0x81): bit0=1 (ready) and (status & 0x1F) == 0x0D before sending 6 bytes.
    m_dma_status = 0x01 | 0x0D;
    m_dma_needed = 6;    // next 6 writes to 0x80 are the DMA record
}

// Port 0x81: status (bit0=ready, low 5 bits = code)
u8 qx11_state::ga_dma_status_r()
{
    return m_dma_status;
}

// Port 0x80: payload stream (6 bytes: ALo, AHi, Page, CLo, CHi, Mode)
void qx11_state::ga_dma_data_w(u8 data)
{
    if (!m_dma_needed) return;

    const int idx = 6 - m_dma_needed;
    switch (idx)
    {
        case 0: m_dma_addr  = (m_dma_addr & 0xFFFF00) | (u32)data; break;          // ALo
        case 1: m_dma_addr  = (m_dma_addr & 0xFF00FF) | (u32)data << 8; break;     // AHi
        case 2: m_dma_addr  = (m_dma_addr & 0x00FFFF) | (u32)data << 16; break;    // Page
        case 3: m_dma_len   = (m_dma_len  & 0xFF00)   | data; break;               // CLo
        case 4: m_dma_len   = (m_dma_len  & 0x00FF)   | (u16)data << 8; break;     // CHi
        case 5: m_dma_mode  = data; break;                                        // Mode
    }

    if (--m_dma_needed == 0)
    {
        // command accepted: clear 'ready' to satisfy the BIOS post-write poll
        m_dma_status &= ~0x01;

        // arm the engine; we'll start moving bytes on the next DRQ cycle
        m_dma_pos    = 0;
        m_dma_active = true;
    }
}



//// possible upd765 ... ports 12 and 13 /////
// 0x12: return current status (bits 7..6 drive the BIOS loops)
u8 qx11_state::status12_r()
{
     // simple “timer”: if we owe a response, raise RX-ready after a short delay
    if (m_resp_pending && m_resp_delay) {
        if (--m_resp_delay == 0)
            m_p12_status = 0xC0;  // RX=1, TX=1 when response becomes available
    }
    return m_p12_status;  // 0x80 (TX only) or 0xC0 (TX+RX)
}

// 0x13 write: BIOS writes a command/data byte when TX-ready was 1.
// We accept it and immediately make one response byte available.
void qx11_state::ga_p13_w(u8 data)
{
    m_p13_out = data;

    // Heuristic: for now, always prepare a benign 0x00 response,
    // but DO NOT raise RX-ready immediately (write helper wants 0x80).
    m_p13_in       = 0x00;
    m_resp_pending = true;
    m_resp_delay   = 2;     // a couple of 0x12 polls later we’ll present RX-ready
    m_p12_status   = 0x80;  
}

// 0x13 read: BIOS reads the response when RX-ready was 1.
// Consume it and drop RX-ready again.
u8 qx11_state::ga_p13_r()
{
    u8 v = m_p13_in;
    m_resp_pending = false;
    m_p12_status   = 0x80;  // drop RX-ready after the read
    return v;
}

// 0x14 write: early “video mode” sequence; just log/park for now.
void qx11_state::ga_video_w(u8 data)
{
    // You can stash this if you want to decode 0x9F,0xBF,0xDF,0xFF later.
    // LOG("GA: video ctl <= %02X\n", data);
}
///////////// possible upd765 ... ports 12 and 13 /////


///// SERIAL port and RTC code /////

// ===== Serial decode =====
qx11_state::ser_cfg qx11_state::decode_serial_mode(u8 m)
{
    ser_cfg c{};

    // Low nibble is baud code (contiguous)
    switch (m & 0x0F) {
        case 0x03: c.baud = 300; break;
        case 0x04: c.baud = 600; break;
        case 0x05: c.baud = 1200; break;
        case 0x06: c.baud = 2400; break;
        case 0x07: c.baud = 4800; break;
        case 0x08: c.baud = 9600; break;
        case 0x09: c.baud = 19200; break;
        case 0x0A: c.baud = 38400; break;
        default:   c.baud = 9600; break; // conservative fallback
    }

    // Parity in bits 7..6
    switch ((m >> 6) & 0x03) {
        case 0b10: c.parity = PAR_NONE; break;
        case 0b01: c.parity = PAR_ODD;  break;
        case 0b11: c.parity = PAR_EVEN; break;
        default:   c.parity = PAR_MARKSPACE; break; // 00
    }

    // Word/stop format is bits 5..4:
    //   00 = 7 data, 1 stop
    //   01 = 8 data, 1 stop
    //   10 = 7 data, 2 stop
    //   11 = 8 data, 2 stop
    const u8 fmt = (m >> 4) & 0x03;
    c.databits = (fmt & 0x01) ? 8 : 7;
    c.stopbits = (fmt & 0x02) ? 2 : 1;

    return c;
}

void qx11_state::apply_serial_cfg(const ser_cfg &cfg)
{
    m_ser_baud      = cfg.baud;
    m_ser_data_bits = cfg.databits;
    m_ser_stop_bits = cfg.stopbits;
    m_ser_parity    = (decltype(m_ser_parity))cfg.parity;

    LOGMASKED(LOG_SERIAL, "SER CFG: baud=%d, data=%d, stop=%d, parity=%s\n",
        m_ser_baud, m_ser_data_bits, m_ser_stop_bits,
        (m_ser_parity==PAR_NONE) ? "NONE" :
        (m_ser_parity==PAR_ODD)  ? "ODD"  :
        (m_ser_parity==PAR_EVEN) ? "EVEN" : "MARK/SPACE");

    // TODO: When you wire an actual UART core, propagate these:
    // - set its frame format (data/stop/parity)
    // - adjust its clock/divider to hit m_ser_baud
}

// ===== Serial/GA I/O =====
void qx11_state::ser_idx_w(u8 data)
{
    m_ser_idx = data & 0x1F; // observed indices: 0x08, 0x0B
    LOGMASKED(LOG_SERIAL, "SER idx <= %02X\n", m_ser_idx);
}

void qx11_state::ser_dat_w(u8 data)
{
    if (m_ser_idx == 0x08) {
        m_ser_mode = data;
        auto cfg = decode_serial_mode(m_ser_mode);
        apply_serial_cfg(cfg);
        LOGMASKED(LOG_SERIAL, "SER mode <= %02X\n", m_ser_mode);
    } else {
        // Other indices can be logged here when discovered (e.g., flow control)
        LOGMASKED(LOG_SERIAL, "SER data write at idx=%02X <= %02X\n", m_ser_idx, data);
    }
}

void qx11_state::brg_idx_w(u8 data)
{
    m_brg_idx = data;
    LOGMASKED(LOG_SERIAL, "BRG idx <= %02X\n", m_brg_idx);
}

u8 qx11_state::brg_idx_r()
{
    // Optional: return last index written
    return 0x10;
}


void qx11_state::brg_dat_w(u8 data)
{
    if (m_brg_idx == 0x23) {
        m_brg_23 = data; // observed 0x04 across your tests
        LOGMASKED(LOG_SERIAL, "BRG[23h] <= %02X (treated as timeout/base family)\n", m_brg_23);
        // Note: No effect on baud; actual rate is set by mode nibble.
    } else {
        LOGMASKED(LOG_SERIAL, "BRG data write at idx=%02X <= %02X\n", m_brg_idx, data);
    }
}

////// MC146818P RTC ///////
// ===== GA page select / status =====

// ---- handlers ----
u8 qx11_state::ga_cmd_r()
{
    // Reading the response consumes it: clear out-ready and default to 0xFF next time.
    const u8 v = m_ga_resp;
    ga_clr_out_ready();
    m_ga_resp = 0xFF;
    LOG("Read on Port 0x0C -> %02X\n", v);
    return v;
}

void qx11_state::ga_cmd_w(u8 data)
{
    // BIOS already waited for bit0=1. Accept command immediately.
    m_ga_page = data;

    // For page selects like 0xE0 (RTC window), acknowledge with OK (00) and raise bit1.
    m_ga_resp = 0x00;      // "OK"
    ga_set_out_ready();    // response available
    ga_set_in_ready();     // keep input-ready high (it likely polls bit0 too)
    LOG("Write on port 0x0C GA: -> %02X\n", data);
}

u8 qx11_state::ga_status_r()
{
    logerror("Read on Port 0D: status_r -> %02X\n", m_ga_status);
    return m_ga_status;
}

void qx11_state::ga_status_w(u8 data)
{
    // Some firmwares clear status bits by writing 0—be permissive.
    if ((data & 0x02) == 0) ga_clr_out_ready();
    if ((data & 0x01) == 0) m_ga_status &= ~0x01;

    logerror("Write on Port 0D: status<=%02X (now %02X)\n", data, m_ga_status);
}


// ===== RTC window proxies (only active when page==0xE0) =====
void qx11_state::ga_rtc_index_w(u8 data)
{
    if (ga_rtc_window()) { m_rtc->address_w(data & 0x3F); /* latch */ }
}

// Optional readback of index: mc146818 doesn't have an official "address read";
// we return 0xFF when not windowed (or you could mirror an internal latch if you keep one).
u8 qx11_state::ga_rtc_index_r()
{
    return ga_rtc_window() ? /*optional: return last index*/ 0xFF : 0xFF;
}

void qx11_state::ga_rtc_data_w(u8 data)
{
    if (ga_rtc_window()) m_rtc->data_w(data);
}


u8 qx11_state::ga_rtc_data_r()
{
    return ga_rtc_window() ? m_rtc->data_r() : 0xFF;
}


u8 qx11_state::io10_r()
{
    // Index port read semantics:
    //  - CRTC: return current index register
    //  - RTC : many parts don’t support index read; return the latched index
    if (rtc_window())
        return m_rtc_index_latch;          // readback helps BIOS probes
    else
        return crtc_index_r();              // your existing helper
}

void qx11_state::io10_w(u8 data)
{
    if (rtc_window()) {
        m_rtc_index_latch = data & 0x3F;   // 64 regs on 146818
        m_rtc->address_w(m_rtc_index_latch);
    } else {
        crtc_index_w(data);                 // normal CRTC path
    }
}

u8 qx11_state::io11_r()
{
    if (rtc_window())
        return m_rtc->data_r();             // RTC data read
    else
        return crtc_data_r();               // CRTC data read
}

void qx11_state::io11_w(u8 data)
{
    if (rtc_window())
        m_rtc->data_w(data);                // RTC data write
    else
        crtc_data_w(data);                  // CRTC data write
}

/////// END SERIAL PORT and RTC code /////



static inline bool is_highlight(u8 attr) {
    // Strict: return attr == 0x70;
    // Looser (any nonzero background nibble): return (attr & 0x70) != 0;
    return attr == 0x70;
}

void qx11_state::rasterize_textbuffer_highlight_only()
{
    const u32 base = m_vram_display_origin;

    for (int row = 0; row < ROWS; ++row) {
        const u32 row_base = base + u32(row) * 8;      // 8 scanlines per cell
        const u32 tb_row   = u32(row) * (COLS * 2);    // 2 bytes per cell in textbuffer

        for (int col = 0; col < COLS; ++col) {
            const u32 i     = tb_row + u32(col) * 2;
            const u8  ch    = m_textbuffer[i + 1];     // char
            const u8  attr  = m_textbuffer[i + 0];     // attribute
            const u32 col_off = u32(col) * k_col_stride;

            // choose glyph row source:
            //  - if you have a font: use it
            //  - otherwise: use what’s already in VRAM and only apply highlight
            for (int y = 0; y < 8; ++y) {
                u8 bits;
                if (m_font8x8) {
                    const u8* g = &m_font8x8[(u32)ch * 8];
                    bits = (ch == 0x20 || ch == 0x00) ? 0x00 : g[y]; // keep CLS working
                } else {
                    // No font wired: keep existing pixels, but make highlight visible
                    const u32 vram_off_rd = row_base + y + col_off;
                    bits = (vram_off_rd < m_vram9000.bytes()) ? m_vram9000[vram_off_rd] : 0x00;
                    if (ch == 0x20 || ch == 0x00) bits = 0x00; // spaces still blank
                }

                if (is_highlight(attr)) bits ^= 0xFF; // invert for highlight (0x70)

                const u32 vram_off_wr = row_base + y + col_off;
                if (vram_off_wr < m_vram9000.bytes())
                    m_vram9000[vram_off_wr] = bits;
            }
        }
    }
}

void qx11_state::rasterize_textbuffer_to_bitmap()
{
    const u32 base = m_vram_display_origin;

    for (int row = 0; row < ROWS; ++row)
    {
        const u32 row_base = base + u32(row) * 8;   // 8 scanlines per glyph
        const u32 cell_row = u32(row) * (COLS * 2); // 2 bytes per cell

        for (int col = 0; col < COLS; ++col)
        {
            const u32 i   = cell_row + u32(col) * 2;
            const u8  ch  = m_textbuffer[i + 1];     // low byte = character
           
            // const u8 attr = m_textbuffer[i + 1];  // (unused for now)

            const u32 col_off = u32(col) * k_col_stride;

            if (ch == 0x20 || ch == 0x00) {
                // Space / NUL -> clear 8 rows in the bitmap
                for (int y = 0; y < 8; ++y) {
                    const u32 vram_off = row_base + y + col_off;
                    if (vram_off < m_vram9000.bytes())
                        m_vram9000[vram_off] = 0x00;
                }
            } else if (m_font8x8) {
                // Optional: draw non-spaces if you’ve wired a font
                const u8* g = &m_font8x8[(u32)ch * 8];
                for (int y = 0; y < 8; ++y) {
                    const u32 vram_off = row_base + y + col_off;
                    if (vram_off < m_vram9000.bytes())
                        m_vram9000[vram_off] = g[y];
                }
            }
            // else: leave existing non-space pixels as-is (your 0x9000 path will paint them)
        }
    }
}
//////////////// INT 13h (disk services) trap handler ///////////////////

/////////////////// ********** FDC CODE uPD765 ********** ///////////////////


u8 qx11_state::fdc_fifo_r()
{   
    auto v = m_fdc->fifo_r();

    logerror("FDC: CMD FIFO read (cmdlen=%d)\n", m_cmdlen);
    return v;
}

void qx11_state::fdc_fifo_w(u8 data)
{
    logerror("FDC: CMD FIFO write %02X\n", data);
    m_fdc->fifo_w(data);
}

u8 qx11_state::fdc_msr_r()
{
   u8 v = m_fdc->msr_r();
   logerror("FDC: CMD MSR read %02X\n", v);
   
   // not used by BIOS
}

void qx11_state::fdc_intrq_w(int state)
{
    m_fdc_irq = bool(state);
   
    //m_fdc->set_ready_line_connected(true);
    //m_fdc->dor_w(4);
    

     // active low
    //logerror("FDC: INTRQ %d\n", state);
    //m_maincpu->set_input_line(INPUT_LINE_IRQ0, state);
    
     switch (state)
    {
        case 0: 
            break;//m_maincpu->set_input_line(7, ASSERT_LINE); break;  // IRQ low
        
        case 1: 
            m_maincpu->set_input_line(7, CLEAR_LINE); 
            break;   // IRQ high
    } 
    //m_maincpu->set_input_line(6, state ? CLEAR_LINE : ASSERT_LINE);
    
}

// Normalize an opcode to its base function (mask off MT/MF/SK modifiers)


/////////////////// ********** END FDC CODE ********** ///////////////////

//////////////////// ********** SCREEN ********** ///////////////////


void qx11_state::qx11_palette_init(palette_device &palette) const
{
    palette.set_pen_color(0, rgb_t(0x00, 0x00, 0x00)); // black
    palette.set_pen_color(1, rgb_t(0xFF, 0xFF, 0xFF)); // white
}

u32 qx11_state::screen_update_qx11(screen_device &screen, bitmap_rgb32 &bmp, const rectangle &clip)
{
    //maybe_refresh_text_from_rom();
    refresh_text_from_extfont_if_dirty();

    // ---------------- Constants ----------------
    constexpr u32 COL_STRIDE      = 0x0200;   // 512 bytes between character columns (confirmed by dump)
    // Graphics plane in ES=0x8000 window
    constexpr u32 GFX_BASE_TOP    = 0x0000;   // top field
    constexpr u32 GFX_BASE_BOTTOM = 0x0100;   // bottom field base (y >= 200)
    constexpr int GFX_COLS_DRAW   = 80;
    constexpr int BOTTOM_COL_BIAS = 0;

    // Text plane — bitmap rasterized at 0x9000:0100 (top 200 lines source)
    constexpr u32 TXT_BASE_TOP    = 0x00100;
    constexpr int TXT_COLS_DRAW   = 80;

    // Colors
    const u32 BG = rgb_t(0xFF,0x00,0x00,0x00);  // black
    const u32 FG = rgb_t(0xFF,0x00,0xFF,0x00);  // green

    bmp.fill(BG, clip);

    const u32 bytes8000 = m_vram8000.bytes();
    const u32 bytes9000 = m_vram9000.bytes();

    // -------------------------------- PASS A: GRAPHICS (unchanged) --------------------------------
    for (int y = std::max(clip.min_y, 0); y <= std::min(clip.max_y, 399); ++y) {
        u32 *dst = &bmp.pix(y, clip.min_x);

        const bool lower = (y >= 200);
        const int  rel_y = lower ? (y - 200) : y;              // 0..199 within half
        const u32  y_swz = u32(rel_y & 7) + u32(rel_y >> 3) * 0x08;

        const u32 base = GFX_BASE_TOP + (lower ? GFX_BASE_BOTTOM : 0);
        const int col_bias = lower ? BOTTOM_COL_BIAS : 0;

        for (int col = 0; col < GFX_COLS_DRAW; ++col) {
            const int s_col = col + col_bias;
            if (s_col < 0) continue;

            const u32 off = base + u32(s_col) * COL_STRIDE + y_swz;
            if (off >= bytes8000) break;

            const u8 b = m_vram8000[off];
            const int x_start = (col << 3);

            for (int bit = 0; bit < 8; ++bit) {
                const int x = x_start + bit;
                if (x < clip.min_x || x > clip.max_x) continue;
                dst[x - clip.min_x] = (b & (0x80 >> bit)) ? FG : BG;
            }
        }
    }

    // In qx11_state:
int m_text_margin_x = 4;   // pixels to shift text right
int m_text_margin_y = 1;   // pixels to shift text down
// ------------------------------ PASS B: TEXT (8x16 via vertical doubling, with margins) ------------------------------
{
    constexpr int ROWS = 25;
    constexpr int COLS = 80;
    constexpr int CELL_SRC_H = 8;   // source glyph height (in VRAM)
    // destination cell height = 16 (8*2) implicitly

    const int y_min = std::max(clip.min_y, 0);
    const int y_max = std::min(clip.max_y, 399);

    const int MARGIN_X = m_text_margin_x;  // <-- configurable
    const int MARGIN_Y = m_text_margin_y;  // <--

    for (int row = 0; row < ROWS; ++row) {
        const int y_src_base = row * CELL_SRC_H;      // 0..199
        const int y_dst_base = MARGIN_Y + row * 16;   // apply top margin

        if (y_dst_base > y_max)
            break;                       // further rows are below the clip
        if (y_dst_base + 15 < y_min)
            continue;                    // this row is entirely above the clip

        for (int gy = 0; gy < CELL_SRC_H; ++gy) {
            const int y_src = y_src_base + gy;                      // 0..199
            const u32 y_swz = u32(y_src & 7) + u32(y_src >> 3) * 0x08;

            // Write each 1-pixel source line twice to make 16px tall
            for (int rep = 0; rep < 2; ++rep) {
                const int y_dst = y_dst_base + (gy * 2 + rep);
                if (y_dst < y_min || y_dst > y_max) continue;

                u32 *dst = &bmp.pix(y_dst, clip.min_x);

                for (int col = 0; col < COLS; ++col) {
                    const u32 off = TXT_BASE_TOP + y_swz + u32(col) * COL_STRIDE;
                    if (off >= bytes9000) break;

                    const u8 b = m_vram9000[off];

                    // Left margin: shift where we draw on screen
                    const int x_start = MARGIN_X + (col << 3);

                    // Optional invert using your m_textbuffer (kept from your code)
                    bool inv = false;
                    if (m_textbuffer) {
                        const int cell_idx = row * 80 + col;
                        inv = (m_textbuffer[cell_idx * 2 + 0] == 'p');
                    }

                    // Foreground-only draw so graphics show through
                    for (int bit = 0; bit < 8; ++bit) {
                        const int x = x_start + bit;
                        if (x < clip.min_x || x > clip.max_x) continue;

                        const bool on = ((b >> (7 - bit)) & 1) ^ inv;
                        if (on) dst[x - clip.min_x] = FG;
                    }
                }
            }
        }
    }
}

    return 0;
}

// Bulk clear entire 80x25 text plane in the 0x9000 bitmap
void qx11_state::clear_full_text_bitmap()
{
    address_space &prog = m_maincpu->space(AS_PROGRAM);
    // rows 0..24, cols 0..79
    for (int row = 0; row < 25; ++row)
        for (int col = 0; col < 80; ++col)
            clear_text_cell_bitmap(row, col);
}

u32  m_font_base_phys = 0x00F6560;  // your current best guess
int  m_font_index_bias = 0x00;         // try 0 or -0x20 if table starts at ' ' (0x20)
bool m_font_flip_rows  = true;     // true if the table is upside down

void qx11_state::draw_text_cell_from_rom(int row, int col, u8 ch)
{
    address_space &prog = m_maincpu->space(AS_PROGRAM);

    const u32 base = (0x9000u << 4) + 0x0100u + u32(col) * 0x0200u;
    const u32 y0   = u32(row) * FONT_HEIGHT;

    for (int sub = 0; sub < FONT_HEIGHT; ++sub) {
        const u32 rom  = FONT_PHYS_BASE + u32(ch) * FONT_HEIGHT + sub; // idx = ch
        const u8  bits = prog.read_byte(rom);
        prog.write_byte(base + (y0 + sub), bits);  // overwrite (not XOR)
    }
}


// Shadow buffer region: 80*25*2 bytes (char,attr) starting at 0000:0B05
static constexpr offs_t SHADOW_BASE = 0x0000B05;
//static constexpr offs_t SHADOW_BASE = 0x00B800;
static constexpr offs_t SHADOW_END  = SHADOW_BASE + 80*25*2 - 1;

bool m_text_frame_dirty = false;  // add to your state class

void qx11_state::maybe_refresh_text_from_rom()
{
    if (!m_text_frame_dirty) return;
    m_text_frame_dirty = false;

    address_space &prog = m_maincpu->space(AS_PROGRAM);
    offs_t a = SHADOW_BASE;

    for (int row = 0; row < 25; ++row)
        for (int col = 0; col < 80; ++col, a += 2) {
            const u8 ch = prog.read_byte(a);
            if (ch == 0x20 || ch == 0x00) clear_text_cell_bitmap(row, col);
            else                           draw_text_cell_from_rom(row, col, ch);
        }
}

static constexpr u32 TXT_PHYS    = 0x9000u << 4; // 0x90000
static constexpr u32 TXT_BASEOFF = 0x0100u;
static constexpr u32 COL_STRIDE  = 0x0200u;
static constexpr int GLYPH_H     = 8;

void qx11_state::clear_text_cell_bitmap(int row, int col)
{
    address_space &p = m_maincpu->space(AS_PROGRAM);
    const u32 base = (TXT_PHYS + TXT_BASEOFF) + u32(col) * COL_STRIDE;
    const u32 y0   = u32(row) * GLYPH_H;
    for (int s = 0; s < GLYPH_H; ++s) p.write_byte(base + (y0 + s), 0x00);
}

inline void qx11_state::draw_text_cell_from_extfont(int row, int col, u8 ch)
{
    const u8 *font = memregion("extfont")->base();
    if (!font) return;  // safety
    const u8 *glyph = &font[u32(ch) * GLYPH_H];

    address_space &p = m_maincpu->space(AS_PROGRAM);
    const u32 base = (TXT_PHYS + TXT_BASEOFF) + u32(col) * COL_STRIDE;
    const u32 y0   = u32(row) * GLYPH_H;

    for (int s = 0; s < GLYPH_H; ++s)
        p.write_byte(base + (y0 + s), glyph[s]);   // overwrite (not XOR)
}

void qx11_state::refresh_text_from_extfont_if_dirty()
{
    if (!m_text_frame_dirty) return;
    m_text_frame_dirty = false;

    address_space &p = m_maincpu->space(AS_PROGRAM);
    offs_t a = SHADOW_BASE;
    


    for (int row = 0; row < 25; ++row)
        for (int col = 0; col < 80; ++col, a += 2) {
            const u8 ch = p.read_byte(a);
            if (ch == 0x00 || ch == 0x20) clear_text_cell_bitmap(row, col);
            else                           draw_text_cell_from_extfont(row, col, ch);
        }
}

void qx11_state::activate_cga_output()
{
    // Use the CGA device’s screen_update (adjust bitmap type if your tree differs)
     //m_screen->set_screen_update(*m_cga, FUNC(isa8_ega_device::clock));
}


void qx11_state::activate_native_output()
{
   m_screen->set_screen_update(*m_cga, FUNC(qx11_state::screen_update_qx11));
}

void qx11_state::cga_seen_w(offs_t, u8)
{
    activate_cga_output(); 
}
//////////////////// ********** END SCREEN ********** ///////////////////

/////////////////// INT 08 /////////////////////////


void qx11_state::tick_cb(int /*param*/)
{
     if (post_ready)
            bios_tick_once();
}



void qx11_state::bios_tick_once()
{
    auto &space = m_maincpu->space(AS_PROGRAM);

    u16 lo = space.read_word(0x046C);
    u16 hi = space.read_word(0x046E);
    u8  mf = space.read_byte(0x0470);

    lo++; if (!lo) hi++;
    if (hi > 0x0018 || (hi == 0x0018 && lo >= 0x00B0)) {
        u32 t = (u32(hi) << 16) | lo;
        t -= 0x001800B0u;
        lo = u16(t);
        hi = u16(t >> 16);
        mf = 1;
    }

    
    space.write_word(0x046C, lo);
    space.write_word(0x046E, hi);
    space.write_byte(0x0470, mf);
    
    //logerror("tick_clock\n");
}


/////////////////// INT 08 ENDS /////////////////////

//////////////////// ********** MACHINE START and RESET ********** ///////////////////
void qx11_state::machine_start()
{


m_fd20 = std::make_unique<fd20_epsp>();
// m_cmdbuf.clear();
// m_cmdbuf.reserve(32);   // plenty for cmd+params+results
m_expect  = 0;
m_resleft = 0;


    m_fdc->reset_w(0);
   

///////////////// END SERIAL PORT and RTC code /////
   
    if (!m_screen) fatalerror("Screen device not found\n");

    if (!m_maincpu) fatalerror("CPU device not found\n");

 
    

    address_space &io = m_maincpu->space(AS_IO); // <-- reference, do NOT copy   
    
   address_space &prog = m_maincpu->space(AS_PROGRAM);

    m_shadow_tap = prog.install_write_tap(
        SHADOW_BASE, SHADOW_END, "qx11_shadow_spaces_only",
        [this, &prog](offs_t byte_addr, u8 &data, u8 /*mask*/)
        {
            m_text_frame_dirty = true;

            // char byte = even address; attr byte = odd
            if (((byte_addr - SHADOW_BASE) & 1) != 0) return;

            const offs_t cell = (byte_addr - SHADOW_BASE) >> 1;
            const int row = int(cell / 80);
            const int col = int(cell % 80);

            const u8 ch = data;
            if (ch == 0x20 || ch == 0x00)
                clear_text_cell_bitmap(row, col);  // zero 8 scanlines in 0x9000
        }
    );

    // Add any noisy ports you want to ignore here
    static const u16 kIgnore[] = { 0x12,0x13/* add more if needed */ };

    auto ignore = [](u16 port)->bool {
        for (u16 p : kIgnore) if (p == port) return true;
        return false;
    };

     m_io_tap = io.install_readwrite_tap(
        0x0000, 0xff, "io_sniffer",
        [this, ignore](offs_t off, u8 &data, u8) {
            u16 port = (u16)off;
            if (!ignore(port))
                logerror("Read  in I/O port %04X, Value read    %02X (PC=%s)\n",
                         port, data, machine().describe_context());
        },
        [this, ignore](offs_t off, u8 data, u8) {
            u16 port = (u16)off;
            if (!ignore(port))
                logerror("Write to I/O port %04X, Value written %02X (PC=%s)\n",
                         port, data, machine().describe_context());
        }
    );

    // INT 08 timer at ~18.2065 Hz

m_tick = timer_alloc(FUNC(qx11_state::tick_cb), this);
m_tick->adjust(attotime::from_hz(18.20648), 0, attotime::from_hz(18.20648));    
    // INT 08 Timer
     
}

void qx11_state::machine_reset()
{
    post_ready = false;

// Reset observed latches
    m_ser_idx   = 0;
    m_brg_idx   = 0;
    m_ser_prime = 8;

    m_p12_status = 0x80;
    m_p13_in = m_p13_out = 0x00;
    m_resp_pending = false;
    m_resp_delay = 0;

     //m_fd20->reset();

    if (!cmos_initialized) {

        m_rtc->address_w(0x0F);
        m_rtc->data_w(0x80);   // set bit7

        cmos_initialized = true;
    }
  
    // Keep last programmed serial config (BIOS re-programs it anyway)   

}

//////////////////// ********** END MACHINE START and RESET ********** ///////////////////

///////////////////// ********** Memory and I/O maps ********** //////////////////////////

void qx11_state::mem_map(address_map &map)
{
    // === RAM: 0x00000–0x7FFFF (512 KiB) ===
    map(0x00000, 0x07ffff).ram();  // Main RAM 512K (base QX11 model cam with 128Kb)
   
    //QX-11 Bios Map
    map(0xf0000, 0xfffff).rom().region("bios", 0x0000); // This is the BIOS.. even though the BIOS for QX11 is 32 KB, the BIOS is mirrored on F000 an F800
    map(0xe0000, 0xeffff).rom().region("rom2", 0x0000); // This is the MSDOS/Command.com Also mirroed to the E0000 space.


    
    //map(0x0A0000, 0x0CFFFF).ram();

       // QX-11 Temporary framebuffer 
    map(0x080000, 0x08FFFF).ram().share("vram8000");  // Mapped to graphic VRAM native video mode  
    map(0x090000, 0x09FFFF).ram().share("vram9000");  // Mapped to Text (character drawing) native Video Mode
    map(0x00b04,0x01A9f).ram().share("textbuffer");   // This are is some kind of screen buffer.. It gets erased when issuing a CLS
    map(0xB8000,0xB8FFF).ram().share("vram_vga");
    map(0xA0000,0xA0000).ram().share("vga_graphics_vram");
    // QX-11 framebuffer

}

void qx11_state::io_map(address_map &map)
{
    //map.global_mask(0xff);
    map.unmap_value_high();

    // BRG/timeout family (seen sequence uses index 0x23; value stayed 0x04)
    map(0x04, 0x04).rw(FUNC(qx11_state::brg_idx_r), FUNC(qx11_state::brg_idx_w));
    map(0x05, 0x05).w(FUNC(qx11_state::brg_dat_w));
    map(0x06,0x06).rw(FUNC(qx11_state::ser_data_r),   FUNC(qx11_state::ser_data_w));  // related to Serial Port Probably GAVNIO
    map(0x07,0x07).rw(FUNC(qx11_state::ser_status_r), FUNC(qx11_state::ser_param_w)); // Serial Port  probably GAVNIO
    map(0x08,0x08).w (FUNC(qx11_state::ser_cfg_w));                                   // Serial Port  probably GAVNIO
    map(0x0c, 0x0c).rw(FUNC(qx11_state::ga_cmd_r),    FUNC(qx11_state::ga_cmd_w));
    map(0x0d, 0x0d).rw(FUNC(qx11_state::ga_status_r), FUNC(qx11_state::ga_status_w));
    map(0x0e, 0x0e).rw(FUNC(qx11_state::p13_in_r),     FUNC(qx11_state::p13_out_w)); // It reads this port to check if the floppy drive is ready (have a disk )
    map(0x0F,0x0F).w (FUNC(qx11_state::floppy_motor_w)); // Used for drive selection and to indicate the data phase of the 765 ended probably GAFDDC
    map(0x10, 0x10).w(m_rtc, FUNC(mc146818_device::address_w)); // HD146818 RTC index
    map(0x11, 0x11).rw(m_rtc, FUNC(mc146818_device::data_r), FUNC(mc146818_device::data_w)); // HD146818 RTC data
    map(0x12, 0x13).m(m_fdc, FUNC(upd765a_device::map));  // FDC uPD765A MSR(port 12) and FIFO (port 13)
    map(0x14, 0x14).w(m_psg, FUNC(sn76489_device::write));  // SN76489 Sound chip
    
    map(0x7e, 0x7e).r(FUNC(qx11_state::status7e_r));
    map(0x80, 0x80).rw(m_postmux, FUNC(qx11_postmux_device::port80_r), FUNC(qx11_postmux_device::port80_w)); // Port 80,81,82 seem to be related to the hard drive.
    map(0x81, 0x81).rw(m_postmux, FUNC(qx11_postmux_device::port81_r), FUNC(qx11_postmux_device::port81_w));   // Port 81 & 82 seems to be the Hard Drive Controller
    map(0x82, 0x82).w (m_postmux, FUNC(qx11_postmux_device::port82_w));
    map(0x92, 0x92).rw(FUNC(qx11_state::port92_r),  FUNC(qx11_state::port92_w));
    map(0x93, 0x93).rw(FUNC(qx11_state::port93_r),  FUNC(qx11_state::port93_w));

     //map(0x03D4, 0x03D5).w(FUNC(qx11_state::cga_seen_w)); // CGA CARD ICRTDRV.SYS

}


//////////////////////// ********** END Memory and I/O maps ********** //////////////////////////

///////////////////// ********** KEYBOARD ********** /////////////////// 

u8 qx11_state::ascii_to_qx(u8 a)
{
    // COMMAND.COM usually accepts plain ASCII; make sure Enter becomes CR
    if (a == 0x0A) return 0x0D; // LF -> CR
    return a;
}

void qx11_state::kbd_push_ascii(u8 ascii, u8 scancode /*=0*/)
{
    // Program space reference (DON'T copy!)
    address_space &mem = m_maincpu->space(AS_PROGRAM);

    // Read head/tail
    u16 head = mem.read_word(KBD_HEAD_PTR);
    u16 tail = mem.read_word(KBD_TAIL_PTR);

    // Compute "next" tail with 4-byte stride and wrap
    auto wrap4 = [](u16 p) { return (u16)(p + 4); };
    u16 next_tail = wrap4(tail);
    if (next_tail >= KBD_BUF_END) next_tail = KBD_BUF_START;

    // Leave one slot empty: if next_tail == head, buffer is full → drop (or overwrite)
    if (next_tail == head)
        return; // or overwrite by advancing head too

    // Compose AX (AL=ASCII, AH=scancode per your INT16 code)
    u16 ax = (u16(scancode) << 8) | ascii;
    //printf("Key : %U04",ax);

    // Write entry: [tail+0]=AX, [tail+2]=flags snapshot
    mem.write_word(tail + 0, ax);

    u8 flags_lo = mem.read_byte(0x0417); // BDA shift/toggle flags
    u8 flags_hi = mem.read_byte(0x0418);
    mem.write_word(tail + 2, (u16(flags_hi) << 8) | flags_lo);

    // Advance tail
    mem.write_word(KBD_TAIL_PTR, next_tail);

    // If your BIOS expects an IRQ on key arrival, assert it here (optional):
    // if (m_pic) m_pic->ir1_w(1);
}

// --- BEGIN: QX-11 PC-compatible keyboard helpers (impl) ---

// BDA helpers (0040:)
static inline u8 rb_bda(address_space &sp, u32 off) { return sp.read_byte(0x400 + off); }
static inline void wb_bda(address_space &sp, u32 off, u8 v) { sp.write_byte(0x400 + off, v); }

// Push one key "word" to 0040:001E ring buffer (16 words, 32 bytes)
void qx11_state::bios_kbd_enqueue(u8 ascii, u8 sc)
{
    address_space &sp = m_maincpu->space(AS_PROGRAM);

    u8 head = rb_bda(sp, 0x1A);
    u8 tail = rb_bda(sp, 0x1C);
    u8 next = (u8)((head + 2) & 0x1F);  // wrap at 32

    if (next == tail) {
        // buffer full -> drop (or overwrite oldest by advancing tail)
        return;
    }

    const u16 entry = (u16(sc) << 8) | ascii;     // [AL, AH]
    const u16 off = 0x1E + head;
    wb_bda(sp, off + 0, u8(entry & 0xFF));       // AL
    wb_bda(sp, off + 1, u8(entry >> 8));         // AH
    wb_bda(sp, 0x1A, next);                      // advance head

    // If you raise a GA keyboard IRQ, do it here.
}

// 0x40:0x17 shift flags (PC/XT layout):
// bit0=RightShift, bit1=LeftShift, bit2=Ctrl, bit3=Alt,
// bit4=ScrollLock, bit5=NumLock, bit6=CapsLock, bit7=Insert (varies)
void qx11_state::set_shift_flags(u8 mask, bool pressed)
{
    address_space &sp = m_maincpu->space(AS_PROGRAM);
    u8 v = rb_bda(sp, 0x17);
    v = pressed ? (v | mask) : (v & ~mask);
    wb_bda(sp, 0x17, v);
}

// Map a few printables to XT Set-1 makes (US layout). Extend as needed.
u8 qx11_state::ascii_to_set1(u8 ch)
{
    // Letters: case-insensitive to same scancode
    if (ch >= 'A' && ch <= 'Z') ch = ch - 'A' + 'a';
    switch (ch) {
        // control keys (ASCII)
        case 0x1B: return 0x01; // Esc
        case 0x09: return 0x0F; // Tab
        case 0x0D: return 0x1C; // Enter
        case 0x08: return 0x0E; // Backspace
        case ' ':  return 0x39; // Space
        // digits
        case '1': return 0x02; case '2': return 0x03; case '3': return 0x04; case '4': return 0x05;
        case '5': return 0x06; case '6': return 0x07; case '7': return 0x08; case '8': return 0x09;
        case '9': return 0x0A; case '0': return 0x0B;
        // letters
        case 'q': return 0x10; case 'w': return 0x11; case 'e': return 0x12; case 'r': return 0x13; case 't': return 0x14;
        case 'y': return 0x15; case 'u': return 0x16; case 'i': return 0x17; case 'o': return 0x18; case 'p': return 0x19;
        case 'a': return 0x1E; case 's': return 0x1F; case 'd': return 0x20; case 'f': return 0x21; case 'g': return 0x22;
        case 'h': return 0x23; case 'j': return 0x24; case 'k': return 0x25; case 'l': return 0x26;
        case 'z': return 0x2C; case 'x': return 0x2D; case 'c': return 0x2E; case 'v': return 0x2F; case 'b': return 0x30;
        case 'n': return 0x31; case 'm': return 0x32;
        // punctuation (common)
        case '-': return 0x0C; case '=': return 0x0D; case '[': return 0x1A; case ']': return 0x1B; case '\\': return 0x2B;
        case ';': return 0x27; case '\'': return 0x28; case ',': return 0x33; case '.': return 0x34; case '/': return 0x35;
        case ':': return 0x28; case '|': return 0x2C; case '"': return 0x29;
        default:  return 0x00;
    }
}

// Called when a non-printable key changes (press/release). param = Set-1 scancode (or extended code).


// Map Fn number (1..16) to the BIOS-style scan code we’ll put in AH.
// F1..F10 = 3B..44, F11=85, F12=86, F13..F16=87..8A (common extendeds).
static inline u8 fkey_scan(u8 fn) {
    switch (fn) {
        case  1: return 0x3B; case  2: return 0x3C; case  3: return 0x3D; case  4: return 0x3E; case  5: return 0x3F;
        case  6: return 0x40; case  7: return 0x41; case  8: return 0x42; case  9: return 0x43; case 10: return 0x44;
        case 11: return 0x85; case 12: return 0x86;
        case 13: return 0x87; case 14: return 0x88; case 15: return 0x89; case 16: return 0x8A;
        default: return 0x00;
    }
}

// INPUT_CHANGED for non-printables (arrows/F-keys, etc.)
// param = Set-1 scancode; newval!=0 => make, newval==0 => break

INPUT_CHANGED_MEMBER(qx11_state::key_makebreak_changed)
{
    const bool pressed = (newval != 0);
    const u8 sc = u8(param);

    if (pressed) {
        // Non-printables: AL=0, AH=scancode
        //bios_kbd_enqueue(0x00, sc);
        kbd_push_ascii(0x00,sc);
    } else {
        // Breaks are often ignored, but emitting make|80h helps some apps
        kbd_push_ascii(0x00,sc | 0x80);
        //bios_kbd_enqueue(0x00, sc | 0x80);
    }
}

// INPUT_CHANGED for modifiers (Shift/Ctrl/Alt…and locks if you want)
// param = bit mask in 0x40:0x17 to set/clear
INPUT_CHANGED_MEMBER(qx11_state::mod_changed)
{
    const bool pressed = (newval != 0);
    set_shift_flags(u8(param), pressed);
}

// --- END: QX-11 PC-compatible keyboard helpers (impl) ---


void qx11_state::kbd_put(u8 ascii)
{
    // 1) Keep your existing GA path if you have one
    //    (e.g., push to GA FIFO / raise GA IRQ)

    // 2) PC-compatible path: also push to BDA ring
    const u8 sc = ascii_to_set1(ascii);
    if (sc) {
        // printable keys: AL=ASCII, AH=make scancode
        kbd_push_ascii(ascii,sc);
        //bios_kbd_enqueue(ascii, sc);
    } else {
        // If it's a control not covered above, you can special-case it here.
        // (Most GENERIC_KEYBOARD delivery will land in ascii_to_set1 anyway.)
    }
}
 

 /*
/// OLD KEYBOARD
void qx11_state::kbd_put(u8 ascii)
{
 // Minimal: map LF->CR for COMMAND.COM
    if (ascii == 0x0A) ascii = 0x0D;
    //printf("key: %04X",ascii);
    kbd_push_ascii(ascii, 0); // fill real scancode later if needed
}
 */
u8 qx11_state::kb_status_r()
{
    // bit0: data ready; bit1: tx ready (always 1 unless you implement command channel)
    //return (m_kb_status & 0x01) | 0x02;
    return 0x01;
}

u8 qx11_state::kb_data_r()
{
    u8 val = 0x02 ;
    if (!m_kb_fifo.empty())
    {
        val = m_kb_fifo.front();
        m_kb_fifo.pop_front();
    }

    // Update flags
    if (m_kb_fifo.empty())
    {
        m_kb_status &= ~0x01; // clear data ready
        //if (m_pic)
        //    m_pic->ir1_w(0);  // lower IRQ when queue drains
    }

    return val;
}

void qx11_state::kb_data_w(u8 data)
{
    // If the firmware writes commands to the keyboard, handle them here.
    // For many simple ROMs this can be a NOP initially.
}
INPUT_CHANGED_MEMBER(qx11_state::key_up_changed)    { if (newval) kbd_push_ascii(0x00, 0x48);  }
INPUT_CHANGED_MEMBER(qx11_state::key_down_changed)  { if (newval) kbd_push_ascii(0x00, 0x50);  }
INPUT_CHANGED_MEMBER(qx11_state::key_left_changed)  { if (newval) kbd_push_ascii(0x00, 0x4B);  }
INPUT_CHANGED_MEMBER(qx11_state::key_right_changed) { if (newval) kbd_push_ascii(0x00, 0x4D);  }
INPUT_CHANGED_MEMBER(qx11_state::key_f9_changed)    { if (newval) kbd_push_ascii(0x00, 0x43);  }


static INPUT_PORTS_START(qx11)
    PORT_START("EXTK")
    PORT_BIT(0x0001, IP_ACTIVE_HIGH, IPT_KEYBOARD) PORT_NAME("Up")
        PORT_CODE(KEYCODE_UP)    PORT_CHANGED_MEMBER(DEVICE_SELF, FUNC(qx11_state::key_up_changed), 0)
    PORT_BIT(0x0002, IP_ACTIVE_HIGH, IPT_KEYBOARD) PORT_NAME("Down")
        PORT_CODE(KEYCODE_DOWN)  PORT_CHANGED_MEMBER(DEVICE_SELF, FUNC(qx11_state::key_down_changed), 0)
    PORT_BIT(0x0004, IP_ACTIVE_HIGH, IPT_KEYBOARD) PORT_NAME("Left")
        PORT_CODE(KEYCODE_LEFT)  PORT_CHANGED_MEMBER(DEVICE_SELF, FUNC(qx11_state::key_left_changed), 0)
    PORT_BIT(0x0008, IP_ACTIVE_HIGH, IPT_KEYBOARD) PORT_NAME("Right")
        PORT_CODE(KEYCODE_RIGHT) PORT_CHANGED_MEMBER(DEVICE_SELF, FUNC(qx11_state::key_right_changed), 0)
    //PORT_BIT(0x0011, IP_ACTIVE_HIGH, IPT_KEYBOARD) PORT_NAME("F9")
     //   PORT_CODE(KEYCODE_F9) PORT_CHANGED_MEMBER(DEVICE_SELF, FUNC(qx11_state::key_f9_changed), 0)
INPUT_PORTS_END
   
    

ioport_constructor qx11_state::device_input_ports() const
{
    return INPUT_PORTS_NAME(qx11);
}


////////////////////// ********** END KEYBOARD ********** ///////////////////

static void qx11_floppies(device_slot_interface &device)
{
	device.option_add("525dd", FLOPPY_525_DD); // The most common Drive in the QX11. The QX11 was also capable of reading Single sided Disk.
    device.option_add("35dd", FLOPPY_35_DD);  // Documentation says, the QC11 (Japanese version) came with 720kb Floppy drives.
}
////////////////////// ********** MACHINE CONFIGURATION ********** ///////////////////


void qx11_state::qx11(machine_config &config)
{
    I8088(config, m_maincpu, 4'772'000);
    m_maincpu->set_addrmap(AS_PROGRAM, &qx11_state::mem_map);
    m_maincpu->set_addrmap(AS_IO,      &qx11_state::io_map);

    RAM(config, m_ram);
    m_ram->set_default_size("128K");
    //m_ram->set_extra_options("128K,256K,384K,512K");  
    PIC8259(config, m_pic_s, 0);
	m_pic_s->out_int_callback().set_inputline(m_maincpu, 0);

    // QX-11 Framebuffer 
    SCREEN(config, m_screen, SCREEN_TYPE_RASTER);
    //PALETTE(config, m_palette, 2).set_init(FUNC(qx11_state::qx11_palette_init));

    //m_qx11screen->set_raw(12'000'000, 800, 0, 640, 262, 0, 200);
    m_screen->set_refresh_hz(60);
    m_screen->set_size(640, 400);
    m_screen->set_visarea(0, 640-1, 0, 400-1);
    m_screen->set_raw(14.318181_MHz_XTAL / 2, 912, 0, 640, 262, 0, 400);
    m_screen->set_screen_update(FUNC(qx11_state::screen_update_qx11));

    //m_screen->set_palette(m_palette);  

    // SOUND
    SPEAKER(config, "mono").front_center();
    //SN76489(config,"sn76489",XTAL(14'318'181)/4).add_route(ALL_OUTPUTS, "mono", 0.80);
    SN76489A(config, m_psg, XTAL(3'579'545)).add_route(ALL_OUTPUTS, "mono", 1.0);
    // Flooppy
     // NEC uPD765A FDC (PC-compatible 8272A)
    UPD765A(config, m_fdc, 16'000'000,true, true);           // intrq, drq enabled
    m_fdc->set_rate(250000); // 250 kHz
   
    
    FLOPPY_CONNECTOR(config, m_floppy[0], qx11_floppies, "525dd", floppy_image_device::default_pc_floppy_formats).enable_sound(true);
	FLOPPY_CONNECTOR(config, m_floppy[1], qx11_floppies, "525dd", floppy_image_device::default_pc_floppy_formats).enable_sound(true);
    m_fdc->intrq_wr_callback().set(FUNC(qx11_state::fdc_intrq_w)); /// There is a GAVNIT that may be used for Interrupt handling, but we don't have any documentation about it
    //m_fdc->drq_wr_callback().set_inputline(m_maincpu, INPUT_LINE_HALT).invert(); // drq is active low


    // QX10 Keyboard 
    //EPSON_QX_KEYBOARD_PORT(config, m_epkbd, bus::epson_qx::keyboard::keyboard_devices, "qx10_ascii");
	//m_kbd->txd_handler().set(m_scc, FUNC(upd7201_device::rxa_w));
    // Keyboard
    GENERIC_KEYBOARD(config, m_kbd, 0);
    m_kbd->set_keyboard_callback(FUNC(qx11_state::kbd_put));

    // Real time Clock
    MC146818(config, m_rtc, 32.768_kHz_XTAL);
    m_rtc->set_binary(false);                  // BCD mode (DM=0)
    m_rtc->set_24hrs(true);                  // 24-hour mode (24/12=1)
    //m_rtc->irq().set_inputline(m_maincpu, INPUT_LINE_IRQ0).invert(); 

    // One of the Gate Array variants (not reverse-engineered yet)
    QX11_POSTMUX(config, m_postmux, 0);

  // -------------- CPU stays as you already have it --------------

// --- Minimal internal ISA8 bus to host CGA ---

ISA8(config, m_isabus, 0);
m_isabus->set_memspace(m_maincpu, AS_PROGRAM);
m_isabus->set_iospace(m_maincpu,  AS_IO);

ISA8_SLOT(config, "isa1", 0, m_isabus, pc_isa8_cards, "cga_mc1502", false);
 
} 

/////////////////////// ********** END MACHINE CONFIGURATION ********** ///////////////////

u8 qx11_state::status7e_r()
{
    // Return a stable value; BIOS reads twice and compares.
    // Keep 0xFF unless you later discover bit meanings (DIPs, ready, etc).
    //logerror("IN  7E -> %02X\n", m_status7e);
    post_ready = true;
    return m_status7e;
}

u8 qx11_state::status81_r()
{
    // For bring-up: report bits 7..6 = 10b (0x80).
    // You can add real logic later (e.g., tie to VBLANK or GDC-ready).
    const u8 v = 0x80;
    //logerror("STAT81 -> %02X\n", v);
    return v;
}

void qx11_state::port92_w (u8 data)
{
    // used during POST; unknown purpose
    logerror("STAT92 <- %02X\n", data);
}

void qx11_state::port93_w (u8 data)
{
    // used during POST; unknown purpose
    logerror("STAT93 <- %02X\n", data);
}

u8 qx11_state::port92_r ()
{
    u8 data = 0xAA;
    // used during POST; unknown purpose
    logerror("STAT92 <- %02X\n", data);
    return data;
}

u8 qx11_state::port93_r ()
{
    u8 data = 0x55;
    // used during POST; unknown purpose
    logerror("STAT92 <- %02X\n", data);
    return data;
}

inline bool qx11_state::drive_has_disk(int drv) {
    auto *img = m_floppy[drv]->get_device();
    return img && img->exists();
}

void qx11_state::floppy_motor_w(uint8_t state) // Probably the GAFDDC listening to port 0x0F
{
    u8 drive_index = 0xFF;
    

    // Before accessing the drive the BIOS resets the upd765 and writes to port 0x0F 

    if (state == 0x04) 
        { drive_index = 0;
            m_dir = 0x01;
        } else     // The BIOS write 4 to port 0x0F when selecting drive A
        if (state == 0x08) { 
            drive_index =1;
            m_dir=0x02;
        }       // the BIOS writes 8 to port 0x0F when selecting drive B

    if (state == 0x10) {                         // The BIOS write 0x10 to port 0x0F when the upd765 data Phase finish 
     // 1) Assert Terminal Count to the 765
        m_fdc->tc_line_w(1);

        // 2) (Optional but typical) immediately release it; a short pulse is enough
        // Use a scheduled callback so the edge is visible to the device
        machine().scheduler().synchronize(timer_expired_delegate(
            FUNC(qx11_state::clear_tc), this));
        
        m_dir=0x00; // The BIOS checks this latch on port 0x0D.. if it is 0, it won't read the disk.. If it is 1, i will execture the disk access. (Could be the Disk inserted signal)
    }
    
    
    if (drive_index != 0xFF)     { //Select the appopiate drive

      
        auto *floppy = m_floppy[drive_index]->get_device();
        if (floppy) {
            logerror("Write to Port 0x0F - Value %02X, FLOPPY Drive %d selected\n", state,drive_index);
            m_fdc->set_floppy(floppy);  // Select the Floppy
            floppy->mon_w(0);           // Turn the floopy motor on
            
            
    
            floppy->set_rpm(300); // typical 5.25" RPM
            m_fdc->set_rate(250000); // 250 kHz
            

            
            

        } 
    }

    logerror("Write to port 0x0F - Value  -> %02X\n", state);
    
}

void qx11_state::clear_tc(s32)
{
    m_fdc->tc_line_w(0);
}

u8 qx11_state::p13_in_r()
{

    
    
    logerror("Reading Port 0x0E IN -> %02X\n", m_dir);
    return m_dir;
}

void qx11_state::p13_out_w(u8 data)
{
    m_p13_out = data;
    logerror("Writing to port 0x0E <- %02X\n", data);
}

u8 qx11_state::io_low_r(offs_t port)
{
    //logerror("IN  %02X -> FF (stub)\n", port);
    return 0xFF; // safe default until real devices are wired
}

void qx11_state::io_low_w(offs_t port, u8 data)
{
    //logerror("OUT %02X = %02X\n", port, data);

   
}

u8 qx11_state::crtc_index_r()
{
    //logerror("CRTC IDX -> %02X\n", m_crtc_index);
    return m_crtc_index;
}

void qx11_state::crtc_index_w(u8 data)
{
    m_crtc_index = data & 0x1F; // assume up to 32 regs
    //logerror("CRTC IDX <- %02X\n", m_crtc_index);
}

void qx11_state::status81_w(u8 data)
{
    m_crtc_index = data & 0x1F; // assume up to 32 regs
    //logerror("STAT82 <- %02X\n", m_crtc_index);
}

u8 qx11_state::crtc_data_r()
{
    u8 v = m_crtc_regs[m_crtc_index];
    //logerror("CRTC DAT -> [%02X] = %02X\n", m_crtc_index, v);
    return v;
}

void qx11_state::crtc_data_w(u8 data)
{
    //logerror("CRTC DAT <- [%02X] = %02X\n", m_crtc_index, data);
    m_crtc_regs[m_crtc_index] = data;


}
u8 qx11_state::status0D_r()
{
    
    //logerror("PORT 0D READ -> [%02X] = %02X\n", D_status, D_status);
    return D_status--;
}

void qx11_state::status0D_w(u8 data)
{
    
    //logerror("PORT 0D READ <- [%02X] = %02X\n", D_status, data);
    D_status = data;
}
u8 qx11_state::status0C_r()
{
    u8 v = 0x00;
    //logerror("PORT 0C READ -> [%02X] = %02X\n", v, v);
    return v;
}


//static INPUT_PORTS_START(qx11)
//INPUT_PORTS_END

ROM_START(qx11)
    ROM_REGION(0x10000, "bios", 0)
    //Lower half (F0000–F7FFF)
    ROM_LOAD("MBM27256@DIP28_EPSON_ABACUS_M25141CA.BIN", 0x00000, 0x10000, CRC(b0ac8134) SHA1(737e9ff8bb78161704b463393b69afd3c5b5c007))
    
    ROM_REGION(0x10000, "rom2", 0)
    ROM_LOAD("MBM27256@DIP28_EPSON_ABACUS_M25140CA.BIN", 0x00000, 0x10000, CRC(eb6329ec) SHA1(55d0ec5f6ffa680dc2d50623e8645bb50a6c263b))
    
    ROM_REGION(0x800, "extfont", 0) // 2048 bytes = 256*8
    ROM_LOAD("qx11_font_8x8.bin", 0x000, 0x800, CRC(00000000) SHA1(0000000000000000000000000000000000000000))
ROM_END

COMP(1983, qx11, 0, 0, qx11, qx11, qx11_state, empty_init, "Epson", "QX-11 (skeleton, 512K)", MACHINE_NOT_WORKING)
