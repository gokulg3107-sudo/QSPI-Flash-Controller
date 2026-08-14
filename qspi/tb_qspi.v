`timescale 1ns/100ps
`include "command_code.h"
module tb_qspi_flash_controller;

    reg         sclk;
    reg         presetn;
    reg         start;
    reg  [7:0]  cmd_reg;
    reg  [7:0]  width_reg;
    reg  [7:0]  len_reg;
    reg  [7:0]  data_reg;
    reg  [23:0] addr_reg;
    reg  [4:0]  dummy_reg;
    wire valid;
    wire [7:0] dout;
    wire cs;
    wire si, so, wp, sio3;

    integer pass_count;
    integer fail_count;
    reg     dout_bit0;

    qspi_flash_controller dut (
        .sclk      (sclk),
        .presetn   (presetn),
        .cmd_reg   (cmd_reg),
        .addr_reg  (addr_reg),
        .dummy_reg (dummy_reg),
        .width_reg (width_reg),
        .len_reg   (len_reg),
        .data_reg  (data_reg),
        .start     (start),
        .cs        (cs),
        .si        (si),
        .so        (so),
        .wp        (wp),
        .sio3      (sio3),
        .dout (dout),
        .valid(valid)
    );

    MX25U6432FM2I02 flash (
        .SCLK (sclk),
        .CS   (cs),
        .SI   (si),
        .SO   (so),
        .WP   (wp),
        .SIO3 (sio3)
    );

    initial sclk = 0;
    always #80 sclk = ~sclk;

    task write_reg(input [7:0] cmd, len, data, input [4:0] dummy_data, input [23:0] addr);
    begin
            cmd_reg   = cmd;
            len_reg   = len;
            data_reg  = data;
            dummy_reg = dummy_data;
            addr_reg  = addr;
            @(posedge sclk);
            #1 start = 1;
            @(posedge sclk);
            #1 start = 0;
            #200000;
    end
    endtask

    task poll_wip;
    begin
        dout_bit0 = 1;
        while (dout_bit0) begin
            write_reg(8'h05, 0, 0, 0, 0);   // RDSR1
            dout_bit0 = dout[0];
        end
    end
    endtask

    reg [7:0] expected_burst [0:19];
    integer   burst_idx;

    // samples dout on posedge sclk whenever valid is high, one full
    // clock period after the DUT drives it - avoids racing the DUT's
    // own posedge-triggered valid/dout update
    task check_fast_read_burst;
    begin
        burst_idx = 0;
        while (burst_idx < 20) begin
            @(posedge sclk);
            #1;
            if (valid) begin
                if (dout === expected_burst[burst_idx]) pass_count = pass_count + 1;
                else fail_count = fail_count + 1;
                $display("byte[%0d] dout=%h expected=%h at t=%0t", burst_idx, dout, expected_burst[burst_idx], $time);
                burst_idx = burst_idx + 1;
            end
        end
    end
    endtask

    integer i;
    initial begin
            pass_count = 0;
            fail_count = 0;

            start     = 0;
            cmd_reg   = 0;
            width_reg = 0;
            len_reg   = 0;
            data_reg  = 0;
            addr_reg  = 0;
            dummy_reg = 0;

            // Page Program (10 bytes, all 0x05 - single-reg stand-in
            // for FIFO repeats the same byte) at address 200-209,
            // rest of the sector erased -> 0xFF
            for (i = 0; i < 10; i = i + 1) expected_burst[i] = 8'h05;
            for (i = 10; i < 20; i = i + 1) expected_burst[i] = 8'hFF;

            presetn = 0;
            #200; presetn = 1;
            #800_000;   // tVSL power-up wait

            write_reg(8'h06, 0, 0, 0, 0);              // WREN
            write_reg(8'h05, 0, 0, 0, 0);               // RDSR1
            write_reg(8'h9f, 0, 0, 0, 0);               // RDID

            write_reg(8'h06, 0, 0, 0, 0);               // WREN
            write_reg(8'h20, 0, 0, 0, 2);               // Sector Erase
            poll_wip;

            write_reg(8'h06, 0, 0, 0, 0);               // WREN
            write_reg(8'h02, 10, 8'h05, 0, 200);        // Page Program
            poll_wip;

            $display("Flash mem[200] = %h", flash.mxArray[flash.oriMAIN + 200]);
            $display("Flash mem[209] = %h", flash.mxArray[flash.oriMAIN + 209]);
            $display("Flash mem[210] = %h", flash.mxArray[flash.oriMAIN + 210]);

            // dummy_reg = 7 gives 8 real dummy cycles per the FSM's
            // 0-indexed compare convention (count 0..dummy_reg inclusive)
            cmd_reg   = 8'h0b;
            len_reg   = 20;
            dummy_reg = 8;
            addr_reg  = 200;
            @(posedge sclk);
            #1 start = 1;
            @(posedge sclk);
            #1 start = 0;
            check_fast_read_burst;

            #2000;
            $display("========================================");
            $display("TOTAL: pass=%0d fail=%0d", pass_count, fail_count);
            $display("========================================");
            $finish;
    end

    initial begin
        $dumpfile("wave.vcd");
        $dumpvars(0, tb_qspi_flash_controller);
    end
endmodule
