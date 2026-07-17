`timescale 1ns/1ps
`include "dma_defs.vh"

module tb;

reg clk, rstn, soft_reset;
reg [511:0] s_axis_tdata;
reg [63:0] s_axis_tkeep;
reg s_axis_tvalid, s_axis_tlast;
wire s_axis_tready;
wire [511:0] m_axis_tdata;
wire m_axis_tvalid;
reg m_axis_tready;
wire stat_accept, stat_drop;
wire [7:0] stat_drop_reason;

integer errors, timeout, output_count, accept_count, drop_count;
integer expected_sequence, case_count, input_fire_count;
integer last_drop_reason;
integer drop_reason_count [0:255];
integer reason_index;
reg [7:0] packet_bytes [0:511];
reg [511:0] stalled_data_q;
reg stalled_valid_q;
reg [1023:0] scenario_name;

localparam integer EXPECTED_CASES   = 23;
localparam integer EXPECTED_DROPS   = 17;
localparam integer EXPECTED_ACCEPTS = 23;

localparam MODE_NORMAL=0;
localparam MODE_HEADER_SHORT=1;
localparam MODE_NONLAST_KEEP=2;
localparam MODE_LAST_NONCONTIG=3;
localparam MODE_TRUNCATED=4;

dma_udp_ipv4_to_shdr64_adapter u_dut(
    .clk(clk),.rstn(rstn),.soft_reset(soft_reset),
    .s_axis_tdata(s_axis_tdata),.s_axis_tkeep(s_axis_tkeep),
    .s_axis_tvalid(s_axis_tvalid),.s_axis_tready(s_axis_tready),
    .s_axis_tlast(s_axis_tlast),
    .m_axis_tdata(m_axis_tdata),.m_axis_tvalid(m_axis_tvalid),
    .m_axis_tready(m_axis_tready),
    .stat_accept(stat_accept),.stat_drop(stat_drop),
    .stat_drop_reason(stat_drop_reason)
);

initial begin clk=0; forever #5 clk=~clk; end

task fail;
    input [1023:0] msg;
    begin errors=errors+1; $display("[ERR] %0s @%0t",msg,$time); end
endtask

task set_scenario;
    input [1023:0] name;
    begin
        scenario_name=name;
        $display("SCENARIO %0s", name);
    end
endtask

task build_packet;
    input integer payload_len;
    output integer wire_len;
    integer i,ip_len,udp_len;
    begin
        ip_len=28+payload_len; udp_len=8+payload_len;
        wire_len=42+payload_len; if(wire_len<60) wire_len=60;
        for(i=0;i<512;i=i+1) packet_bytes[i]=0;
        for(i=0;i<12;i=i+1) packet_bytes[i]=8'h50+i;
        packet_bytes[12]=8'h08; packet_bytes[13]=8'h00;
        packet_bytes[14]=8'h45;
        packet_bytes[16]=(ip_len>>8)&8'hff; packet_bytes[17]=ip_len&8'hff;
        packet_bytes[20]=8'h40; packet_bytes[21]=0;
        packet_bytes[22]=8'h40; packet_bytes[23]=8'h11;
        packet_bytes[26]=8'h0a; packet_bytes[29]=1;
        packet_bytes[30]=8'h0a; packet_bytes[33]=2;
        packet_bytes[34]=8'h12; packet_bytes[35]=8'h34;
        packet_bytes[36]=8'h45; packet_bytes[37]=8'h67;
        packet_bytes[38]=(udp_len>>8)&8'hff; packet_bytes[39]=udp_len&8'hff;
        for(i=0;i<payload_len;i=i+1) packet_bytes[42+i]=(i*13+7)&8'hff;
    end
endtask

task drive_packet;
    input integer wire_len_in;
    input integer mode;
    integer wire_len,offset,lane,valid_bytes,input_before;
    reg [511:0] beat;
    reg [63:0] keep;
    begin
        wire_len=wire_len_in;
        if(mode==MODE_HEADER_SHORT) wire_len=30;
        if(mode==MODE_TRUNCATED) wire_len=60;
        offset=0;
        while(offset<wire_len) begin
            valid_bytes=wire_len-offset; if(valid_bytes>64) valid_bytes=64;
            beat=0; keep=0;
            for(lane=0;lane<valid_bytes;lane=lane+1) begin
                beat[lane*8 +: 8]=packet_bytes[offset+lane]; keep[lane]=1;
            end
            if(mode==MODE_NONLAST_KEEP && offset==0) keep[63]=0;
            if(mode==MODE_LAST_NONCONTIG && offset+valid_bytes==wire_len) begin
                keep[valid_bytes-2]=0; keep[valid_bytes]=1;
            end
            @(negedge clk);
            s_axis_tdata=beat; s_axis_tkeep=keep;
            s_axis_tlast=(offset+valid_bytes==wire_len); s_axis_tvalid=1;
            input_before=input_fire_count;
            timeout=0;
            while(input_fire_count==input_before&&timeout<2000) begin timeout=timeout+1; @(posedge clk); #1; end
            if(input_fire_count==input_before) fail("input handshake timeout");
            @(negedge clk);
            s_axis_tvalid=0; s_axis_tdata=0; s_axis_tkeep=0; s_axis_tlast=0;
            offset=offset+valid_bytes;
        end
    end
