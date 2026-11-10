`timescale 1ns / 1ps

module tb_pwm_ctrl;
    import pkg_lab6::*;

    localparam int SLOTS = 1024;
    localparam int PWM_W = $clog2(SLOTS);

    //DUT signals - 4-state logic, so X/Z from the DUT stays visible
    logic clk = 0;
    logic rst_n = 0;
    logic [N_CH-1:0][PWM_W-1:0] duty = '0;  // {R, G, B}
    logic led_sel = 1;                      // 1 = LED16, 0 = LED17
    logic [N_CH-1:0] led16, led17;          // {R, G, B}

    //tb-internal bookkeeping - 2-state / int
    int errors = 0;
    int hi16 [N_CH], hi17 [N_CH];           // measured high cycles per channel
    int cnt_hi;

    pwm_ctrl #(.PWM_SLOTS(SLOTS)) dut (
        .clk(clk), .rst_n(rst_n), .duty(duty), .led_sel(led_sel),
        .led16(led16), .led17(led17));

    always #5 clk = ~clk;                   // 100 MHz

    //X/Z check on the outputs; returns 1 if the outputs are clean
    function automatic bit outputs_known();
        if ($isunknown({led16, led17})) begin
            $display("[%0t] FAILED: X/Z on PWM outputs (led16=%b led17=%b)", $time, led16, led17);
            errors++;
            return 0;
        end
        return 1;
    endfunction : outputs_known

    //stop on the last slot of the current period -> the next period uses the new duty
    task automatic wait_period_end();
        do @(negedge clk); while (dut.cnt !== '1);
    endtask : wait_period_end

    //count high cycles over one full period
    //window starts at cnt == 1 because the outputs are registered (1-clock lag)
    task automatic measure(output int h16 [N_CH], output int h17 [N_CH]);
        bit x_seen = 0;                     // report X/Z only once per period
        do @(negedge clk); while (dut.cnt !== PWM_W'(1));
        foreach (h16[c]) begin
            h16[c] = 0;
            h17[c] = 0;
        end
        repeat (SLOTS) begin
            if (!x_seen && !outputs_known()) x_seen = 1;
            foreach (h16[c]) begin
                h16[c] += (led16[c] === 1'b1);
                h17[c] += (led17[c] === 1'b1);
            end
            @(negedge clk);
        end
    endtask : measure

    //program duty / led_sel, measure one period, compare with the expected counts
    task automatic check_duty(input int r, input int g, input int b,
                              input logic sel, input string name);
        int exp [N_CH];
        int n_bad;
        exp = '{b, g, r};                   // index 0 = B, 1 = G, 2 = R
        @(negedge clk);
        duty    = {PWM_W'(r), PWM_W'(g), PWM_W'(b)};
        led_sel = sel;
        wait_period_end();
        measure(hi16, hi17);
        n_bad = 0;
        foreach (exp[c]) begin
            if (hi16[c] != (sel ? exp[c] : 0)) n_bad++;
            if (hi17[c] != (sel ? 0 : exp[c])) n_bad++;
        end
        if (n_bad != 0) begin
            $display("%s FAILED: sel=%0b exp RGB=%0d/%0d/%0d | LED16=%0d/%0d/%0d LED17=%0d/%0d/%0d",
                     name, sel, r, g, b, hi16[2], hi16[1], hi16[0], hi17[2], hi17[1], hi17[0]);
            errors++;
        end
        else
            $display("%s PASSED: %s RGB=%0d/%0d/%0d", name, sel ? "LED16" : "LED17", r, g, b);
    endtask : check_duty

    initial begin
        //test 1: reset - all outputs off (=== also rejects X/Z)
        #15;
        if (led16 !== '0 || led17 !== '0) begin
            $display("Test 1 FAILED: outputs active or X/Z during reset");
            errors++;
        end
        else
            $display("Test 1 PASSED: outputs off during reset");
        #5 rst_n = 1;

        //test 2: typical values on each LED
        check_duty(100, 512, 1000, 1'b1, "Test 2a");
        check_duty(100, 512, 1000, 1'b0, "Test 2b");

        //test 3: edge values (fully off, max, one-off-max)
        check_duty(0, 0, 0, 1'b1, "Test 3a");
        check_duty(1023, 1023, 1023, 1'b1, "Test 3b");
        check_duty(1, 1022, 0, 1'b0, "Test 3c");

        //test 4: duty changed in the middle of a period -> current period keeps the old value
        @(negedge clk);
        duty = {PWM_W'(200), PWM_W'(0), PWM_W'(0)};
        led_sel = 1'b1;
        wait_period_end();
        do @(negedge clk); while (dut.cnt !== PWM_W'(1));
        cnt_hi = 0;
        for (int i = 0; i < SLOTS; i++) begin
            if (i == SLOTS/2) duty[2] = PWM_W'(800);    // change mid-period
            cnt_hi += (led16[2] === 1'b1);
            @(negedge clk);
        end
        measure(hi16, hi17);
        if (cnt_hi != 200 || hi16[2] != 800) begin
            $display("Test 4 FAILED: period with change=%0d (exp 200), next period=%0d (exp 800)",
                     cnt_hi, hi16[2]);
            errors++;
        end
        else
            $display("Test 4 PASSED: new duty applied only from the next period");

        // test 5: random values and LED selection
        repeat (20)
            check_duty($urandom_range(SLOTS-1), $urandom_range(SLOTS-1),
                       $urandom_range(SLOTS-1), 1'($urandom_range(1)), "Test 5");

        if (errors == 0) $display("ALL TESTS PASSED");
        else $display("%0d TEST(S) FAILED", errors);
        $finish;
    end

endmodule : tb_pwm_ctrl