`timescale 1ns/1ps
`include "dma_sim_def.vh"

module dma_ref_model;

reg [31:0] global_ctrl;
reg [31:0] global_status_sticky;
reg [31:0] irq_status;
reg [31:0] irq_mask;
reg [31:0] cq_base_l;
reg [31:0] cq_base_h;
reg [31:0] cq_size;
reg [31:0] cq_wr_ptr;
reg [31:0] cq_rd_ptr;
reg [31:0] intr_coal_cnt;
reg [31:0] intr_coal_timer;
reg [31:0] global_drop_cnt;
reg [31:0] global_err_cnt;
reg [31:0] debug_state;

reg [31:0] rx_ctrl      [0:`DMA_MAX_CH-1];
reg [31:0] rx_cfg       [0:`DMA_MAX_CH-1];
reg [31:0] rx_base_l    [0:`DMA_MAX_CH-1];
reg [31:0] rx_base_h    [0:`DMA_MAX_CH-1];
reg [31:0] rx_size      [0:`DMA_MAX_CH-1];
reg [31:0] rx_max_len   [0:`DMA_MAX_CH-1];
reg [31:0] rx_wr_ptr    [0:`DMA_MAX_CH-1];
reg [31:0] rx_rd_ptr    [0:`DMA_MAX_CH-1];
reg [31:0] rx_used      [0:`DMA_MAX_CH-1];
reg [31:0] rx_high_wm   [0:`DMA_MAX_CH-1];
reg [31:0] rx_low_wm    [0:`DMA_MAX_CH-1];
reg [31:0] rx_status    [0:`DMA_MAX_CH-1];
reg [31:0] rx_frame_cnt [0:`DMA_MAX_CH-1];
reg [31:0] rx_drop_cnt  [0:`DMA_MAX_CH-1];
reg [31:0] rx_err_cnt   [0:`DMA_MAX_CH-1];
reg [31:0] rx_user      [0:`DMA_MAX_CH-1];

integer i;

function [7:0] hdr_byte;
    input [511:0] beat;
    input integer index;
    begin
        hdr_byte = beat[index*8 +: 8];
    end
endfunction

function ref_cq_has_space;
    input dummy;
    reg [31:0] next_ptr;
    begin
        next_ptr = (cq_wr_ptr + 1 >= cq_size) ? 0 : cq_wr_ptr + 1;
        ref_cq_has_space = (cq_size != 0) && (next_ptr != cq_rd_ptr);
    end
endfunction

function [15:0] hdr_u16;
    input [511:0] beat;
    input integer index;
    begin
        hdr_u16 = {hdr_byte(beat, index+1), hdr_byte(beat, index)};
    end
endfunction

function [31:0] hdr_u32;
    input [511:0] beat;
    input integer index;
    begin
        hdr_u32 = {hdr_byte(beat, index+3), hdr_byte(beat, index+2),
                   hdr_byte(beat, index+1), hdr_byte(beat, index)};
    end
endfunction

function [63:0] hdr_u64;
    input [511:0] beat;
    input integer index;
    begin
        hdr_u64 = {hdr_u32(beat, index+4), hdr_u32(beat, index)};
    end
endfunction

