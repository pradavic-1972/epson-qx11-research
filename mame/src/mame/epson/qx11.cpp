// license:BSD-3-Clause
// Epson QX-11 (skeleton) — 512 KiB max RAM

#include "emu.h"
#include "cpu/i86/i86.h"
#include "machine/ram.h"

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

class qx11_state : public driver_device
{
public:
    qx11_state(const machine_config &mconfig, device_type type, const char *tag)
        : driver_device(mconfig, type, tag)
        , m_maincpu(*this, "maincpu")
        , m_ram(*this, "ram")
        , m_pic_s(*this, "pic8259")
        , m_qx11screen(*this, "screen")
        , m_vram8000(*this, "vram8000")
        , m_vram9000(*this, "vram9000") 
        , m_textbuffer(*this, "textbuffer")  
        , m_kbd(*this, "kbd")
        , m_rtc(*this, "rtc")
        , m_fdc(*this, "upd765")
        , m_floppy(*this, "upd765:%u", 0U)
        , m_postmux(*this, "postmux")    
        , m_psg(*this, "sn76489")  
      

        
  
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


    protected:
    // ✅ Declare these exactly like this
    virtual void machine_start() override;
    virtual void machine_reset() override;
    u32 screen_update_qx11(screen_device &screen, bitmap_rgb32 &bmp, const rectangle &clip);

private:
    void mem_map(address_map &map);
    void io_map(address_map &map);
    
    void pallete_init(palette_device &palette) const;
 
    // TAP INT 10h 
    // qx11.cpp (inside qx11_state private:)
    memory_passthrough_handler m_int10_tap{};

    // INT 10h taps
    memory_passthrough_handler m_int10_vec_tap{};
    memory_passthrough_handler m_int10_entry_tap{};

  
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
    required_device<screen_device>   m_qx11screen;

    required_device<qx11_postmux_device> m_postmux;  // add to your state

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

void dma_p81_w(u8 data);
u8 dma_p81_r();

bool cmos_initialized = false;


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
    logerror("FDC: INTRQ %d\n", state);
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

u32 qx11_state::screen_update_qx11(screen_device &screen, bitmap_rgb32 &bmp, const rectangle &clip)
{
    // ---------- constants ----------
    constexpr u32 COL_STRIDE      = 0x0200;   // byte-columns are 0x200 apart

    // Graphics plane (keep your working setup)
    constexpr u32 GFX_BASE_TOP    = 0x0000;   // ES=0x8000
    constexpr u32 GFX_BASE_BOTTOM = 0x0100;   // ES=0x8010 (extra base for y>=200)
    constexpr int GFX_COLS_DRAW   = 80;       // full width (keep as-is)
    constexpr int BOTTOM_COL_BIAS = 0;        // 0..3 if your bottom half needs nudging

    // Text plane — TOP HALF ONLY (640x200), with software scroll origin
    constexpr u32 TXT_BASE_TOP    = 0x00100;  // ES=0x9010 (+0x100)
    constexpr int TXT_COLS_DRAW   = 80;       // full width

    // Colors
    const u32 BG = rgb_t(0xFF,0x00,0x00,0x00);
    const u32 FG = rgb_t(0xFF,0x00,0xFF,0x00);

    bmp.fill(BG, clip);
    rasterize_textbuffer_to_bitmap(); // keep your attribute flags

    const u32 bytes8000 = m_vram8000.bytes();
    const u32 bytes9000 = m_vram9000.bytes();

    // ---------- PASS A: GRAPHICS (unchanged) ----------
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

    // ---------- PASS B: TEXT (TOP 200 lines only) with software origin ----------
    // We keep a tiny per-frame signature of each 8-pixel text band (25 bands).
    // If the new frame looks like the previous frame shifted by +1 band, we advance the origin (scroll up 8px).
    {
        // Persistent state across frames
        static bool  s_init = false;
        static int   s_txt_start_band = 0;      // 0..24 (virtual origin band)
        static u16   s_prev_sig[25] = {0};      // previous band signatures

        // Build current signatures
        u16 cur_sig[25] = {0};
        int nonzero_total = 0;

        for (int band = 0; band < 25; ++band) {
            u16 sig = 0;
            for (int sub = 0; sub < 8; ++sub) {
                const u32 line_base = TXT_BASE_TOP + u32(band)*0x08 + u32(sub);
                // sample a handful of spread columns to make a quick signature
                for (int col : { 0, 5, 10, 20, 30, 40, 60, 79 }) {
                    const u32 off = line_base + u32(col) * COL_STRIDE;
                    if (off < bytes9000) sig = (sig * 131) ^ m_vram9000[off];
                }
            }
            cur_sig[band] = sig;
            if (sig) ++nonzero_total;
        }

        // Detect CLS (clear) → reset origin
        if (nonzero_total == 0) {
            s_txt_start_band = 0;
            // fall through (we still render; it'll be empty until text arrives)
        } else if (s_init) {
            // Check if current looks like previous shifted by +1 band
            int matches_plus1 = 0, matches_0 = 0;
            for (int i = 0; i < 25; ++i) {
                if (cur_sig[i] == s_prev_sig[i])                 ++matches_0;
                if (cur_sig[i] == s_prev_sig[(i + 1) % 25])      ++matches_plus1;
            }
            // Conservative rule: require more agreement on +1 than 0 to advance
            if (matches_plus1 > matches_0 + 4) {                 // margin to avoid jitter
                s_txt_start_band = (s_txt_start_band + 1) % 25;  // scroll up by one 8px row
            }
        }
        // Save signatures for next frame
        for (int i = 0; i < 25; ++i) s_prev_sig[i] = cur_sig[i];
        s_init = true;

        // Now render the text page at y=0..199 using the virtual origin
        const int y_min = std::max(clip.min_y, 0);
        const int y_max = std::min(clip.max_y, 199);

        for (int y = y_min; y <= y_max; ++y) {
            u32 *dst = &bmp.pix(y, clip.min_x);

            const int rel_y = y;                  // top field only
            const int row8  = rel_y >> 3;         // 0..24 visible rows
            const int sub   = rel_y & 7;          // 0..7

            const int vrow8 = (row8 + s_txt_start_band) % 25;  // apply software scroll origin
            const u32 base  = TXT_BASE_TOP + u32(vrow8) * 0x08 + u32(sub);

            for (int col = 0; col < TXT_COLS_DRAW; ++col) {
                const u32 off = base + u32(col) * COL_STRIDE;
                if (off >= bytes9000) break;

                const u8 b = m_vram9000[off];
                const int x_start = (col << 3);

                for (int bit = 0; bit < 8; ++bit) {
                    const int x = x_start + bit;
                    if (x < clip.min_x || x > clip.max_x) continue;

                    // Attribute lookup from your logical 25×80 buffer at the *displayed* row
                    const int cell_idx = row8 * 80 + col;    // row8 is the on-screen row index (0..24)
                    const bool inv     = (m_textbuffer[cell_idx * 2 + 0] == 'p');

                    const bool on = ((b >> (7 - bit)) & 1) ^ inv;
                    if (on) dst[x - clip.min_x] = FG;        // overlay over graphics
                }
            }
        }
    }

    return 0;
}


//////////////////// ********** END SCREEN ********** ///////////////////

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
   
