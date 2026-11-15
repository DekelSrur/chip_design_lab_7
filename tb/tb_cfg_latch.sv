`timescale 1ns / 1ps

module tb_cfg_latch;

    localparam int HOLD = 10;                   // 1 s in hardware, 10 clocks in simulation

    logic clk = 0;
    logic rst_n = 0;
    logic btn_db = 0, busy = 0, rx_mode = 0;   // TX mode, TX idle
    logic [14:0] sw_db = '0;
    logic start;
    logic [7:0] byte_val;
    logic [1:0] speed_sel, count_sel;

    int errors = 0;
    int n_start = 0;                            // start pulses seen

    cfg_latch #(.HOLD_CYCLES(HOLD)) dut (.clk(clk), .rst_n(rst_n), .btn_db(btn_db), .busy(busy),
                   .rx_mode(rx_mode), .sw_db(sw_db), .start(start),
                   .byte_val(byte_val), .speed_sel(speed_sel), .count_sel(count_sel));

    always #5 clk = ~clk;

    always @(posedge clk) #1 if (start === 1'b1) n_start++;

    // hold the button for n clocks, then release it
    task automatic hold(input int n);
        @(negedge clk) btn_db = 1;
        repeat (n) @(negedge clk);
        btn_db = 0;
        repeat (3) @(negedge clk);
    endtask

    task automatic check(input string name, input int exp_starts);
        if (n_start !== exp_starts) begin
            $display("%s FAILED: %0d start pulses, expected %0d", name, n_start, exp_starts);
            errors++;
        end
        else
            $display("%s PASSED", name);
        n_start = 0;
    endtask

    initial begin
        #20 rst_n = 1;
        sw_db = 15'b10_000_01_1010_0101;        // {count = 2, unused, speed = 1, byte = A5}

        // test 1: short press (shorter than the hold time) - nothing happens
        hold(HOLD - 2);
        check("Test 1: short press ignored", 0);
        if (byte_val !== '0) begin
            $display("Test 1 FAILED: switches latched on a short press");
            errors++;
        end

        // test 2: long press - one start pulse and the switches are latched
        hold(HOLD + 2);
        check("Test 2: long press latches", 1);
        if (byte_val !== 8'hA5 || speed_sel !== 1 || count_sel !== 2) begin
            $display("Test 2 FAILED: byte=%h speed=%0d count=%0d", byte_val, speed_sel, count_sel);
            errors++;
        end

        // test 3: very long press - still only one start pulse
        hold(HOLD * 5);
        check("Test 3: one start per press", 1);

        // test 4: long press while busy - no start
        busy = 1;
        hold(HOLD + 2);
        check("Test 4: ignored while busy", 0);
        busy = 0;

        // test 5: long press in RX mode - no start
        rx_mode = 1;
        hold(HOLD + 2);
        check("Test 5: ignored in RX mode", 0);
        rx_mode = 0;

        // test 6: two short presses do not add up to a long one
        hold(HOLD - 2);
        hold(HOLD - 2);
        check("Test 6: hold timer restarts on release", 0);

        if (errors == 0) $display("tb_cfg_latch PASSED");
        else             $display("tb_cfg_latch FAILED, %0d errors", errors);
        $finish;
    end

endmodule