function [31:0] crc32_byte;
    input [31:0] crc_in;
    input [7:0] data;
    integer b;
    reg [31:0] c;
    begin
        c = crc_in ^ {24'h0, data};
        for (b = 0; b < 8; b = b + 1) begin
            if (c[0])
                c = (c >> 1) ^ 32'hEDB88320;
            else
                c = (c >> 1);
        end
        crc32_byte = c;
    end
endfunction

function [31:0] header_crc32;
    input [511:0] beat;
    integer b;
    reg [31:0] crc;
    begin
        crc = 32'hffff_ffff;
        for (b = 0; b < 48; b = b + 1)
            crc = crc32_byte(crc, hdr_byte(beat, b));
        header_crc32 = crc ^ 32'hffff_ffff;
    end
endfunction

function [31:0] align64;
    input [31:0] value;
    begin
        align64 = (value + (`DMA_ALIGN_BYTES-1)) & 32'hffff_ffc0;
    end
endfunction

function policy_supported;
    input [3:0] traffic_class;
    input [3:0] policy;
    begin
        case (traffic_class)
        `DMA_TC_CONT:
            policy_supported = (policy == `DMA_RX_POL_DISABLE_DROP) ||
                               (policy == `DMA_RX_POL_LINEAR_CAPTURE) ||
                               (policy == `DMA_RX_POL_RING_BUFFER);
        `DMA_TC_FC:
            policy_supported = (policy == `DMA_RX_POL_DISABLE_DROP) ||
                               (policy == `DMA_RX_POL_QUEUE_DROP_NEW) ||
                               (policy == `DMA_RX_POL_QUEUE_WITH_FC) ||
                               (policy == `DMA_RX_POL_QUEUE_LOSSLESS);
        `DMA_TC_AUX:
            policy_supported = (policy == `DMA_RX_POL_DISABLE_DROP) ||
                               (policy == `DMA_RX_POL_LINEAR_CAPTURE) ||
                               (policy == `DMA_RX_POL_MAILBOX) ||
                               (policy == `DMA_RX_POL_AUX_FIFO);
        default:
            policy_supported = 1'b0;
        endcase
    end
endfunction

function [31:0] make_status;
    input integer ch;
    input [7:0] code;
    reg [31:0] s;
    begin
        s = rx_status[ch];
        s[`DMA_RX_STATUS_IDLE] = 1'b1;
        s[`DMA_RX_STATUS_BUSY] = 1'b0;
        s[`DMA_RX_STATUS_ENABLED] = rx_ctrl[ch][`DMA_RX_CTRL_ENABLE];
        s[23:16] = code;
        make_status = s;
    end
endfunction

task mem_wr8;
    input [31:0] addr;
    input [7:0] data;
    begin
        if (addr < `DMA_SIM_MEM_BYTES)
            `DMA_REF_MEM_PATH[addr] = data;
        else
            $display("%t Error: ref mem write out of range addr=%08x", $time, addr);
    end
endtask

task mem_wr16_le;
    input [31:0] addr;
    input [15:0] data;
    begin
        mem_wr8(addr + 0, data[7:0]);
        mem_wr8(addr + 1, data[15:8]);
    end
endtask

task mem_wr32_le;
    input [31:0] addr;
    input [31:0] data;
    begin
        mem_wr8(addr + 0, data[7:0]);
        mem_wr8(addr + 1, data[15:8]);
        mem_wr8(addr + 2, data[23:16]);
        mem_wr8(addr + 3, data[31:24]);
    end
endtask

task mem_wr64_le;
    input [31:0] addr;
    input [63:0] data;
    begin
        mem_wr32_le(addr + 0, data[31:0]);
        mem_wr32_le(addr + 4, data[63:32]);
    end
endtask

task write_cqe;
    input integer ch;
    input [7:0] status_code;
    input [3:0] traffic_class;
    input [3:0] policy;
    input [15:0] cqe_flags;
    input [15:0] flow_id;
    input [15:0] msg_id;
    input [31:0] payload_addr_l;
    input [31:0] payload_len;
    input [31:0] aligned_len;
    input [63:0] timestamp;
    input [31:0] frame_seq;
    input [31:0] sample_count;
    reg [31:0] cqe_addr;
    reg [31:0] next_ptr;
    integer clear_i;
    begin
        if (cq_size == 0) begin
            rx_status[ch][`DMA_RX_STATUS_CQ] = 1'b1;
            rx_err_cnt[ch] = rx_err_cnt[ch] + 1;
            global_err_cnt = global_err_cnt + 1;
            irq_status[`DMA_IRQ_CQ_FULL] = 1'b1;
        end else begin
            next_ptr = (cq_wr_ptr + 1 >= cq_size) ? 0 : cq_wr_ptr + 1;
            if (next_ptr == cq_rd_ptr) begin
                rx_status[ch][`DMA_RX_STATUS_CQ] = 1'b1;
                rx_err_cnt[ch] = rx_err_cnt[ch] + 1;
                global_err_cnt = global_err_cnt + 1;
                irq_status[`DMA_IRQ_CQ_FULL] = 1'b1;
            end else begin
                cqe_addr = cq_base_l + (cq_wr_ptr << 6);
                for (clear_i = 0; clear_i < `DMA_CQE_BYTES; clear_i = clear_i + 1)
                    mem_wr8(cqe_addr + clear_i, 8'h00);
                mem_wr32_le(cqe_addr + `DMA_CQE_MAGIC_OFF, `DMA_CQE_MAGIC);
                mem_wr16_le(cqe_addr + `DMA_CQE_DESC_LEN_OFF, `DMA_CQE_BYTES);
                mem_wr16_le(cqe_addr + `DMA_CQE_STATUS_OFF, {8'h0, status_code});
                mem_wr8(cqe_addr + `DMA_CQE_TC_OFF, {4'h0, traffic_class});
                mem_wr8(cqe_addr + `DMA_CQE_POLICY_OFF, {4'h0, policy});
                mem_wr16_le(cqe_addr + `DMA_CQE_FLAGS_OFF, cqe_flags);
                mem_wr8(cqe_addr + `DMA_CQE_CHANNEL_ID_OFF, ch[7:0]);
                mem_wr8(cqe_addr + `DMA_CQE_DIRECTION_OFF, `DMA_CQE_DIR_RX);
                mem_wr16_le(cqe_addr + `DMA_CQE_RESERVED0_OFF, 16'h0000);
                mem_wr16_le(cqe_addr + `DMA_CQE_FLOW_ID_OFF, flow_id);
                mem_wr16_le(cqe_addr + `DMA_CQE_MSG_ID_OFF, msg_id);
                mem_wr64_le(cqe_addr + `DMA_CQE_ADDR_OFF, {32'h0, payload_addr_l});
                mem_wr32_le(cqe_addr + `DMA_CQE_LENGTH_OFF, payload_len);
                mem_wr32_le(cqe_addr + `DMA_CQE_ALEN_OFF, aligned_len);
                mem_wr64_le(cqe_addr + `DMA_CQE_TS_OFF, timestamp);
                mem_wr32_le(cqe_addr + `DMA_CQE_FRAME_SEQ_OFF, frame_seq);
                mem_wr32_le(cqe_addr + `DMA_CQE_SAMPLE_CNT_L_OFF, sample_count);
                mem_wr32_le(cqe_addr + `DMA_CQE_SAMPLE_CNT_H_OFF, 32'h0);
                mem_wr16_le(cqe_addr + `DMA_CQE_DROP_CNT_OFF, 16'h0);
                mem_wr16_le(cqe_addr + `DMA_CQE_OVF_CNT_OFF, 16'h0);
                mem_wr32_le(cqe_addr + `DMA_CQE_OWNER_OFF, 32'h0000_0001);
                cq_wr_ptr = next_ptr;
                irq_status[`DMA_IRQ_RX_COMPLETION] = 1'b1;
            end
        end
    end
endtask

task ref_reset;
    integer ch;
    begin
        global_ctrl = 32'h0;
        global_status_sticky = 32'h0;
        irq_status = 32'h0;
        irq_mask = 32'h0;
        cq_base_l = 32'h0;
        cq_base_h = 32'h0;
        cq_size = 32'h0;
        cq_wr_ptr = 32'h0;
        cq_rd_ptr = 32'h0;
        intr_coal_cnt = 32'h1;
        intr_coal_timer = 32'h0;
        global_drop_cnt = 32'h0;
        global_err_cnt = 32'h0;
        debug_state = 32'h0;
        for (ch = 0; ch < `DMA_MAX_CH; ch = ch + 1) begin
            rx_ctrl[ch] = 32'h0;
            rx_cfg[ch] = 32'h0;
            rx_base_l[ch] = 32'h0;
            rx_base_h[ch] = 32'h0;
            rx_size[ch] = 32'h0;
            rx_max_len[ch] = 32'h0;
            rx_wr_ptr[ch] = 32'h0;
            rx_rd_ptr[ch] = 32'h0;
            rx_used[ch] = 32'h0;
            rx_high_wm[ch] = 32'h0;
            rx_low_wm[ch] = 32'h0;
            rx_status[ch] = 32'h1;
            rx_frame_cnt[ch] = 32'h0;
            rx_drop_cnt[ch] = 32'h0;
            rx_err_cnt[ch] = 32'h0;
            rx_user[ch] = 32'h0;
        end
    end
endtask

task ref_write_reg;
    input [31:0] addr;
    input [31:0] data;
    input [3:0] strb;
    integer ch;
    reg [11:0] off;
    reg [11:0] ch_off;
    reg protect_busy;
    reg [31:0] release_delta;
    begin
        off = addr[11:0];
        if (off < `DMA_TX_CH_BASE) begin
            case (off)
            `DMA_REG_GLOBAL_CTRL: begin
                if (data[`DMA_GCTRL_SOFT_RESET])
                    ref_reset();
                else begin
                    global_ctrl = (global_ctrl & 32'hffff_fc00) | (data & 32'h0000_001b);
                    if (data[`DMA_GCTRL_CLR_STATUS])
                        global_status_sticky = 32'h0;
                end
            end
            `DMA_REG_IRQ_STATUS: irq_status = irq_status & ~data;
            `DMA_REG_IRQ_MASK: irq_mask = data;
            `DMA_REG_CQ_BASE_L: cq_base_l = data;
            `DMA_REG_CQ_BASE_H: cq_base_h = data;
            `DMA_REG_CQ_SIZE: cq_size = data;
            `DMA_REG_CQ_RD_PTR: cq_rd_ptr = data;
            `DMA_REG_INTR_COAL_CNT: intr_coal_cnt = data;
            `DMA_REG_INTR_COAL_TMR: intr_coal_timer = data;
            `DMA_REG_SOFT_RESET: if (data[0]) ref_reset();
            default: ;
            endcase
        end else if ((off >= `DMA_RX_CH_BASE) && (off < (`DMA_RX_CH_BASE + (`DMA_MAX_CH * `DMA_CH_STRIDE)))) begin
            ch = (off - `DMA_RX_CH_BASE) >> 6;
            ch_off = off - `DMA_RX_CH_BASE - (ch << 6);
            protect_busy = rx_ctrl[ch][`DMA_RX_CTRL_ENABLE];
            case (ch_off)
            `DMA_CH_CTRL: begin
                if (data[`DMA_RX_CTRL_SOFT_RST]) begin
                    rx_wr_ptr[ch] = 32'h0;
                    rx_rd_ptr[ch] = 32'h0;
                    rx_status[ch] = 32'h1;
                end
                if (data[`DMA_RX_CTRL_CLR_STAT])
                    rx_status[ch] = make_status(ch, `DMA_ST_OK);
                rx_ctrl[ch] = (rx_ctrl[ch] & 32'hffff_fcc2) | (data & 32'h00ff_0c5d);
                rx_status[ch][`DMA_RX_STATUS_ENABLED] = rx_ctrl[ch][`DMA_RX_CTRL_ENABLE];
            end
            `DMA_CH_CFG: if (!protect_busy) rx_cfg[ch] = data;
            `DMA_CH_BASE_L: if (!protect_busy) rx_base_l[ch] = data;
            `DMA_CH_BASE_H: if (!protect_busy) rx_base_h[ch] = data;
            `DMA_CH_SIZE: if (!protect_busy) rx_size[ch] = data;
            `DMA_CH_MAX_LEN: if (!protect_busy) rx_max_len[ch] = data;
            `DMA_RX_CH_RD_PTR: begin
                if ((rx_size[ch] == 0) || (data >= rx_size[ch]) || (data[5:0] != 6'h0)) begin
                    rx_status[ch] = make_status(ch, `DMA_ST_RD_PTR_ERR);
                    rx_err_cnt[ch] = rx_err_cnt[ch] + 1;
                    global_err_cnt = global_err_cnt + 1;
                end else begin
                    if (data >= rx_rd_ptr[ch])
                        release_delta = data - rx_rd_ptr[ch];
                    else
                        release_delta = rx_size[ch] - rx_rd_ptr[ch] + data;
                    if (release_delta > rx_used[ch]) begin
                        rx_status[ch] = make_status(ch, `DMA_ST_RD_PTR_ERR);
                        rx_err_cnt[ch] = rx_err_cnt[ch] + 1;
                        global_err_cnt = global_err_cnt + 1;
                    end else begin
                        rx_rd_ptr[ch] = data;
                        rx_used[ch] = rx_used[ch] - release_delta;
                    end
                end
            end
            `DMA_RX_CH_HIGH_WM: rx_high_wm[ch] = data;
            `DMA_RX_CH_LOW_WM: rx_low_wm[ch] = data;
            `DMA_CH_USER: if (!protect_busy) rx_user[ch] = data;
            default: ;
            endcase
        end
    end
endtask

task ref_read_reg;
    input [31:0] addr;
    output [31:0] data;
    integer ch;
    reg [11:0] off;
    reg [11:0] ch_off;
    reg [31:0] feature_status;
    reg [31:0] global_status;
    begin
        off = addr[11:0];
        feature_status = 32'h0;
        feature_status[`DMA_FEATURE_RX] = 1'b1;
        feature_status[`DMA_FEATURE_TX] = 1'b1;
        feature_status[`DMA_FEATURE_UFC] = 1'b1;
        feature_status[`DMA_FEATURE_DESC_Q] = 1'b1;
        feature_status[`DMA_FEATURE_MULTI_OUT] = ((`DMA_TX_RD_MAX_OUTSTANDING > 1) || (`DMA_RX_WR_MAX_OUTSTANDING > 1));
        feature_status[`DMA_FEATURE_PER_CH_FIFO] = 1'b1;
        feature_status[`DMA_FEATURE_FC_PER_CH_INGRESS] = 1'b1;
        feature_status[`DMA_FEATURE_FC_DDR_RING] = 1'b1;
        feature_status[`DMA_FEATURE_SPLIT_FRAME_WRITE] = 1'b0;
        global_status = global_status_sticky;
        global_status[0] = 1'b1;
        global_status[6] = |(irq_status & irq_mask);
        data = 32'h0;
        if (off < `DMA_TX_CH_BASE) begin
            case (off)
            `DMA_REG_IP_ID: data = `DMA_IP_ID;
            `DMA_REG_VERSION: data = `DMA_VERSION;
            `DMA_REG_GLOBAL_CTRL: data = global_ctrl;
            `DMA_REG_GLOBAL_STATUS: data = global_status;
            `DMA_REG_IRQ_STATUS: data = irq_status;
            `DMA_REG_IRQ_MASK: data = irq_mask;
            `DMA_REG_RX_CH_NUM: data = `DMA_RX_CH_NUM;
            `DMA_REG_TX_CH_NUM: data = `DMA_TX_CH_NUM;
            `DMA_REG_CQ_BASE_L: data = cq_base_l;
            `DMA_REG_CQ_BASE_H: data = cq_base_h;
            `DMA_REG_CQ_SIZE: data = cq_size;
            `DMA_REG_CQ_WR_PTR: data = cq_wr_ptr;
            `DMA_REG_CQ_RD_PTR: data = cq_rd_ptr;
            `DMA_REG_INTR_COAL_CNT: data = intr_coal_cnt;
            `DMA_REG_INTR_COAL_TMR: data = intr_coal_timer;
            `DMA_REG_DROP_CNT: data = global_drop_cnt;
            `DMA_REG_ERR_CNT: data = global_err_cnt;
            `DMA_REG_DEBUG_STATE: data = debug_state;
            `DMA_REG_FEATURE: data = feature_status;
            default: data = 32'h0;
            endcase
        end else if ((off >= `DMA_RX_CH_BASE) && (off < (`DMA_RX_CH_BASE + (`DMA_MAX_CH * `DMA_CH_STRIDE)))) begin
            ch = (off - `DMA_RX_CH_BASE) >> 6;
            ch_off = off - `DMA_RX_CH_BASE - (ch << 6);
            case (ch_off)
            `DMA_CH_CTRL: data = rx_ctrl[ch];
            `DMA_CH_CFG: data = rx_cfg[ch];
            `DMA_CH_BASE_L: data = rx_base_l[ch];
            `DMA_CH_BASE_H: data = rx_base_h[ch];
            `DMA_CH_SIZE: data = rx_size[ch];
            `DMA_CH_MAX_LEN: data = rx_max_len[ch];
            `DMA_RX_CH_WR_PTR: data = rx_wr_ptr[ch];
            `DMA_RX_CH_RD_PTR: data = rx_rd_ptr[ch];
            `DMA_CH_USED: data = rx_used[ch];
            `DMA_RX_CH_HIGH_WM: data = rx_high_wm[ch];
            `DMA_RX_CH_LOW_WM: data = rx_low_wm[ch];
            `DMA_CH_STATUS: data = rx_status[ch];
            `DMA_CH_FRAME_CNT: data = rx_frame_cnt[ch];
            `DMA_CH_DROP_CNT: data = rx_drop_cnt[ch];
            `DMA_CH_ERR_CNT: data = rx_err_cnt[ch];
            `DMA_CH_USER: data = rx_user[ch];
            default: data = 32'h0;
            endcase
        end
    end
endtask

task ref_build_header;
    output [511:0] beat;
    input [7:0] traffic_class;
    input [15:0] flow_id;
    input [15:0] msg_id;
    input [31:0] payload_len;
    input [31:0] frame_seq;
    input [63:0] timestamp;
    input [63:0] sample_counter_start;
    input [31:0] sample_count;
    integer b;
    reg [31:0] crc;
    begin
        beat = 512'h0;
        beat[0*8 +: 32] = `DMA_FRAME_MAGIC;
        beat[4*8 +: 8] = 8'h07;
        beat[5*8 +: 8] = `DMA_HEADER_BYTES;
        beat[6*8 +: 8] = traffic_class;
        beat[7*8 +: 8] = 8'h0;
        beat[8*8 +: 16] = flow_id;
        beat[10*8 +: 16] = msg_id;
        beat[12*8 +: 32] = payload_len;
        beat[16*8 +: 32] = frame_seq;
        beat[20*8 +: 16] = 16'h0;
        beat[22*8 +: 8] = 8'h1;
        beat[23*8 +: 8] = 8'h0;
        beat[24*8 +: 64] = timestamp;
        beat[32*8 +: 64] = sample_counter_start;
        beat[40*8 +: 32] = sample_count;
        beat[44*8 +: 32] = 32'h0;
        crc = header_crc32(beat);
        beat[48*8 +: 32] = crc;
    end
endtask

task ref_process_frame;
    input [511:0] header_beat;
    input [31:0] payload_src_addr;
    integer ch;
    integer found_ch;
    integer copy_i;
    reg [31:0] magic;
    reg [7:0] version;
    reg [7:0] header_len;
    reg [3:0] traffic_class;
    reg [3:0] policy;
    reg [15:0] flow_id;
    reg [15:0] msg_id;
    reg [15:0] match_id;
    reg [31:0] payload_len;
    reg [31:0] frame_seq;
    reg [63:0] timestamp;
    reg [31:0] sample_count;
    reg [31:0] aligned_len;
    reg [31:0] dst_addr;
    reg [31:0] next_wr_ptr;
    reg [31:0] ddr_free;
    reg ddr_need_wrap;
    reg ddr_ok;
    reg [7:0] status_code;
    reg [7:0] traffic_class_byte;
    begin
        magic = hdr_u32(header_beat, 0);
        version = hdr_byte(header_beat, 4);
        header_len = hdr_byte(header_beat, 5);
        traffic_class_byte = hdr_byte(header_beat, 6);
        traffic_class = traffic_class_byte[3:0];
        flow_id = hdr_u16(header_beat, 8);
        msg_id = hdr_u16(header_beat, 10);
        payload_len = hdr_u32(header_beat, 12);
        frame_seq = hdr_u32(header_beat, 16);
        timestamp = hdr_u64(header_beat, 24);
        sample_count = hdr_u32(header_beat, 40);
        aligned_len = align64(payload_len);
        status_code = `DMA_ST_FRAME_DONE;

        if (!global_ctrl[`DMA_GCTRL_GLOBAL_EN] || !global_ctrl[`DMA_GCTRL_RX_EN]) begin
            $display("%t Warning: ref_process_frame ignored because RX is disabled", $time);
        end else if ((magic != `DMA_FRAME_MAGIC) || (version != 8'h07) ||
                     (header_len != `DMA_HEADER_BYTES) ||
                     (header_crc32(header_beat) != hdr_u32(header_beat, 48))) begin
            irq_status[`DMA_IRQ_HEADER_ERROR] = 1'b1;
            global_status_sticky[10] = 1'b1;
            global_err_cnt = global_err_cnt + 1;
        end else begin
            found_ch = -1;
            for (ch = 0; ch < `DMA_MAX_CH; ch = ch + 1) begin
                if (found_ch < 0 && rx_ctrl[ch][`DMA_RX_CTRL_ENABLE]) begin
                    match_id = (traffic_class == `DMA_TC_AUX) ? msg_id : flow_id;
                    if ((rx_cfg[ch][3:0] == traffic_class) && (rx_cfg[ch][31:16] == match_id))
                        found_ch = ch;
                end
            end

            if (found_ch < 0) begin
                irq_status[`DMA_IRQ_POLICY_REJECT] = 1'b1;
                global_err_cnt = global_err_cnt + 1;
            end else begin
                ch = found_ch;
                policy = rx_cfg[ch][7:4];
                if (!policy_supported(traffic_class, policy)) begin
                    status_code = `DMA_ST_POLICY_REJECT;
                    rx_status[ch][`DMA_RX_STATUS_POLICY] = 1'b1;
                    rx_err_cnt[ch] = rx_err_cnt[ch] + 1;
                    global_err_cnt = global_err_cnt + 1;
                    irq_status[`DMA_IRQ_POLICY_REJECT] = 1'b1;
                end else if ((rx_max_len[ch] != 0) && (payload_len > rx_max_len[ch])) begin
                    status_code = `DMA_ST_FRAME_TOO_BIG;
                    rx_status[ch][`DMA_RX_STATUS_DROP] = 1'b1;
                    rx_drop_cnt[ch] = rx_drop_cnt[ch] + 1;
                    global_drop_cnt = global_drop_cnt + 1;
                    irq_status[`DMA_IRQ_RX_OVERFLOW] = 1'b1;
                end else if (rx_ctrl[ch][`DMA_RX_CTRL_CPL_EN] && !ref_cq_has_space(1'b0)) begin
                    status_code = `DMA_ST_CQ_FULL;
                    rx_status[ch] = make_status(ch, status_code);
                    rx_status[ch][`DMA_RX_STATUS_CQ] = 1'b1;
                    rx_err_cnt[ch] = rx_err_cnt[ch] + 1;
                    global_err_cnt = global_err_cnt + 1;
                    irq_status[`DMA_IRQ_CQ_FULL] = 1'b1;
                end else begin
                    ddr_ok = 1'b1;
                    ddr_need_wrap = 1'b0;
                    ddr_free = 32'hffff_ffff;
                    dst_addr = rx_base_l[ch] + rx_wr_ptr[ch];
                    next_wr_ptr = rx_wr_ptr[ch] + aligned_len;

                    if (traffic_class == `DMA_TC_FC && rx_size[ch] != 0) begin
                        ddr_free = (rx_size[ch] > rx_used[ch]) ? (rx_size[ch] - rx_used[ch]) : 32'h0;
                        ddr_need_wrap = (rx_wr_ptr[ch] + aligned_len > rx_size[ch]);
                        if (aligned_len > ddr_free) begin
                            ddr_ok = 1'b0;
                            status_code = `DMA_ST_DDR_QUEUE_FULL;
                        end else if (!ddr_need_wrap) begin
                            next_wr_ptr = rx_wr_ptr[ch] + aligned_len;
                            if (next_wr_ptr == rx_size[ch])
                                next_wr_ptr = 32'h0;
                        end else if (aligned_len <= rx_rd_ptr[ch]) begin
                            dst_addr = rx_base_l[ch];
                            next_wr_ptr = aligned_len;
                        end else begin
                            ddr_ok = 1'b0;
                            status_code = `DMA_ST_WRAP_NOT_ALLOWED;
                        end
                    end else if ((rx_size[ch] != 0) && (rx_wr_ptr[ch] + aligned_len > rx_size[ch]) &&
                                 (policy != `DMA_RX_POL_RING_BUFFER)) begin
                        ddr_ok = 1'b0;
                        status_code = `DMA_ST_BUFFER_FULL;
                    end else if ((policy == `DMA_RX_POL_RING_BUFFER) && (rx_size[ch] != 0)) begin
                        next_wr_ptr = (rx_wr_ptr[ch] + aligned_len) % rx_size[ch];
                    end

                    if (!ddr_ok) begin
                    rx_status[ch][`DMA_RX_STATUS_OVF] = 1'b1;
                    rx_drop_cnt[ch] = rx_drop_cnt[ch] + 1;
                    global_drop_cnt = global_drop_cnt + 1;
                    irq_status[`DMA_IRQ_RX_OVERFLOW] = 1'b1;
                    end else begin
                    for (copy_i = 0; copy_i < payload_len; copy_i = copy_i + 1)
                        mem_wr8(dst_addr + copy_i, `DMA_PKT_MEM_PATH[payload_src_addr + copy_i]);
                    rx_wr_ptr[ch] = next_wr_ptr;
                    rx_used[ch] = rx_used[ch] + aligned_len;
                    rx_frame_cnt[ch] = rx_frame_cnt[ch] + 1;
                    rx_status[ch] = make_status(ch, status_code);
                    if (rx_ctrl[ch][`DMA_RX_CTRL_CPL_EN])
                        write_cqe(ch, status_code, traffic_class, policy,
                                  ddr_need_wrap ? (16'h1 << `DMA_CQE_FLAG_WRAP_BEFORE) : 16'h0,
                                  flow_id, msg_id,
                                  dst_addr, payload_len, aligned_len, timestamp,
                                  frame_seq, sample_count);
                    end
                end
            end
        end
    end
endtask

task ref_mem_chk;
    input [31:0] start_addr;
    input [31:0] len;
    integer addr;
    begin
        for (addr = start_addr; addr < start_addr + len; addr = addr + 1) begin
            if (`DMA_SYS_MEM_PATH[addr] !== `DMA_REF_MEM_PATH[addr]) begin
                $display("%t Error: Memory mismatch addr=%08x sys=%02x ref=%02x",
                         $time, addr, `DMA_SYS_MEM_PATH[addr], `DMA_REF_MEM_PATH[addr]);
                $finish;
            end
        end
    end
endtask

endmodule
