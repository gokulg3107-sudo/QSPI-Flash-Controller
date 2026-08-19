module qspi_status(sclk, presetn, cs, busy, done);
input sclk, presetn, cs;
output reg busy, done;

localparam [1:0] idle = 2'd0, qspi_operation = 2'd1, qspi_done = 2'd2;
reg [1:0] current_state, next_state;

//Whenever cs is deasserted it means it's performing operation on the flash 

always@(posedge sclk or negedge presetn)begin
    if(~presetn) current_state <= idle;
    else current_state <= next_state;
end

always@(*)begin
    case(current_state)
    idle: next_state = cs ? idle : qspi_operation;
    qspi_operation: next_state = cs ? qspi_done : qspi_operation;
    qspi_done: next_state = idle;
    default: next_state = idle;
    endcase
end
always@(*)begin 
    case(current_state)
    idle: begin
        busy = 0;
        done = 0;
    end
    qspi_operation: begin
        busy = 1;
        done = 0;
    end
    qspi_done: begin
        busy = 0;
        done = 1;
    end
    default: begin
        busy = 0;
        done = 0;
    end
    endcase
end
endmodule