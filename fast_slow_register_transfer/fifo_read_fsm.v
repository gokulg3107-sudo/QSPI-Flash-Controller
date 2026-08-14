`include "command_code.h"
module fifo_read_fsm(sclk, presetn, read_data, cmd_reg, len_reg, start, ren, fifo_read_data);
input sclk, presetn, start;
input [7:0] fifo_read_data, cmd_reg, len_reg;
output reg ren;
output reg [7:0] read_data;

localparam idle = 0, data_read = 1;

reg current_state, next_state;
reg [7:0] count_bytes_sent;
always@(posedge sclk or negedge presetn)begin
        if(~presetn) count_bytes_sent <= 0;
        else begin
                if(current_state == data_read) count_bytes_sent <= count_bytes_sent + 1;
                else count_bytes_sent <= 0;
        end
end
always@(posedge sclk or negedge presetn)begin
        if(~presetn) current_state <= idle;
        else current_state <= next_state;
end

always@(current_state, start, fifo_read_data)begin
        if(current_state == idle) next_state = (cmd_reg == `page_program & start) ? data_read : idle;
        else next_state = (count_bytes_sent == 3 * len_reg - 1) ? idle : data_read;
end
always@(*)begin
        case(current_state)
        idle: begin
                ren = 0;
                read_data = 0;
        end
        data_read: begin
                ren = 1;
                read_data = fifo_read_data;
        end
        default: begin
                ren = 0;
                read_data = 0;
        end
        endcase
end
endmodule

