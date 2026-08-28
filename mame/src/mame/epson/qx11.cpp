// license:BSD-3-Clause
// Epson QX-11 (skeleton) — 512 KiB max RAM

#include "emu.h"
#include "cpu/i86/i86.h"
#include "machine/ram.h"
#include "gavnit.h"
#include "gavdp.h"
#include "gavnio.h"
#include "sound/sn76496.h"
#include "speaker.h"
#include "machine/mc146818.h"
#include "machine/upd765.h"
#include "bus/epson_qx/keyboard/keyboard.h"
#include "imagedev/floppy.h"
#include "formats/pc_dsk.h"
#include "gafddc.h"
#include "epson_hd.h"


// ICRT Card
#include "epson_icrt.h"

class qx11_state : public driver_device
{
public:
    qx11_state(const machine_config &mconfig, device_type type, const char *tag)
        : driver_device(mconfig, type, tag)
        , m_maincpu(*this, "maincpu")
        , m_ram(*this, "ram")
        , m_gavnit(*this, "gavnit")
        , m_gavnio(*this, "gavnio")
        , m_gavdp(*this,"gavdp")
        , m_psg(*this, "sn76489")
        , m_rtc(*this, "rtc")
        , m_fdc(*this, "upd765")
        , m_epkbd (*this, "m_epkbd")
        , m_gafddc(*this, "gafddc")
        , m_floppy(*this, "upd765:%u", 0U) 
        , m_hd(*this, "epson_hd")

        , m_screen(*this, "screen")
        , m_icrt(*this, "icrt")
        //, m_vram8000(*this, "vram8000")
        //, m_vram9000(*this, "vram9000") 
        //, m_textbuffer(*this, "textbuffer")  
        //, m_epkbd(*this, "m_epkbd")
        //, m_rtc(*this, "rtc")
        //, m_fdc(*this, "upd765")
        //, m_floppy(*this, "upd765:%u", 0U)    
         
  
    {}

    required_device<i8088_cpu_device> m_maincpu;
    required_device<ram_device>       m_ram;
    required_device<epson_gavnit_device> m_gavnit;
    required_device<epson_gavnio_device> m_gavnio;
    required_device<gavdp_device> m_gavdp;
    required_device<sn76489a_device> m_psg;  // 76489 Sound Chip port 0x14
    required_device<mc146818_device> m_rtc;  // Real Time Clock ports 0x10 and 0x11
    required_device<upd765a_device>     m_fdc;
    required_device<bus::epson_qx::keyboard::keyboard_port_device> m_epkbd;
    required_device<epson_gafddc_device> m_gafddc;
    required_device_array<floppy_connector, 2> m_floppy;
    required_device<epson_hd_device> m_hd;
 

    required_device<screen_device>   m_screen;
    optional_device<epson_icrt_device> m_icrt;

   
    void qx11(machine_config &config);
    void mem_map(address_map &map);
    void io_map(address_map &map);
    ioport_constructor device_input_ports() const override;
    virtual void machine_start() override;
    u8 port7e_r();
    int irq_ack(device_t &device, int line); 

    // 48 KiB window: 0x8000 .. 0x8BFFF inclusive
    const offs_t vram_start = 0x80000;
    const offs_t vram_end   = 0x9ffff;//vram_start + epson_gavdp_device::VRAM_BYTES - 1; // 0x8BFFF

   u32 screen_update(screen_device &screen, bitmap_rgb32 &bitmap, const rectangle &cliprect);

    //Temporal Serial
    u8 serial_io7_r();
    void serial_io7_w(u8 data);
    u8 serial_ioF_r();

  
};

u8 qx11_state::serial_io7_r(){
    return 0x60;
}

u8 qx11_state::serial_ioF_r(){
    u8 v = 0;     // what BIOS last wrote
    v = (v & ~0x07) | 0x07;    // force modem inputs present
    return v;
}

