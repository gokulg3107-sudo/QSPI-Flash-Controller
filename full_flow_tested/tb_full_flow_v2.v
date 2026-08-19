`timescale 1ns/100ps
`include "command_code.h"

module tb_top_cdc_fifo_integrated;

// ------------------------------------------------------------------
// Clocks / reset
// hclk/pclk = 50MHz (20ns), sclk = 12.5MHz = hclk/4 (80ns)
// ------------------------------------------------------------------
reg pclk;
reg sclk;
reg presetn;

initial pclk = 0;
always #10 pclk = ~pclk;   // 20ns period -> 50MHz

initial sclk = 0;
always #40 sclk = ~sclk;   // 80ns period -> 12.5MHz

// ------------------------------------------------------------------
// APB driver signals
// ------------------------------------------------------------------
reg        psel, penable, pwrite;
reg [31:0] paddr, pwdata;
wire       pready, pslverr;

// top-level monitor/debug ports
wire [7:0] cmd_reg_sync, len_reg_sync, read_output;
wire [23:0] addr_reg_sync;
wire [4:0] dummy_reg_sync;
wire start_toggle, start_out, busy_reg;
wire [7:0] rx_read_data;
wire qspi_busy_status, qspi_done_status;

// ------------------------------------------------------------------
// DUT
// ------------------------------------------------------------------
top_cdc_fifo_integrated dut (
    .sclk(sclk),
    .psel(psel), .penable(penable), .pclk(pclk), .presetn(presetn),
    .pwrite(pwrite), .paddr(paddr), .pwdata(pwdata),
    .pready(pready), .pslverr(pslverr),
    .cmd_reg_sync(cmd_reg_sync), .len_reg_sync(len_reg_sync),
    .dummy_reg_sync(dummy_reg_sync), .addr_reg_sync(addr_reg_sync),
    .start_toggle(start_toggle), .start_out(start_out), .busy_reg(busy_reg),
    .read_output(read_output),
    .rx_read_data(rx_read_data),
    .qspi_busy_status(qspi_busy_status), .qspi_done_status(qspi_done_status)
);

// ------------------------------------------------------------------
// Macronix flash model
// si/so/wp/sio3/cs are NOT top-level ports on dut, so we hook the
// flash model onto them via hierarchical reference into the DUT.
// If top_cdc_fifo_integrated ever gets these exposed as ports,
// swap these four lines for direct port connections.
// ------------------------------------------------------------------
MX25U6432FM2I02 flash_inst (
    .SCLK(sclk),
    .CS  (dut.cs),
    .SI  (dut.si),
    .SO  (dut.so),
    .WP  (dut.wp),
    .SIO3(dut.sio3)
);

// ------------------------------------------------------------------
// APB register offsets (paddr[2:0]), from command_code.h
// ------------------------------------------------------------------
localparam ADDR_CMD    = `command_code;
localparam ADDR_ADDR   = `address_bytes;
localparam ADDR_DUMMY  = `dummy_cycles_count;
localparam ADDR_LEN    = `length_of_data;
localparam ADDR_CTRL   = `control_signals;
localparam ADDR_TXFIFO = `write_fifo_data;

// ------------------------------------------------------------------
// APB write task
// setup phase (psel=1,penable=0) then access phase (psel=1,penable=1)
// ------------------------------------------------------------------
task apb_write(input [2:0] offset, input [31:0] data);
begin
    @(posedge pclk);
    #1;                 // avoid racing apb_slave's own posedge-triggered blocks
    psel    = 1;
    penable = 0;
    pwrite  = 1;
    paddr   = offset;
    pwdata  = data;
    @(posedge pclk);
    #1;
    penable = 1;
    @(posedge pclk); // pready is tied high in apb_slave, one cycle in access phase is enough
    #1;
    psel    = 0;
    penable = 0;
    pwrite  = 0;
end
endtask

