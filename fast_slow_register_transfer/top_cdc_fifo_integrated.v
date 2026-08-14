module top_cdc_fifo_integrated(sclk, psel, penable, pclk, presetn, pwrite, paddr, pwdata, pready, pslverr, cmd_reg_sync, len_reg_sync, dummy_reg_sync, addr_reg_sync, start_toggle, start_out, busy_reg, read_output);

input psel, penable, sclk, pclk, presetn, pwrite;
input [31:0] paddr, pwdata;

output wire pready;
output wire pslverr;

wire [7:0] cmd_reg;
wire [23:0] addr_reg;
wire [4:0] dummy_reg;
wire [7:0] len_reg, tx_fifo_data;
wire [7:0] tx_fifo_reg;
wire tx_fifo_wr_pulse;
output wire start_toggle;
output wire busy_reg;
output wire [7:0] cmd_reg_sync, len_reg_sync, read_output;
output wire [23:0] addr_reg_sync;
output wire [4:0] dummy_reg_sync;
output wire start_out;
wire ren;
wire start;
wire full, empty;
wire [7:0] fifo_read;
apb_slave slave(
    .qspi_busy(busy_reg),
    .start_toggle(start_toggle),
    .rx_fifo_data(8'b0),
    .tx_fifo_wr_pulse(tx_fifo_wr_pulse),
    .psel(psel), .penable(penable), .paddr(paddr), .pwdata(pwdata), .pwrite(pwrite),
    .pready(pready), .pslverr(pslverr),
    .cmd_reg(cmd_reg), .addr_reg(addr_reg), .dummy_reg(dummy_reg),
    .pclk(pclk), .presetn(presetn),
    .len_reg(len_reg), .tx_fifo_data(tx_fifo_reg),
    .start(start)
);
wire [7:0] fifo_data_in;
domain_crossing lo(cmd_reg, addr_reg, dummy_reg, len_reg, start_toggle, start_out, sclk, presetn, busy_reg, cmd_reg_sync, addr_reg_sync, dummy_reg_sync, len_reg_sync)                                          ;
fifo_write_fsm fifo_logic(pclk, presetn, tx_fifo_reg, tx_fifo_wr_pulse, cmd_reg, len_reg, start, wen, fifo_data_in);
async_fifo fifo_module(pclk, wen, presetn, fifo_data_in, sclk, ren, presetn, fifo_read, full, empty);
fifo_read_fsm read_logic(sclk, presetn, read_output, cmd_reg_sync, len_reg_sync, start_out, ren, fifo_read);
endmodule