void qx11_state::serial_io7_w(u8 data){
    logerror("Serial Port Write: %02X\n", data);
}

u32 qx11_state::screen_update(screen_device &screen, bitmap_rgb32 &bitmap, const rectangle &cliprect)
{
    if (m_icrt->active()) {

        return m_icrt->screen_update(screen, bitmap, cliprect);
    }

    return m_gavdp->screen_update(screen, bitmap, cliprect);
}


void qx11_state::mem_map(address_map &map)
{
    // === RAM: 0x00000–0x7FFFF (512 KiB) ===
    map(0x00000, 0x07ffff).ram();  // Main RAM 512K (base QX11 model came with 128Kb) 

    // ICRT Video RAM Mapping
    // Color (CGA-style) 32K
    map(0xB8000, 0xBFFFF).m(m_icrt, FUNC(epson_icrt_device::vram_map_color));
    // APX-ICRT VM6 exposes the complete 32 KiB framebuffer here.  The four
    // 8 KiB scanline banks begin at B0000, B2000, B4000 and B6000.
    map(0xB0000, 0xB7FFF).m(m_icrt, FUNC(epson_icrt_device::vram_map_mono));


    
    //QX-11 Bios Map
    //map(0xc0000, 0xdffff).rom().region("cgdno",0x0000); // Cartridge Memory Space up to 256KB
    map(0xE0000, 0xEffff).rom().region("msdos", 0x0000); // This is the MSDOS/Command.com Also mirroed to the E0000 space.
    map(0xf0000, 0xfffff).rom().region("bios", 0x0000); // This is the BIOS.. even though the BIOS for QX11 is 32 KB, the BIOS is mirrored on F000 an F80
    //IBM FONT ROM Area
    //map(0xFFA62,0xFFAFF).rom().region("ibm_font", 0x0000);
    
}

void qx11_state::io_map(address_map &map)
{
    //map.global_mask(0xff);
    map.unmap_value_high();
    map(0x00, 0x00).rw(m_gavnit, FUNC(epson_gavnit_device::port0_r),FUNC(epson_gavnit_device::port0_w));
    map(0x01, 0x01).rw(m_gavnit, FUNC(epson_gavnit_device::port1_r),FUNC(epson_gavnit_device::port1_w));
    map(0x04, 0x04).rw(m_gavnit, FUNC(epson_gavnit_device::intmask_lo_r), FUNC(epson_gavnit_device::intmask_lo_w));
    map(0x05, 0x05).rw(m_gavnit, FUNC(epson_gavnit_device::intmask_hi_r), FUNC(epson_gavnit_device::intmask_hi_w));
    
    map(0x07, 0x07).rw(FUNC(qx11_state::serial_io7_r), FUNC(qx11_state::serial_io7_w));

    map(0x0C,0x0C).rw(m_gavnio, FUNC(epson_gavnio_device::data_r),FUNC(epson_gavnio_device::data_w));
    //map(0x0C,0x0C).r(m_gavnio, FUNC(epson_gavnio_device::data_r));
    map(0x0D,0x0D).r(m_gavnio, FUNC(epson_gavnio_device::status_r));
    map(0x0E,0x0E).r(m_gavnio, FUNC(epson_gavnio_device::floppy_status_r));
    map(0x0F,0x0F).w(m_gavnio, FUNC(epson_gavnio_device::floppy_control_w));
    
    map(0x0F,0x0F).r(FUNC(qx11_state::serial_ioF_r));

    map(0x10, 0x10).w(m_rtc, FUNC(mc146818_device::address_w)); // HD146818 RTC index
    map(0x11, 0x11).rw(m_rtc, FUNC(mc146818_device::data_r), FUNC(mc146818_device::data_w)); // HD146818 RTC data
    map(0x12, 0x13).m(m_fdc, FUNC(upd765a_device::map));  // FDC uPD765A MSR(port 12) and FIFO (port 13)
    map(0x14, 0x14).w(m_psg, FUNC(sn76489_device::write));  // SN76489 Sound chip
   
    map(0x7e, 0x7e).r(FUNC(qx11_state::port7e_r));  // DIP switches and other status bits

    // EPSON HD-10 Hard Disk Controller ports
    map(0x80, 0x80).rw(m_hd, FUNC(epson_hd_device::port80_r), FUNC(epson_hd_device::port80_w));
    map(0x81, 0x81).rw(m_hd, FUNC(epson_hd_device::port81_r), FUNC(epson_hd_device::port81_w));
    map(0x82, 0x82).w (m_hd, FUNC(epson_hd_device::port82_w));

    // ICRT Card I/O Mapping
    map(0x03b0, 0x03bf).m(m_icrt, FUNC(epson_icrt_device::io_map_mono));
    map(0x03c0, 0x03cf).m(m_icrt, FUNC(epson_icrt_device::io_map_mono)); // for 3CE/3CF
    map(0x03d0, 0x03df).m(m_icrt, FUNC(epson_icrt_device::io_map_mono));


}


