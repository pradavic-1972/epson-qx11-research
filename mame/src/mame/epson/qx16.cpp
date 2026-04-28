// license:BSD-3-Clause
// Epson QX-16 (8088 + µPD7220 GDC) — WIP bring-up driver.

#include "emu.h"

#include "cpu/i86/i86.h"            // i8088_cpu_device
#include "machine/ram.h"

//#include "video/upd7220.h"

#include "machine/am9517a.h"
#include "machine/pic8259.h"
#include "machine/pit8253.h"
#include "bus/rs232/rs232.h"
#include "bus/epson_qx/keyboard/keyboard.h"
#include "emupal.h"
#include "screen.h"

#include "machine/i8255.h"
#include "machine/output_latch.h"
#include "machine/z80sio.h"
#include "machine/mc146818.h"

#include "sound/spkrdev.h"
#include "speaker.h"
#include "machine/upd765.h"
#include "imagedev/floppy.h"
#include "formats/ipf_dsk.h"
#include "formats/pc_dsk.h"


// ICRT Card
#include "epson_icrt.h"


#include <array>
#include <algorithm>                // for std::fill_n

// ===== VRAM placement =====
// Default to 0x8000 based on your trace; switch to 0x80000 if needed.
static constexpr u32 VRAM_BASE = 0x8000;   // try 0x8000 first
// static constexpr u32 VRAM_BASE = 0x80000; // alt: 0x80000
static constexpr u32 VRAM_SIZE = 0x20000;    // 64 KiB window

class qx16_raw_format : public floppy_image_format_t
{
public:
	qx16_raw_format() = default;

	virtual int identify(util::random_read &io, uint32_t form_factor, const std::vector<uint32_t> &variants) const override
	{
		if ((form_factor != floppy_image::FF_UNKNOWN) && (form_factor != floppy_image::FF_525))
			return 0;

		uint64_t size;
		if (io.length(size))
			return 0;

		for (auto const &format : s_formats)
		{
			if (size == uint64_t(format.sector_count * format.logical_tracks * format.head_count * format.sector_size))
				return FIFID_SIZE;
		}

		return 0;
	}

	virtual bool load(util::random_read &io, uint32_t form_factor, const std::vector<uint32_t> &variants, floppy_image &image) const override
	{
		format const *selected = nullptr;
		uint64_t size;
		if (io.length(size))
			return false;

		for (auto const &candidate : s_formats)
		{
			uint64_t const expected_size = uint64_t(candidate.sector_count * candidate.logical_tracks * candidate.head_count * candidate.sector_size);
			if (size == expected_size)
			{
				selected = &candidate;
				break;
			}
		}

		if (!selected)
			return false;

		int img_tracks, img_heads;
		image.get_maximal_geometry(img_tracks, img_heads);
		if ((selected->physical_tracks > img_tracks) || (selected->head_count > img_heads))
			return false;

		auto const [err, image_data, actual] = read_at(io, 0, size);
		if (err || (actual != size))
			return false;

		desc_pc_sector sectors[16] = {};
		int const size_code = size_to_code(selected->sector_size);
		int const cell_count = 200000000 / selected->cell_size;
		int const track_size = selected->sector_count * selected->sector_size;

		for (int physical_track = 0; physical_track < selected->physical_tracks; physical_track++)
		{
			int const logical_track = physical_track / 2;

			for (int head = 0; head < selected->head_count; head++)
			{
				uint8_t *const track_data = image_data.get() + ((logical_track * selected->head_count + head) * track_size);
				for (int sector = 0; sector < selected->sector_count; sector++)
				{
					sectors[sector].track = logical_track;
					sectors[sector].head = head;
					sectors[sector].sector = selected->sector_base_id + sector;
					sectors[sector].size = size_code;
					sectors[sector].actual_size = selected->sector_size;
					sectors[sector].data = track_data + (sector * selected->sector_size);
					sectors[sector].deleted = false;
					sectors[sector].bad_data_crc = false;
					sectors[sector].bad_addr_crc = false;
				}

				build_pc_track_mfm(
						physical_track,
						head,
						image,
						cell_count,
						selected->sector_count,
						sectors,
						selected->gap_3,
						selected->gap_4a,
						selected->gap_1,
						selected->gap_2);
			}
		}

		image.set_form_variant(floppy_image::FF_525, selected->variant);
		return true;
	}

	virtual bool save(util::random_read_write &io, const std::vector<uint32_t> &variants, const floppy_image &image) const override
	{
		format const *selected = nullptr;

		for (auto const &candidate : s_formats)
		{
			auto const bitstream = generate_bitstream_from_track(0, 0, candidate.cell_size, image);
			auto const sectors = extract_sectors_from_bitstream_mfm_pc(bitstream);
			bool match = true;

			for (int sector = 0; sector < candidate.sector_count; sector++)
			{
				int const sector_id = candidate.sector_base_id + sector;
				if ((sector_id >= int(sectors.size())) || (sectors[sector_id].size() != size_t(candidate.sector_size)))
				{
					match = false;
					break;
				}
			}

			if (match)
			{
				selected = &candidate;
				break;
			}
		}

		if (!selected)
			return false;

		std::vector<uint8_t> raw_image(selected->sector_count * selected->logical_tracks * selected->head_count * selected->sector_size, 0x00);
		int const track_size = selected->sector_count * selected->sector_size;

		for (int logical_track = 0; logical_track < selected->logical_tracks; logical_track++)
		{
			int const physical_track = logical_track * 2;

			for (int head = 0; head < selected->head_count; head++)
			{
				auto const bitstream = generate_bitstream_from_track(physical_track, head, selected->cell_size, image);
				auto const sectors = extract_sectors_from_bitstream_mfm_pc(bitstream);
				uint8_t *const track_data = raw_image.data() + ((logical_track * selected->head_count + head) * track_size);

				for (int sector = 0; sector < selected->sector_count; sector++)
				{
					int const sector_id = selected->sector_base_id + sector;
					if ((sector_id >= int(sectors.size())) || (sectors[sector_id].size() != size_t(selected->sector_size)))
						return false;

					std::copy(sectors[sector_id].begin(), sectors[sector_id].end(), track_data + (sector * selected->sector_size));
				}
			}
		}

		auto const [err, actual] = write_at(io, 0, raw_image.data(), raw_image.size());
		return !err && (actual == raw_image.size());
	}

	virtual bool supports_save() const noexcept override
	{
		return true;
	}

	virtual const char *name() const noexcept override
	{
		return "qx16raw";
	}

	virtual const char *description() const noexcept override
	{
		return "Epson QX-16 40-track compatibility floppy image";
	}

	virtual const char *extensions() const noexcept override
	{
		return "img,ima,360";
	}

private:
	struct format
	{
		uint32_t variant;
		int cell_size;
		int sector_count;
		int logical_tracks;
		int physical_tracks;
		int head_count;
		int sector_size;
		int sector_base_id;
		int gap_4a;
		int gap_1;
		int gap_2;
		int gap_3;
	};

