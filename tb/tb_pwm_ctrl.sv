`timescale 1ns / 1ps

module tb_pwm_ctrl;
    import pkg_sys::*;

    localparam int SLOTS = 1024;
    localparam int PWM_W = $clog2(SLOTS);

    //DUT signals - 4-state logic, so X/Z from the DUT stays visible
    logic clk = 0;
    logic rst_n = 0;
    logic [N_CH-1:0][PWM_W-1:0] duty = '0;  // {R, G, B}
    logic led_sel = 1;                      // 1 = LED16, 0 = LED17
    logic [15:0] pwm_slots = SLOTS;         // PWM_CFG.time_slots
    logic [N_CH-1:0] led16, led17;          // {R, G, B}

    //tb-internal bookkeeping - 2-state / int
    int errors = 0;
    int hi16 [N_CH], hi17 [N_CH];           // measured high cycles per channel
    int cnt_hi;
    int per;                                // measured period length

    pwm_ctrl #(.PWM_SLOTS(SLOTS)) dut (
        .clk(clk), .rst_n(rst_n), .duty(duty), .pwm_slots(pwm_slots), .led_on({~led_sel, led_sel}),
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
        do @(negedge clk); while (dut.last_slot !== 1'b1);
    endtask : wait_period_end

    //count high cycles over one full period
    //window starts at cnt == 1 because the outputs are registered (1-clock lag)
    task automatic measure(output int h16 [N_CH], output int h17 [N_CH]);
        bit x_seen = 0;                     // report X/Z only once per period
        int n;
        do @(negedge clk); while (dut.cnt !== 1);
        n = dut.slots_q;                    // length of this period
        foreach (h16[c]) begin
            h16[c] = 0;
            h17[c] = 0;
        end
        for (int i = 0; i < n; i++) begin
            if (!x_seen && !outputs_known()) x_seen = 1;
            foreach (h16[c]) begin
                h16[c] += (led16[c] === 1'b1);
                h17[c] += (led17[c] === 1'b1);
            end
            @(negedge clk);
        end
    endtask : measure

    //length of the next full period, in clocks (cnt == 0 to the next cnt == 0)
    task automatic period_len(output int len);
        do @(negedge clk); while (dut.cnt !== 0);
        len = 0;
        do begin
            @(negedge clk);
            len++;
        end while (dut.cnt !== 0 && len < 20000);
    endtask : period_len

    //runtime period: duty rescaled to slots, period length, both LEDs
    task automatic check_slots(input int slots, input int exp_per, input int r, input int g, input int b,
                               input string name);
        int exp [N_CH];
        int n_bad = 0;
        @(negedge clk);
        pwm_slots = 16'(slots);
        duty = {PWM_W'(r), PWM_W'(g), PWM_W'(b)};
        led_sel = 1'b1;
        wait_period_end();                  // new values are loaded here
        period_len(per);
        exp[0] = (b * exp_per) >> PWM_W;
        exp[1] = (g * exp_per) >> PWM_W;
        exp[2] = (r * exp_per) >> PWM_W;
        measure(hi16, hi17);
        for (int c = 0; c < N_CH; c++)
            if (hi16[c] != exp[c] || hi17[c] != 0) n_bad++;
        if (per != exp_per || n_bad != 0) begin
            $display("%s FAILED: slots=%0d period=%0d (exp %0d), LED16 RGB=%0d/%0d/%0d (exp %0d/%0d/%0d)",
                     name, slots, per, exp_per, hi16[2], hi16[1], hi16[0], exp[2], exp[1], exp[0]);
            errors++;
        end
        else
            $display("%s PASSED: slots=%0d -> period %0d, LED16 RGB=%0d/%0d/%0d",
                     name, slots, per, hi16[2], hi16[1], hi16[0]);
    endtask : check_slots

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

        // test 6: runtime period from PWM_CFG.time_slots, duty rescaled to it
        check_slots(300,  300,  512, 1023, 0,   "Test 6a");
        check_slots(2048, 2048, 256, 768,  100, "Test 6b");
        check_slots(5000, 5000, 1023, 1,   512, "Test 6c");

        // test 7: illegal values are clamped (0 -> 2 slots, 9000 -> 8192 slots)
        check_slots(0,    2,    512, 1023, 0,   "Test 7a");
        check_slots(9000, 8192, 512, 1023, 1,   "Test 7b");

        // test 8: a new period length takes effect only at the end of the current period
        check_slots(1000, 1000, 100, 100, 100, "Test 8 setup");
        do @(negedge clk); while (dut.cnt !== 500);
        pwm_slots = 16'd400;                // change in the middle of a 1000-slot period
        cnt_hi = 1;
        while (dut.cnt !== 0) begin         // finish the current period
            @(negedge clk);
            cnt_hi++;
        end
        period_len(per);
        if (cnt_hi != 501 || per != 400) begin
            $display("Test 8 FAILED: current period ended after %0d more clocks (exp 501), next period %0d (exp 400)",
                     cnt_hi, per);
            errors++;
        end
        else
            $display("Test 8 PASSED: period change applied at the period end");

        if (errors == 0) $display("ALL TESTS PASSED");
        else $display("%0d TEST(S) FAILED", errors);
        $finish;
    end

endmodule : tb_pwm_ctrl