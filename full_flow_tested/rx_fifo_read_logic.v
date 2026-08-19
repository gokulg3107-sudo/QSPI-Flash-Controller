`include "command_code.h"
module rx_fifo_read_logic(pclk, presetn, qspi_done, ren, read_data, fifo_data, cmd_reg, len_reg);
input pclk, presetn, qspi_done;
input [7:0] fifo_data, cmd_reg, len_reg;
output reg ren;
output reg [7:0] read_data;
reg sync1, qspi_done_sync, qspi_done_sync_d;
wire qspi_done_sync_pulse;
localparam idle = 0, read_fifo_data = 1;
reg current_state, next_state;
//Dual Rank Synchronizer for done signal sent from "qspi_status" module of pclk Domain 
//Convert the synchronized done signal from level to a pulse
always@(posedge pclk or negedge presetn)begin
    if(~presetn) begin
        sync1 <= 0;
        qspi_done_sync <= 0;
        qspi_done_sync_d <= 0;
    end
    else begin
        sync1 <= qspi_done;
        qspi_done_sync <= sync1;
        qspi_done_sync_d <= qspi_done_sync;
    end
end

//Logic to keep count of number of bytes read
reg [7:0] count_bytes_read;
always@(posedge pclk or negedge presetn)begin  
    if(~presetn) count_bytes_read <= 0;
    else if(current_state == read_fifo_data)begin
        if(cmd_reg == `fast_read | cmd_reg == `quad_io_read) count_bytes_read <= count_bytes_read + 1;
        else count_bytes_read <= 0;
    end
    else count_bytes_read <= 0;
end
//Convert qspi_done signal to a pulse because if it is a level then it is possible that the fsm will be triggered again
//as sclk Time period is 80ns and qspi_busy in pclk domain will be high for 80ns which is 4 clock cycles in PCLK domain. 
//Hence we are converting qspi_done_sync to a pulse
assign qspi_done_sync_pulse = qspi_done_sync & ~qspi_done_sync_d;

always@(posedge pclk or negedge presetn)begin
    if(~presetn) current_state <= idle;
    else current_state <= next_state;
end
//Take count of number of bytes to read from len_reg presetn in "apb_slave" memory bank. Assert ren until the count_bytes_read equals to len_reg in "data read commmands"
always@(*)begin
    if(current_state == idle) next_state = (qspi_done_sync_pulse & cmd_reg != `write_enable & cmd_reg != `page_program & cmd_reg != `sector_erase) ? read_fifo_data : idle;
    else begin
        case(cmd_reg)
        `read_status_reg: next_state = idle;
        `read_jedec_id: next_state = (count_bytes_read == 2) ? idle : read_fifo_data; //Outputs two bytes of data by standard
        `fast_read: next_state = (count_bytes_read == len_reg - 1) ? idle : read_fifo_data; 
        `quad_io_read: next_state = (count_bytes_read == len_reg - 1) ? idle : read_fifo_data; 
        default: next_state = idle;
        endcase
    end
end
always@(*)begin
    if(current_state == idle) ren = 0;
   else ren = 1;
end
reg ren_d;
always@(posedge pclk or negedge presetn)begin
    if(~presetn) ren_d <= 0;
    else ren_d <= ren;
end

always@(posedge pclk or negedge presetn)begin
    if(~presetn) read_data <= 0;
    else if(ren_d) read_data <= fifo_data;
end


endmodule