endtask

task wait_idle_ready;
    begin
        timeout=0;
        while(!s_axis_tready&&timeout<3000) begin timeout=timeout+1; @(posedge clk); end
        if(!s_axis_tready) fail("adapter did not recover to ready");
    end
endtask

task run_valid_recovery;
    integer wire_len,accept_before,drop_before;
    begin
        build_packet(65,wire_len);
        accept_before=accept_count; drop_before=drop_count;
        drive_packet(wire_len,MODE_NORMAL);
        timeout=0;
        while(accept_count==accept_before&&timeout<3000) begin timeout=timeout+1; @(posedge clk); end
        if(accept_count==accept_before) fail("recovery packet not accepted");
        if(drop_count!=drop_before) fail("recovery packet dropped");
        expected_sequence=expected_sequence+1;
    end
endtask

task expect_drop_and_recover;
    input integer wire_len;
    input integer mode;
    input [7:0] reason;
    integer drop_before,accept_before,output_before;
    begin
        drop_before=drop_count; accept_before=accept_count; output_before=output_count;
        drive_packet(wire_len,mode);
        timeout=0;
        while(drop_count==drop_before&&timeout<3000) begin timeout=timeout+1; @(posedge clk); end
        if(drop_count!=drop_before+1) fail("drop pulse count mismatch");
        if(last_drop_reason!==reason) fail("drop reason mismatch");
        wait_idle_ready();
        repeat(3) @(posedge clk);
        if(output_count!=output_before) fail("first-beat error produced output");
        if(accept_count!=accept_before) fail("invalid packet accepted");
        run_valid_recovery();
        case_count=case_count+1;
    end
endtask

task pulse_soft_reset;
    begin
        @(negedge clk); soft_reset=1;
        @(negedge clk); soft_reset=0;
        repeat(2) @(posedge clk);
    end
endtask

task send_first_beat_only;
    input integer payload_len;
    integer wire_len,lane,input_before;
    reg [511:0] beat;
    begin
        build_packet(payload_len,wire_len); beat=0;
        for(lane=0;lane<64;lane=lane+1) beat[lane*8 +: 8]=packet_bytes[lane];
        @(negedge clk); s_axis_tdata=beat; s_axis_tkeep=~64'h0;
        s_axis_tlast=0; s_axis_tvalid=1;
        input_before=input_fire_count;
        while(input_fire_count==input_before) begin @(posedge clk); #1; end
        @(negedge clk); s_axis_tvalid=0; s_axis_tdata=0; s_axis_tkeep=0;
    end
endtask

task run_stall_case;
    input integer payload_len;
    input integer target_beat;
    integer wire_len,accept_before,target_seen,i;
    reg [511:0] held;
    begin
        build_packet(payload_len,wire_len);
        accept_before=accept_count; target_seen=output_count+target_beat;
        fork
            drive_packet(wire_len,MODE_NORMAL);
            begin
                timeout=0;
                while(output_count<target_seen&&timeout<3000) begin timeout=timeout+1; @(negedge clk); end
                m_axis_tready=0;
                timeout=0;
                while(!m_axis_tvalid&&timeout<3000) begin timeout=timeout+1; @(posedge clk); end
                held=m_axis_tdata;
                for(i=0;i<5;i=i+1) begin
                    @(posedge clk);
                    if(!m_axis_tvalid||m_axis_tdata!==held) fail("stalled output not stable");
                end
                @(negedge clk); m_axis_tready=1;
            end
        join
        timeout=0;
        while(accept_count==accept_before&&timeout<3000) begin timeout=timeout+1; @(posedge clk); end
        if(accept_count==accept_before) fail("stall case did not complete");
        expected_sequence=expected_sequence+1;
        case_count=case_count+1;
    end
endtask

