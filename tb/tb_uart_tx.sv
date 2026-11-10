`timescale 1ns / 1ps

module tb_uart_tx;

    localparam CPB   = 8;           // clocks per bit in simulation (instead of 1736)
    localparam T_BIT = CPB * 10;    // one bit = 80 ns

    logic clk = 0, rst_n = 0;
    logic tx_start = 0;
    logic [7:0] tx_data = '0;
    logic tx, tx_busy, tx_done;
    
    int errors = 0;
    int n_done = 0;                 // number of tx_done pulses

    uart_tx #(.CLKS_PER_BIT(CPB)) dut (.clk(clk), .rst_n(rst_n), .tx_start(tx_start),
                                       .tx_data(tx_data), .tx(tx), .tx_busy(tx_busy),
                                       .tx_done(tx_done));

    always #5 clk = ~clk;

    always @(posedge clk)           // count the tx_done pulses
        if (tx_done) n_done++;

    // send one byte and read it back from the tx line (8N1, LSB first)
    task automatic send_and_check(input logic [7:0] b);
        logic [7:0] rx;
        int         e;
        e = errors;                  // errors before this byte
        @(negedge clk);
        tx_start = 1;
        tx_data  = b;
        @(negedge clk);
        tx_start = 0;
        #(T_BIT/2 - 10);             // middle of the start bit
        if (tx !== 0 || tx_busy !== 1) begin
            $display("Byte %h FAILED: no start bit / not busy", b);
            errors++;
        end
        for (int i = 0; i < 8; i++) begin       // sample every data bit in its middle
            #(T_BIT);
            rx[i] = tx;
        end
        #(T_BIT);                               // middle of the stop bit
        if (tx !== 1 || tx_busy !== 1) begin
            $display("Byte %h FAILED: no stop bit", b);
            errors++;
        end
        if (rx !== b) begin
            $display("Byte %h FAILED: received %h", b, rx);
            errors++;
        end
        #(T_BIT);                               // frame is over
        if (tx_busy !== 0) begin
            $display("Byte %h FAILED: still busy after the frame", b);
            errors++;
        end
        if (errors == e)                        // no new errors for this byte
            $display("Byte %h PASSED: received %h", b, rx);
    endtask

    initial begin

        // test 1: after reset the line is idle (1) and not busy
        #20 rst_n = 1;
        #1;
        if (tx !== 1 || tx_busy !== 0) begin
            $display("Test 1 FAILED: tx=%b busy=%b", tx, tx_busy);
            errors++;
        end
        else
            $display("Test 1 PASSED: line idle after reset");

        // test 2: send a few bytes, each one is read back correctly
        send_and_check(8'hA5);                  // alternating bits
        send_and_check(8'h00);
        send_and_check(8'hFF);
        send_and_check(8'h41);

        // test 3: one tx_done pulse for every byte
        if (n_done !== 4) begin
            $display("Test 3 FAILED: %0d tx_done pulses, expected 4", n_done);
            errors++;
        end
        else
            $display("Test 3 PASSED: 4 tx_done pulses");

        // test 4: tx_start while busy is ignored - only one frame is sent
        @(negedge clk);
        tx_start = 1;
        tx_data  = 8'h0F;
        @(negedge clk);
        tx_start = 0;
        #(3 * T_BIT);                           // in the middle of the frame
        @(negedge clk);
        tx_start = 1;                           // second request while busy
        tx_data  = 8'hFF;
        @(negedge clk);
        tx_start = 0;
        #(10 * T_BIT);
        if (n_done !== 5 || tx_busy !== 0 || tx !== 1) begin
            $display("Test 4 FAILED: second start was not ignored");
            errors++;
        end
        else
            $display("Test 4 PASSED: tx_start ignored while busy");

        // test 5: reset in the middle of a frame - line goes back to idle at once
        @(negedge clk);
        tx_start = 1;
        tx_data  = 8'h00;
        @(negedge clk);
        tx_start = 0;
        #(2 * T_BIT);
        rst_n = 0;
        #1;
        if (tx !== 1 || tx_busy !== 0) begin
            $display("Test 5 FAILED: tx=%b busy=%b", tx, tx_busy);
            errors++;
        end
        else
            $display("Test 5 PASSED: asynchronous reset");

        if (errors == 0) $display("tb_uart_tx PASSED");
        else             $display("tb_uart_tx FAILED, %0d errors", errors);
        $finish;
    end

endmodule