// ------------------------------------------------------------------
// Kick off a transaction: load cmd/addr/dummy/len then pulse ctrl_reg[0]
// ------------------------------------------------------------------
task start_transaction(
    input [7:0]  cmd,
    input [23:0] addr,
    input [4:0]  dummy,
    input [7:0]  len
);
begin
    apb_write(ADDR_CMD,   cmd);
    apb_write(ADDR_ADDR,  addr);
    apb_write(ADDR_DUMMY, dummy);
    apb_write(ADDR_LEN,   len);
    apb_write(ADDR_CTRL,  32'h1);   // ctrl_reg[0] = start (self-clears per apb_slave logic)
end
endtask

// push one byte into tx_fifo via write_fifo_data (for page program)
task load_tx_byte(input [7:0] data);
begin
    apb_write(ADDR_TXFIFO, data);
end
endtask

task wait_for_idle;
begin
    @(posedge sclk);
    while (busy_reg !== 1'b0) @(posedge sclk);
    // extra margin for the transaction itself to finish inside qspi_flash_controller
    repeat (200) @(posedge sclk);
end
endtask

// ------------------------------------------------------------------
// Stimulus
// ------------------------------------------------------------------
initial begin
    psel = 0; penable = 0; pwrite = 0; paddr = 0; pwdata = 0;
    presetn = 0;

    // hold reset a few clocks
    repeat (10) @(posedge pclk);
    presetn = 1;

    // Macronix model requires 800us tVSL before it accepts commands
    #800_000;
    repeat (5) @(posedge sclk);

    $display("[%0t] ---- WREN ----", $time);
    start_transaction(`write_enable, 24'h0, 5'd0, 8'd0);
    wait_for_idle;

    $display("[%0t] ---- RDID ----", $time);
    start_transaction(`read_jedec_id, 24'h0, 5'd0, 8'd3);
    wait_for_idle;
    $display("[%0t] RDID last byte via read_output = %h", $time, read_output);
    $display("[%0t] RDID last byte via rx_read_data = %h", $time, rx_read_data);

    $display("[%0t] ---- WREN (before page program) ----", $time);
    start_transaction(`write_enable, 24'h0, 5'd0, 8'd0);
    wait_for_idle;

    $display("[%0t] ---- PAGE PROGRAM (4 bytes @ 0x000010) ----", $time);
    load_tx_byte(8'hDE);
    load_tx_byte(8'hAD);
    load_tx_byte(8'hBE);
    load_tx_byte(8'hEF);
    start_transaction(`page_program, 24'h000010, 5'd0, 8'd4);
    wait_for_idle;
    // page program time is tPP (~400us typ in the model) - allow it to finish
    #500_000;

    $display("[%0t] ---- WREN (before sector erase) ----", $time);
    start_transaction(`write_enable, 24'h0, 5'd0, 8'd0);
    wait_for_idle;

    $display("[%0t] ---- SECTOR ERASE @ 0x000000 ----", $time);
    start_transaction(`sector_erase, 24'h000000, 5'd0, 8'd0);
    wait_for_idle;
    // sector erase tSE (~30ms typ) - shorten via force in sim if this is too slow,
    // otherwise expect a long real-time wait here
    #30_000_000;

    $display("[%0t] ---- FAST READ (4 bytes @ 0x000010, 8 dummy cycles) ----", $time);
    start_transaction(`fast_read, 24'h000010, 5'd8, 8'd4);
    wait_for_idle;
    $display("[%0t] Fast read last byte via read_output = %h", $time, read_output);
    $display("[%0t] Fast read last byte via rx_read_data = %h", $time, rx_read_data);

    $display("[%0t] ---- Test sequence complete ----", $time);
    #1000;
    $finish;
end

// ------------------------------------------------------------------
// Debug monitor
// ------------------------------------------------------------------
initial begin
    $monitor("[%0t] busy_reg=%b start_out=%b cmd_sync=%h addr_sync=%h dout=%h valid=%b tx_read=%h rx_read=%h",
              $time, busy_reg, start_out, cmd_reg_sync, addr_reg_sync,
              dut.dout, dut.valid, read_output, rx_read_data);
end
initial begin
    $dumpfile("wave.vcd");
    $dumpvars(0, tb_top_cdc_fifo_integrated);
end

endmodule