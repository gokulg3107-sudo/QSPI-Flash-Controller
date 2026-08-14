module apb_slave(qspi_busy, start_toggle, rx_fifo_data, psel, penable, paddr, pwdata, pwrite, pready, pslverr, cmd_reg, addr_reg, dummy_reg, pclk, presetn,  width_reg, len_reg, tx_fifo_data, ctrl_reg, fifo_state_reg);
input psel, penable, pclk, presetn, pwrite;
input [31:0] paddr, pwdata;
input [7:0] rx_fifo_data;
output reg pready;
output wire  pslverr;
input qspi_busy;
localparam [2:0] command_code = 0, address_bytes = 1, dummy_cycles_count = 2,  data_width = 3, length_of_data = 4, write_fifo_data = 5, control_signals = 6;
//Register bank
output reg [7:0] cmd_reg; //Command code
output reg [23:0] addr_reg; //Contains addr for qspi controller
output reg [4:0] dummy_reg; //mentions number of dummy cycles needed
//Width reg mentions per phase line width
output reg [7:0] width_reg, len_reg, tx_fifo_data;
output reg [1:0] ctrl_reg; // {Abort, Start}
output reg [3:0] fifo_state_reg; //{RX_empty, RX_full, TX_empty, TX_full}

localparam [1:0] idle = 2'b00, setup = 2'b01, access_state = 2;
reg [1:0] current_state, next_state;

output reg start_toggle;
wire start, abort;
reg ctrl_reg_prev;
assign start = ~ctrl_reg_prev & ctrl_reg[0];
assign abort = ctrl_reg[1];

reg [1:0] count_access;
//state transition logic
always@(posedge pclk or negedge presetn)begin
        if(!presetn) current_state <= idle;
        else current_state <= next_state;
end

//next state logic
always@(current_state, psel, penable, count_access)begin
        case(current_state)
        idle: next_state = psel ? setup : idle;
        setup: next_state = (psel & penable) ? access_state : setup;
        access_state: next_state = (count_access == 2) ? (psel & penable) ? setup : idle : access_state;
        default: next_state = idle;
        endcase
end

assign pslverr = 0;

//Register to keep count during ACCESS fsm state
//In access_state state:
//1. Count = 0, latch the addr and value, ready = 0
//2. Count = 1, write the value in that addr of register bank, ready = 0
//3. Count = 2, Data is written into the register bank, assert ready
always@(posedge pclk or negedge presetn)begin
        if(!presetn) count_access <= 0;
        else if (current_state == access_state) count_access <= count_access + 1;
        else count_access <= 0;
end

always@(*)begin
        case(current_state)
        idle: pready = 1;
        setup: pready = 1;
        access_state: begin
                if(count_access == 0 | count_access == 1) pready = 0;
                else pready = 1;
        end
        default: pready = 1;
        endcase
end

reg sync1, qspi_busy_sync;
always@(posedge pclk or negedge presetn)begin
        if(~presetn) begin
                sync1 <= 0;
                qspi_busy_sync <= 0;
        end
        else begin
                sync1 <= qspi_busy;
                qspi_busy_sync <= sync1;
        end
end

// ---------------------------------------------------------------------
// req_pending: closes the CDC data-enable-sequencing gap flagged by
// SpyGlass (Ac_datahold01a) on cmd_reg/addr_reg/dummy_reg/len_reg.
//
// qspi_busy_sync only asserts AFTER domain_crossing has latched the bus
// (in the sclk domain) and busy_reg has propagated back through 2 pclk
// sync flops. That leaves a window - from the pclk edge that writes the
// start bit, through the start_toggle -> sclk CDC, up to the moment
// domain_crossing samples cmd_reg/addr_reg/dummy_reg/len_reg - during
// which qspi_busy_sync is still 0 and these registers were previously
// unprotected. req_pending is set on that same edge the start bit is
// written and held until qspi_busy_sync confirms the destination has
// taken over, guaranteeing the source bus is stable for the entire
// synchronization latency.
// ---------------------------------------------------------------------
reg req_pending;
wire busy_or_pending = qspi_busy_sync | req_pending;

always@(posedge pclk or negedge presetn) begin
        if(!presetn) req_pending <= 1'b0;
        else if (current_state == access_state && count_access == 1 && pwrite
                  && paddr == control_signals && pwdata[0])
                req_pending <= 1'b1;      // set the instant 'start' is written
        else if (qspi_busy_sync)
                req_pending <= 1'b0;      // clear once destination has ack'd -
                                           // data is guaranteed captured by then
end

always@(posedge pclk or negedge presetn)begin
        if(!presetn) begin
                cmd_reg <= 0;
                addr_reg <= 0;
                dummy_reg <= 0;
                width_reg <= 0;
                len_reg <= 0;
                tx_fifo_data <= 0;
                ctrl_reg <= 0;
                ctrl_reg_prev <= 0;
        end
        else begin
                ctrl_reg_prev <= ctrl_reg[0];
                if (current_state == access_state && count_access == 1 && pwrite) begin
                 case (paddr)
                 command_code:        if (~busy_or_pending) cmd_reg   <= pwdata[7:0];
                address_bytes:        if (~busy_or_pending) addr_reg  <= pwdata[23:0];
                dummy_cycles_count:    if (~busy_or_pending) dummy_reg <= pwdata[4:0];
                length_of_data:        if (~busy_or_pending) len_reg   <= pwdata[7:0];
                data_width: width_reg    <= pwdata[7:0];   // not CDC-gated yet, separate known gap
                write_fifo_data: tx_fifo_data <= pwdata[7:0];
                control_signals: ctrl_reg     <= pwdata[1:0];   // keep writable — abort should work even while busy
    endcase
end
        end
end
always@(posedge pclk or negedge presetn)begin
        if(~presetn) start_toggle <= 0;
        else if(start) start_toggle <= ~start_toggle;
        else start_toggle <= start_toggle;
end
endmodule