	static int size_to_code(int sector_size)
	{
		int code = 0;
		for (int size = 128; size < sector_size; size <<= 1)
			code++;
		return code;
	}

	static constexpr format s_formats[] = {
		{ floppy_image::DSDD, 2000, 8, 40, 80, 2, 512, 1, 80, 50, 22, 80 },
		{ floppy_image::DSDD, 2000, 9, 40, 80, 2, 512, 1, 80, 50, 22, 80 }
	};
};

static const qx16_raw_format FLOPPY_QX16_RAW_FORMAT;

class qx16_525_qd_double_step_device : public floppy_525_qd
{
public:
	qx16_525_qd_double_step_device(const machine_config &mconfig, const char *tag, device_t *owner, uint32_t clock)
		: floppy_525_qd(mconfig, tag, owner, clock)
	{
	}

	void set_step_mode(bool is_96tpi, bool double_step_compat)
	{
		if ((m_is_96tpi != is_96tpi) || (m_double_step_compat != double_step_compat))
		{
			logerror("%s: step mode update PC1=%d (%s), double-step=%d\n",
				tag(), is_96tpi ? 1 : 0, is_96tpi ? "96TPI" : "48TPI", double_step_compat ? 1 : 0);
		}

		m_is_96tpi = is_96tpi;
		m_double_step_compat = double_step_compat;
	}

	virtual void stp_w(int state) override
	{
		if (m_stp == state)
			return;

		cache_clear();
		m_stp = state;
		if (m_stp == 0)
		{
			int const ocyl = m_cyl;
			int const steps = m_double_step_compat ? 2 : 1;
			for (int step = 0; step < steps; step++)
			{
				if (m_dir)
				{
					if (m_cyl)
						m_cyl--;
				}
				else
				{
					if (m_cyl < (m_tracks - 1))
						m_cyl++;
				}
			}

			logerror("%s: STEP dir=%s PC1=%d (%s) double-step=%d cyl %d -> %d\n",
				tag(),
				m_dir ? "in" : "out",
				m_is_96tpi ? 1 : 0,
				m_is_96tpi ? "96TPI" : "48TPI",
				m_double_step_compat ? 1 : 0,
				ocyl,
				m_cyl);

			if (ocyl != m_cyl)
			{
				track_changed();
			}

			if (exists() && !m_dskchg_writable && !m_dskchg)
				m_dskchg = 1;
		}

		m_subcyl = 0;
	}

private:
	bool m_is_96tpi = false;
	bool m_double_step_compat = false;
};

DEFINE_DEVICE_TYPE_PRIVATE(QX16_FLOPPY_525_QD_DS, floppy_525_qd, qx16_525_qd_double_step_device, "qx16_floppy_525_qd_ds", "Epson QX-16 5.25\" quad density floppy drive (double step)")

namespace {

#define MAIN_CLK    15974400

class qx16_state : public driver_device
{
public:
    qx16_state(const machine_config &mconfig, device_type type, const char *tag)
        : driver_device(mconfig, type, tag)
        , m_cpu(*this, "maincpu")
        , m_ram(*this, RAM_TAG)
        , m_dma1(*this, "dma8237_1")
        , m_dma2(*this, "dma8237_2")
        , m_pic_m(*this, "pic8259_master")
		, m_pic_s(*this, "pic8259_slave")
        , m_pit1(*this, "pit8253_1")
        , m_pit2(*this, "pit8253_2")
        , m_ppi(*this, "i8255")
        , m_scc(*this, "upd7201")
        , m_screen(*this, "screen")
        , m_icrt(*this, "icrt")   
        
        , m_palette(*this, "palette")
      //  , m_char_rom(*this, "chargen")
        , m_rtc(*this, "rtc")
        , m_kbd(*this, "kbd")
        , m_speaker(*this, "speaker")
        , m_fdc(*this, "upd765")
        , m_floppy(*this, "upd765:%u", 0U)
        
        , m_vram_bank(0)
        
    {}

    void qx16(machine_config &config);
	static void floppy_formats(format_registration &fr);

protected:
    virtual void machine_start() override
    {
      //m_fdc->set_floppy(m_floppy[0]->get_device());
      address_space &cpu_io = m_cpu->space(AS_IO);
    // cpu_io.write_byte(0x03, 0x32);
    // cpu_io.write_byte(0x00, 0x00);
    // cpu_io.write_byte(0x00, 0x01);
    // cpu_io.write_byte(0x07, 0x36);
    // cpu_io.write_byte(0x04, 0x00);
    // cpu_io.write_byte(0x04, 0x08);
    // cpu_io.write_byte(0x07, 0x76);
    // cpu_io.write_byte(0x05, 0x80);
    // cpu_io.write_byte(0x05, 0x06);
    // cpu_io.write_byte(0x07, 0xB6);
    // cpu_io.write_byte(0x06, 0xD4);
    // cpu_io.write_byte(0x06, 0x00);

    // END Timers initialization based on IPL sequence
      for (auto &fdd : m_floppy)
      {
        if (floppy_image_device *const floppy = fdd->get_device(); floppy)
        {
          floppy->setup_load_cb(floppy_image_device::load_cb(&qx16_state::floppy_load_cb, this));
          floppy->setup_unload_cb(floppy_image_device::unload_cb(&qx16_state::floppy_unload_cb, this));
          floppy->setup_ready_cb(floppy_image_device::ready_cb(&qx16_state::floppy_ready_cb, this));
        }
      }
      save_item(NAME(m_counter));
      save_item(NAME(m_motor_clk));
    }

     virtual void machine_reset() override;

private:
    void prog_map(address_map &map);
    void io_map(address_map &map);
   
    u8  io_fallback_r(offs_t offset);
    void io_fallback_w(offs_t offset, u8 data);

    u32 screen_update(screen_device &screen, bitmap_rgb32 &bitmap, const rectangle &cliprect);
    //UPD7220_DISPLAY_PIXELS_MEMBER( hgdc_display_pixels );
	//UPD7220_DRAW_TEXT_LINE_MEMBER( hgdc_draw_text );


    required_device<i8088_cpu_device>  m_cpu;     // corrected type
    required_device<ram_device>        m_ram; 
    required_device<am9517a_device> m_dma1;
	required_device<am9517a_device> m_dma2;
    required_device<pic8259_device> m_pic_m;
	required_device<pic8259_device> m_pic_s;
    required_device<pit8253_device> m_pit1;
    required_device<pit8253_device> m_pit2;
    required_device<i8255_device> m_ppi;
    required_device<upd7201_device> m_scc;
    required_device<screen_device>   m_screen;
    optional_device<epson_icrt_device> m_icrt;
    required_device<mc146818_device> m_rtc;
    required_device<bus::epson_qx::keyboard::keyboard_port_device> m_kbd;
    required_device<speaker_sound_device>   m_speaker;
    required_device<upd765a_device> m_fdc;
    required_device_array<floppy_connector, 2> m_floppy;
    
