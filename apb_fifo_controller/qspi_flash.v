`include "command_code.h"
module qspi_flash_controller(sclk, presetn, cmd_reg, addr_reg, dummy_reg, width_reg, len_reg, start, cs, si, so, wp, sio3);
input sclk, presetn, start;
input [7:0] cmd_reg, width_reg, len_reg;
input [23:0] addr_reg;
input [4:0] dummy_reg;
output cs;
inout si, so, wp, sio3;

localparam [2:0] idle = 0, deassert_cs = 1, read_command = 2, read_addr = 3, read_dummy = 4, read_data = 5, done = 6;
reg [2:0] current_state, next_state;

//counting number of clock cycles under each stage
reg [4:0] count_clock_cycles;
always@(posedge sclk or negedge presetn)begin
        if(~presetn) count_clock_cycles <= 0;
        else if(current_state == read_command) begin
                if(count_clock_cycles == 7) count_clock_cycles <= 0;
                else  count_clock_cycles <= count_clock_cycles + 1;
        end
        else if(current_state == read_addr)begin
                if(count_clock_cycles == 23) count_clock_cycles <= 0;
                else  count_clock_cycles <= count_clock_cycles + 1;
        end
         else if(current_state == read_data) begin
                if(count_clock_cycles == 7) count_clock_cycles <= 0;
                else  count_clock_cycles <= count_clock_cycles + 1;
        end
        else count_clock_cycles <= 0;
end

//latching value of cmd_reg and addr_reg during read command / read addr state
reg [7:0] cmd_reg_temp;
reg [23:0] addr_reg_temp;
always@(posedge sclk or negedge presetn)begin
        if(!presetn)begin
                cmd_reg_temp <= 0;
                addr_reg_temp <= 0;
        end
        else if (current_state == idle && start) begin
                cmd_reg_temp <= cmd_reg;
        end
        else if (current_state == read_command) begin
                if (count_clock_cycles == 7)
                        addr_reg_temp <= addr_reg;
                else
                        cmd_reg_temp <= cmd_reg_temp << 1;
        end
        else if (current_state == read_addr) begin
                addr_reg_temp <= addr_reg_temp << 1;
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
always@(current_state, cmd_reg, start, count_clock_cycles)begin
        case(current_state)
        idle: next_state = start ? read_command : idle;
        deassert_cs: next_state = read_command;
        read_command: begin
        case(cmd_reg)
        `write_enable: next_state = (count_clock_cycles == 7) ? idle : read_command;
        `read_status_reg: next_state = (count_clock_cycles == 7) ? read_data : read_command;
        `read_jedec_id: next_state = (count_clock_cycles == 7) ? read_data : read_command;
        `sector_erase: next_state = (count_clock_cycles == 7) ? read_addr : read_command;
        default: next_state = read_command; //Just for initial draft for minimal feature test
        endcase
        end
        read_addr: next_state = (count_clock_cycles == 23) ? idle : read_addr;
        read_dummy: next_state = idle; //Initial draft
        read_data: next_state = (count_clock_cycles == 7) ? idle : read_data;
        default: next_state = idle;
        endcase
end

// cs_next / io_out_next / io_oe_next: combinational scratch logic.
// cs is taken straight from cs_next (see assign above); io_out_next/io_oe_next
// still feed the negedge-registered io_out/io_oe below.
always@(current_state, cmd_reg_temp, addr_reg_temp)begin
        case(current_state)
        idle: begin
                cs_next = 1;
                io_out_next = 0;
                io_oe_next = 0;
        end
        deassert_cs: begin
                cs_next = 0;
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
                io_oe_next = 4'b0001;  // full tri-state during read: only receiving on SO
                io_out_next = 0;
        end
        default: begin
                cs_next = 1;
                io_oe_next = 4'b0001;
                io_out_next = 0;
        end
        endcase
end

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
    if (!presetn) rx_shift_reg <= 0;
    else if (current_state == read_data) rx_shift_reg <= {rx_shift_reg[6:0], io_in[1]};
end

endmodule
