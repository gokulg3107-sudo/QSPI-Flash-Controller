module fifo_write_fsm(pclk, presetn, write_data, len_reg, start, wen, fifo_data_in);
input pclk, presetn, start;
input [7:0] write_data, len_reg;
output reg wen;
output reg [7:0] fifo_data_in;
localparam idle = 0, data_write = 1;
reg current_state, next_state;

reg [7:0] count_bytes_sent;
always@(posedge pclk or negedge presetn)begin
	if(~presetn) count_bytes_sent <= 0;
	else begin
		if(current_state == data_write) count_bytes_sent <= count_bytes_sent + 1;
		else count_bytes_sent <= 0;
	end
end
always@(posedge pclk or negedge presetn)begin
	if(~presetn) current_state <= idle;
	else current_state <= next_state;
end

always@(current_state, start, write_data)begin
	if(current_state == idle) next_state = start ? data_write : idle;
	else next_state = count_bytes_sent == len_reg - 1 ? idle : data_write;
end
always@(*)begin
	case(current_state)
	idle: begin
		wen = 0;
		fifo_data_in = 0;
	end
	data_write: begin
		wen = 1;
		fifo_data_in = write_data;
	end
	default: begin
		wen = 0;
		fifo_data_in = 0;
	end
	endcase
end
endmodule