always @(posedge clk) begin
    if(rstn&&!soft_reset) begin
        if (s_axis_tvalid&&s_axis_tready)
            input_fire_count<=input_fire_count+1;
        if (u_dut.input_fire_w)
            $display("EVENT input scenario=%0s time=%0t state=%0d ethertype=%02x%02x version_ihl=%02x", scenario_name, $time, u_dut.state_q, s_axis_tdata[111:104], s_axis_tdata[103:96], s_axis_tdata[119:112]);
        if(m_axis_tvalid&&m_axis_tready) output_count<=output_count+1;
        if(stat_accept) begin
            accept_count<=accept_count+1;
            $display("EVENT accept scenario=%0s time=%0t state=%0d accepts=%0d drops=%0d outputs=%0d", scenario_name, $time, u_dut.state_q, accept_count+1, drop_count, output_count);
        end
        if(stat_drop) begin
            drop_count<=drop_count+1; last_drop_reason<=stat_drop_reason;
            drop_reason_count[stat_drop_reason]=drop_reason_count[stat_drop_reason]+1;
            $display("EVENT drop scenario=%0s time=%0t reason=0x%02x state=%0d accepts=%0d drops=%0d outputs=%0d", scenario_name, $time, stat_drop_reason, u_dut.state_q, accept_count, drop_count+1, output_count);
        end
        if (stat_accept && stat_drop)
            fail("packet produced accept and drop together");
    end
end

always @(posedge clk) begin
    if(!rstn||soft_reset) stalled_valid_q<=0;
    else if(m_axis_tvalid&&!m_axis_tready) begin
        if(stalled_valid_q&&m_axis_tdata!==stalled_data_q) fail("global stable assertion failed");
        stalled_data_q<=m_axis_tdata; stalled_valid_q<=1;
    end else stalled_valid_q<=0;
end