void qx11_state::machine_start()
{
m_gavdp->install_vram_window(m_maincpu->space(AS_PROGRAM), 0x80000);
m_gavdp->install_vram_window(m_maincpu->space(AS_PROGRAM), 0x90000);


        m_rtc->address_w(0x0F);
        m_rtc->data_w(0x80); 

}

static void qx11_floppies(device_slot_interface &device)
{
    // 3.5" double-density 40-track 9-sector drive (360K),
    // which matches the TEAC SMD-125 used in the QX-11.
    device.option_add("35dd", FLOPPY_35_DD);
    device.option_add("525dd", FLOPPY_525_DD);
   
    // Optional: pick a default
    device.set_default_option("35dd");
    // Optional: if you want the media type fixed for this slot:
    // device.set_fixed(true);
}

void qx11_state::qx11(machine_config &config)
{
    I8088(config, m_maincpu, XTAL(14'745'600)/2  ); // 4.9152 MHz
    m_maincpu->set_addrmap(AS_PROGRAM, &qx11_state::mem_map);
    m_maincpu->set_addrmap(AS_IO,      &qx11_state::io_map);
    RAM(config, m_ram);
    m_ram->set_default_size("128K");

    EPSON_GAVNIO(config, m_gavnio, XTAL(14'745'600));
  

    SCREEN(config, m_screen, SCREEN_TYPE_RASTER);
    m_screen->set_raw(14.318181_MHz_XTAL, 912, 0, 640, 262, 0, 400);
    EPSON_GAVDP(config,m_gavdp,0);
    m_gavdp->set_screen(m_screen);
    //m_screen->set_screen_update(m_gavdp,FUNC(gavdp_device::screen_update));

    //m_gavdp->set_geometry(640, 400, 200);
    //m_gavdp->set_column_stride(0x200);
    //m_gavdp->set_bottom_offset(0x100);
    //m_gavdp->set_char_columns(80);
    //m_gavdp->set_screen("gavdp:screen");
    
    EPSON_GAVNIT(config, m_gavnit, XTAL(14'745'600));
    m_gavnit->intr_cb().set_inputline(m_maincpu, INPUT_LINE_IRQ0);
    m_maincpu->set_irq_acknowledge_callback(*this, FUNC(qx11_state::irq_ack));

    EPSON_QX_KEYBOARD_PORT(config, m_epkbd, bus::epson_qx::keyboard::keyboard_devices,"qx10_hasci");
    
   
    m_gavnio->kbd_clk_cb().set(m_epkbd, FUNC(bus::epson_qx::keyboard::keyboard_port_device::clk_w));
    m_gavnio->kbd_rxd_cb().set(m_epkbd, FUNC(bus::epson_qx::keyboard::keyboard_port_device::rxd_w));
   
   // Keyboard IRQ line from GAVNIO into GAVNIT
    
    m_epkbd->txd_handler().set(m_gavnio, FUNC(epson_gavnio_device::kbd_txd_w));
    m_gavnio->irq_to_gavnit().set(m_gavnit, FUNC(epson_gavnit_device::keyboard_irq_w));

    EPSON_GAFDDC(config, m_gafddc, 0);
    m_gavnio->set_gafddc(m_gafddc);

    // SOUND
    SPEAKER(config, "mono").front_center();
    SN76489A(config, m_psg, XTAL(3'579'545)).add_route(ALL_OUTPUTS, "mono", 1.0);
    MC146818(config, m_rtc, 32.768_kHz_XTAL);
    m_rtc->irq().set(m_gavnit, FUNC(epson_gavnit_device::rtc_irq_w));
    
    UPD765A(config, m_fdc, 16'000'000, true, true);
    FLOPPY_CONNECTOR(config, m_floppy[0], qx11_floppies, "525dd", floppy_image_device::default_pc_floppy_formats).enable_sound(true);
    FLOPPY_CONNECTOR(config, m_floppy[1], qx11_floppies, "525dd",  floppy_image_device::default_pc_floppy_formats).enable_sound(true);
  
    m_fdc->intrq_wr_callback().set(m_gavnit, FUNC(epson_gavnit_device::fdc_intrq_w));

    m_gafddc->set_fdc(*m_fdc);
    m_gafddc->set_floppy_tag(0, m_floppy[0]->tag());
    m_gafddc->set_floppy_tag(1, m_floppy[1]->tag());

     // --- ICRT ---
    EPSON_ICRT(config, m_icrt, 0);   // clock is driven internally (6845), 0 is fine

    m_screen->set_screen_update(FUNC(qx11_state::screen_update));

    EPSON_HD(config, "epson_hd", 0);

}

