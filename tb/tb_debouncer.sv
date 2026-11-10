`timescale 1ns/1ps

module tb_debouncer;

    localparam DB = 10;         //short debounce window for simulation

    logic clk = 0;
    logic rst_n = 0;
    logic [15:0] sw_in = '0;
    logic btn_in = 0;
    logic btn_db;
    logic [15:0] sw_db;

    int errors;

    debouncer #(.DEBOUNCE_CYCLES(DB))
            dut (.clk(clk), .rst_n(rst_n), .btn_in(btn_in),
                .sw_in(sw_in), .btn_db(btn_db), .sw_db(sw_db));
    
    always #5 clk = ~clk;

     initial begin
        #20 rst_n = 1;

        // test 1: short bounce (5 clocks < DB) - output stays 0
        @(negedge clk) btn_in = 1;
        for (int i = 0; i < 5; i++) @(negedge clk);
        btn_in = 0;
        for (int i = 0; i < 20; i++) @(negedge clk);
        if (btn_db !== 0) begin
            $display("Test 1 FAILED: short bounce passed");
            errors++;
        end
        else
            $display("Test 1 PASSED: short bounce filtered");

        // test 2: stable press - output changes after exactly DB clocks
        @(negedge clk) btn_in = 1;
        for (int i = 0; i < DB - 1; i++) @(posedge clk);
        #1;
        if (btn_db !== 0) begin                 // one edge before the end of the window
            $display("Test 2 FAILED: output changed too early");
            errors++;
        end
        else
            $display("Test 2 PASSED: no change after %0d clocks", DB - 1);
        @(posedge clk);
        #1;
        if (btn_db !== 1) begin                 // window is over
            $display("Test 2 FAILED: output did not change after %0d clocks", DB);
            errors++;
        end
        else
            $display("Test 2 PASSED: output changed after %0d clocks", DB);

        // test 3: all 16 switches pass after a stable window
        @(negedge clk) sw_in = 16'hFFFF;
        for (int i = 0; i < DB + 2; i++) @(negedge clk);
        if (sw_db !== 16'hFFFF) begin
            $display("Test 3 FAILED: sw_db = %h", sw_db);
            errors++;
        end
        else
            $display("Test 3 PASSED: all switches passed");

        // test 4: asynchronous reset clears all outputs at once
        #2 rst_n = 0;                           // middle of a clock cycle
        #1;
        if (btn_db !== 0 || sw_db !== 16'h0000) begin
            $display("Test 4 FAILED: reset did not clear the outputs");
            errors++;
        end
        else
            $display("Test 4 PASSED: asynchronous reset");

        if (errors == 0) $display("tb_debouncer PASSED");
        else             $display("tb_debouncer FAILED, %0d errors", errors);
        $finish;
    end

endmodule