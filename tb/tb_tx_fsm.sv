`timescale 1ns / 1ps

module tb_tx_fsm;

    localparam D50 = 20, D100 = 40, D200 = 80;  // short delays for simulation (in clocks)

    logic clk = 0, rst_n = 0;
    logic start = 0;
    logic [7:0] byte_val = '0;
    logic [1:0] speed_sel = '0, count_sel = '0;
    logic tx_done = 0;
    logic tx_start, led, busy;
    logic [7:0] tx_data;
    logic [8:0] rows_sent;
    logic [16:0] bytes_sent;
    
    int errors = 0;
    int t_sent [3000];                 // time of every tx_start (ns)
    int n = 0;                         // number of characters
    int n_data, n_cr;
    int gap;                           // time between two characters (ns)

    logic [7:0] sent [3000];           // every character the FSM asked to send
    

    tx_fsm #(.DELAY_50MS(D50), .DELAY_100MS(D100), .DELAY_200MS(D200)) dut (
        .clk(clk), .rst_n(rst_n), .start(start), .byte_val(byte_val),
        .speed_sel(speed_sel), .count_sel(count_sel), .tx_done(tx_done),
        .tx_start(tx_start), .tx_data(tx_data), .led(led), .busy(busy),
        .rows_sent(rows_sent), .bytes_sent(bytes_sent));

    always #5 clk = ~clk;

    // stop the simulation if it hangs (for example a wait that never ends)
    initial begin
        #10_000_000;
        $display("tb_tx_fsm FAILED: timeout");
        $finish;
    end

    // simple uart model: save the character and answer with tx_done 3 clocks later
    always @(posedge clk) begin
        if (tx_start) begin
            sent[n]   = tx_data;
            t_sent[n] = $time;
            n++;
            for (int i = 0; i < 3; i++) @(posedge clk);
            tx_done <= 1;
            @(posedge clk);
            tx_done <= 0;
        end
    end

    // start a transfer and wait until it ends
    task automatic run(input logic [7:0] b, input logic [1:0] sp, input logic [1:0] cs);
        byte_val  = b;
        speed_sel = sp;
        count_sel = cs;
        n = 0;
        @(negedge clk) start = 1;
        @(negedge clk) start = 0;
        wait (busy == 0);
        #100;
    endtask

    initial begin
        #20 rst_n = 1;

        // test 1: N = 1 exactly "41 20 0D 0A" (byte, space, CR, LF), LED on after byte 0
        run(8'h41, 0, 0);
        if (n !== 4 || sent[0] !== 8'h41 || sent[1] !== 8'h20 ||
            sent[2] !== 8'h0D || sent[3] !== 8'h0A || led !== 1 || rows_sent !== 1) begin
            $display("Test 1 FAILED: %0d chars %h %h %h %h", n, sent[0], sent[1], sent[2], sent[3]);
            errors++;
        end
        else
            $display("Test 1 PASSED: %h %h %h %h, LED on", sent[0], sent[1], sent[2], sent[3]);

        // test 2: N = 32 rows x 32 bytes, 32x32x2 + 32x2 = 2112 characters
        run(8'h55, 0, 1);
        n_data = 0;
        n_cr   = 0;
        for (int i = 0; i < n; i++) begin
            if (sent[i] == 8'h55) n_data++;     // data bytes
            if (sent[i] == 8'h0D) n_cr++;       // one CR per row
        end
        if (n !== 2112 || n_data !== 1024 || n_cr !== 32 || rows_sent !== 32 ||
            led !== 0) begin                    // last byte (1023) is odd -> LED off
            $display("Test 2 FAILED: %0d chars, %0d data bytes, %0d rows, LED=%b", n, n_data, n_cr, led);
            errors++;
        end
        else
            $display("Test 2 PASSED: %0d chars, %0d data bytes, %0d rows, LED off", n, n_data, n_cr);

        // test 3: delay between bytes - gap from the space of byte 0 to data byte 1
        //         must be at least the delay and at most 10 clocks more
        run(8'h55, 1, 1);
        gap = t_sent[2] - t_sent[1];
        if (gap < D50 * 10 || gap > D50 * 10 + 100) begin
            $display("Test 3 FAILED: 50 ms gap = %0d ns", gap);
            errors++;
        end
        else
            $display("Test 3 PASSED: 50 ms  -> gap %0d ns", gap);
        run(8'h55, 2, 1);
        gap = t_sent[2] - t_sent[1];
        if (gap < D100 * 10 || gap > D100 * 10 + 100) begin
            $display("Test 3 FAILED: 100 ms gap = %0d ns", gap);
            errors++;
        end
        else
            $display("Test 3 PASSED: 100 ms -> gap %0d ns", gap);
        run(8'h55, 3, 1);
        gap = t_sent[2] - t_sent[1];
        if (gap < D200 * 10 || gap > D200 * 10 + 100) begin
            $display("Test 3 FAILED: 200 ms gap = %0d ns", gap);
            errors++;
        end
        else
            $display("Test 3 PASSED: 200 ms -> gap %0d ns", gap);

        // test 4: start during a transfer is ignored
        byte_val = 8'h55; speed_sel = 0; count_sel = 1; n = 0;
        @(negedge clk) start = 1;
        @(negedge clk) start = 0;
        #2000;
        @(negedge clk) start = 1;               // second press in the middle
        @(negedge clk) start = 0;
        wait (busy == 0);
        #100;
        if (n !== 2112) begin
            $display("Test 4 FAILED: %0d chars, expected 2112", n);
            errors++;
        end
        else
            $display("Test 4 PASSED: second start ignored");

        // test 5: reset in the middle of a transfer stops it at once
        byte_val = 8'h55; speed_sel = 0; count_sel = 1;
        @(negedge clk) start = 1;
        @(negedge clk) start = 0;
        #2000;
        rst_n = 0;
        #1;
        if (busy !== 0 || tx_start !== 0) begin
            $display("Test 5 FAILED: busy=%b", busy);
            errors++;
        end
        else
            $display("Test 5 PASSED: asynchronous reset");

        if (errors == 0) $display("tb_tx_fsm PASSED");
        else             $display("tb_tx_fsm FAILED, %0d errors", errors);
        $finish;
    end

endmodule