u8 qx11_state::port7e_r()
{
    // Return a stable value; BIOS reads twice and compares.
    
    //post_ready = true;
    
    // --- Monitor latch to 0000:0783 (bits 7..6) ---
    const u8 mon_sel = (ioport("MONITOR")->read() & 0x03) << 6;  // 00,40,80,C0
    
    //u8 mon_byte = read_lowram(0x000783);
    u8 mon_byte=0;
    mon_byte = (mon_byte & 0x3F) | mon_sel;  // keep low 6 bits, set 7..6
    u8 floppy_count = (ioport("DIP5")->read() & 0x01) << 5;
    u8 columns = (ioport("DIP6")->read() & 0x01) << 4;
    u8 dip1 = (ioport("DIP1")->read() & 0x01) << 3;
    u8 dip2 = (ioport("DIP2")->read() & 0x01) << 2;
    u8 dip3 = (ioport("DIP3")->read() & 0x01) << 1;
    u8 dip4 = (ioport("DIP4")->read() & 0x01) << 0;
    u8 v = (mon_sel| floppy_count | columns | dip1 | dip2 | dip3 | dip4);

    //logerror("Status 7E read: %02X (monitor=%02X, floppy_count=%02X, columns=%02X)\n", v, mon_byte, floppy_count, columns);
    
    logerror("Status 7E read: %02X\n", ~v );
    return ~v;
    //return 0b01110000;
    //return 0b01110111;

    //return 0b10001111; 
    //return 0b01110001;
    
}

int qx11_state::irq_ack(device_t &device, int line)
{
    return m_gavnit->inta_cb(line);   // returns 0x71 for timer, 0x75 for kbd, etc.
}

static INPUT_PORTS_START(qx11)

