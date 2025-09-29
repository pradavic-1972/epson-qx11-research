#include "fd20_epsp.h"

fd20_epsp::fd20_epsp() { reset(); }

void fd20_epsp::reset()
{
    m_rx.clear();
    m_tx.clear();
    m_param = 0x00;
    m_state = rx_state::Idle;
    m_eot_idx = 0;
    m_eot_buf[0] = m_eot_buf[1] = m_eot_buf[2] = 0;
    m_frame.clear();
    m_stx.clear();
}

bool fd20_epsp::has_tx() const { return !m_tx.empty(); }

uint8_t fd20_epsp::dev_data_read()
{
    if (m_tx.empty()) return 0x00;
    uint8_t b = m_tx.front();
    m_tx.pop_front();
    return b;
}

void fd20_epsp::host_param_write(uint8_t v) { m_param = v; }

void fd20_epsp::host_data_write(uint8_t v)
{
    m_rx.push_back(v);
    process_input();
}

void fd20_epsp::push_ack_front() { m_tx.push_front(0x06); }
void fd20_epsp::push_ack_back()  { m_tx.push_back(0x06);  }
void fd20_epsp::push_nak()       { m_tx.push_back(0x15);  }

uint8_t fd20_epsp::hcs_sum(const std::vector<uint8_t>& v)
{
    uint32_t s = 0;
    for (auto b : v) s += b;
    return uint8_t(s & 0xFF);
}

void fd20_epsp::process_input()
{
    while (!m_rx.empty())
    {
        uint8_t b = m_rx.front();
        m_rx.pop_front();

        switch (m_state)
        {
        case rx_state::Idle:        handle_idle_byte(b);   break;
        case rx_state::AfterEOT_04: handle_after_eot(b);   break;
        case rx_state::SOH_Frame:   handle_soh_byte(b);    break;
        case rx_state::STX_Block:   handle_stx_byte(b);    break;
        }
    }
}

void fd20_epsp::handle_idle_byte(uint8_t b)
{
    if (b == 0x05) {                // ENQ
        push_ack_front();
        return;
    }
    if (b == 0x04) {                // EOT preamble start
        m_eot_idx = 0;
        m_state = rx_state::AfterEOT_04;
        return;
    }
    if (b == 0x01) {                // SOH
        m_frame.clear();
        m_frame.push_back(0x01);
        m_state = rx_state::SOH_Frame;
        return;
    }
    if (b == 0x02) {                // STX block from host
        m_stx.clear();
        m_stx.push_back(0x02);
        m_state = rx_state::STX_Block;
        return;
    }
    // else ignore
}

void fd20_epsp::handle_after_eot(uint8_t b)
{
    auto reset_eot = [&](){ m_eot_idx = 0; m_state = rx_state::Idle; };

    if (m_eot_idx < 2) {
        // expect 31, 31
        if ((m_eot_idx == 0 && b != 0x31) ||
            (m_eot_idx == 1 && b != 0x31))
        {
            push_nak();
            reset_eot();
            return;
        }
        m_eot_buf[m_eot_idx++] = b;
        return;
    }

    if (m_eot_idx == 2) {
        // this is <id> (any value)
        m_eot_buf[m_eot_idx++] = b;
        return;
    }

    // trailing 0x05
    if (b != 0x05) {
        push_nak();
        reset_eot();
        return;
    }

    // Good preamble → ACK only
    push_ack_front();
    reset_eot();
}

void fd20_epsp::handle_soh_byte(uint8_t b)
{
    m_frame.push_back(b);

    // Minimum SOH frame is 0x01 fmt dev fd cmd size <hcs>  => 7 bytes total.
    if (m_frame.size() < 7) return;

    // Split HCS off
    std::vector<uint8_t> wo_hcs = m_frame;
    uint8_t hcs = wo_hcs.back();
    wo_hcs.pop_back();
    (void)hcs; // we don't NAK on HCS in this minimal shim

    // ACK FIRST so the next host read sees 0x06
    push_ack_front();

    // Handle command (optionally enqueue follow-ups; but no STX spam)
    dispatch_soh_command(wo_hcs);

    // reset for next frame
    m_frame.clear();
    m_state = rx_state::Idle;
}

void fd20_epsp::handle_stx_byte(uint8_t b)
{
    m_stx.push_back(b);

    // STX block ends with ... 0x03 <HCS>; we need at least 4 bytes total
    if (m_stx.size() < 4) return;

    // If we just saw ETX (0x03), the next byte is HCS and we can ACK
    if (m_stx[m_stx.size() - 2] == 0x03) {
        // We could verify HCS here:
        // std::vector<uint8_t> wo_hcs(m_stx.begin(), m_stx.end() - 1);
        // if (hcs_sum(wo_hcs) != m_stx.back()) { push_nak(); ... }
        // Minimal shim: always ACK
        push_ack_front();

        // Done with this block
        m_stx.clear();
        m_state = rx_state::Idle;
    }
}

void fd20_epsp::dispatch_soh_command(const std::vector<uint8_t>& f)
{
    // f: [01, fmt, dev, fd, cmd, size, (optional payload...)]  (HCS already stripped)
    if (f.size() < 6 || f[0] != 0x01) return;

    uint8_t cmd = f[4];

    switch (cmd)
    {
        case 0x0D: // RESET DISK / READY probe
        case 0x6B: // status
        case 0x76: // inquiry/status
        case 0x70: // param'd command, host may follow with STX
        case 0x73: // block xfer request
        default:
            // For now: do nothing more than the ACK we already queued.
            break;
    }
}
