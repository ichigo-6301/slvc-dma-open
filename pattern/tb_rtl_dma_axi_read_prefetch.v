`timescale 1ns/1ps

module tb_rtl_dma_axi_read_prefetch;

localparam integer COMMANDS = 32;
localparam integer FRAME_BYTES = 4096;
localparam integer OUT_BEATS_PER_FRAME = FRAME_BYTES / 64;
localparam integer AR_QUEUE_DEPTH = 64;

reg clk = 1'b0;
reg rstn = 1'b0;
reg soft_reset = 1'b0;

reg cmd_valid = 1'b0;
wire cmd_ready;
reg [31:0] cmd_addr = 32'h0;
reg [31:0] cmd_len_bytes = 32'h0;
wire cmd_done;
wire cmd_error;

wire [31:0] m_axi_araddr;
wire [7:0] m_axi_arlen;
wire [2:0] m_axi_arsize;
wire [1:0] m_axi_arburst;
wire m_axi_arvalid;
reg m_axi_arready = 1'b0;
reg [63:0] m_axi_rdata = 64'h0;
reg [1:0] m_axi_rresp = 2'b00;
reg m_axi_rlast = 1'b0;
reg m_axi_rvalid = 1'b0;
wire m_axi_rready;

wire [511:0] out_data;
wire out_valid;
reg out_ready = 1'b0;
wire out_last;
wire [7:0] debug_outstanding_count;
wire [7:0] debug_peak_outstanding;
wire [7:0] debug_fifo_level;

reg [31:0] ar_addr_q [0:AR_QUEUE_DEPTH-1];
reg [8:0] ar_beats_q [0:AR_QUEUE_DEPTH-1];
integer ar_wr_ptr = 0;
integer ar_rd_ptr = 0;
integer ar_queue_count = 0;
reg [31:0] active_r_addr_q = 32'h0;
reg [8:0] active_r_beats_q = 9'h0;

integer cycle_count = 0;
integer errors = 0;
integer active_command = 0;
integer command_output_beats = 0;
integer total_output_beats = 0;
integer simultaneous_push_pop = 0;
integer fifo_write_wraps = 0;
integer fifo_read_wraps = 0;
integer lane;
reg [31:0] expected_address;

wire ar_fire = m_axi_arvalid && m_axi_arready;
wire r_fire = m_axi_rvalid && m_axi_rready;
wire r_burst_pop = r_fire && m_axi_rlast;

always #5 clk = ~clk;

function [63:0] memory_word;
    input [31:0] address;
    begin
        memory_word = {address ^ 32'ha5c3_7e19, address};
    end
endfunction

function [31:0] frame_base;
    input integer command_index;
    begin
        frame_base = 32'h0100_0000 + command_index * 32'h0000_2000;
    end
endfunction

task fail;
    input [8*160-1:0] message;
    begin
        $display("FAIL tb_rtl_dma_axi_read_prefetch: %0s", message);
        errors = errors + 1;
    end
endtask

dma_axi_read_prefetch #(
    .DATA_WIDTH(64),
    .OUT_WIDTH(512),
    .MAX_OUTSTANDING(4),
    .FIFO_DEPTH_LOG2(4)
) u_dut (
    .clk(clk),
    .rstn(rstn),
    .soft_reset(soft_reset),
    .cmd_valid(cmd_valid),
    .cmd_ready(cmd_ready),
    .cmd_addr(cmd_addr),
    .cmd_len_bytes(cmd_len_bytes),
    .cmd_done(cmd_done),
    .cmd_error(cmd_error),
    .m_axi_araddr(m_axi_araddr),
    .m_axi_arlen(m_axi_arlen),
    .m_axi_arsize(m_axi_arsize),
    .m_axi_arburst(m_axi_arburst),
    .m_axi_arvalid(m_axi_arvalid),
    .m_axi_arready(m_axi_arready),
    .m_axi_rdata(m_axi_rdata),
    .m_axi_rresp(m_axi_rresp),
    .m_axi_rlast(m_axi_rlast),
    .m_axi_rvalid(m_axi_rvalid),
    .m_axi_rready(m_axi_rready),
    .out_data(out_data),
    .out_valid(out_valid),
    .out_ready(out_ready),
    .out_last(out_last),
    .debug_outstanding_count(debug_outstanding_count),
    .debug_peak_outstanding(debug_peak_outstanding),
    .debug_fifo_level(debug_fifo_level)
);

// Deterministic output backpressure fills and drains the packed-beat FIFO.
always @(negedge clk or negedge rstn) begin
    if (!rstn) begin
        out_ready <= 1'b0;
        m_axi_arready <= 1'b0;
    end else begin
        out_ready <= ((cycle_count % 96) >= 32);
        m_axi_arready <= ((cycle_count % 11) != 3);
    end
end

// Ordered AXI read responder. Queue occupancy also has one next-state owner so
// the test model can independently stress simultaneous AR enqueue/R completion.
always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        ar_wr_ptr <= 0;
        ar_rd_ptr <= 0;
        ar_queue_count <= 0;
        active_r_addr_q <= 32'h0;
        active_r_beats_q <= 9'h0;
        m_axi_rdata <= 64'h0;
        m_axi_rresp <= 2'b00;
        m_axi_rlast <= 1'b0;
        m_axi_rvalid <= 1'b0;
    end else begin
        if (ar_fire) begin
            if (m_axi_arsize != 3'd3 || m_axi_arburst != 2'b01)
                fail("unexpected AXI AR geometry");
            if (ar_queue_count >= AR_QUEUE_DEPTH)
                fail("AXI read response queue overflow");
            ar_addr_q[ar_wr_ptr] <= m_axi_araddr;
            ar_beats_q[ar_wr_ptr] <= {1'b0, m_axi_arlen} + 1'b1;
            ar_wr_ptr <= (ar_wr_ptr + 1) % AR_QUEUE_DEPTH;
        end

        if (!m_axi_rvalid && (ar_queue_count != 0)) begin
            active_r_addr_q <= ar_addr_q[ar_rd_ptr];
            active_r_beats_q <= ar_beats_q[ar_rd_ptr];
            m_axi_rdata <= memory_word(ar_addr_q[ar_rd_ptr]);
            m_axi_rlast <= (ar_beats_q[ar_rd_ptr] == 1);
            m_axi_rvalid <= 1'b1;
        end else if (r_fire) begin
            if (active_r_beats_q == 0)
                fail("AXI responder consumed an empty burst");
            if (m_axi_rlast != (active_r_beats_q == 1))
                fail("AXI responder RLAST mismatch");
            if (m_axi_rlast) begin
                m_axi_rvalid <= 1'b0;
                m_axi_rlast <= 1'b0;
                active_r_beats_q <= 9'h0;
                ar_rd_ptr <= (ar_rd_ptr + 1) % AR_QUEUE_DEPTH;
            end else begin
                active_r_addr_q <= active_r_addr_q + 32'd8;
                active_r_beats_q <= active_r_beats_q - 1'b1;
                m_axi_rdata <= memory_word(active_r_addr_q + 32'd8);
                m_axi_rlast <= (active_r_beats_q == 2);
            end
        end

        case ({ar_fire, r_burst_pop})
        2'b10: ar_queue_count <= ar_queue_count + 1;
        2'b01: ar_queue_count <= ar_queue_count - 1;
        default: ;
        endcase
    end
end

always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        cycle_count <= 0;
        command_output_beats <= 0;
        total_output_beats <= 0;
        simultaneous_push_pop <= 0;
        fifo_write_wraps <= 0;
        fifo_read_wraps <= 0;
    end else begin
        cycle_count <= cycle_count + 1;
        if (u_dut.fifo_write_commit && u_dut.fifo_output_load)
            simultaneous_push_pop <= simultaneous_push_pop + 1;
        if (u_dut.fifo_write_commit &&
            (u_dut.fifo_wr_ptr == {4{1'b1}}))
            fifo_write_wraps <= fifo_write_wraps + 1;
        if (u_dut.fifo_output_load &&
            (u_dut.fifo_rd_ptr == {4{1'b1}}))
            fifo_read_wraps <= fifo_read_wraps + 1;
        if (u_dut.fifo_count > 16)
            fail("packed-beat FIFO occupancy exceeded depth");
        if (u_dut.outstanding_count > 4)
            fail("outstanding read count exceeded configured bound");

        if (out_valid && out_ready) begin
            expected_address = frame_base(active_command) +
                               command_output_beats * 64;
            for (lane = 0; lane < 8; lane = lane + 1) begin
                if (out_data[lane*64 +: 64] !==
                    memory_word(expected_address + lane * 8))
                    fail("packed output data mismatch");
            end
            if (out_last !=
                (command_output_beats == OUT_BEATS_PER_FRAME-1))
                fail("out_last was not exclusive to beat 64");
            command_output_beats <= command_output_beats + 1;
            total_output_beats <= total_output_beats + 1;
        end
    end
end

task run_command;
    input integer command_index;
    begin
        active_command = command_index;
        command_output_beats = 0;
        @(negedge clk);
        cmd_addr = frame_base(command_index);
        cmd_len_bytes = FRAME_BYTES;
        cmd_valid = 1'b1;
        while (!cmd_ready)
            @(negedge clk);
        @(negedge clk);
        cmd_valid = 1'b0;

        while (!cmd_done)
            @(posedge clk);
        @(negedge clk);
        if (cmd_error)
            fail("prefetch command returned error");
        if (command_output_beats != OUT_BEATS_PER_FRAME)
            fail("prefetch command did not emit exactly 64 beats");
        if (u_dut.fifo_count != 0 || out_valid ||
            (u_dut.outstanding_count != 0) || (ar_queue_count != 0))
            fail("prefetch command left queued state");
    end
endtask

integer command_index;
initial begin
    repeat (8) @(posedge clk);
    @(negedge clk);
    rstn = 1'b1;
    repeat (4) @(posedge clk);

    for (command_index = 0; command_index < COMMANDS;
         command_index = command_index + 1)
        run_command(command_index);

    if (total_output_beats != COMMANDS * OUT_BEATS_PER_FRAME)
        fail("total packed output beat count mismatch");
    if (simultaneous_push_pop == 0)
        fail("simultaneous FIFO push/pop was not exercised");
    if (fifo_write_wraps < COMMANDS || fifo_read_wraps < COMMANDS)
        fail("packed-beat FIFO pointers did not repeatedly wrap");
    if (debug_peak_outstanding != 4)
        fail("four outstanding AXI reads were not observed");

    $display("DMA_AXI_READ_PREFETCH_COVER commands=%0d simultaneous_push_pop=%0d write_wraps=%0d read_wraps=%0d peak_outstanding=%0d",
             COMMANDS, simultaneous_push_pop, fifo_write_wraps,
             fifo_read_wraps, debug_peak_outstanding);
    if (errors != 0)
        $fatal(1, "tb_rtl_dma_axi_read_prefetch failed errors=%0d", errors);
    $display("PASS tb_rtl_dma_axi_read_prefetch commands=%0d frame_bytes=%0d output_beats=%0d",
             COMMANDS, FRAME_BYTES, total_output_beats);
    $finish;
end

initial begin
    #5000000;
    $fatal(1, "tb_rtl_dma_axi_read_prefetch timeout");
end

endmodule
