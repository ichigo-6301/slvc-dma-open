`timescale 1ns/1ps

// TX 读预取器把 AXI4 R channel 的 64-bit words 聚合成上层 payload beat。
// FIFO 与 reserved_beats 将 memory latency、多个 outstanding read 和 TX backpressure
// 隔离；AXI 事务仍按 4KB 边界规划，RRESP 错误会使当前输出段进入 flush/error 路径。
module dma_axi_read_prefetch #(
    parameter integer DATA_WIDTH = 64,
    parameter integer OUT_WIDTH = 512,
    parameter integer MAX_OUTSTANDING = 4,
    parameter integer FIFO_DEPTH_LOG2 = 4
)(
    input                       clk,
    input                       rstn,
    input                       soft_reset,

    input                       cmd_valid,
    output                      cmd_ready,
    input      [31:0]           cmd_addr,
    input      [31:0]           cmd_len_bytes,
    output reg                  cmd_done,
    output reg                  cmd_error,

    output reg [31:0]           m_axi_araddr,
    output reg [7:0]            m_axi_arlen,
    output     [2:0]            m_axi_arsize,
    output     [1:0]            m_axi_arburst,
    output reg                  m_axi_arvalid,
    input                       m_axi_arready,
    input      [DATA_WIDTH-1:0] m_axi_rdata,
    input      [1:0]            m_axi_rresp,
    input                       m_axi_rlast,
    input                       m_axi_rvalid,
    output                      m_axi_rready,

    output reg [OUT_WIDTH-1:0]  out_data,
    output reg                  out_valid,
    input                       out_ready,
    output reg                  out_last,

    output reg [7:0]            debug_outstanding_count,
    output reg [7:0]            debug_peak_outstanding,
    output reg [7:0]            debug_fifo_level
);

// WORDS_PER_OUT 描述一个输出 beat 需要的 64-bit word 数，pack_lane 只表示聚合位置。
localparam integer WORDS_PER_OUT = OUT_WIDTH / DATA_WIDTH;
localparam integer BYTES_PER_OUT = OUT_WIDTH / 8;
localparam integer FIFO_DEPTH = (1 << FIFO_DEPTH_LOG2);
localparam integer FIFO_AW = FIFO_DEPTH_LOG2;
localparam [FIFO_DEPTH_LOG2:0] FIFO_DEPTH_CONST = (1 << FIFO_DEPTH_LOG2);

(* ram_style = "distributed" *) reg [OUT_WIDTH-1:0] fifo_data [0:FIFO_DEPTH-1];
reg                 fifo_last [0:FIFO_DEPTH-1];
reg [FIFO_AW-1:0]   fifo_wr_ptr;
reg [FIFO_AW-1:0]   fifo_rd_ptr;
reg [FIFO_DEPTH_LOG2:0] fifo_count;
reg [FIFO_DEPTH_LOG2:0] reserved_beats;

reg                 active;
reg                 error_seen;
reg [31:0]          issue_addr;
reg [31:0]          issue_bytes_left;
reg [31:0]          total_words;
reg [31:0]          words_received;
reg [31:0]          words_remaining;
reg [2:0]           pack_lane;
reg [OUT_WIDTH-1:0] pack_data;
reg [7:0]           ar_words_reg;
reg [3:0]           ar_out_beats_reg;
reg [7:0]           outstanding_count;
reg                 flush_outputs;
reg                 ar_plan_valid_q;
reg [31:0]          ar_plan_addr_q;
reg [7:0]           ar_plan_words_q;
reg [3:0]           ar_plan_out_beats_q;
reg [31:0]          ar_plan_bytes_q;

reg [31:0]          burst_words_c;
reg [31:0]          burst_bytes_c;
reg [31:0]          beats_to_4k_c;
reg [31:0]          burst_out_beats_c;
wire                out_pop = out_valid && out_ready;
wire                fifo_has_data = (fifo_count != 0);
wire                can_load_output = !out_valid || out_ready;
wire                ar_handshake = m_axi_arvalid && m_axi_arready;
wire                r_handshake = m_axi_rvalid && m_axi_rready;
wire                fifo_write_commit = r_handshake && (m_axi_rresp == 2'b00) && !error_seen &&
                                        ((pack_lane == (WORDS_PER_OUT-1)) || (words_remaining <= 1));
wire                fifo_write_last = (words_remaining <= 1);
wire                r_last_handshake = r_handshake && m_axi_rlast;
wire                release_reserved_beat = fifo_write_commit && (reserved_beats != 0);
wire [FIFO_DEPTH_LOG2:0] fifo_total_reserved = fifo_count + reserved_beats;
wire [FIFO_DEPTH_LOG2:0] fifo_space_after_res = FIFO_DEPTH_CONST - fifo_total_reserved;
wire [OUT_WIDTH-1:0] fifo_rd_data = fifo_data[fifo_rd_ptr];
wire [FIFO_DEPTH_LOG2:0] ar_plan_out_beats_ext = ar_plan_out_beats_q;
wire [31:0]         beats_to_4k_fast_c = (32'd4096 - issue_addr[11:0]) >> 3;
wire                issue_more_than_one_out_c = (issue_bytes_left > BYTES_PER_OUT);
wire                boundary_more_than_one_out_c = (beats_to_4k_fast_c > WORDS_PER_OUT);
wire [3:0]          burst_out_beats_fast_c =
                        (issue_more_than_one_out_c && boundary_more_than_one_out_c) ? 4'd2 : 4'd1;
wire can_make_ar_plan = active && !error_seen && !flush_outputs &&
                        !ar_plan_valid_q && !m_axi_arvalid &&
                        (issue_bytes_left != 0) &&
                        (outstanding_count < MAX_OUTSTANDING);
wire can_issue_ar_plan = ar_plan_valid_q && !m_axi_arvalid &&
                         active && !error_seen && !flush_outputs &&
                         (outstanding_count < MAX_OUTSTANDING) &&
                         (fifo_space_after_res > ar_plan_out_beats_ext);

assign cmd_ready = !active && !out_valid && (fifo_count == 0) &&
                   !m_axi_arvalid && !ar_plan_valid_q;
assign m_axi_arsize = 3'd3;
assign m_axi_arburst = 2'b01;
assign m_axi_rready = active && (outstanding_count != 0);

function [OUT_WIDTH-1:0] merge_pack_word;
    input [OUT_WIDTH-1:0] base_data;
    input [2:0]           lane;
    input [DATA_WIDTH-1:0] word_data;
    reg [OUT_WIDTH-1:0] merged;
begin
    merged = base_data;
    case (lane)
    3'd0: merged[  0 +: DATA_WIDTH] = word_data;
    3'd1: merged[ 64 +: DATA_WIDTH] = word_data;
    3'd2: merged[128 +: DATA_WIDTH] = word_data;
    3'd3: merged[192 +: DATA_WIDTH] = word_data;
    3'd4: merged[256 +: DATA_WIDTH] = word_data;
    3'd5: merged[320 +: DATA_WIDTH] = word_data;
    3'd6: merged[384 +: DATA_WIDTH] = word_data;
    default: merged[448 +: DATA_WIDTH] = word_data;
    endcase
    merge_pack_word = merged;
end
endfunction

always @(*) begin
    burst_words_c = (issue_bytes_left + 32'd7) >> 3;
    if (burst_words_c > 32'd16)
        burst_words_c = 32'd16;
    beats_to_4k_c = (32'd4096 - issue_addr[11:0]) >> 3;
    if (beats_to_4k_c == 0)
        beats_to_4k_c = 32'd1;
    if (burst_words_c > beats_to_4k_c)
        burst_words_c = beats_to_4k_c;
    if (burst_words_c == 0)
        burst_words_c = 32'd1;
    burst_bytes_c = burst_words_c << 3;
    burst_out_beats_c = (burst_words_c + (WORDS_PER_OUT-1)) >> 3;
    if (burst_out_beats_c == 0)
        burst_out_beats_c = 32'd1;
end

integer i;
always @(posedge clk) begin
    if (rstn && fifo_write_commit)
        fifo_data[fifo_wr_ptr] <= merge_pack_word(pack_data, pack_lane, m_axi_rdata);
end

always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        active <= 1'b0;
        cmd_done <= 1'b0;
        cmd_error <= 1'b0;
        m_axi_araddr <= 32'h0;
        m_axi_arlen <= 8'h0;
        m_axi_arvalid <= 1'b0;
        out_data <= {OUT_WIDTH{1'b0}};
        out_valid <= 1'b0;
        out_last <= 1'b0;
        fifo_wr_ptr <= {FIFO_AW{1'b0}};
        fifo_rd_ptr <= {FIFO_AW{1'b0}};
        fifo_count <= {(FIFO_DEPTH_LOG2+1){1'b0}};
        reserved_beats <= {(FIFO_DEPTH_LOG2+1){1'b0}};
        issue_addr <= 32'h0;
        issue_bytes_left <= 32'h0;
        total_words <= 32'h0;
        words_received <= 32'h0;
        words_remaining <= 32'h0;
        pack_lane <= 3'h0;
        pack_data <= {OUT_WIDTH{1'b0}};
        ar_words_reg <= 8'h0;
        ar_out_beats_reg <= 4'h0;
        outstanding_count <= 8'h0;
        error_seen <= 1'b0;
        flush_outputs <= 1'b0;
        ar_plan_valid_q <= 1'b0;
        ar_plan_addr_q <= 32'h0;
        ar_plan_words_q <= 8'h0;
        ar_plan_out_beats_q <= 4'h0;
        ar_plan_bytes_q <= 32'h0;
        debug_outstanding_count <= 8'h0;
        debug_peak_outstanding <= 8'h0;
        debug_fifo_level <= 8'h0;
        for (i = 0; i < FIFO_DEPTH; i = i + 1) begin
            fifo_last[i] <= 1'b0;
        end
    end else if (soft_reset) begin
        active <= 1'b0;
        cmd_done <= 1'b0;
        cmd_error <= 1'b0;
        m_axi_araddr <= 32'h0;
        m_axi_arlen <= 8'h0;
        m_axi_arvalid <= 1'b0;
        out_data <= {OUT_WIDTH{1'b0}};
        out_valid <= 1'b0;
        out_last <= 1'b0;
        fifo_wr_ptr <= {FIFO_AW{1'b0}};
        fifo_rd_ptr <= {FIFO_AW{1'b0}};
        fifo_count <= {(FIFO_DEPTH_LOG2+1){1'b0}};
        reserved_beats <= {(FIFO_DEPTH_LOG2+1){1'b0}};
        issue_addr <= 32'h0;
        issue_bytes_left <= 32'h0;
        total_words <= 32'h0;
        words_received <= 32'h0;
        words_remaining <= 32'h0;
        pack_lane <= 3'h0;
        pack_data <= {OUT_WIDTH{1'b0}};
        ar_words_reg <= 8'h0;
        ar_out_beats_reg <= 4'h0;
        outstanding_count <= 8'h0;
        error_seen <= 1'b0;
        flush_outputs <= 1'b0;
        ar_plan_valid_q <= 1'b0;
        ar_plan_addr_q <= 32'h0;
        ar_plan_words_q <= 8'h0;
        ar_plan_out_beats_q <= 4'h0;
        ar_plan_bytes_q <= 32'h0;
        debug_outstanding_count <= 8'h0;
        debug_peak_outstanding <= 8'h0;
        debug_fifo_level <= 8'h0;
        for (i = 0; i < FIFO_DEPTH; i = i + 1) begin
            fifo_last[i] <= 1'b0;
        end
    end else begin
        cmd_done <= 1'b0;
        cmd_error <= 1'b0;
        debug_fifo_level <= fifo_count;

        if (cmd_valid && cmd_ready) begin
            active <= 1'b1;
            error_seen <= 1'b0;
            flush_outputs <= 1'b0;
            issue_addr <= cmd_addr;
            issue_bytes_left <= cmd_len_bytes;
            total_words <= (cmd_len_bytes + 32'd7) >> 3;
            words_received <= 32'h0;
            words_remaining <= (cmd_len_bytes + 32'd7) >> 3;
            pack_lane <= 3'h0;
            pack_data <= {OUT_WIDTH{1'b0}};
            outstanding_count <= 8'h0;
            debug_outstanding_count <= 8'h0;
            debug_peak_outstanding <= 8'h0;
            reserved_beats <= {(FIFO_DEPTH_LOG2+1){1'b0}};
            ar_plan_valid_q <= 1'b0;
            ar_plan_addr_q <= 32'h0;
            ar_plan_words_q <= 8'h0;
            ar_plan_out_beats_q <= 4'h0;
            ar_plan_bytes_q <= 32'h0;
        end

        if (out_pop) begin
            out_valid <= 1'b0;
            out_last <= 1'b0;
        end

        if (flush_outputs) begin
            out_valid <= 1'b0;
            out_last <= 1'b0;
            fifo_count <= {(FIFO_DEPTH_LOG2+1){1'b0}};
            fifo_wr_ptr <= {FIFO_AW{1'b0}};
            fifo_rd_ptr <= {FIFO_AW{1'b0}};
            ar_plan_valid_q <= 1'b0;
        end else if (can_load_output && fifo_has_data) begin
            out_data <= fifo_rd_data;
            out_last <= fifo_last[fifo_rd_ptr];
            out_valid <= 1'b1;
            fifo_rd_ptr <= fifo_rd_ptr + 1'b1;
            fifo_count <= fifo_count - 1'b1;
        end

        if (can_make_ar_plan) begin
            ar_plan_valid_q <= 1'b1;
            ar_plan_addr_q <= issue_addr;
            ar_plan_words_q <= burst_words_c[7:0];
            ar_plan_out_beats_q <= burst_out_beats_fast_c;
            ar_plan_bytes_q <= burst_bytes_c;
        end

        if (can_issue_ar_plan) begin
            m_axi_araddr <= ar_plan_addr_q;
            m_axi_arlen <= ar_plan_words_q - 1'b1;
            m_axi_arvalid <= 1'b1;
            ar_words_reg <= ar_plan_words_q;
            ar_out_beats_reg <= ar_plan_out_beats_q;
            ar_plan_valid_q <= 1'b0;
        end

        if (ar_handshake) begin
            m_axi_arvalid <= 1'b0;
            issue_addr <= issue_addr + (ar_words_reg << 3);
            if (issue_bytes_left > (ar_words_reg << 3))
                issue_bytes_left <= issue_bytes_left - (ar_words_reg << 3);
            else
                issue_bytes_left <= 32'h0;
        end

        if (r_handshake) begin
            if (m_axi_rresp != 2'b00) begin
                error_seen <= 1'b1;
                flush_outputs <= 1'b1;
                fifo_count <= {(FIFO_DEPTH_LOG2+1){1'b0}};
                reserved_beats <= {(FIFO_DEPTH_LOG2+1){1'b0}};
                m_axi_arvalid <= 1'b0;
                ar_plan_valid_q <= 1'b0;
            end else if (!error_seen) begin
                case (pack_lane)
                3'd0: pack_data[  0 +: DATA_WIDTH] <= m_axi_rdata;
                3'd1: pack_data[ 64 +: DATA_WIDTH] <= m_axi_rdata;
                3'd2: pack_data[128 +: DATA_WIDTH] <= m_axi_rdata;
                3'd3: pack_data[192 +: DATA_WIDTH] <= m_axi_rdata;
                3'd4: pack_data[256 +: DATA_WIDTH] <= m_axi_rdata;
                3'd5: pack_data[320 +: DATA_WIDTH] <= m_axi_rdata;
                3'd6: pack_data[384 +: DATA_WIDTH] <= m_axi_rdata;
                default: pack_data[448 +: DATA_WIDTH] <= m_axi_rdata;
                endcase
                words_received <= words_received + 1'b1;
                if (words_remaining != 0)
                    words_remaining <= words_remaining - 1'b1;
                if ((pack_lane == (WORDS_PER_OUT-1)) || (words_remaining <= 1)) begin
                    fifo_last[fifo_wr_ptr] <= fifo_write_last;
                    fifo_wr_ptr <= fifo_wr_ptr + 1'b1;
                    fifo_count <= fifo_count + 1'b1;
                    pack_lane <= 3'h0;
                    pack_data <= {OUT_WIDTH{1'b0}};
                end else begin
                    pack_lane <= pack_lane + 1'b1;
                end
            end

        end

        if (ar_handshake && !r_last_handshake) begin
            outstanding_count <= outstanding_count + 1'b1;
            debug_outstanding_count <= outstanding_count + 1'b1;
            if ((outstanding_count + 1'b1) > debug_peak_outstanding)
                debug_peak_outstanding <= outstanding_count + 1'b1;
        end else if (!ar_handshake && r_last_handshake) begin
            outstanding_count <= outstanding_count - 1'b1;
            debug_outstanding_count <= outstanding_count - 1'b1;
        end

        if (!(r_handshake && (m_axi_rresp != 2'b00))) begin
            case ({ar_handshake, release_reserved_beat})
            2'b10: reserved_beats <= reserved_beats + ar_out_beats_reg;
            2'b01: reserved_beats <= reserved_beats - 1'b1;
            2'b11: reserved_beats <= reserved_beats + ar_out_beats_reg - 1'b1;
            default: ;
            endcase
        end

        if (flush_outputs && (outstanding_count == 0) && !m_axi_rvalid) begin
            active <= 1'b0;
            flush_outputs <= 1'b0;
            cmd_done <= 1'b1;
            cmd_error <= 1'b1;
        end else if (active && !error_seen && (issue_bytes_left == 0) && !m_axi_arvalid &&
                     !ar_plan_valid_q && (outstanding_count == 0) && (words_remaining == 0) &&
                     (total_words != 0) && out_pop && out_last) begin
            active <= 1'b0;
            cmd_done <= 1'b1;
            cmd_error <= 1'b0;
        end
    end
end

endmodule