// SW1..SW4 (reserved / always ON per docs)

    PORT_START("DIP1")
    PORT_DIPNAME(0x01, 0x00, "DIP SW1: Unknown") // 0=2 drives, 1=1 drive
        PORT_DIPSETTING(0x00, "ON")
        PORT_DIPSETTING(0x01, "OFF")

    PORT_START("DIP2")
    PORT_DIPNAME(0x01, 0x00, "DIP SW2: Unknown") // 0=2 drives, 1=1 drive
        PORT_DIPSETTING(0x00, "ON")
        PORT_DIPSETTING(0x01, "OFF")

    PORT_START("DIP3")
    PORT_DIPNAME(0x01, 0x00, "DIP SW3: Unknown") // 0=2 drives, 1=1 drive
        PORT_DIPSETTING(0x00, "ON")
        PORT_DIPSETTING(0x01, "OFF")

    PORT_START("DIP4")
    PORT_DIPNAME(0x01, 0x00, "DIP SW4: Unknown") // 0=2 drives, 1=1 drive
        PORT_DIPSETTING(0x00, "ON")
        PORT_DIPSETTING(0x01, "OFF")

    // PORT_START("DIP1_4")
    // PORT_DIPNAME(0x0F, 0x0F, "DIP SW1..SW4 (reserved)") PORT_DIPSETTING(0x0F, "ON (factory)")

    // SW5 — internal floppies
    PORT_START("DIP5")
    PORT_DIPNAME(0x01, 0x00, "DIP SW5: Internal Floppies") // 0=2 drives, 1=1 drive
        PORT_DIPSETTING(0x00, "2 Drives")
        PORT_DIPSETTING(0x01, "1 Drive")

    // SW6 — default text columns (informational; BIOS may still set mode)
    PORT_START("DIP6")
    PORT_DIPNAME(0x01, 0x00, "DIP SW6: Default Columns")
        PORT_DIPSETTING(0x00, "80 Columns (OFF)")
        PORT_DIPSETTING(0x01, "40 Columns (ON)")

    // SW7+SW8 — monitor type (combine as an enum that maps to bits 7..6 of [0783])
    PORT_START("MONITOR")  // yields 0..3; we'll shift <<6 into [0783]
    PORT_CONFNAME(0x03, 0x00, "Monitor Type (SW7+SW8)")
        PORT_CONFSETTING(0x00, "NTSC Color (Positive Sync)   [7=OFF,8=OFF]")
        PORT_CONFSETTING(0x01, "NTSC Color (Negative Sync)   [7=ON,  8=OFF]")
        PORT_CONFSETTING(0x02, "EPSON High-Resolution        [7=OFF,8=ON ]")
        PORT_CONFSETTING(0x03, "PAL / SECAM                  [7=ON,  8=ON ]")

INPUT_PORTS_END

ioport_constructor qx11_state::device_input_ports() const
{
    return INPUT_PORTS_NAME(qx11);
}

ROM_START(qx11)
    ROM_REGION(0x10000, "bios", 0)
    //Lower half (F0000–F7FFF)
    ROM_LOAD("MBM27256@DIP28_EPSON_ABACUS_M25141CA.BIN", 0x00000, 0x10000, CRC(b0ac8134) SHA1(737e9ff8bb78161704b463393b69afd3c5b5c007))
    
    ROM_REGION(0x10000, "msdos", 0)
    ROM_LOAD("MBM27256@DIP28_EPSON_ABACUS_M25140CA.BIN", 0x00000, 0x10000, CRC(eb6329ec) SHA1(55d0ec5f6ffa680dc2d50623e8645bb50a6c263b))

    ROM_REGION(0x20000, "cgdno", 0)
    ROM_LOAD("elks7.bin", 0x00000, 0x20000, CRC(0) SHA1(0))

    ROM_REGION(0x800, "ibm_font", 0)
    ROM_LOAD("STANDARD.FNT", 0x0000, 0x0800, CRC(0) SHA1())
    

    ROM_END

COMP(1983, qx11, 0, 0, qx11, qx11, qx11_state, empty_init, "Epson", "QX-11 (skeleton, 512K)", MACHINE_NOT_WORKING)
