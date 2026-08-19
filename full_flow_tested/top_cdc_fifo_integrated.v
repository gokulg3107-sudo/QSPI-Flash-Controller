module top_cdc_fifo_integrated(
    sclk, psel, penable, pclk, presetn, pwrite, paddr, pwdata,
    pready, pslverr,
    cmd_reg_sync, len_reg_sync, dummy_reg_sync, addr_reg_sync,
    start_toggle, start_out, busy_reg, read_output,
    rx_read_data, qspi_busy_status, qspi_done_status
);

input psel, penable, sclk, pclk, presetn, pwrite;
input [31:0] paddr, pwdata;

output wire pready;
output wire pslverr;

// ---------------- APB / register bank ----------------
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
wire start;

// ---------------- TX path (unchanged) ----------------
wire tx_wen;
wire [7:0] fifo_data_in;
wire tx_ren;
wire tx_full, tx_empty;
wire [7:0] fifo_read;

// ---------------- RX path (new) ----------------
wire cs, si, so, wp, sio3, valid;
wire [7:0] dout;

wire rx_wen;
wire [7:0] rx_fifo_write_data;
wire rx_full, rx_empty;
wire [7:0] rx_fifo_read_data;
wire rx_ren;
output wire [7:0] rx_read_data;

output wire qspi_busy_status, qspi_done_status;

// ---------------- APB slave ----------------
apb_slave slave(
    .qspi_busy(busy_reg),
    .start_toggle(start_toggle),
    .rx_fifo_data(rx_read_data),
    .tx_fifo_wr_pulse(tx_fifo_wr_pulse),
    .psel(psel), .penable(penable), .paddr(paddr), .pwdata(pwdata), .pwrite(pwrite),
    .pready(pready), .pslverr(pslverr),
    .cmd_reg(cmd_reg), .addr_reg(addr_reg), .dummy_reg(dummy_reg),
    .pclk(pclk), .presetn(presetn),
    .len_reg(len_reg), .tx_fifo_data(tx_fifo_reg)
);

// ---------------- pclk -> sclk domain crossing ----------------
domain_crossing lo(
    cmd_reg, addr_reg, dummy_reg, len_reg, start_toggle, start_out, sclk, presetn,
    busy_reg, cmd_reg_sync, addr_reg_sync, dummy_reg_sync, len_reg_sync
);

// ---------------- TX FIFO chain (firmware -> flash) ----------------
fifo_write_fsm tx_write_logic(pclk, presetn, tx_fifo_reg, tx_fifo_wr_pulse, tx_wen, fifo_data_in);

async_fifo tx_fifo_module(pclk, tx_wen, presetn, fifo_data_in, sclk, tx_ren, presetn, fifo_read);

fifo_read_fsm tx_read_logic(sclk, presetn, read_output, cmd_reg_sync, len_reg_sync, start_out, tx_ren, fifo_read);

// ---------------- QSPI physical sequencer ----------------
qspi_flash_controller flash(
    sclk, presetn, cmd_reg_sync, addr_reg_sync, dummy_reg_sync, len_reg_sync,
    fifo_read, start_out, cs, si, so, wp, sio3, dout, valid
);

// ---------------- RX FIFO chain (flash -> firmware) ----------------
rx_fifo_write_logic rx_write_logic(sclk, presetn, valid, dout, rx_wen, rx_fifo_write_data);

async_fifo rx_fifo_module(sclk, rx_wen, presetn, rx_fifo_write_data, pclk, rx_ren, presetn, rx_fifo_read_data);

qspi_status status(sclk, presetn, cs, qspi_busy_status, qspi_done_status);

rx_fifo_read_logic rx_read_logic(
    pclk, presetn, qspi_done_status, rx_ren, rx_read_data, rx_fifo_read_data, cmd_reg, len_reg
);

endmodule
