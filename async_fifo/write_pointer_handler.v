module write_pointer_handler(wclk, wen, wrst, g_wptr, b_wptr, g_rptr, full);
input wclk, wen, wrst;
input [5:0] g_rptr;
output reg [5:0] g_wptr, b_wptr;   // b_wptr exposed again — this is THE counter
output wire full;
reg [5:0] sync1, g_rptr_sync;
reg [5:0] rptr_bin;                 // renamed from b_rptr to avoid collision

always@(posedge wclk or negedge wrst)begin
        if(!wrst) b_wptr <= 0;
        else if(wen & !full) b_wptr <= b_wptr + 1;
end
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

always@(g_rptr_sync)begin
        rptr_bin[5] = g_rptr_sync[5];
        rptr_bin[4] = rptr_bin[5] ^ g_rptr_sync[4];
        rptr_bin[3] = rptr_bin[4] ^ g_rptr_sync[3];
        rptr_bin[2] = rptr_bin[3] ^ g_rptr_sync[2];
        rptr_bin[1] = rptr_bin[2] ^ g_rptr_sync[1];
        rptr_bin[0] = rptr_bin[1] ^ g_rptr_sync[0];
end
assign full = (rptr_bin[5] != b_wptr[5]) & (b_wptr[4:0] == rptr_bin[4:0]);
endmodule
