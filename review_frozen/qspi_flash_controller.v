`include "command_code.h"
`timescale 1ns/100ps

module qspi_flash_controller(sclk, presetn, cmd_reg, addr_reg, dummy_reg, len_reg, data_reg, start, cs, si, so, wp, sio3, dout, valid, tx_data_req);
input sclk, presetn, start;
input [7:0] cmd_reg, len_reg, data_reg;
input [23:0] addr_reg;
input [4:0] dummy_reg;
output cs;
output reg valid;
output reg [7:0] dout;
inout si, so, wp, sio3;

localparam [2:0] idle = 0, read_command = 1, read_addr = 2, read_dummy = 3,
                 read_data = 4, write_data = 5, done = 6;
reg [2:0] current_state, next_state;

//per-byte bit counter: wraps 0..7 (or 0..23 for addr) to time shifts/loads within one byte/word
reg [20:0] count_clock_cycles;
always@(posedge sclk or negedge presetn)begin
        if(~presetn) count_clock_cycles <= 0;
        else if(current_state == read_dummy) begin
                if(count_clock_cycles == dummy_reg - 1) count_clock_cycles <= 0;
                else count_clock_cycles <= count_clock_cycles + 1;
        end
        else if(current_state == read_addr) begin
                if(count_clock_cycles == 23) count_clock_cycles <= 0;
                else count_clock_cycles <= count_clock_cycles + 1;
        end
        else if(current_state == read_command | current_state == read_data | current_state == write_data) begin
                if(count_clock_cycles == 7) count_clock_cycles <= 0;
                else  count_clock_cycles <= count_clock_cycles + 1;
        end
        else count_clock_cycles <= 0;
end

//total-transfer bit counter: tracks progress across a MULTI-byte read_data/write_data burst
//(count_clock_cycles alone can't do this - it wraps every 8 bits regardless of len_reg)
reg [20:0] total_count;
always@(posedge sclk or negedge presetn)begin
        if(~presetn) total_count <= 0;
        else if(current_state == read_data | current_state == write_data)
                total_count <= total_count + 1;
        else
                total_count <= 0;
end