    optional_device<palette_device> m_palette;
    std::unique_ptr<u16[]> m_vram; // 16-bit words; 16 px/word
    std::unique_ptr<uint16_t[]> m_video_ram;
    uint8_t m_vram_bank;
    //required_region_ptr<uint8_t> m_char_rom;
    
    

    u8 dip_switches_r();
    uint8_t get_slave_ack(offs_t offset);
    u8 mapping_register_r();
    void keyboard_clk(int state);
	void keyboard_irq(int state);
    void speaker_freq(int state);
	void speaker_duration(int state);
    void update_speaker();
    void qx16_18_w(uint8_t data);
    void ppi_portc_w(uint8_t data);
    uint8_t fdc_msr_r();
    uint8_t fdc_fifo_r();
    void fdc_fifo_w(uint8_t data);
    void fdc_intrq_w(int state);
    void fdc_us_w(uint8_t data);
    void log_floppy_state(char const *context, int drive = -1);
    bool floppy_ready_asserted(floppy_image_device *floppy) const;
    void log_fdc_command_start(uint8_t data);
    void log_fdc_command_complete();
    int fdc_command_expected_length(uint8_t command) const;
    char const *fdc_command_name(uint8_t command) const;
    int fdc_command_drive() const;
    void reset_fdc_command_tracking();
    void floppy_load_cb(floppy_image_device *floppy);
    void floppy_unload_cb(floppy_image_device *floppy);
    void floppy_ready_cb(floppy_image_device *floppy, int state);
    void set_fdd_tpi_mode(bool is_96tpi);
    void update_floppy_step_mode();
    void update_fdd_motor(uint8_t state);
    void fdd_motor_w(uint8_t data);
    void sqw_out(uint8_t state);
    uint8_t qx10_30_r();
    void tc_w(int state);
    void dma_hrq_changed(int state);
    void mfdc_drq(bool state);
    void qx16_28_w (uint8_t data);
    uint8_t qx16_1c_r();
    void qx16_1c_w(uint8_t data);
    void upd7220_map(address_map &map);
    uint16_t vram_r(offs_t offset);
    void vram_w(offs_t offset, uint16_t data, uint16_t mem_mask);
    void qx16_palette(palette_device &palette) const;

