module qspi_flash_controller(sclk, presetn, cmd_reg, addr_reg, dummy_reg, width_reg, len_reg, start);
input sclk, presetn, start;
input [7:0] cmd, width_reg, len_reg;
input [23:0] addr_reg;
input [4:0] dummy_reg;

output reg cs, si, so, wp, sio3;

localparam [2:0] idle = 0, deassert_cs = 1, read_command = 2, read_addr = 3, read_dummy = 4, read_data = 5, done = 6;
reg [2:0] current_state, next_state;

always@(posedge sclk or negedge presetn)begin
	if(!presetn) curren_state <= idle;
	else current_state <= next_state;
end

always@(current_state, cmd, start, count_clock_cycles)begin
	case(current_state)
	idle: next_state = start ? deassert_cs : idle;
	deassert_cs: next_state = read_command;
	read_command: begin
	case(cmd_reg)
	`write_enable: next_state = (count_clock_cycles == 8) ? idle : read_command;
	`read_status_reg: next_state = (count_clock_cycles == 8) ? read_data : read_command;
	`read_jedec_id: next_state = (count_clock_cycles == 8) ? read_data : read_command;
	`sector_erase: next_state = (count_clock_cycles == 8) ? read_addr : read_command;
	default: next_state = read_command; //Just for initial draft for minimal feature test
	endcase
	end 	
	read_addr: next_state = (count_clock_cycles == 24) ? idle : read_addr;
	read_dummy: next_state = idle; //Initial draft
	read_data: next_state = (count_clock_cycles == 8) ? idle : read_data;
	default: next_state = idle;
end

always@(current_state)begin
	case(current_state)
	idle: begin
		cs = 1;
	 			
