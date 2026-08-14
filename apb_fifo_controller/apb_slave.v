`include "command_code.h"
module apb_slave(start_toggle, psel, penable, paddr, pwdata, pwrite, pready, pslverr, cmd_reg, addr_reg, dummy_reg, pclk, presetn, len_reg, ctrl_reg);
input psel, penable, pclk, presetn, pwrite;
input [31:0] paddr, pwdata;
input [7:0] rx_fifo_data;
output reg pready;
output wire  pslverr;
input qspi_busy;
//Register bank 
output reg [7:0] cmd_reg; 
output reg [23:0] addr_reg; 
output reg [4:0] dummy_reg; 
output reg [7:0] len_reg, tx_fifo_data;
output reg [1:0] ctrl_reg; // {Abort, Start}

localparam [1:0] idle = 2'b00, setup = 2'b01, access_state = 2;
reg [1:0] current_state, next_state;

output reg start_toggle;
wire start, abort;
reg ctrl_reg_prev;
assign start = ~ctrl_reg_prev & ctrl_reg[0];
assign abort = ctrl_reg[1];

reg [1:0] count_access;
//state transition logic
always@(posedge pclk or negedge presetn)begin
	if(!presetn) current_state <= idle;
	else current_state <= next_state;
end

//next state logic
always@(current_state, psel, penable, count_access)begin
	case(current_state) 
	idle: next_state = psel ? setup : idle;
	setup: next_state = (psel & penable) ? access_state : setup;
	access_state: next_state = (count_access == 2) ? (psel & penable) ? setup : idle : access_state;
	default: next_state = idle;
	endcase
end

assign pslverr = 0;

//Register to keep count during ACCESS fsm state
//In access_state state: 
//1. Count = 0, latch the addr and value, ready = 0
//2. Count = 1, write the value in that addr of register bank, ready = 0
//3. Count = 2, Data is written into the register bank, assert ready
always@(posedge pclk or negedge presetn)begin
	if(!presetn) count_access <= 0;
	else if (current_state == access_state) count_access <= count_access + 1;
	else count_access <= 0;
end

always@(*)begin
	case(current_state)
	idle: pready = 1;
	setup: pready = 1;
	access_state: begin
		if(count_access == 0 | count_access == 1) pready = 0;
		else pready = 1;
	end
	default: pready = 1;
	endcase
end
always@(posedge pclk or negedge presetn)begin
	if(!presetn) begin
		cmd_reg <= 0;
		addr_reg <= 0;
		dummy_reg <= 0;
		width_reg <= 0;
		len_reg <= 0;
		tx_fifo_data <= 0;
		ctrl_reg <= 0;
		ctrl_reg_prev <= 0;
	end
	else begin
		ctrl_reg_prev <= ctrl_reg[0];
		if (current_state == access_state && count_access == 1 && pwrite) begin
   		 case (paddr[2:0])
       		 command_code: cmd_reg <= pwdata[7:0];
              	 address_bytes: addr_reg <= pwdata[23:0];
    		 dummy_cycles_count: dummy_reg <= pwdata[4:0];
        	 length_of_data: len_reg <= pwdata[7:0];
        	 data_width: width_reg <= pwdata[7:0]; 
        	 write_fifo_data: tx_fifo_data <= pwdata[7:0];
        	 control_signals: ctrl_reg <= pwdata[1:0];
    		endcase
		end
	end
end
always@(posedge pclk or negedge presetn)begin
	if(~presetn) start_toggle <= 0;
	else if(start) start_toggle <= ~start_toggle;
	else start_toggle <= start_toggle;
end
endmodule
