// license:BSD-3-Clause
#pragma once

#include "emu.h"

#include <array>
#include <vector>
#include <utility>

class epson_hd_device : public device_t, public device_image_interface
{
public:
	epson_hd_device(const machine_config &mconfig, const char *tag, device_t *owner, u32 clock = 0);

	// Host-visible ports
	u8  port80_r();
	void port80_w(u8 data);

	u8  port81_r();
	void port81_w(u8 data);

	void port82_w(u8 data);

protected:
	// device_t
	virtual void device_start() override;
	virtual void device_reset() override;

	// device_image_interface (newer MAME API)
	virtual std::pair<std::error_condition, std::string> call_load() override;
	virtual std::pair<std::error_condition, std::string> call_create(s32 format_type, util::option_resolution *format_options) override;
	virtual void call_unload() override;

	virtual bool is_readable()  const noexcept override { return true; }
	virtual bool is_writeable() const noexcept override { return true; }
	virtual bool is_creatable() const noexcept override { return true; }
	virtual bool is_reset_on_load() const noexcept override { return false; }

	virtual const char *image_type_name() const noexcept override { return "harddisk"; }
	virtual const char *image_brief_type_name() const noexcept override { return "hdd"; }
	virtual const char *file_extensions() const noexcept override { return "img,raw,bin"; }
    virtual void device_stop() override;


private:
	// Use u8 phases so save_item works across MAME revisions
	enum : u8
	{
		PH_WAIT_PREFIX = 0,
		PH_WAIT_STROBE,
		PH_REQ_FRAME,
		PH_RECV_FRAME,
		PH_PARAM_TX,
		PH_RES_R0,
		PH_RES_R1,
		PH_STREAM_READ,
		PH_STREAM_WRITE,
        PH_STREAM_0F,
		PH_IDLE
	};

	enum : u8
	{
		SM_NONE = 0,
		SM_READ,
		SM_WRITE
	};

private:
	void abort_all();
	void start_command_transaction(u8 prefix);

	void decode_frame();
	void begin_command();

	// NEW: transition from data/param phase into final result phase (0x0F/0x1F + 2 bytes on port80)
	void enter_final_results();

	void finish_ok();
	void finish_err(u8 err);

	void start_read_stream();
	void start_write_stream();

	u8  read_media_byte(u32 lba, u32 off) const;
	void write_media_byte(u32 lba, u32 off, u8 data);

	void ensure_image_min_size(u64 bytes);

private:
	// protocol state
	u8  m_phase = PH_WAIT_PREFIX;

	bool m_probe_pending = false;

	u8   m_prefix = 0x00;
	bool m_armed  = false;

	std::array<u8, 6> m_cmd{};
	u8  m_cmd_pos = 0;

	// decoded frame
	u8  m_op    = 0;
	u32 m_addr  = 0;     // 24-bit "addr" field
	u16 m_count = 0;     // count==0 => 256 (class-0 convention)
	u8  m_magic = 0;

	// result bytes read on port 80 during PH_RES_R0/PH_RES_R1
	u8  m_r0 = 0;
	u8  m_r1 = 0;

	// post-frame ack behavior
	bool m_need_post_ack = false;
	u8   m_after_ack_phase = PH_RES_R0;

	// 0x0C param-tx
	u16 m_param_left = 0;
	u16 m_param_pos  = 0;
	std::array<u8, 64> m_param_buf{};

	// streaming payload
	u8  m_stream_mode  = SM_NONE;
	u32 m_stream_total = 0;
	u32 m_stream_pos   = 0;

	// backing store (raw image bytes)
	std::vector<u8> m_image;
    bool m_dirty = false;
    void flush_image();
};

DECLARE_DEVICE_TYPE(EPSON_HD, epson_hd_device)
