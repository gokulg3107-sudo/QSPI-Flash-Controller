`timescale 1ns/100ps

module async_fifo(wclk, wen, wrst, write_datain, rclk, ren, rrst, read_dataout);
input wclk, wen, wrst, rclk, ren, rrst;
wire full, empty;
input [7:0] write_datain;
output reg [7:0] read_dataout;
integer i;
reg [7:0] fifo_register [31:0];
wire [5:0] b_wptr, g_wptr, b_rptr, g_rptr;

write_pointer_handler w1(wclk, wen, wrst, g_wptr, b_wptr, g_rptr, full);
read_pointer_handler  w2(rclk, ren, rrst, g_rptr, b_rptr, g_wptr, empty);

always@(posedge wclk or negedge wrst)begin
        if(!wrst) for(i = 0; i < 32; i = i + 1) fifo_register[i] <= 0;
        else if(wen & !full) fifo_register[b_wptr[4:0]] <= write_datain;
end
always@(posedge rclk or negedge rrst)begin
        if(!rrst) read_dataout <= 0;
        else if(ren & !empty) read_dataout <= fifo_register[b_rptr[4:0]];
end
endmodule


module read_pointer_handler(rclk, ren, rrst, g_rptr, b_rptr, g_wptr, empty);
input rclk, ren, rrst;
input [5:0] g_wptr;
output reg [5:0] b_rptr, g_rptr;
output empty;
reg [5:0] g_wptr_sync, sync1;

//Dual rank synchronizer
always@(posedge rclk or negedge rrst)begin
        if(!rrst) sync1 <= 0;
        else sync1 <= g_wptr;
end
always@(posedge rclk or negedge rrst)begin
        if(!rrst) g_wptr_sync <= 0;
        else g_wptr_sync <= sync1;
end

//Read pointer management
always@(posedge rclk or negedge rrst)begin
        if(~rrst) b_rptr <= 0;
        else if (ren & !empty) b_rptr <= b_rptr + 1;
end

wire [5:0] g_rptr_temp;
//Conversion of binary to gray coded read pointer for domain crossing to write
//pointer handler
assign g_rptr_temp = b_rptr ^ (b_rptr >> 1);

//Latching gray coded read pointer for domain crossing because directly
//transmitting combo block output to different domain can cause glitch
always@(posedge rclk or negedge rrst)begin
        if(!rrst) g_rptr <= 0;
        else g_rptr <= g_rptr_temp;
end

reg [5:0] b_wptr;
//Convert synchronized gray coded write pointer to binary coded
always@(g_wptr_sync)begin
        b_wptr[5] = g_wptr_sync[5];
        b_wptr[4] = b_wptr[5] ^ g_wptr_sync[4];
        b_wptr[3] = b_wptr[4] ^ g_wptr_sync[3];
        b_wptr[2] = b_wptr[3] ^ g_wptr_sync[2];
        b_wptr[1] = b_wptr[2] ^ g_wptr_sync[1];
        b_wptr[0] = b_wptr[1] ^ g_wptr_sync[0];
end

//Driving empty signal
assign empty = (b_wptr[5] == b_rptr[5]) & (b_wptr[4:0] == b_rptr[4:0]);
endmodule


module write_pointer_handler(wclk, wen, wrst, g_wptr, b_wptr, g_rptr, full);
input wclk, wen, wrst;
input [5:0] g_rptr;
output reg [5:0] g_wptr, b_wptr;
reg [5:0] sync1, g_rptr_sync;
output wire full;
reg [5:0] b_rptr;

always@(posedge wclk or negedge wrst)begin
        if(!wrst) b_wptr <= 0;
        else if(wen & !full) b_wptr <= b_wptr + 1;
end

wire [5:0] g_wptr_temp;
assign g_wptr_temp = b_wptr ^ (b_wptr >> 1);

always@(posedge wclk or negedge wrst)begin
        if(!wrst) g_wptr <= 0;
        else g_wptr <= g_wptr_temp;
end

//Dual rank synchronizer for gray coded read pointer from rclk domain
always@(posedge wclk or negedge wrst)begin
        if(!wrst) sync1 <= 0;
        else sync1 <= g_rptr;
end
always@(posedge wclk or negedge wrst)begin
        if(!wrst) g_rptr_sync <= 0;
        else g_rptr_sync <= sync1;
end

//Conversion of synchronized gray coded read pointer to binary coded
always@(g_rptr_sync)begin
        b_rptr[5] = g_rptr_sync[5];
        b_rptr[4] = b_rptr[5] ^ g_rptr_sync[4];
        b_rptr[3] = b_rptr[4] ^ g_rptr_sync[3];
        b_rptr[2] = b_rptr[3] ^ g_rptr_sync[2];
        b_rptr[1] = b_rptr[2] ^ g_rptr_sync[1];
        b_rptr[0] = b_rptr[1] ^ g_rptr_sync[0];
end

assign full = (b_rptr[5] != b_wptr[5]) & (b_wptr[4:0] == b_rptr[4:0]);
endmodule
