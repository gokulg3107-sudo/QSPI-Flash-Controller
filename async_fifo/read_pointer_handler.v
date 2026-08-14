module read_pointer_handler(rclk, ren, rrst, g_rptr, b_rptr, g_wptr, empty);
input rclk, ren, rrst;
input [5:0] g_wptr;
output reg [5:0] b_rptr, g_rptr;   // b_rptr exposed again — this is THE counter
output empty;
reg [5:0] g_wptr_sync, sync1;
reg [5:0] wptr_bin;                 // renamed from b_wptr to avoid collision

always@(posedge rclk or negedge rrst)begin
        if(~rrst) b_rptr <= 0;
        else if (ren & !empty) b_rptr <= b_rptr + 1;
end
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

always@(g_wptr_sync)begin
        wptr_bin[5] = g_wptr_sync[5];
        wptr_bin[4] = wptr_bin[5] ^ g_wptr_sync[4];
        wptr_bin[3] = wptr_bin[4] ^ g_wptr_sync[3];
        wptr_bin[2] = wptr_bin[3] ^ g_wptr_sync[2];
        wptr_bin[1] = wptr_bin[2] ^ g_wptr_sync[1];
        wptr_bin[0] = wptr_bin[1] ^ g_wptr_sync[0];
end
assign empty = (wptr_bin[5] == b_rptr[5]) & (wptr_bin[4:0] == b_rptr[4:0]);
endmodule
