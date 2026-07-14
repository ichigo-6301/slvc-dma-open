`timescale 1ns/1ps

module tb;
    localparam integer CH_NUM = 4;
    localparam integer CH_ID_W = 2;
    localparam integer BLOCK_NUM = 8;
    localparam integer BLOCK_AW = 3;
    localparam integer DATA_W = 512;
    localparam integer KEEP_W = 64;
    localparam integer META_DEPTH = 4;
    localparam integer META_AW = 2;
    localparam integer MAX_FRAME_BLOCKS = 4;

    reg clk = 1'b0;
    reg rstn = 1'b0;
    always #5 clk = ~clk;

    reg                  s_valid = 1'b0;
    wire                 s_ready;
    reg [CH_ID_W-1:0]    s_ch_id = {CH_ID_W{1'b0}};
    reg [DATA_W-1:0]     s_data = {DATA_W{1'b0}};
    reg [KEEP_W-1:0]     s_keep = {KEEP_W{1'b0}};
    reg                  s_last = 1'b0;
    reg                  s_drop_enable = 1'b0;
    reg                  s_no_drop = 1'b1;

    wire                 m_valid;
    reg                  m_ready = 1'b0;
    wire [CH_ID_W-1:0]   m_ch_id;
    wire [DATA_W-1:0]    m_data;
    wire [KEEP_W-1:0]    m_keep;
    wire                 m_last;

    wire [15:0] free_count;
    wire [15:0] alloc_count;
    wire [15:0] committed_frame_count;
    wire [15:0] dropped_frame_count;
    wire overflow_sticky;
    wire double_free_error;
    wire double_alloc_error;
    wire leak_check_error;
    wire commit_event_valid;
    wire [CH_ID_W-1:0] commit_event_ch;
    wire [31:0] commit_event_byte_count;
    wire drop_event_valid;
    wire [CH_ID_W-1:0] drop_event_ch;

    dma_frame_shared_pool #(
        .CH_NUM(CH_NUM),
        .CH_ID_W(CH_ID_W),
        .BLOCK_NUM(BLOCK_NUM),
        .BLOCK_AW(BLOCK_AW),
        .DATA_W(DATA_W),
        .KEEP_W(KEEP_W),
        .META_DEPTH(META_DEPTH),
        .META_AW(META_AW),
        .MAX_FRAME_BLOCKS(MAX_FRAME_BLOCKS),
        .DEBUG_OWNERSHIP(1)
    ) u_dut (
        .clk(clk),
        .rstn(rstn),
        .s_valid(s_valid),
        .s_ready(s_ready),
        .s_ch_id(s_ch_id),
        .s_data(s_data),
        .s_keep(s_keep),
        .s_last(s_last),
        .s_drop_enable(s_drop_enable),
        .s_no_drop(s_no_drop),
        .m_valid(m_valid),
        .m_ready(m_ready),
        .m_ch_id(m_ch_id),
        .m_data(m_data),
        .m_keep(m_keep),
        .m_last(m_last),
        .free_count(free_count),
        .alloc_count(alloc_count),
        .committed_frame_count(committed_frame_count),
        .dropped_frame_count(dropped_frame_count),
        .overflow_sticky(overflow_sticky),
        .double_free_error(double_free_error),
        .double_alloc_error(double_alloc_error),
        .leak_check_error(leak_check_error),
        .commit_event_valid(commit_event_valid),
        .commit_event_ch(commit_event_ch),
        .commit_event_byte_count(commit_event_byte_count),
        .drop_event_valid(drop_event_valid),
        .drop_event_ch(drop_event_ch)
    );

    function [511:0] make_data;
        input [7:0] ch;
        input [15:0] frame;
        input [15:0] beat;
        integer lane;
        begin
            make_data = 512'h0;
            for (lane = 0; lane < 16; lane = lane + 1)
                make_data[lane*32 +: 32] = {ch, frame[7:0], beat[7:0], lane[7:0]};
        end
    endfunction

    function [15:0] keep_count;
        input [63:0] keep;
        integer k;
        begin
            keep_count = 16'h0;
            for (k = 0; k < 64; k = k + 1)
                keep_count = keep_count + keep[k];
        end
    endfunction

    task fail;
        input [255:0] msg;
        begin
            $display("Error: %0s", msg);
            $finish;
        end
    endtask

    task expect_eq;
        input [31:0] got;
        input [31:0] exp;
        input [255:0] name;
        begin
            if (got !== exp) begin
                $display("Error: %0s expected %0d got %0d", name, exp, got);
                $finish;
            end
        end
    endtask

    task expect_clean;
        begin
            if (double_free_error || double_alloc_error || leak_check_error) begin
                $display("Error: debug flags double_free=%0b double_alloc=%0b leak=%0b",
                         double_free_error, double_alloc_error, leak_check_error);
                $finish;
            end
            if ((free_count + alloc_count) !== BLOCK_NUM[15:0]) begin
                $display("Error: conservation free=%0d alloc=%0d block_num=%0d",
                         free_count, alloc_count, BLOCK_NUM);
                $finish;
            end
        end
    endtask

    task wait_counts;
        input [15:0] exp_free;
        input [15:0] exp_alloc;
        input [255:0] name;
        integer guard;
        begin
            guard = 0;
            while (((free_count !== exp_free) || (alloc_count !== exp_alloc)) && guard < 200) begin
                @(posedge clk);
                guard = guard + 1;
            end
            if ((free_count !== exp_free) || (alloc_count !== exp_alloc)) begin
                $display("Error: %0s expected free=%0d alloc=%0d got free=%0d alloc=%0d",
                         name, exp_free, exp_alloc, free_count, alloc_count);
                $finish;
            end
            expect_clean();
        end
    endtask

    task reset_dut;
        begin
            s_valid <= 1'b0;
            s_ch_id <= {CH_ID_W{1'b0}};
            s_data <= {DATA_W{1'b0}};
            s_keep <= {KEEP_W{1'b0}};
            s_last <= 1'b0;
            s_drop_enable <= 1'b0;
            s_no_drop <= 1'b1;
            m_ready <= 1'b0;
            rstn <= 1'b0;
            repeat (8) @(posedge clk);
            rstn <= 1'b1;
            repeat (4) @(posedge clk);
            expect_eq(free_count, BLOCK_NUM, "free_count after reset");
            expect_eq(alloc_count, 0, "alloc_count after reset");
            expect_clean();
        end
    endtask

    task send_beat;
        input [CH_ID_W-1:0] ch;
        input [15:0] frame;
        input [15:0] beat;
        input last;
        input drop_enable;
        input no_drop;
        input [63:0] keep;
        integer guard;
        integer accepted;
        begin
            @(negedge clk);
            s_ch_id = ch;
            s_data = make_data({6'h0, ch}, frame, beat);
            s_keep = keep;
            s_last = last;
            s_drop_enable = drop_enable;
            s_no_drop = no_drop;
            s_valid = 1'b1;
            guard = 0;
            accepted = 0;
            while (!accepted && guard < 40) begin
                @(posedge clk);
                if (s_ready)
                    accepted = 1;
                else
                    guard = guard + 1;
            end
            if (!accepted) begin
                $display("Error: send_beat timed out ch=%0d frame=%0h beat=%0d last=%0b drop=%0b no_drop=%0b free=%0d alloc=%0d",
                         ch, frame, beat, last, drop_enable, no_drop, free_count, alloc_count);
                $finish;
            end
            @(negedge clk);
            s_valid = 1'b0;
            s_last = 1'b0;
            s_drop_enable = 1'b0;
            s_no_drop = 1'b1;
            s_keep = {KEEP_W{1'b0}};
            s_data = {DATA_W{1'b0}};
            repeat (1) @(posedge clk);
            expect_clean();
        end
    endtask

    task send_frame;
        input [CH_ID_W-1:0] ch;
        input [15:0] frame;
        input integer beats;
        integer b;
        begin
            for (b = 0; b < beats; b = b + 1)
                send_beat(ch, frame, b[15:0], (b == beats-1), 1'b0, 1'b1, {64{1'b1}});
        end
    endtask

    task drain_frame;
        input [CH_ID_W-1:0] exp_ch;
        input [15:0] frame;
        input integer beats;
        input [63:0] keep_last;
        integer b;
        integer guard;
        reg [63:0] exp_keep;
        reg [31:0] byte_sum;
        reg [15:0] free_before;
        begin
            byte_sum = 32'h0;
            for (b = 0; b < beats; b = b + 1) begin
                guard = 0;
                while (!m_valid && guard < 80) begin
                    @(posedge clk);
                    guard = guard + 1;
                end
                if (!m_valid)
                    fail("drain_frame timed out waiting for m_valid");
                exp_keep = (b == beats-1) ? keep_last : {64{1'b1}};
                if (m_ch_id !== exp_ch)
                    fail("m_ch_id mismatch");
                if (m_data !== make_data({6'h0, exp_ch}, frame, b[15:0]))
                    fail("m_data mismatch");
                if (m_keep !== exp_keep)
                    fail("m_keep mismatch");
                if (m_last !== (b == beats-1))
                    fail("m_last mismatch");
                byte_sum = byte_sum + keep_count(m_keep);
                free_before = free_count;
                m_ready <= 1'b1;
                @(posedge clk);
                m_ready <= 1'b0;
                guard = 0;
                while ((free_count !== (free_before + 16'd1)) && guard < 120) begin
                    @(posedge clk);
                    guard = guard + 1;
                end
                if (free_count !== (free_before + 16'd1))
                    fail("drain release timed out");
            end
            expect_clean();
            if (byte_sum !== (((beats-1) * 64) + keep_count(keep_last))) begin
                $display("Error: byte count mismatch got=%0d", byte_sum);
                $finish;
            end
        end
    endtask

    task test_reset_init;
        begin
            $display("E19_CASE T0 reset_init");
            reset_dut();
        end
    endtask

    task test_single_frame;
        begin
            $display("E19_CASE T1 single_frame");
            reset_dut();
            send_frame(2'd0, 16'h0101, 4);
            expect_eq(committed_frame_count, 1, "committed after T1 enqueue");
            drain_frame(2'd0, 16'h0101, 4, {64{1'b1}});
            expect_eq(free_count, BLOCK_NUM, "free_count after T1");
            expect_eq(alloc_count, 0, "alloc_count after T1");
        end
    endtask

    task test_back_to_back;
        begin
            $display("E19_CASE T2 back_to_back");
            reset_dut();
            send_frame(2'd1, 16'h0201, 1);
            send_frame(2'd1, 16'h0202, 1);
            send_frame(2'd1, 16'h0203, 1);
            expect_eq(committed_frame_count, 3, "committed after T2 enqueue");
            drain_frame(2'd1, 16'h0201, 1, {64{1'b1}});
            drain_frame(2'd1, 16'h0202, 1, {64{1'b1}});
            drain_frame(2'd1, 16'h0203, 1, {64{1'b1}});
            expect_eq(free_count, BLOCK_NUM, "free_count after T2");
        end
    endtask

    task test_multi_channel;
        begin
            $display("E19_CASE T3 multi_channel");
            reset_dut();
            send_frame(2'd0, 16'h0300, 2);
            send_frame(2'd1, 16'h0301, 2);
            send_frame(2'd2, 16'h0302, 1);
            drain_frame(2'd0, 16'h0300, 2, {64{1'b1}});
            drain_frame(2'd1, 16'h0301, 2, {64{1'b1}});
            drain_frame(2'd2, 16'h0302, 1, {64{1'b1}});
            expect_eq(free_count, BLOCK_NUM, "free_count after T3");
        end
    endtask

    task test_pool_full_nodrop;
        integer guard;
        begin
            $display("E19_CASE T4 pool_full_nodrop");
            reset_dut();
            send_beat(2'd0, 16'h0400, 0, 1'b0, 1'b0, 1'b1, {64{1'b1}});
            send_beat(2'd0, 16'h0400, 1, 1'b0, 1'b0, 1'b1, {64{1'b1}});
            send_beat(2'd0, 16'h0400, 2, 1'b0, 1'b0, 1'b1, {64{1'b1}});
            send_beat(2'd0, 16'h0400, 3, 1'b0, 1'b0, 1'b1, {64{1'b1}});
            send_beat(2'd1, 16'h0401, 0, 1'b0, 1'b0, 1'b1, {64{1'b1}});
            send_beat(2'd1, 16'h0401, 1, 1'b0, 1'b0, 1'b1, {64{1'b1}});
            send_beat(2'd1, 16'h0401, 2, 1'b0, 1'b0, 1'b1, {64{1'b1}});
            send_beat(2'd1, 16'h0401, 3, 1'b0, 1'b0, 1'b1, {64{1'b1}});
            expect_eq(free_count, 0, "free_count before no-drop backpressure");
            @(posedge clk);
            s_ch_id <= 2'd2;
            s_data <= make_data(8'd2, 16'h0402, 16'h0);
            s_keep <= {64{1'b1}};
            s_last <= 1'b0;
            s_drop_enable <= 1'b0;
            s_no_drop <= 1'b1;
            s_valid <= 1'b1;
            repeat (4) @(posedge clk);
            if (s_ready)
                fail("no-drop s_ready should stay low when pool is full");
            s_valid <= 1'b0;
            repeat (2) @(posedge clk);
            expect_eq(free_count, 0, "free_count after rejected no-drop beat");
            expect_eq(alloc_count, BLOCK_NUM, "alloc_count after rejected no-drop beat");
        end
    endtask

    task test_pool_full_drop;
        begin
            $display("E19_CASE T5 pool_full_drop");
            reset_dut();
            send_beat(2'd0, 16'h0500, 0, 1'b0, 1'b1, 1'b0, {64{1'b1}});
            send_beat(2'd0, 16'h0500, 1, 1'b0, 1'b1, 1'b0, {64{1'b1}});
            send_beat(2'd0, 16'h0500, 2, 1'b0, 1'b1, 1'b0, {64{1'b1}});
            send_beat(2'd1, 16'h0501, 0, 1'b0, 1'b0, 1'b1, {64{1'b1}});
            send_beat(2'd1, 16'h0501, 1, 1'b0, 1'b0, 1'b1, {64{1'b1}});
            send_beat(2'd1, 16'h0501, 2, 1'b0, 1'b0, 1'b1, {64{1'b1}});
            send_beat(2'd1, 16'h0501, 3, 1'b0, 1'b0, 1'b1, {64{1'b1}});
            send_beat(2'd2, 16'h0502, 0, 1'b0, 1'b0, 1'b1, {64{1'b1}});
            expect_eq(free_count, 0, "free_count before droppable partial drop");
            send_beat(2'd0, 16'h0500, 3, 1'b1, 1'b1, 1'b0, {64{1'b1}});
            wait_counts(16'd3, 16'd5, "partial release after T5");
            expect_eq(dropped_frame_count, 1, "dropped count after T5");
            expect_eq(committed_frame_count, 0, "committed count after T5");
            expect_eq(free_count, 3, "partial blocks released after T5");
            expect_clean();
        end
    endtask

    task test_oversized_drop;
        begin
            $display("E19_CASE T6 oversized_drop");
            reset_dut();
            send_beat(2'd0, 16'h0600, 0, 1'b0, 1'b1, 1'b0, {64{1'b1}});
            send_beat(2'd0, 16'h0600, 1, 1'b0, 1'b1, 1'b0, {64{1'b1}});
            send_beat(2'd0, 16'h0600, 2, 1'b0, 1'b1, 1'b0, {64{1'b1}});
            send_beat(2'd0, 16'h0600, 3, 1'b0, 1'b1, 1'b0, {64{1'b1}});
            send_beat(2'd0, 16'h0600, 4, 1'b1, 1'b1, 1'b0, {64{1'b1}});
            wait_counts(BLOCK_NUM[15:0], 16'd0, "oversized release after T6");
            expect_eq(dropped_frame_count, 1, "dropped count after oversized");
            expect_eq(free_count, BLOCK_NUM, "free_count after oversized");
            expect_eq(alloc_count, 0, "alloc_count after oversized");
            expect_eq(committed_frame_count, 0, "committed after oversized");
            if (!overflow_sticky)
                fail("overflow_sticky should set after oversized drop");
        end
    endtask

    task test_drain_stall;
        reg [511:0] hold_data;
        reg [63:0] hold_keep;
        reg hold_last;
        begin
            $display("E19_CASE T7 drain_stall");
            reset_dut();
            send_frame(2'd3, 16'h0700, 3);
            wait (m_valid);
            hold_data = m_data;
            hold_keep = m_keep;
            hold_last = m_last;
            m_ready <= 1'b0;
            repeat (5) begin
                @(posedge clk);
                if (!m_valid || m_data !== hold_data || m_keep !== hold_keep || m_last !== hold_last)
                    fail("m output changed while stalled");
            end
            drain_frame(2'd3, 16'h0700, 3, {64{1'b1}});
            expect_eq(free_count, BLOCK_NUM, "free_count after T7");
        end
    endtask

    task test_reset_recovery;
        begin
            $display("E19_CASE T8 reset_recovery");
            reset_dut();
            send_beat(2'd0, 16'h0800, 0, 1'b0, 1'b0, 1'b1, {64{1'b1}});
            send_beat(2'd0, 16'h0800, 1, 1'b0, 1'b0, 1'b1, {64{1'b1}});
            send_frame(2'd1, 16'h0801, 2);
            if (free_count == BLOCK_NUM)
                fail("expected allocated blocks before reset recovery");
            reset_dut();
            expect_eq(free_count, BLOCK_NUM, "free_count after reset recovery");
            expect_eq(alloc_count, 0, "alloc_count after reset recovery");
            expect_eq(committed_frame_count, 0, "committed after reset recovery");
            expect_eq(dropped_frame_count, 0, "dropped after reset recovery");
        end
    endtask

    initial begin
        test_reset_init();
        test_single_frame();
        test_back_to_back();
        test_multi_channel();
        test_pool_full_nodrop();
        test_pool_full_drop();
        test_oversized_drop();
        test_drain_stall();
        test_reset_recovery();
        $display("OK: dma RTL v33e19 shared frame pool test passed.");
        repeat (10) @(posedge clk);
        $finish;
    end
endmodule