    int m_spkr_enable = 0;
	int m_spkr_freq = 0;
    int m_pit1_out0 = 0;
    bool m_fdc_irq = false;
    //bool mfdc_drq = false;
    uint16_t m_counter = 0;
    uint8_t m_motor_clk = 0;
    int m_fdcint = 0;
    uint8_t m_ipl = 1; //ipl disabled for 8088
    uint8_t active_cpu = 1; // 1 = 8088 Enabled, 0 = Z80 enabled
    uint8_t m_color_mode = 0;
    uint8_t m_zoom = 0;
    uint8_t m_mem_group = 0;
    uint8_t m_ppi_portc = 0x00;
    bool m_fdd_96tpi = false;
    bool m_media_48tpi_compat = true;
    bool m_fdd_double_step = false;
    int m_fdc_selected_drive = -1;
    std::array<uint8_t, 16> m_fdc_cmd_bytes = {};
    int m_fdc_cmd_count = 0;
    int m_fdc_cmd_expected = 0;
    uint8_t m_last_fdc_cmd = 0x00;
    uint32_t m_dma_read_count = 0;
    uint32_t m_dma_write_count = 0;
};

void qx16_state::machine_reset()
{
    m_dma1->dreq0_w(1);
	m_dma1->dreq1_w(1);

	m_spkr_enable = 0;
	m_pit1_out0 = 1;
	m_ppi_portc = 0x00;
	m_fdd_96tpi = false;
	m_media_48tpi_compat = true;
	m_fdd_double_step = false;
	m_fdc_selected_drive = -1;
	m_counter = 0;
	m_motor_clk = 0;
	reset_fdc_command_tracking();
	update_floppy_step_mode();
    
}

// ---------------- Program map ----------------
void qx16_state::prog_map(address_map &map)
{
    map(0x00000, 0x07ffff).ram();  // Main RAM 512K (base QX11 model cam with 128Kb)
    
    map(0xB8000, 0xBFFFF).m(m_icrt, FUNC(epson_icrt_device::vram_map_color));
    // Mono (MDA-style) at least 4K; many adapters mirror more. Start with 4K.
    map(0xB0000, 0xB7FFF).m(m_icrt, FUNC(epson_icrt_device::vram_map_mono));

    map(0xf0000, 0xfffff).rom().region("bios", 0x0000);
}

// ---------------- I/O map ----------------
u8 qx16_state::io_fallback_r(offs_t offset)
{
    logerror("I/O  read  @%04X (unmapped)\n", u16(offset));
    return 0xff;
}
void qx16_state::io_fallback_w(offs_t offset, u8 data)
{
    logerror("I/O  write @%04X = %02X (unmapped)\n", u16(offset), data);
}

void qx16_state::io_map(address_map &map)
{
    map.unmap_value_high();
    map(0x0000, 0xffff).rw(FUNC(qx16_state::io_fallback_r), FUNC(qx16_state::io_fallback_w));
    map(0x00, 0x03).rw(m_pit1, FUNC(pit8253_device::read), FUNC(pit8253_device::write));
	map(0x04, 0x07).rw(m_pit2, FUNC(pit8253_device::read), FUNC(pit8253_device::write));
    map(0x08, 0x09).rw(m_pic_m, FUNC(pic8259_device::read), FUNC(pic8259_device::write));
	map(0x0c, 0x0d).rw(m_pic_s, FUNC(pic8259_device::read), FUNC(pic8259_device::write));
    map(0x10, 0x13).rw(m_scc, FUNC(upd7201_device::cd_ba_r), FUNC(upd7201_device::cd_ba_w));
    map(0x14, 0x17).rw(m_ppi, FUNC(i8255_device::read), FUNC(i8255_device::write));
    //map(0x18, 0x1b).portr("DSW").w(FUNC(qx16_state::qx16_18_w));
    map(0x18,0x18).r(FUNC(qx16_state::dip_switches_r)); // DIP_SWITCHES_READ
    map(0x18, 0x1b).w(FUNC(qx16_state::qx16_18_w));
    map(0x1c, 0x1c).rw(FUNC(qx16_state::qx16_1c_r), FUNC(qx16_state::qx16_1c_w));
    map(0x24, 0x24).rw(FUNC(qx16_state::qx16_1c_r), FUNC(qx16_state::qx16_1c_w));
    map(0x28, 0x28).w(FUNC(qx16_state::qx16_28_w));
    map(0x2c, 0x2c).portr("CONFIG");
    map(0x30, 0x33).rw(FUNC(qx16_state::qx10_30_r), FUNC(qx16_state::fdd_motor_w));
    map(0x34, 0x34).r(FUNC(qx16_state::fdc_msr_r));
    map(0x35, 0x35).rw(FUNC(qx16_state::fdc_fifo_r), FUNC(qx16_state::fdc_fifo_w));
    //map(0x38, 0x39).rw(m_hgdc, FUNC(upd7220_device::read), FUNC(upd7220_device::write));
    map(0x3c, 0x3c).rw(m_rtc, FUNC(mc146818_device::data_r), FUNC(mc146818_device::data_w));
    map(0x3d, 0x3d).w(m_rtc, FUNC(mc146818_device::address_w));
    map(0x40, 0x4f).rw(m_dma1, FUNC(am9517a_device::read), FUNC(am9517a_device::write));
	map(0x50, 0x5f).rw(m_dma2, FUNC(am9517a_device::read), FUNC(am9517a_device::write));


      // ICRT Card I/O Mapping
    map(0x03b0, 0x03bf).m(m_icrt, FUNC(epson_icrt_device::io_map_mono));
    map(0x03c0, 0x03cf).m(m_icrt, FUNC(epson_icrt_device::io_map_mono)); // for 3CE/3CF
    map(0x03d0, 0x03df).m(m_icrt, FUNC(epson_icrt_device::io_map_mono));
    
}

uint16_t qx16_state::vram_r(offs_t offset)
{
	int bank = 0;

	if (m_vram_bank & 1)     { bank = 0; } // B
	else if(m_vram_bank & 2) { bank = 1; } // G
	else if(m_vram_bank & 4) { bank = 2; } // R

	return m_video_ram[offset + (0x10000 * bank)];
}

void qx16_state::vram_w(offs_t offset, uint16_t data, uint16_t mem_mask)
{
	int bank = 0;

	if (m_vram_bank & 1)     { bank = 0; } // B
	else if(m_vram_bank & 2) { bank = 1; } // G
	else if(m_vram_bank & 4) { bank = 2; } // R

	COMBINE_DATA(&m_video_ram[offset + (0x10000 * bank)]);
}

// void qx16_state::upd7220_map(address_map &map)
// {
// 	map(0x0000, 0xffff).rw(FUNC(qx16_state::vram_r), FUNC(qx16_state::vram_w)).mirror(0x30000);
// }

void qx16_state::qx16_palette(palette_device &palette) const
{
	// ...
}

uint8_t qx16_state::qx16_1c_r()
{
    return m_ipl;
}

void qx16_state::qx16_1c_w(uint8_t data)
{
    m_ipl = data & 1;
    active_cpu = (data & 1); // 1 = 8088 Enabled, 0 = Z80 enabled
    logerror("Port 1C/24 write: %02X\n", data);
}

void qx16_state::qx16_18_w(uint8_t data)
{
	//m_membank = (data >> 4) & 0x0f;
	m_spkr_enable = (data ) & 0x01;
	//m_external_bank = (data >> 3) & 0x01;
	m_pit1->write_gate2(BIT(data, 1));
	m_pit1->write_gate0(data & 1);
	update_speaker();
	//update_memory_mapping();
}

void qx16_state::ppi_portc_w(uint8_t data)
{
	m_ppi_portc = data;
	logerror("8255 Port C write: %02X  PC1=%d (%s)\n",
		data, BIT(data, 1) ? 1 : 0, BIT(data, 1) ? "96TPI" : "48TPI");
	set_fdd_tpi_mode(BIT(data, 1));
}

bool qx16_state::floppy_ready_asserted(floppy_image_device *floppy) const
{
	// MAME floppy core exposes READY# as active-low:
	// ready_r() == 0 means the drive is ready.
	return floppy && !floppy->ready_r();
}

void qx16_state::log_floppy_state(char const *context, int drive)
{
	int const first = (drive >= 0) ? drive : 0;
	int const last = (drive >= 0) ? drive : 1;

	for (int index = first; index <= last; index++)
	{
		floppy_image_device *const floppy = m_floppy[index]->get_device();
		if (!floppy)
		{
			logerror("%s: drive %d <no device>\n", context, index);
			continue;
		}

		logerror(
				"%s: drive %d exists=%d ready=%d ready_n=%d mon=%d idx=%d trk00=%d dskchg=%d wpt=%d twosid=%d ss=%d cyl=%d selected=%d\n",
				context,
				index,
				floppy->exists() ? 1 : 0,
				floppy_ready_asserted(floppy) ? 1 : 0,
				floppy->ready_r() ? 1 : 0,
				floppy->mon_r(),
				floppy->idx_r(),
				floppy->trk00_r() ? 1 : 0,
				floppy->dskchg_r(),
				floppy->wpt_r() ? 1 : 0,
				floppy->twosid_r() ? 1 : 0,
				floppy->ss_r() ? 1 : 0,
				floppy->get_cyl(),
				(index == m_fdc_selected_drive) ? 1 : 0);
	}
}

char const *qx16_state::fdc_command_name(uint8_t command) const
{
	switch (command & 0x1f)
	{
	case 0x02: return "READ TRACK";
	case 0x03: return "SPECIFY";
	case 0x04: return "SENSE DRIVE STATUS";
	case 0x05: return "WRITE DATA";
	case 0x06: return "READ DATA";
	case 0x07: return "RECALIBRATE";
	case 0x08: return "SENSE INTERRUPT STATUS";
	case 0x09: return "WRITE DELETED DATA";
	case 0x0a: return "READ ID";
	case 0x0c: return "READ DELETED DATA";
	case 0x0d: return "FORMAT TRACK";
	case 0x0f: return "SEEK";
	case 0x11: return "SCAN EQUAL";
	case 0x19: return "SCAN LOW OR EQUAL";
	case 0x1d: return "SCAN HIGH OR EQUAL";
	default:   return "UNKNOWN";
	}
}

int qx16_state::fdc_command_expected_length(uint8_t command) const
{
	switch (command & 0x1f)
	{
	case 0x02: return 9;
	case 0x03: return 3;
	case 0x04: return 2;
	case 0x05: return 9;
	case 0x06: return 9;
	case 0x07: return 2;
	case 0x08: return 1;
	case 0x09: return 9;
	case 0x0a: return 2;
	case 0x0c: return 9;
	case 0x0d: return 6;
	case 0x0f: return 3;
	case 0x11: return 9;
	case 0x19: return 9;
	case 0x1d: return 9;
	default:   return 1;
	}
}

int qx16_state::fdc_command_drive() const
{
	if (!m_fdc_cmd_count)
		return -1;

	switch (m_last_fdc_cmd & 0x1f)
	{
	case 0x04:
	case 0x05:
	case 0x06:
	case 0x07:
	case 0x09:
	case 0x0a:
	case 0x0c:
	case 0x0d:
	case 0x0f:
	case 0x11:
	case 0x19:
	case 0x1d:
		return (m_fdc_cmd_count >= 2) ? (m_fdc_cmd_bytes[1] & 0x03) : -1;
	default:
		return -1;
	}
}

void qx16_state::reset_fdc_command_tracking()
{
	m_fdc_cmd_bytes.fill(0x00);
	m_fdc_cmd_count = 0;
	m_fdc_cmd_expected = 0;
	m_last_fdc_cmd = 0x00;
	m_dma_read_count = 0;
	m_dma_write_count = 0;
}

void qx16_state::floppy_load_cb(floppy_image_device *floppy)
{
	floppy_image_format_t const *const load_format = floppy->get_load_format();
	logerror("Floppy load: file=%s tag=%s format=%s exists=%d ready=%d ready_n=%d mon=%d cyl=%d drive-sides=%d media-twosid=%d side=%d\n",
		floppy->filename(),
		floppy->tag(),
		load_format ? load_format->name() : "<unknown>",
		floppy->exists() ? 1 : 0,
		floppy_ready_asserted(floppy) ? 1 : 0,
		floppy->ready_r() ? 1 : 0,
		floppy->mon_r(),
		floppy->get_cyl(),
		floppy->get_sides(),
		floppy->twosid_r() ? 1 : 0,
		floppy->ss_r() ? 1 : 0);
}

void qx16_state::floppy_unload_cb(floppy_image_device *floppy)
{
	logerror("Floppy unload: tag=%s\n", floppy->tag());
}

void qx16_state::floppy_ready_cb(floppy_image_device *floppy, int state)
{
	logerror("Floppy ready change: tag=%s ready=%d ready_n=%d mon=%d idx=%d cyl=%d side=%d twosid=%d\n",
		floppy->tag(),
		!state ? 1 : 0,
		state ? 1 : 0,
		floppy->mon_r(),
		floppy->idx_r(),
		floppy->get_cyl(),
		floppy->ss_r() ? 1 : 0,
		floppy->twosid_r() ? 1 : 0);
}

void qx16_state::fdc_us_w(uint8_t data)
{
	m_fdc_selected_drive = int(data);
	logerror("FDC unit select: drive=%d\n", m_fdc_selected_drive);
	log_floppy_state("FDC unit select state", m_fdc_selected_drive);
}

void qx16_state::set_fdd_tpi_mode(bool is_96tpi)
{
	if (m_fdd_96tpi == is_96tpi)
		return;

	m_fdd_96tpi = is_96tpi;
	logerror("QX16 live TPI mode: %s\n", m_fdd_96tpi ? "96TPI" : "48TPI");
	update_floppy_step_mode();
}

void qx16_state::log_fdc_command_start(uint8_t data)
{
	m_last_fdc_cmd = data;
	m_fdc_cmd_expected = fdc_command_expected_length(data);
	m_fdc_cmd_count = 0;
	m_dma_read_count = 0;
	m_dma_write_count = 0;

	logerror("FDC command start: %02X (%s), expected-bytes=%d\n",
		data, fdc_command_name(data), m_fdc_cmd_expected);
}

void qx16_state::log_fdc_command_complete()
{
	int const drive = fdc_command_drive();
	logerror("FDC command complete: %s bytes=",
		fdc_command_name(m_last_fdc_cmd));
	for (int i = 0; i < m_fdc_cmd_expected; i++)
		logerror("%s%02X", i ? " " : "", m_fdc_cmd_bytes[i]);
	logerror("\n");

	switch (m_last_fdc_cmd & 0x1f)
	{
	case 0x06:
	case 0x05:
	case 0x09:
	case 0x0c:
	case 0x11:
	case 0x19:
	case 0x1d:
		if (m_fdc_cmd_expected >= 9)
		{
			logerror("FDC %s decode: drv=%d hd=%d C=%d H=%d R=%d N=%d EOT=%d GPL=%d DTL=%d\n",
				fdc_command_name(m_last_fdc_cmd),
				m_fdc_cmd_bytes[1] & 0x03,
				BIT(m_fdc_cmd_bytes[1], 2),
				m_fdc_cmd_bytes[2],
				m_fdc_cmd_bytes[3],
				m_fdc_cmd_bytes[4],
				m_fdc_cmd_bytes[5],
				m_fdc_cmd_bytes[6],
				m_fdc_cmd_bytes[7],
				m_fdc_cmd_bytes[8]);
		}
		break;

	case 0x07:
		if (m_fdc_cmd_expected >= 2)
			logerror("FDC RECALIBRATE decode: drv=%d\n", m_fdc_cmd_bytes[1] & 0x03);
		break;

	case 0x0f:
		if (m_fdc_cmd_expected >= 3)
			logerror("FDC SEEK decode: drv=%d target-cyl=%d\n", m_fdc_cmd_bytes[1] & 0x03, m_fdc_cmd_bytes[2]);
		break;

	case 0x04:
		if (m_fdc_cmd_expected >= 2)
			logerror("FDC SENSE DRIVE STATUS decode: drv=%d hd=%d\n",
				m_fdc_cmd_bytes[1] & 0x03, BIT(m_fdc_cmd_bytes[1], 2));
		break;
	}

	log_floppy_state("FDC command state", drive);
}

uint8_t qx16_state::fdc_msr_r()
{
	uint8_t const data = m_fdc->msr_r();
	logerror("FDC MSR read: %02X\n", data);
	return data;
}

uint8_t qx16_state::fdc_fifo_r()
{
	uint8_t const data = m_fdc->fifo_r();
	logerror("FDC FIFO read: %02X during %s dma-r=%u dma-w=%u\n",
		data, fdc_command_name(m_last_fdc_cmd), m_dma_read_count, m_dma_write_count);
	return data;
}

void qx16_state::fdc_fifo_w(uint8_t data)
{
	logerror("FDC FIFO write: %02X\n", data);

	if (!m_fdc_cmd_count || (m_fdc_cmd_expected && (m_fdc_cmd_count >= m_fdc_cmd_expected)))
	{
		reset_fdc_command_tracking();
		log_fdc_command_start(data);
	}

	if (m_fdc_cmd_count < int(m_fdc_cmd_bytes.size()))
		m_fdc_cmd_bytes[m_fdc_cmd_count] = data;
	m_fdc_cmd_count++;
	if (m_fdc_cmd_count == m_fdc_cmd_expected)
		log_fdc_command_complete();

	m_fdc->fifo_w(data);
}

void qx16_state::qx16_28_w(uint8_t data)
{
    m_mem_group = data;
    logerror("Port 28 write - Memory group select: %02X (high_group=%d)\n",
             data, BIT(data, 0));
}


u8 qx16_state::dip_switches_r() 
{ 
	u8 dip_value = 0;

	u8 dip1 = (ioport("DIP1")->read() & 0x01);
    u8 dip2 = (ioport("DIP2")->read() & 0x01) << 1;
    u8 dip3 = (ioport("DIP3")->read() & 0x01) << 2;
    u8 dip4 = (ioport("DIP4")->read() & 0x01) << 3;
	u8 dip5 = (ioport("DIP5")->read() & 0x01) << 4;
    u8 dip6 = (ioport("DIP6")->read() & 0x01) << 5;
    u8 dip7 = (ioport("DIP7")->read() & 0x01) << 6;
    u8 dip8 = (ioport("DIP8")->read() & 0x01) << 7;

	dip_value = dip1 | dip2 | dip3 | dip4 | dip5 | dip6 | dip7 | dip8;
	
	logerror("DIP switches read: %02X\n", dip_value);

    return dip_value; 
} 

u8 qx16_state::mapping_register_r()
{
    /*
     QX-16 uses a mapping register at port 0x3CF to control VRAM mapping.
     The 3 most significant bits (D7, D6, D5) determine the base address for VRAM.

     0b11100000 = 0xE0 = B0000-BFFFF
     0b10100000 = 0xC0 = B0000 to B7FFF Enabled , B8000 to BFFFF Disabled
     0b11000000 = 0xA0 = B8000 to BFFFF Enabled , B0000 to B7FFF Disabled
     0b10000000 = 0x80 = B8000 to BFFFF Disabled , B0000 to B7FFF Disabled

    */

    return 0xC0; 
}

uint8_t qx16_state::get_slave_ack(offs_t offset)
{
	if (offset==7) { // IRQ = 7
		return m_pic_s->acknowledge();
	}
	return 0x00;
}

void qx16_state::update_speaker()
{

	/*
	 *                 freq -----
	 * pit1_out0 -----            NAND ---- level
	 *                 NAND -----
	 * !enable   -----
	 */

	uint8_t level = ((!m_spkr_enable && m_pit1_out0) || !m_spkr_freq) ? 1 : 0;
	m_speaker->level_w(level);
}

void qx16_state::speaker_duration(int state)
{
	m_pit1_out0 = state;
	update_speaker();
}

void qx16_state::speaker_freq(int state)
{
	m_spkr_freq = state;
	update_speaker();
}

void qx16_state::keyboard_irq(int state)
{
	m_scc->m1_r(); // always set
	m_pic_m->ir4_w(state);
}

void qx16_state::keyboard_clk(int state)
{
	// clock keyboard too
	m_kbd->clk_w(state);
	m_scc->rxca_w(state);
	m_scc->txca_w(state);
}

void qx16_state::fdc_intrq_w(int state)
{
    m_fdc_irq = bool(state);
   
 
	logerror("Interrupt from upd765: %d during %s dma-r=%u dma-w=%u\n",
		state, fdc_command_name(m_last_fdc_cmd), m_dma_read_count, m_dma_write_count);
	if (state)
		log_floppy_state("FDC IRQ state", fdc_command_drive());
	// signal interrupt
	m_pic_m->ir6_w(state);  
    //if (state == 0)
        //m_fdc->tc_line_w(0);
}

void qx16_state::floppy_formats(format_registration &fr)
{
	fr.add_mfm_containers();
	fr.add(FLOPPY_QX16_RAW_FORMAT);
	fr.add(FLOPPY_PC_FORMAT);
	fr.add(FLOPPY_IPF_FORMAT);
}

static void qx16_floppies(device_slot_interface &device)
{
	device.option_add("525qd", FLOPPY_525_QD);
	device.option_add("525qd_ds", QX16_FLOPPY_525_QD_DS);
	device.option_add("35dd", FLOPPY_35_DD);
	device.set_default_option("525qd_ds");
}

void qx16_state::update_floppy_step_mode()
{
	// Hardware behavior: Port C bit 1 selects the drive step resolution.
	//  1 = 96 TPI -> single-step
	//  0 = 48 TPI -> double-step
	// Keep the media flag around for logging while we converge on the
	// remaining geometry issues.
	m_fdd_double_step = !m_fdd_96tpi;

	for (auto &fdd : m_floppy)
	{
		auto *const floppy = dynamic_cast<qx16_525_qd_double_step_device *>(fdd->get_device());
		if (floppy)
			floppy->set_step_mode(m_fdd_96tpi, m_fdd_double_step);
	}

	logerror("QX16 floppy mode: PC1=%d (%s), media-48tpi=%d, effective-double-step=%d\n",
		m_fdd_96tpi ? 1 : 0,
		m_fdd_96tpi ? "96TPI" : "48TPI",
		m_media_48tpi_compat ? 1 : 0,
		m_fdd_double_step ? 1 : 0);
}

void qx16_state::update_fdd_motor(uint8_t state)
{
	for (int index = 0; index < 2; index++)
	{
		floppy_image_device *const floppy = m_floppy[index]->get_device();
		if (floppy)
		{
			floppy->mon_w(state);
			logerror("FDD motor update: drive %d mon=%d ready=%d idx=%d cyl=%d\n",
				index,
				floppy->mon_r(),
				floppy_ready_asserted(floppy) ? 1 : 0,
				floppy->idx_r(),
				floppy->get_cyl());
		}
	}
}

void qx16_state::fdd_motor_w(uint8_t data)
{
	m_counter = 0;
	logerror("FDD motor port write: %02X\n", data);
	update_fdd_motor(0);
	// motor off controlled by clock
}

void qx16_state::sqw_out(uint8_t state)
{
	uint8_t const clk = !(state || BIT(m_counter, 11));
	uint16_t cnt = m_counter;

	if (!clk && m_motor_clk)
		cnt = (cnt + 1) & 0x0fff;

	if (BIT(cnt, 11) && !BIT(m_counter, 11))
	{
		logerror("RTC SQW motor timeout: counter=%03X -> motor off\n", cnt);
		update_fdd_motor(1);
	}

	m_motor_clk = clk;
	m_counter = cnt;
}

// uint8_t qx16_state::qx10_30_r()
// {
// 	auto *floppy = m_floppy[0]->get_device(); 

// 	//floppy1 = m_floppy[0]->get_device();
// 	//floppy2 = m_floppy[1]->get_device();

    
//     if (floppy)
//             return m_fdc_irq  | 
// 			m_counter << 1 |
// 			0b00001000; 
//     else
//             return m_fdc_irq  |m_counter << 1 | 0b00000000;
		

// }

uint8_t qx16_state::qx10_30_r()
{
    auto *floppy1 = m_floppy[0]->get_device();
    auto *floppy2 = m_floppy[1]->get_device();
    uint8_t const data = m_fdc_irq |
           (BIT(m_counter, 11) << 1) |
           (((floppy1 != nullptr) || (floppy2 != nullptr)) ? 0x08 : 0x00);

	logerror("Port 30 read: %02X irq=%d motor-timer=%d drive-present=%d\n",
		data,
		m_fdc_irq ? 1 : 0,
		BIT(m_counter, 11),
		((floppy1 != nullptr) || (floppy2 != nullptr)) ? 1 : 0);

    return data;
}

void qx16_state::tc_w(int state)
{
	/* floppy terminal count */
    logerror("Terminal count from DMA: %d during %s dma-r=%u dma-w=%u\n",
		state, fdc_command_name(m_last_fdc_cmd), m_dma_read_count, m_dma_write_count);
	log_floppy_state("DMA terminal count state", fdc_command_drive());
	m_fdc->tc_w(!state);
	//m_bus->slots_w<&bus::epson_qx::option_slot_device::eopf>(state);
}

void qx16_state::dma_hrq_changed(int state)
{
	/* Assert HLDA */
	m_dma1->hack_w(state);
}

void qx16_state::mfdc_drq(bool state)
{
    logerror("DMA request from FDC: %d during %s dma-r=%u dma-w=%u\n",
		state, fdc_command_name(m_last_fdc_cmd), m_dma_read_count, m_dma_write_count);
 
    m_dma1->dreq0_w(state ? 1 : 0);
}

u32 qx16_state::screen_update(screen_device &screen, bitmap_rgb32 &bitmap, const rectangle &cliprect)
{
    if (m_icrt->active()) {
        
        return m_icrt->screen_update(screen, bitmap, cliprect);
    }

    
}

// ---------------- Machine config ----------------
void qx16_state::qx16(machine_config &config)
{
    I8088(config, m_cpu, 15.9744_MHz_XTAL / 3);
    m_cpu->set_addrmap(AS_PROGRAM, &qx16_state::prog_map);
    m_cpu->set_addrmap(AS_IO,      &qx16_state::io_map);
    m_cpu->set_irq_acknowledge_callback("pic8259_master", FUNC(pic8259_device::inta_cb));

    RAM(config, RAM_TAG).set_default_size("512K");

    
    PIC8259(config, m_pic_m, 0);
	m_pic_m->out_int_callback().set_inputline(m_cpu, 0);
	m_pic_m->in_sp_callback().set_constant(1);
	m_pic_m->read_slave_ack_callback().set(FUNC(qx16_state::get_slave_ack));

	PIC8259(config, m_pic_s, 0);
	m_pic_s->out_int_callback().set(m_pic_m, FUNC(pic8259_device::ir7_w));
	m_pic_s->in_sp_callback().set_constant(0);
 
    PIT8253(config, m_pit1, 0);
	m_pit1->set_clk<0>(1200);
	m_pit1->out_handler<0>().set(FUNC(qx16_state::speaker_duration));
	m_pit1->set_clk<1>(1200);
	m_pit1->out_handler<1>().set(m_pic_s, FUNC(pic8259_device::ir5_w));
	m_pit1->set_clk<2>(MAIN_CLK / 8);
	m_pit1->out_handler<2>().set(m_pic_m, FUNC(pic8259_device::ir1_w)); 

	PIT8253(config, m_pit2, 0);
	m_pit2->set_clk<0>(MAIN_CLK / 8);
	m_pit2->out_handler<0>().set(FUNC(qx16_state::speaker_freq));
	m_pit2->set_clk<1>(MAIN_CLK / 8);
	m_pit2->out_handler<1>().set(FUNC(qx16_state::keyboard_clk));
	m_pit2->set_clk<2>(MAIN_CLK / 8);
	m_pit2->out_handler<2>().set(m_scc, FUNC(upd7201_device::rxtxcb_w));
 
    UPD7201(config, m_scc, MAIN_CLK/4); // channel b clock set by pit2 channel 2
	// Channel A: Keyboard
	m_scc->out_txda_callback().set(m_kbd, FUNC(bus::epson_qx::keyboard::keyboard_port_device::rxd_w));
	// Channel B: RS232
	//m_scc->out_txdb_callback().set(RS232_TAG, FUNC(rs232_port_device::write_txd));
	//m_scc->out_dtrb_callback().set(RS232_TAG, FUNC(rs232_port_device::write_dtr));
	//m_scc->out_rtsb_callback().set(RS232_TAG, FUNC(rs232_port_device::write_rts));
	m_scc->out_int_callback().set(FUNC(qx16_state::keyboard_irq));
   

    EPSON_QX_KEYBOARD_PORT(config, m_kbd, bus::epson_qx::keyboard::keyboard_devices, "qx10_hasci");
	m_kbd->txd_handler().set(m_scc, FUNC(upd7201_device::rxa_w));

    AM9517A(config, m_dma1, 15.9744_MHz_XTAL/3);
	m_dma1->dreq_active_low();
    m_dma1->out_hreq_callback().set(FUNC(qx16_state::dma_hrq_changed));
    // m_dma1->in_memr_callback().set([this](offs_t addr) {
    //     logerror("DMA read from %05X\n", addr);
    // return m_cpu->space(AS_PROGRAM).read_byte(addr);
    // });
    // m_dma1->out_memw_callback().set([this](offs_t addr, u8 data) {
    //     //logerror("DMA write to %05X = %02X\n", addr, data);
    // m_cpu->space(AS_PROGRAM).write_byte(addr, data);
    // });

    m_dma1->in_memr_callback().set([this](offs_t addr) -> u8
{
    int slot;
    if      (BIT(m_mem_group, 4)) slot = 0;
    else if (BIT(m_mem_group, 5)) slot = 1;
    else if (BIT(m_mem_group, 6)) slot = 2;
    else if (BIT(m_mem_group, 7)) slot = 3;
    else                          slot = 0;   // fallback

    const int group = BIT(m_mem_group, 0) ? 1 : 0;
    const int bank  = slot + (group * 4);

    const uint32_t phys = (uint32_t(bank) << 16) | (addr & 0xffff);

    logerror("DMA READ  addr=%04X port28=%02X slot=%d group=%d bank=%d phys=%05X\n",
             u16(addr), m_mem_group, slot, group, bank, phys);
    m_dma_read_count++;
    if (m_dma_read_count == 1)
        log_floppy_state("DMA read phase start", fdc_command_drive());

    return m_cpu->space(AS_PROGRAM).read_byte(phys);
});

m_dma1->out_memw_callback().set([this](offs_t addr, u8 data)
{
    int slot;
    if      (BIT(m_mem_group, 4)) slot = 0;
    else if (BIT(m_mem_group, 5)) slot = 1;
    else if (BIT(m_mem_group, 6)) slot = 2;
    else if (BIT(m_mem_group, 7)) slot = 3;
    else                          slot = 0;   // fallback

    const int group = BIT(m_mem_group, 0) ? 1 : 0;
    const int bank  = slot + (group * 4);

    const uint32_t phys = (uint32_t(bank) << 16) | (addr & 0xffff);

    logerror("DMA WRITE addr=%04X data=%02X port28=%02X slot=%d group=%d bank=%d phys=%05X\n",
             u16(addr), data, m_mem_group, slot, group, bank, phys);
    m_dma_write_count++;
    if (m_dma_write_count == 1)
        log_floppy_state("DMA write phase start", fdc_command_drive());

    m_cpu->space(AS_PROGRAM).write_byte(phys, data);
});

    
    AM9517A(config, m_dma2, 15.9744_MHz_XTAL/3);
	m_dma2->dreq_active_low();
    m_dma2->in_memr_callback().set([this](offs_t a){ return m_cpu->space(AS_PROGRAM).read_byte(a); });
    m_dma2->out_memw_callback().set([this](offs_t a, u8 d){ m_cpu->space(AS_PROGRAM).write_byte(a, d); });

       // Slave HRQ -> Master DREQ4
    m_dma2->out_hreq_callback().set(m_dma1, FUNC(am9517a_device::dreq3_w));
    // Master DACK4 -> Slave HACK
    //m_dma1->out_dack_callback<4>().set(m_dma2, FUNC(am9517a_device::hack_w));

    I8255(config, m_ppi, 0);
	m_ppi->out_pa_callback().set("prndata", FUNC(output_latch_device::write));
	m_ppi->out_pc_callback().set(FUNC(qx16_state::ppi_portc_w));
    output_latch_device &prndata(OUTPUT_LATCH(config, "prndata"));

  	SCREEN(config, m_screen, SCREEN_TYPE_RASTER);
	m_screen->set_screen_update(FUNC(qx16_state::screen_update));

    m_screen->set_raw(14.318181_MHz_XTAL, 912, 0, 640, 262, 0, 400);
	//m_screen->set_raw(16.67_MHz_XTAL, 872, 152, 792, 421, 4, 404);

    /* sound hardware */
	SPEAKER(config, "mono").front_center();
    SPEAKER_SOUND(config, m_speaker).add_route(ALL_OUTPUTS, "mono", 1.00);
	



    PALETTE(config, m_palette, FUNC(qx16_state::qx16_palette), 8);

     // Real time Clock
    MC146818(config, m_rtc, 32.768_kHz_XTAL);
    m_rtc->set_binary(false);                  // BCD mode (DM=0)
    m_rtc->set_24hrs(true);                  // 24-hour mode (24/12=1)
    m_rtc->irq().set(m_pic_s, FUNC(pic8259_device::ir2_w));
    m_rtc->sqw().set(FUNC(qx16_state::sqw_out));

    UPD765A(config, m_fdc, 8'000'000,true, true);           // intrq, drq enabled
    //m_fdc->set_rate(250000); // 250 kHz
    FLOPPY_CONNECTOR(config, m_floppy[0], qx16_floppies, "525qd_ds", qx16_state::floppy_formats).enable_sound(true);
	FLOPPY_CONNECTOR(config, m_floppy[1], qx16_floppies, "525qd_ds", qx16_state::floppy_formats).enable_sound(true);
    m_fdc->intrq_wr_callback().set(FUNC(qx16_state::fdc_intrq_w));
    m_fdc->us_wr_callback().set(FUNC(qx16_state::fdc_us_w));
    m_fdc->drq_wr_callback().set(m_dma1, FUNC(am9517a_device::dreq0_w)).invert();
    



    m_dma1->out_eop_callback().set(FUNC(qx16_state::tc_w));
    m_dma1->in_ior_callback<0>().set(m_fdc, FUNC(upd765a_device::dma_r));
    m_dma1->out_iow_callback<0>().set(m_fdc, FUNC(upd765a_device::dma_w));

    //m_dma1->in_ior_callback<1>().set(m_hgdc, FUNC(upd7220_device::dack_r));
	//m_dma1->out_iow_callback<1>().set(m_hgdc, FUNC(upd7220_device::dack_w));


      // --- ICRT ---
    EPSON_ICRT(config, m_icrt, 0);   // clock is driven internally (6845), 0 is fine

    m_screen->set_screen_update(FUNC(qx16_state::screen_update));


}

// ---------------- ROMs / inputs ----------------
static INPUT_PORTS_START(qx16)
    
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