    if (!m_qx11screen) fatalerror("Screen device not found\n");

    if (!m_maincpu) fatalerror("CPU device not found\n");
   

    address_space &io = m_maincpu->space(AS_IO); // <-- reference, do NOT copy    

    // Add any noisy ports you want to ignore here
    static const u16 kIgnore[] = { /* add more if needed */ };

    auto ignore = [](u16 port)->bool {
        for (u16 p : kIgnore) if (p == port) return true;
        return false;
    };

     m_io_tap = io.install_readwrite_tap(
        0x0012, 0x13, "io_sniffer",
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
     
}

void qx11_state::machine_reset()
{
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


    
    map(0x0A0000, 0x0CFFFF).ram();

       // QX-11 Temporary framebuffer 
    map(0x080000, 0x08FFFF).ram().share("vram8000");  // Mapped to graphic VRAM native video mode  
    map(0x090000, 0x09FFFF).ram().share("vram9000");  // Mapped to Text (character drawing) native Video Mode
    map(0x00b04,0x01A9f).ram().share("textbuffer");   // This are is some kind of screen buffer.. It gets erased when issuing a CLS
    
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
    map(0x81, 0x81).rw(m_postmux, FUNC(qx11_postmux_device::port81_r),
                              FUNC(qx11_postmux_device::port81_w));
    map(0x82, 0x82).w (m_postmux, FUNC(qx11_postmux_device::port82_w));
    map(0x92, 0x92).rw(FUNC(qx11_state::port92_r),  FUNC(qx11_state::port92_w));
    map(0x93, 0x93).rw(FUNC(qx11_state::port93_r),  FUNC(qx11_state::port93_w));

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

void qx11_state::kbd_put(u8 ascii)
{
 // Minimal: map LF->CR for COMMAND.COM
    if (ascii == 0x0A) ascii = 0x0D;
    //printf("key: %04X",ascii);
    kbd_push_ascii(ascii, 0); // fill real scancode later if needed
}

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
    SCREEN(config, m_qx11screen, SCREEN_TYPE_RASTER);

    //m_qx11screen->set_raw(12'000'000, 800, 0, 640, 262, 0, 200);
    m_qx11screen->set_refresh_hz(60);
    m_qx11screen->set_size(640, 400);
    m_qx11screen->set_visarea(0, 640-1, 0, 400-1);
    m_qx11screen->set_screen_update(FUNC(qx11_state::screen_update_qx11));
    //m_qx11screen->set_palette(m_palette);  

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

 
} 

/////////////////////// ********** END MACHINE CONFIGURATION ********** ///////////////////

u8 qx11_state::status7e_r()
{
    // Return a stable value; BIOS reads twice and compares.
    // Keep 0xFF unless you later discover bit meanings (DIPs, ready, etc).
    //logerror("IN  7E -> %02X\n", m_status7e);
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
            logerror("Write to Port 0xF0 - Value %02X, FLOPPY Drive %d selected\n", state,drive_index);
            m_fdc->set_floppy(floppy);  // Select the Floppy
            floppy->mon_w(0);           // Turn the floopy motor on

            
            
            floppy->set_rpm(300); // typical 5.25" RPM
            m_fdc->set_rate(250000); // 250 kHz

            
            

        } 
    }

    logerror("Write to port 0xF0 - Value  -> %02X\n", state);
    
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
    
ROM_END

COMP(1983, qx11, 0, 0, qx11, qx11, qx11_state, empty_init, "Epson", "QX-11 (skeleton, 512K)", MACHINE_NOT_WORKING)
