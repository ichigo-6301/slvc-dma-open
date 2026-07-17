`timescale 1ns/1ps
`include "dma_defs.vh"

module tb;

reg clk;
reg rstn;
reg soft_reset;
reg [511:0] s_axis_tdata;
reg [63:0] s_axis_tkeep;
reg s_axis_tvalid;
wire s_axis_tready;
reg s_axis_tlast;
wire [511:0] m_axis_tdata;
wire m_axis_tvalid;
reg m_axis_tready;
wire stat_accept;
wire stat_drop;
wire [7:0] stat_drop_reason;

integer errors;
integer timeout;
integer output_count;
integer accept_count;
integer drop_count;
integer sequence_expected;
integer seed_state;
integer random_value;
integer seed_index;
integer packet_index;
integer total_packets;
reg [31:0] ready_lfsr;
reg [511:0] output_beats [0:31];
reg [7:0] packet_bytes [0:2047];

dma_udp_ipv4_to_shdr64_adapter u_dut (
    .clk(clk), .rstn(rstn), .soft_reset(soft_reset),
    .s_axis_tdata(s_axis_tdata), .s_axis_tkeep(s_axis_tkeep),
    .s_axis_tvalid(s_axis_tvalid), .s_axis_tready(s_axis_tready),
    .s_axis_tlast(s_axis_tlast),
    .m_axis_tdata(m_axis_tdata), .m_axis_tvalid(m_axis_tvalid),
    .m_axis_tready(m_axis_tready),
    .stat_accept(stat_accept), .stat_drop(stat_drop),
    .stat_drop_reason(stat_drop_reason)
);

initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
end

function [7:0] beat_byte;
    input [511:0] beat;
    input integer index;
    begin beat_byte = beat[index*8 +: 8]; end
endfunction

function [15:0] beat_u16;
    input [511:0] beat;
    input integer index;
    begin beat_u16 = {beat_byte(beat, index+1), beat_byte(beat, index)}; end
endfunction

function [31:0] beat_u32;
    input [511:0] beat;
    input integer index;
    begin
        beat_u32 = {beat_byte(beat,index+3), beat_byte(beat,index+2),
                    beat_byte(beat,index+1), beat_byte(beat,index)};
    end
endfunction

