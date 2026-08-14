module domain_crossing(cmd_reg, addr_reg, dummy_reg, len_reg, start, start_out, sclk, presetn, busy_reg, cmd_reg_sync, addr_reg_sync, dummy_reg_sync, len_reg_sync );
input sclk, presetn, start;
input [7:0] cmd_reg, len_reg;
input [23:0] addr_reg;
input [4:0] dummy_reg;
output reg [7:0] cmd_reg_sync, len_reg_sync;
output reg [23:0] addr_reg_sync;
output reg [4:0] dummy_reg_sync;
output reg busy_reg, start_out;

reg start_prev, start_sync1, start_sync2, start_sync3;

localparam [1:0] idle = 2'd0, latch_inputdata = 2'd1, send_acknowledge = 2'd2;

reg [1:0] current_state, next_state;

//dual rank synchronizer for start signal
always@(posedge sclk or negedge presetn)begin
    if(~presetn)begin
        start_sync1 <= 0;
        start_sync2 <= 0;
        start_sync3 <= 0;
    end
    else begin
        start_sync1 <= start;
        start_sync2 <= start_sync1;
        start_sync3 <= start_sync2;
    end
end

wire start_sync_toggle;
assign start_sync_toggle = start_sync2 ^ start_sync3;

always@(posedge sclk or negedge presetn)begin
if(~presetn) start_prev <= 0;
else start_prev <= start_sync_toggle;
end

wire start_pulse;
assign start_pulse = start_sync_toggle & ~start_prev;

always@(posedge sclk or negedge presetn)begin
    if(~presetn) current_state <= idle;
    else current_state <= next_state;
end

always@(*)begin
    case(current_state)
        idle: next_state = start_pulse ? latch_inputdata : idle;
        latch_inputdata: next_state = send_acknowledge;
        send_acknowledge: next_state = idle;
        default: next_state = idle;
    endcase
end

reg busy_temp;

always@(*)begin
    case(current_state)
        idle: begin busy_temp = 0; start_out = 0; end
        latch_inputdata: begin busy_temp = 1; start_out = 0; end
        send_acknowledge: begin busy_temp = 1; start_out = 1; end
        default: begin busy_temp = 0; start_out = 0; end
    endcase
end

always@(posedge sclk or negedge presetn) begin
    if(~presetn) begin
        cmd_reg_sync   <= 0;
        addr_reg_sync  <= 0;
        dummy_reg_sync <= 0;
        len_reg_sync   <= 0;
    end
    else if (current_state == latch_inputdata) begin
        cmd_reg_sync <= cmd_reg;
        addr_reg_sync <= addr_reg;
        dummy_reg_sync <= dummy_reg;
        len_reg_sync <= len_reg;
    end
end

always@(posedge sclk or negedge presetn)begin
    if(~presetn) busy_reg <= 0;
    else busy_reg <= busy_temp;
end

endmodule