//latching value of cmd_reg / addr_reg / data_reg during their respective states
reg [7:0] cmd_reg_temp;
reg [23:0] addr_reg_temp;
reg [7:0] data_reg_temp;
always@(posedge sclk or negedge presetn)begin
        if(!presetn)begin
                data_reg_temp <= 0;
                cmd_reg_temp  <= 0;
                addr_reg_temp <= 0;
        end
        else if (current_state == idle && start) begin
                cmd_reg_temp <= cmd_reg;
        end
        else if (current_state == read_command) begin
                if (count_clock_cycles == 7)
                        addr_reg_temp <= addr_reg;
                else
                        cmd_reg_temp <= {cmd_reg_temp[6:0], 1'b0};
        end
        else if (current_state == read_addr) begin
                if (count_clock_cycles == 23)
                        data_reg_temp <= data_reg; // pre-load first write byte before entering write_data
                else
                        addr_reg_temp <= {addr_reg_temp[22:0], 1'b0};
        end
        else if(current_state == write_data) begin
                if (count_clock_cycles == 7)
                        data_reg_temp <= data_reg; // load next byte at each byte boundary (single-reg stand-in for FIFO)
                else
                        data_reg_temp <= {data_reg_temp[6:0], 1'b0};
        end
end

//state transition logic
always@(posedge sclk or negedge presetn)begin
        if(!presetn) current_state <= idle;
        else current_state <= next_state;
end
//Driving inout ports of Flash
wire [3:0] io_in;
reg  [3:0] io_out_next, io_oe_next;   // combinational, computed from current_state
reg        cs_next;

reg  [3:0] io_out, io_oe;             // registered on negedge sclk (data pins only)

assign cs   = cs_next;
assign si   = io_oe[0] ? io_out[0] : 1'bz;
assign so   = io_oe[1] ? io_out[1] : 1'bz;
assign wp   = io_oe[2] ? io_out[2] : 1'bz;
assign sio3 = io_oe[3] ? io_out[3] : 1'bz;

assign io_in = {sio3, wp, so, si};

//next state logic
always@(*)begin
        case(current_state)
        idle: next_state = start ? read_command : idle;
        read_command: begin
                case(cmd_reg)
                `write_enable:    next_state = (count_clock_cycles == 7) ? idle : read_command;
                `read_status_reg: next_state = (count_clock_cycles == 7) ? read_data : read_command;
                `read_jedec_id:   next_state = (count_clock_cycles == 7) ? read_data : read_command;
                `sector_erase:    next_state = (count_clock_cycles == 7) ? read_addr : read_command;
                `fast_read:       next_state = (count_clock_cycles == 7) ? read_addr : read_command;
                `page_program:    next_state = (count_clock_cycles == 7) ? read_addr : read_command;
                default:          next_state = read_command; //Just for initial draft for minimal feature test
                endcase
        end
        read_addr: begin
                if(cmd_reg == `sector_erase)      next_state = (count_clock_cycles == 23) ? idle : read_addr;
                else if(cmd_reg == `fast_read)    next_state = (count_clock_cycles == 23) ? read_dummy : read_addr;
                else if(cmd_reg == `page_program) next_state = (count_clock_cycles == 23) ? write_data : read_addr;
                else                              next_state = (count_clock_cycles == 23) ? read_data : read_addr;
        end
        read_dummy: next_state = (count_clock_cycles == dummy_reg - 1) ? read_data : read_dummy;
        read_data: begin
                case(cmd_reg)
                `read_status_reg: next_state = (count_clock_cycles == 7) ? idle : read_data;
                `read_jedec_id:   next_state = (total_count == 23) ? idle : read_data;
                `fast_read:       next_state = (total_count == (len_reg*8 - 1)) ? idle : read_data;
                default:          next_state = idle;
                endcase
        end
        write_data: next_state = (total_count == (len_reg*8 - 1)) ? idle : write_data;
        default: next_state = idle;
        endcase
end

// cs_next / io_out_next / io_oe_next: combinational scratch logic.
// cs is taken straight from cs_next (see assign above); io_out_next/io_oe_next
// still feed the negedge-registered io_out/io_oe below.
always@(*)begin
        case(current_state)
        idle: begin
                cs_next = 1;
                io_out_next = 0;
                io_oe_next = 0;
        end
        read_command: begin
                cs_next = 0;
                io_out_next = {3'd0, cmd_reg_temp[7]};
                io_oe_next = 4'b0001;
        end
        read_addr: begin
                cs_next = 0;
                io_oe_next = 4'b0001;
                io_out_next = {3'd0, addr_reg_temp[23]};
        end
        read_dummy: begin
                cs_next = 0;
                io_oe_next = 4'b0000;
                io_out_next = 0;
        end
        read_data: begin
                cs_next = 0;
                io_oe_next = 4'b0000;  // full tri-state during read: only receiving on SO
                io_out_next = 0;
        end
        write_data: begin
                cs_next = 0;
                io_oe_next = 4'b0001;
                io_out_next = {3'd0, data_reg_temp[7]};
        end
        default: begin
                cs_next = 1;
                io_out_next = 0;
                io_oe_next = 0;
        end
        endcase
end

// io_out/io_oe: still registered on negedge sclk. current_state only changes
// on posedge sclk, so by the time this negedge fires it has already settled
// -- these outputs update mid-cycle, well clear of the next posedge sampling
// edge on the flash side. This is the real hold-time fix and cs does not
// need it (see note above).
always@(negedge sclk or negedge presetn)begin
        if(!presetn) begin
                io_out  <= 4'b0;
                io_oe   <= 4'b0;
        end
        else begin
                io_out  <= io_out_next;
                io_oe   <= io_oe_next;
        end
end

reg [7:0] rx_shift_reg;
always @(posedge sclk or negedge presetn) begin
    if (!presetn) begin
        rx_shift_reg <= 0;
        dout  <= 0;
        valid <= 0;
    end
    else if (current_state == read_data) begin
        rx_shift_reg <= {rx_shift_reg[6:0], io_in[1]};
        if (count_clock_cycles == 7) begin
            dout  <= {rx_shift_reg[6:0], io_in[1]};  // full byte, including the bit landing this cycle
            valid <= 1;
        end
        else valid <= 0;
    end
    else valid <= 0;
end
// one cycle before data_reg_temp latches, so the FIFO's registered
// output has already updated to the right byte by then
output wire tx_data_req;
assign tx_data_req = (current_state == read_addr  && count_clock_cycles == 22) || (current_state == write_data && count_clock_cycles == 6 && total_count < (len_reg*8 - 8));
endmodule
