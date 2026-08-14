module top_cdc(sclk, psel, penable, pclk, presetn, pwrite, paddr, pwdata, pready, pslverr, cmd_reg_sync, len_reg_sync, dummy_reg_sync, addr_reg_sync, start_toggle, start_out, busy_reg);

input psel, penable, sclk, pclk, presetn, pwrite;
input [31:0] paddr, pwdata;

output wire pready;
output wire pslverr;

wire [7:0] cmd_reg;
wire [23:0] addr_reg;
wire [4:0] dummy_reg;
wire [7:0] len_reg, tx_fifo_data;
wire [7:0] tx_fifo_reg;

output wire start_toggle;
output wire busy_reg;
output wire [7:0] cmd_reg_sync, len_reg_sync;
output wire [23:0] addr_reg_sync;
output wire [4:0] dummy_reg_sync;
output wire start_out;

wire start;

apb_slave slave(
    .qspi_busy(busy_reg),
    .start_toggle(start_toggle),
    .rx_fifo_data(8'b0),
    .psel(psel), .penable(penable), .paddr(paddr), .pwdata(pwdata), .pwrite(pwrite),
    .pready(pready), .pslverr(pslverr),
    .cmd_reg(cmd_reg), .addr_reg(addr_reg), .dummy_reg(dummy_reg),
    .pclk(pclk), .presetn(presetn),
    .len_reg(len_reg), .tx_fifo_data(tx_fifo_reg),
    .start(start)
);
domain_crossing lo(cmd_reg, addr_reg, dummy_reg, len_reg, start_toggle, start_out, sclk, presetn, busy_reg, cmd_reg_sync, addr_reg_sync, dummy_reg_sync, len_reg_sync);

endmodule
