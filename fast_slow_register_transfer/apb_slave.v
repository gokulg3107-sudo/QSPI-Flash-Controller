`include "command_code.h"
module apb_slave(qspi_busy, start_toggle, rx_fifo_data, psel, penable, paddr, pwdata, pwrite, pready, pslverr, cmd_reg, addr_reg, dummy_reg, pclk, presetn, len_reg, tx_fifo_data, start, tx_fifo_wr_pulse);
input psel, penable, pclk, presetn, pwrite;
input [31:0] paddr, pwdata;
input [7:0] rx_fifo_data;
output reg pready;
output wire pslverr;
input qspi_busy;
//Register bank
output reg [7:0] cmd_reg;
output reg [23:0] addr_reg;
output reg [4:0] dummy_reg;
output reg [7:0] len_reg, tx_fifo_data;
reg [1:0] ctrl_reg;
output wire tx_fifo_wr_pulse;

localparam [1:0] idle = 2'b00, setup = 2'b01, access_state = 2;
reg [1:0] current_state, next_state;

output reg start_toggle;
output wire start;

wire abort;
reg ctrl_reg_prev;

assign start = ~ctrl_reg_prev & ctrl_reg[0];
assign abort = ctrl_reg[1];

//state transition logic
always@(posedge pclk or negedge presetn)begin
        if(!presetn) current_state <= idle;
        else current_state <= next_state;
end

//next state logic
always@(current_state, psel, penable)begin
        case(current_state)
        idle: next_state = psel ? setup : idle;
        setup: next_state = (psel & penable) ? access_state : setup;
        access_state: next_state = (psel & penable) ? setup : idle;
        default: next_state = idle;
        endcase
end

assign pslverr = 0;


always@(*)begin
        case(current_state)
        idle: pready = 1;
        setup: pready = 1;
        access_state: pready = 1;
        default: pready = 1;
        endcase
end

reg sync1, qspi_busy_sync;

always@(posedge pclk or negedge presetn)begin
        if(~presetn) begin
                sync1 <= 0;
                qspi_busy_sync <= 0;
        end
        else begin
                sync1 <= qspi_busy;
                qspi_busy_sync <= sync1;
        end
end

always@(posedge pclk or negedge presetn)begin
        if(!presetn) begin
                cmd_reg <= 0;
                addr_reg <= 0;
                dummy_reg <= 0;
                len_reg <= 0;
                tx_fifo_data <= 0;
                ctrl_reg <= 0;
                ctrl_reg_prev <= 0;
        end
        else begin
                ctrl_reg <= ctrl_reg ? 1'b0 : ctrl_reg;
                ctrl_reg_prev <= ctrl_reg[0];
                if (current_state == setup & pwrite) begin
                 case (paddr[2:0])
                 `command_code: if(~qspi_busy_sync) cmd_reg <= pwdata[7:0];
                 `address_bytes: if(~qspi_busy_sync) addr_reg <= pwdata[23:0];
                 `dummy_cycles_count: if(~qspi_busy_sync) dummy_reg <= pwdata[4:0];
                 `length_of_data: if(~qspi_busy_sync) len_reg <= pwdata[7:0];
                 `write_fifo_data: tx_fifo_data <= pwdata[7:0];
                 `control_signals: ctrl_reg <= pwdata[1:0];
                 endcase
                end
        end
end

always@(posedge pclk or negedge presetn)begin
        if(~presetn) start_toggle <= 0;
        else if(start) start_toggle <= ~start_toggle;
        else start_toggle <= start_toggle;
end
assign tx_fifo_wr_pulse = (current_state == setup) & pwrite & (paddr[2:0] == `write_fifo_data);

endmodule