integer wire_len;
integer output_before;
initial begin
    rstn=0; soft_reset=0; s_axis_tdata=0; s_axis_tkeep=0;
    s_axis_tvalid=0; s_axis_tlast=0; m_axis_tready=1;
    errors=0; output_count=0; accept_count=0; drop_count=0;
    expected_sequence=0; case_count=0; input_fire_count=0; last_drop_reason=0; scenario_name="startup";
    for (reason_index=0; reason_index<256; reason_index=reason_index+1)
        drop_reason_count[reason_index]=0;
    repeat(5) @(posedge clk); rstn=1; repeat(2) @(posedge clk);

    set_scenario("non_ipv4_ethertype");
    build_packet(0,wire_len); packet_bytes[12]=8'h08; packet_bytes[13]=8'h06;
    expect_drop_and_recover(wire_len,MODE_NORMAL,8'h01);
    set_scenario("ipv6_ethertype");
    build_packet(0,wire_len); packet_bytes[12]=8'h86; packet_bytes[13]=8'hdd;
    expect_drop_and_recover(wire_len,MODE_NORMAL,8'h01);
    set_scenario("vlan_ethertype");
    build_packet(0,wire_len); packet_bytes[12]=8'h81; packet_bytes[13]=8'h00;
    expect_drop_and_recover(wire_len,MODE_NORMAL,8'h01);
    set_scenario("bad_ipv4_version");
    build_packet(0,wire_len); packet_bytes[14]=8'h55;
    expect_drop_and_recover(wire_len,MODE_NORMAL,8'h02);
    set_scenario("bad_ipv4_ihl");
    build_packet(0,wire_len); packet_bytes[14]=8'h46;
    expect_drop_and_recover(wire_len,MODE_NORMAL,8'h03);
    set_scenario("non_udp_protocol");
    build_packet(0,wire_len); packet_bytes[23]=8'h06;
    expect_drop_and_recover(wire_len,MODE_NORMAL,8'h04);
    set_scenario("fragment_offset");
    build_packet(0,wire_len); packet_bytes[20]=8'h40; packet_bytes[21]=8'h01;
    expect_drop_and_recover(wire_len,MODE_NORMAL,8'h05);
    set_scenario("more_fragments");
    build_packet(0,wire_len); packet_bytes[20]=8'h20; packet_bytes[21]=8'h00;
    expect_drop_and_recover(wire_len,MODE_NORMAL,8'h05);
    set_scenario("short_ip_total_length");
    build_packet(0,wire_len); packet_bytes[16]=0; packet_bytes[17]=8'd20;
    expect_drop_and_recover(wire_len,MODE_NORMAL,8'h06);
    set_scenario("udp_length_too_short");
    build_packet(0,wire_len); packet_bytes[38]=0; packet_bytes[39]=8'd7;
    expect_drop_and_recover(wire_len,MODE_NORMAL,8'h07);
    set_scenario("udp_exceeds_ip_payload");
    build_packet(0,wire_len); packet_bytes[38]=0; packet_bytes[39]=8'd16;
    expect_drop_and_recover(wire_len,MODE_NORMAL,8'h08);
    set_scenario("length_profile_mismatch");
    build_packet(0,wire_len); packet_bytes[16]=0; packet_bytes[17]=8'd40;
    expect_drop_and_recover(wire_len,MODE_NORMAL,8'h09);
    set_scenario("payload_too_large");
    build_packet(0,wire_len);
    packet_bytes[16]=8'h10; packet_bytes[17]=8'h1d;
    packet_bytes[38]=8'h10; packet_bytes[39]=8'h09;
    expect_drop_and_recover(wire_len,MODE_NORMAL,8'h0e);
    set_scenario("header_short");
    build_packet(0,wire_len);
    expect_drop_and_recover(wire_len,MODE_HEADER_SHORT,8'h0a);
    set_scenario("nonlast_partial_keep");
    build_packet(100,wire_len);
    expect_drop_and_recover(wire_len,MODE_NONLAST_KEEP,8'h0b);
    set_scenario("last_noncontiguous_keep");
    build_packet(0,wire_len);
    expect_drop_and_recover(wire_len,MODE_LAST_NONCONTIG,8'h0c);
    set_scenario("truncated_packet");
    build_packet(64,wire_len);
    expect_drop_and_recover(wire_len,MODE_TRUNCATED,8'h0d);

    set_scenario("idle_reset_recovery");
    pulse_soft_reset(); run_valid_recovery(); case_count=case_count+1;

    output_before=output_count;
    set_scenario("header_stage_reset");
    send_first_beat_only(128);
    repeat(2) @(posedge clk);
    pulse_soft_reset();
    if(m_axis_tvalid) fail("header-stage reset left output valid");
    if(output_count!=output_before) fail("header-stage reset leaked output");
    run_valid_recovery(); case_count=case_count+1;

    output_before=output_count;
    set_scenario("payload_stage_reset");
    send_first_beat_only(128);
    timeout=0;
    while(output_count==output_before&&timeout<1000) begin timeout=timeout+1; @(posedge clk); end
    pulse_soft_reset();
    if(m_axis_tvalid) fail("payload-stage reset left output valid");
    run_valid_recovery(); case_count=case_count+1;

    set_scenario("payload_stall");
    run_stall_case(65,0);
    set_scenario("header_stall");
    run_stall_case(128,1);
    set_scenario("tail_stall");
    run_stall_case(65,2);

    repeat(10) @(posedge clk);
    if (drop_reason_count[8'h01] != 3) fail("unexpected DROP_ETHERTYPE count");
    if (drop_reason_count[8'h02] != 1) fail("unexpected DROP_IPV4_VERSION count");
    if (drop_reason_count[8'h03] != 1) fail("unexpected DROP_IPV4_IHL count");
    if (drop_reason_count[8'h04] != 1) fail("unexpected DROP_IPV4_PROTOCOL count");
    if (drop_reason_count[8'h05] != 2) fail("unexpected DROP_IPV4_FRAGMENT count");
    if (drop_reason_count[8'h06] != 1) fail("unexpected DROP_IPV4_TOTAL_LENGTH count");
    if (drop_reason_count[8'h07] != 1) fail("unexpected DROP_UDP_LENGTH_MIN count");
    if (drop_reason_count[8'h08] != 1) fail("unexpected DROP_UDP_EXCEEDS_IP count");
    if (drop_reason_count[8'h09] != 1) fail("unexpected DROP_LENGTH_PROFILE count");
    if (drop_reason_count[8'h0a] != 1) fail("unexpected DROP_HEADER_SHORT count");
    if (drop_reason_count[8'h0b] != 1) fail("unexpected DROP_NONLAST_KEEP count");
    if (drop_reason_count[8'h0c] != 1) fail("unexpected DROP_LAST_KEEP count");
    if (drop_reason_count[8'h0d] != 1) fail("unexpected DROP_TRUNCATED count");
    if (drop_reason_count[8'h0e] != 1) fail("unexpected DROP_PAYLOAD_TOO_LARGE count");
    if(errors==0 && case_count==EXPECTED_CASES && drop_count==EXPECTED_DROPS && accept_count==EXPECTED_ACCEPTS) begin
        $display("Errors: 0, Warnings: 0");
        $display("PASS tb_rtl_v33e20a106_udp_to_shdr_error_matrix cases=%0d drops=%0d accepts=%0d",case_count,drop_count,accept_count);
    end else begin
        $display("Errors: %0d expected_cases=%0d actual_cases=%0d expected_drops=%0d actual_drops=%0d expected_accepts=%0d actual_accepts=%0d",errors,EXPECTED_CASES,case_count,EXPECTED_DROPS,drop_count,EXPECTED_ACCEPTS,accept_count);
        $fatal(1,"tb_rtl_v33e20a106_udp_to_shdr_error_matrix failed");
    end
    $finish;
end

initial begin #5000000; $fatal(1,"tb_rtl_v33e20a106_udp_to_shdr_error_matrix timeout"); end

endmodule
