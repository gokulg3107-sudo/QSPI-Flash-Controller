`include "command_code.h"
module tb_cdc_check;

reg psel, penable, sclk, pclk, presetn, pwrite;
reg [31:0] paddr, pwdata;
wire [7:0] read_output;
wire pready;
wire pslverr;
wire start_toggle;
wire busy_reg;

wire [7:0] cmd_reg_sync, len_reg_sync;
wire [23:0] addr_reg_sync;
wire [4:0] dummy_reg_sync;
wire start_out;

top_cdc_fifo_integrated uut(.*);

initial pclk = 0;
always #20 pclk = ~pclk;

initial sclk = 0;
always #80 sclk = ~sclk;
task write_data(input [31:0] addr, data);
begin
        // SETUP
        @(negedge pclk);
        psel = 1;
        penable = 0;
        paddr = addr;
        pwdata = data;
        pwrite = 1;

        // ACCESS
        @(negedge pclk);
        penable = 1;

        // Wait until ACCESS is complete
        @(posedge pclk);
        while(!pready)
                @(posedge pclk);

        // IDLE
        @(negedge pclk);
        psel = 0;
        penable = 0;
        pwrite = 0;

        #10;
end
endtask
initial begin

        $dumpfile("wave.vcd");
        $dumpvars(0, tb_cdc_check);

        psel = 0;
        penable = 0;
        paddr = 0;
        pwdata = 0;
        pwrite = 0;

        presetn = 0;

        #50 presetn = 1;

        #200;

        write_data(`command_code,  32'd2);
        write_data(`address_bytes, 32'd255);
        write_data(`dummy_cycles_count, 32'd15);
        write_data(`length_of_data, 32'd6);
        write_data(`control_signals, 32'd1);
        write_data(`write_fifo_data, 32'd4);

        write_data(`write_fifo_data, 32'd5);
        write_data(`write_fifo_data, 32'd6);
        write_data(`write_fifo_data, 32'd7);
        write_data(`write_fifo_data, 32'd8);
        write_data(`write_fifo_data, 32'd9);
        #3500;

        $finish;

end

endmodule

