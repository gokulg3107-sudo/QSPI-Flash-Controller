module async(wclk, wen, wrst, write_datain, rclk, ren, rrst, read_dataout, full, empty);
input wclk, wen, wrst, rclk, ren, rrst;
output full, empty;
input [7:0] write_datain;
output reg [7:0] read_dataout;
reg [7:0] fifo_register [31:0];
wire [5:0] b_wptr, g_wptr, b_rptr, g_rptr;   // real, top-level wires again

write_pointer_handler w1(wclk, wen, wrst, g_wptr, b_wptr, g_rptr, full);
read_pointer_handler  w2(rclk, ren, rrst, g_rptr, b_rptr, g_wptr, empty);

always@(posedge wclk)begin
        if(wen & !full) fifo_register[b_wptr[4:0]] <= write_datain;
end
always@(posedge rclk or negedge rrst)begin
        if(!rrst) read_dataout <= 0;
        else if(ren & !empty) read_dataout <= fifo_register[b_rptr[4:0]];
end
endmodule
