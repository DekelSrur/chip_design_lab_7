`timescale 1ns / 1ps

module tb_cfg_latch;

    logic clk = 0;
    logic rst_n = 0;
    logic btn_db = 0, busy = 0, rx_mode = 0;   // TX mode, TX idle
    logic [14:0] sw_db = '0;
    logic start;
    logic [7:0] byte_val;
    logic [1:0] speed_sel, count_sel;
    
    int errors = 0;

    cfg_latch dut (.clk(clk), .rst_n(rst_n), .btn_db(btn_db), .busy(busy),
                   .rx_mode(rx_mode), .sw_db(sw_db), .start(start),
                   .byte_val(byte_val), .speed_sel(speed_sel), .count_sel(count_sel));

    always #5 clk = ~clk;

    // press the button for one clock
    task automatic press();
        @(negedge clk) btn_db = 1;
        @(negedge clk) btn_db = 0;
    endtask

    initial begin
        #20 rst_n = 1;

        // test 1: normal press - start pulse and values latched
        sw_db = 15'b10_000_01_1010_0101;        // {count = 2, unused, speed = 1, byte = A5}
        press();
        if (start !== 1 || byte_val !== 8'hA5 || speed_sel !== 1 || count_sel !== 2) begin
            $display("Test 1 FAILED");
            errors++;
        end
        else
            $display("Test 1 PASSED: start pulse, byte=%h speed=%0d count=%0d", byte_val, speed_sel, count_sel);

        // test 2: press while busy - no start
        busy = 1;
        press();
        if (start !== 0) begin
            $display("Test 2 FAILED");
            errors++;
        end
        else
            $display("Test 2 PASSED: press ignored while busy");
        busy = 0;

        // test 3: press in RX mode - no start
        rx_mode = 1;
        press();
        if (start !== 0) begin
            $display("Test 3 FAILED");
            errors++;
        end
        else
            $display("Test 3 PASSED: press ignored in RX mode");
        rx_mode = 0;

        // test 4: button held down - start only once (edge, not level)
        @(negedge clk) btn_db = 1;
        for (int i = 0; i < 3; i++) @(negedge clk);
        if (start !== 0) begin
            $display("Test 4 FAILED");
            errors++;
        end
        else
            $display("Test 4 PASSED: one start pulse while the button is held");
        btn_db = 0;

        if (errors == 0) $display("tb_cfg_latch PASSED");
        else             $display("tb_cfg_latch FAILED, %0d errors", errors);
        $finish;
    end

endmodule