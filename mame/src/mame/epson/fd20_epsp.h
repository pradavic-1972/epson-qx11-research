#pragma once
#include <cstdint>
#include <deque>
#include <vector>

class fd20_epsp
{
public:
    fd20_epsp();
    size_t  debug_tx_size() const { return m_tx.size(); }
    // Host -> device (ports 8 and 6)
    void host_param_write(uint8_t v);   // port 8
    void host_data_write(uint8_t v);    // port 6

    // Device -> host (port 6)
    bool    has_tx() const;
    uint8_t dev_data_read();            // pop from TX

    void    reset();

private:
    // queues
    std::deque<uint8_t> m_rx;   // collected from host_data_write
    std::deque<uint8_t> m_tx;   // bytes host will read

    // last param (port 8) write
    uint8_t m_param = 0x00;

    // parser state
    enum class rx_state : uint8_t {
        Idle,
        AfterEOT_04,    // expecting 31,31,<id>,05
        SOH_Frame,      // 0x01 ... HCS
        STX_Block       // 0x02 ... 0x03 HCS
    };
    rx_state m_state = rx_state::Idle;

    // EOT tracking
    uint8_t m_eot_idx = 0;
    uint8_t m_eot_buf[3] = {0,0,0};

    // in-flight frames
    std::vector<uint8_t> m_frame;   // used for SOH
    std::vector<uint8_t> m_stx;     // used for STX

    // helpers
    void process_input();
    void handle_idle_byte(uint8_t b);
    void handle_after_eot(uint8_t b);
    void handle_soh_byte(uint8_t b);
    void handle_stx_byte(uint8_t b);

    void push_ack_front();  // guarantee ACK is next
    void push_ack_back();
    void push_nak();

    static uint8_t hcs_sum(const std::vector<uint8_t>& bytes_wo_hcs);

    // SOH command dispatch (after we ACK)
    void dispatch_soh_command(const std::vector<uint8_t>& f_wo_hcs);
};