	PORT_START("DIP5")
    PORT_DIPNAME(0x01, 0x00, "DIP SW5: Color Monitor") 
        PORT_DIPSETTING(0x00, "ON")
        PORT_DIPSETTING(0x01, "OFF")

    PORT_START("DIP6")
    PORT_DIPNAME(0x01, 0x00, "DIP SW6: Unknown") // 0=2 drives, 1=1 drive
        PORT_DIPSETTING(0x00, "ON")
        PORT_DIPSETTING(0x01, "OFF")

    PORT_START("DIP7")
    PORT_DIPNAME(0x01, 0x00, "DIP SW7: Unknown") // 0=2 drives, 1=1 drive
        PORT_DIPSETTING(0x00, "ON")
        PORT_DIPSETTING(0x01, "OFF")

    PORT_START("DIP8")
    PORT_DIPNAME(0x01, 0x00, "DIP SW8: Unknown") // 0=2 drives, 1=1 drive
        PORT_DIPSETTING(0x00, "ON")
        PORT_DIPSETTING(0x01, "OFF")

	PORT_START("CONFIG")
	PORT_CONFNAME( 0x03, 0x01, "Video Board" )
	PORT_CONFSETTING( 0x02, "Monochrome" )
	PORT_CONFSETTING( 0x01, "Color" )
	PORT_BIT(0xfc, IP_ACTIVE_LOW, IPT_UNUSED)

INPUT_PORTS_END

ROM_START(qx16)
    ROM_REGION(0x10000, "bios", ROMREGION_ERASEFF)
    ROM_LOAD( "bios2.26h.bin", 0x0c000, 0x4000, CRC(3d5deb8e) SHA1(2999423882bd4b6e33fa2f40e1c2677bc103a79b) )
    ROM_RELOAD(                0x08000, 0x4000 )
    ROM_RELOAD(                0x04000, 0x4000 )
    ROM_RELOAD(                0x00000, 0x4000 )
    //ROM_REGION( 0x1000, "chargen", 0 )
    //ROM_LOAD( "qge.2e",   0x0000, 0x1000, BAD_DUMP CRC(eb31a2d5) SHA1(6dc581bf2854a07ae93b23b6dfc9c7abd3c0569e))
ROM_END

} // anonymous namespace

COMP(1984, qx16, 0, 0, qx16, qx16, qx16_state, empty_init, "Epson", "QX-16 (BIOS 2.26h)", MACHINE_NOT_WORKING | MACHINE_NO_SOUND_HW)
