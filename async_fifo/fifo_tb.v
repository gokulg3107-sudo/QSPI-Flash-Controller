`timescale 1ns/1ps

module async_fifo_tb;

reg         wclk, rclk;
reg         wrst, rrst;
reg         wen, ren;
reg  [7:0]  write_datain;
wire [7:0]  read_dataout;
wire        full, empty;

integer i;
integer errors;
reg [7:0] expected_q [0:63];   // scoreboard of values pushed, in order
integer   push_count, pop_count;

// ---------------------------------------------------------
// DUT
// ---------------------------------------------------------
async_fifo dut (
    .wclk(wclk), .wen(wen), .wrst(wrst), .write_datain(write_datain),
    .rclk(rclk), .ren(ren), .rrst(rrst), .read_dataout(read_dataout),
    .full(full), .empty(empty)
);

// ---------------------------------------------------------
// Clocks - deliberately mismatched, non-clean ratio
// ---------------------------------------------------------
initial wclk = 0;
always #5   wclk = ~wclk;    // 10ns period  -> 100 MHz

initial rclk = 0;
always #11.5 rclk = ~rclk;   // 23ns period  -> ~43.5 MHz

// ---------------------------------------------------------
// Tasks
// ---------------------------------------------------------
task do_reset;
begin
    wrst = 0; rrst = 0;
    wen  = 0; ren  = 0;
    write_datain = 0;
    push_count = 0; pop_count = 0;
    errors = 0;
    repeat (3) @(posedge wclk);
    wrst = 1;
    repeat (3) @(posedge rclk);
    rrst = 1;
    @(posedge wclk);
end
endtask

// Push one byte, only if not full. Records into scoreboard on success.
task push_byte(input [7:0] data);
begin
    @(negedge wclk);
    if (!full) begin
        write_datain = data;
        wen = 1;
        @(posedge wclk);
        #1;
        expected_q[push_count] = data;
        push_count = push_count + 1;
        @(negedge wclk);
        wen = 0;
    end
    else begin
        $display("[%0t] INFO: push skipped, FIFO full (data=%0h not pushed)", $time, data);
        wen = 0;
    end
end
endtask

// Attempt a push while expecting it to be blocked (full=1) - checks data is NOT accepted
task push_blocked_check(input [7:0] data);
begin
    @(negedge wclk);
    if (!full) begin
        $display("[%0t] ERROR: expected FIFO full, but full=0 before blocked-push check", $time);
        errors = errors + 1;
    end
    write_datain = data;
    wen = 1;
    @(posedge wclk);
    #1;
    @(negedge wclk);
    wen = 0;
    // push_count intentionally NOT incremented - this push should not have been accepted
end
endtask

// Pop one byte, only if not empty. Checks against scoreboard.
task pop_byte;
    reg [7:0] got;
begin
    @(negedge rclk);
    if (!empty) begin
        got = read_dataout;
	ren = 1;
        @(posedge rclk);
        #1;
        if (got !== expected_q[pop_count]) begin
            $display("[%0t] ERROR: pop #%0d mismatch. Expected=%0h Got=%0h",
                       $time, pop_count, expected_q[pop_count], got);
            errors = errors + 1;
        end
        else begin
            $display("[%0t] PASS: pop #%0d = %0h", $time, pop_count, got);
        end
        pop_count = pop_count + 1;
        @(negedge rclk);
        ren = 0;
    end
    else begin
        $display("[%0t] INFO: pop skipped, FIFO empty", $time);
        ren = 0;
    end
end
endtask

// Attempt a pop while expecting it to be blocked (empty=1) - checks pointer doesn't advance
task pop_blocked_check;
begin
    @(negedge rclk);
    if (!empty) begin
        $display("[%0t] ERROR: expected FIFO empty, but empty=0 before blocked-pop check", $time);
        errors = errors + 1;
    end
    ren = 1;
    @(posedge rclk);
    #1;
    @(negedge rclk);
    ren = 0;
    // pop_count intentionally NOT incremented
end
endtask

// ---------------------------------------------------------
// Main test sequence
// ---------------------------------------------------------
initial begin
    $display("=========================================================");
    $display(" async_fifo testbench start");
    $display(" wclk period = 10ns, rclk period = 23ns (mismatched ratio)");
    $display("=========================================================");

    do_reset;

    // ---------------- Test 1: fill completely (32 entries) ----------------
    $display("\n--- Test 1: fill FIFO to full (32 pushes) ---");
    for (i = 0; i < 32; i = i + 1)
        push_byte(i[7:0]);

    @(negedge wclk);
    if (full !== 1) begin
        $display("[%0t] ERROR: expected full=1 after 32 pushes, got full=%0d", $time, full);
        errors = errors + 1;
    end else begin
        $display("[%0t] PASS: full correctly asserted after 32 pushes", $time);
    end

    // ---------------- Test 2: 33rd push must be blocked ----------------
    $display("\n--- Test 2: attempt 33rd push while full ---");
    push_blocked_check(8'hAA);
    $display("[%0t] INFO: push_count still %0d (should be 32)", $time, push_count);

    // ---------------- Test 3: drain completely (32 pops) ----------------
    $display("\n--- Test 3: drain FIFO to empty (32 pops) ---");
    for (i = 0; i < 32; i = i + 1)
        pop_byte;

    @(negedge rclk);
    if (empty !== 1) begin
        $display("[%0t] ERROR: expected empty=1 after 32 pops, got empty=%0d", $time, empty);
        errors = errors + 1;
    end else begin
        $display("[%0t] PASS: empty correctly asserted after 32 pops", $time);
    end

    // ---------------- Test 4: pop while empty must be blocked ----------------
    $display("\n--- Test 4: attempt pop while empty ---");
    pop_blocked_check;

    // ---------------- Test 5: interleaved push/pop ----------------
    $display("\n--- Test 5: interleaved push/pop traffic ---");
    push_count = 0;
    pop_count  = 0;

    push_byte(8'h10);
    push_byte(8'h11);
    push_byte(8'h12);
    pop_byte;
    push_byte(8'h13);
    pop_byte;
    pop_byte;
    push_byte(8'h14);
    push_byte(8'h15);
    pop_byte;
    pop_byte;
    pop_byte;

    // drain anything left
    while (!empty) pop_byte;

    // ---------------- Summary ----------------
    #100;
    $display("\n=========================================================");
    if (errors == 0)
        $display(" ALL TESTS PASSED");
    else
        $display(" TESTS FAILED: %0d error(s)", errors);
    $display("=========================================================");
    $finish;
end

// Safety timeout in case of hang (e.g. FSM stuck, blocked push/pop deadlock)
initial begin
    #50000;
    $display("[%0t] ERROR: TIMEOUT - simulation did not finish in time", $time);
    $finish;
end

endmodule