function [31:0] crc32_byte;
    input [31:0] crc_in;
    input [7:0] data;
    integer b;
    reg [31:0] c;
    begin
        c = crc_in ^ {24'h0,data};
        for (b=0;b<8;b=b+1)
            c = c[0] ? ((c>>1)^32'hEDB88320) : (c>>1);
        crc32_byte = c;
    end
endfunction

function [31:0] header_crc32;
    input [511:0] beat;
    integer i;
    reg [31:0] c;
    begin
        c=32'hffff_ffff;
        for(i=0;i<48;i=i+1) c=crc32_byte(c,beat_byte(beat,i));
        header_crc32=c^32'hffff_ffff;
    end
endfunction

task fail;
    input [1023:0] message;
    begin
        errors=errors+1;
        $display("[ERR] %0s seed_index=%0d packet=%0d @%0t",
                 message,seed_index,packet_index,$time);
    end
endtask

task build_packet;
    input integer payload_len;
    input [15:0] dst_port;
    input integer salt;
    output integer wire_len;
    integer i;
    integer ip_len;
    integer udp_len;
    begin
        ip_len=28+payload_len;
        udp_len=8+payload_len;
        wire_len=42+payload_len;
        if(wire_len<60) wire_len=60;
        for(i=0;i<2048;i=i+1) packet_bytes[i]=0;
        for(i=0;i<12;i=i+1) packet_bytes[i]=(8'h30+i+salt)&8'hff;
        packet_bytes[12]=8'h08; packet_bytes[13]=8'h00;
        packet_bytes[14]=8'h45; packet_bytes[15]=8'h00;
        packet_bytes[16]=(ip_len>>8)&8'hff; packet_bytes[17]=ip_len&8'hff;
        packet_bytes[18]=salt[15:8]; packet_bytes[19]=salt[7:0];
        packet_bytes[20]=8'h40; packet_bytes[21]=0;
        packet_bytes[22]=8'h40; packet_bytes[23]=8'h11;
        packet_bytes[26]=8'h0a; packet_bytes[29]=8'h01;
        packet_bytes[30]=8'h0a; packet_bytes[33]=8'h02;
        packet_bytes[34]=8'hc1; packet_bytes[35]=salt[7:0];
        packet_bytes[36]=dst_port[15:8]; packet_bytes[37]=dst_port[7:0];
        packet_bytes[38]=(udp_len>>8)&8'hff; packet_bytes[39]=udp_len&8'hff;
        for(i=0;i<payload_len;i=i+1)
            packet_bytes[42+i]=(i*29+salt*17+dst_port[7:0])&8'hff;
    end
endtask

task drive_packet;
    input integer wire_len;
    input integer allow_gaps;
    integer offset;
    integer lane;
    integer valid_bytes;
    integer gap;
    reg [511:0] beat;
    reg [63:0] keep;
    begin
        offset=0;
        while(offset<wire_len) begin
            if(allow_gaps) begin
                random_value=$random(seed_state);
                gap=(random_value&32'h7fffffff)%3;
                repeat(gap) @(negedge clk);
            end
            valid_bytes=wire_len-offset;
            if(valid_bytes>64) valid_bytes=64;
            beat=0; keep=0;
            for(lane=0;lane<valid_bytes;lane=lane+1) begin
                beat[lane*8 +: 8]=packet_bytes[offset+lane];
                keep[lane]=1'b1;
            end
            @(negedge clk);
            s_axis_tdata=beat; s_axis_tkeep=keep;
            s_axis_tlast=(offset+valid_bytes==wire_len);
            s_axis_tvalid=1'b1;
            timeout=0;
            while(!s_axis_tready && timeout<5000) begin
                timeout=timeout+1;
                @(negedge clk);
            end
            if(!s_axis_tready) fail("input ready timeout");
            @(negedge clk);
            s_axis_tvalid=0; s_axis_tdata=0; s_axis_tkeep=0; s_axis_tlast=0;
            offset=offset+valid_bytes;
        end
    end
endtask

task check_packet;
    input integer payload_len;
    input [15:0] dst_port;
    input integer expected_seq;
    input integer wire_len;
    integer expected_beats;
    integer accept_before;
    integer i;
    integer beat_index;
    integer lane;
    begin
        output_count=0;
        accept_before=accept_count;
        drive_packet(wire_len,(packet_index%5)!=0);
        expected_beats=1+((payload_len+63)/64);
        timeout=0;
        while(((accept_count==accept_before)||(output_count<expected_beats))&&timeout<10000) begin
            timeout=timeout+1;
            @(posedge clk);
        end
        if(timeout>=10000) fail("packet completion timeout");
        if(output_count!=expected_beats) fail("output beat count mismatch");
        if(beat_u32(output_beats[0],0)!==`DMA_FRAME_MAGIC) fail("magic mismatch");
        if(beat_u16(output_beats[0],8)!==dst_port) fail("flow id mismatch");
        if(beat_u32(output_beats[0],12)!==payload_len) fail("payload length mismatch");
        if(beat_u32(output_beats[0],16)!==expected_seq) fail("sequence mismatch");
        if(beat_u32(output_beats[0],48)!==header_crc32(output_beats[0])) fail("CRC mismatch");
        for(i=0;i<payload_len;i=i+1) begin
            beat_index=1+i/64; lane=i%64;
            if(beat_byte(output_beats[beat_index],lane)!==packet_bytes[42+i])
                fail("payload mismatch");
        end
        if(payload_len!=0 && (payload_len%64)!=0) begin
            beat_index=1+(payload_len-1)/64;
            for(lane=payload_len%64;lane<64;lane=lane+1)
                if(beat_byte(output_beats[beat_index],lane)!==0) fail("tail padding mismatch");
        end
    end
endtask

always @(posedge clk) begin
    if(!rstn||soft_reset) begin
        m_axis_tready<=0;
        ready_lfsr<=32'h1;
    end else begin
        ready_lfsr<={ready_lfsr[30:0],ready_lfsr[31]^ready_lfsr[21]^ready_lfsr[1]^ready_lfsr[0]};
        m_axis_tready<=|(ready_lfsr[2:0]);
    end
end

always @(posedge clk) begin
    if(rstn&&!soft_reset) begin
        if(m_axis_tvalid&&m_axis_tready) begin
            if(output_count<32) output_beats[output_count]<=m_axis_tdata;
            output_count<=output_count+1;
        end
        if(stat_accept) accept_count<=accept_count+1;
        if(stat_drop) begin
            drop_count<=drop_count+1;
            fail("valid random packet dropped");
        end
    end
end

reg [511:0] stalled_data_q;
reg stalled_valid_q;
always @(posedge clk) begin
    if(!rstn||soft_reset) stalled_valid_q<=0;
    else if(m_axis_tvalid&&!m_axis_tready) begin
        if(stalled_valid_q&&m_axis_tdata!==stalled_data_q) fail("output changed while stalled");
        stalled_data_q<=m_axis_tdata; stalled_valid_q<=1;
    end else stalled_valid_q<=0;
end

integer payload_len;
integer wire_len;
reg [15:0] dst_port;
initial begin
    rstn=0; soft_reset=0; s_axis_tdata=0; s_axis_tkeep=0;
    s_axis_tvalid=0; s_axis_tlast=0; m_axis_tready=0;
    errors=0; output_count=0; accept_count=0; drop_count=0;
    sequence_expected=0; total_packets=0; ready_lfsr=32'h1;
    repeat(5) @(posedge clk); rstn=1; repeat(2) @(posedge clk);

    for(seed_index=0;seed_index<4;seed_index=seed_index+1) begin
        case(seed_index)
            0: seed_state=32'h13579bdf;
            1: seed_state=32'h2468ace1;
            2: seed_state=32'h51a7c0de;
            default: seed_state=32'h6d2b79f5;
        endcase
        ready_lfsr=seed_state;
        for(packet_index=0;packet_index<100;packet_index=packet_index+1) begin
            random_value=$random(seed_state);
            payload_len=(random_value&32'h7fffffff)%1473;
            random_value=$random(seed_state);
            dst_port=16'h4000+((random_value&32'h7fffffff)%16'h3fff);
            build_packet(payload_len,dst_port,packet_index+seed_index*100,wire_len);
            check_packet(payload_len,dst_port,sequence_expected,wire_len);
            sequence_expected=sequence_expected+1;
            total_packets=total_packets+1;
        end
    end

    repeat(20) @(posedge clk);
    if(errors==0&&accept_count==400&&drop_count==0) begin
        $display("Errors: 0, Warnings: 0");
        $display("PASS tb_rtl_v33e20a105_udp_to_shdr_random seeds=13579bdf,2468ace1,51a7c0de,6d2b79f5 packets_per_seed=100 total=400");
    end else begin
        $display("Errors: %0d accepts=%0d drops=%0d",errors,accept_count,drop_count);
        $fatal(1,"tb_rtl_v33e20a105_udp_to_shdr_random failed");
    end
    $finish;
end

initial begin
    #20000000;
    $fatal(1,"tb_rtl_v33e20a105_udp_to_shdr_random timeout");
end

endmodule
