`timescale 1ns / 1ps
//   dut_1k  : 1024 slots, CIE 128 (G_EQ - default configuration)
//   dut_4k  : 4096 slots, CIE 256 (G_UP - no brightness limit)
//   dut_512 :  512 slots, CIE 64 (G_DOWN)
module tb_color_translate;
    import pkg_lab6::*;

//DUT signals - 4-state logic, so X/Z from the DUT stays visible
    logic clk = 0;
    logic rst_n = 0;
    logic [N_CH*BYTE-1:0] applyRGB = '0;    // {R, G, B}
    logic busy = 0;                         // tx_fsm busy (driven by the TB)

    logic [N_CH-1:0][9:0]  duty_1k; logic [N_CH*10-1:0] trns_1k; logic start_1k;
    logic [N_CH-1:0][11:0] duty_4k; logic [N_CH*12-1:0] trns_4k;   logic start_4k;
    logic [N_CH-1:0][8:0]  duty_512; logic [N_CH*9-1:0] trns_512;  logic start_512;

    // TB-internal bookkeeping - 2-state / int
    int errors  = 0;
    int n_start = 0;                        // color_start pulses seen on dut_1k
    int lat, bad, n_before;
    logic [N_CH*BYTE-1:0] rgb;

    color_translate #(.PWM_SLOTS(1024), .CIE_SCALE(128)) dut_1k (
        .clk(clk), .rst_n(rst_n), .applyRGB(applyRGB), .busy(busy),
        .duty(duty_1k), .color_start(start_1k), .trns_msg(trns_1k));

    color_translate #(.PWM_SLOTS(4096), .CIE_SCALE(256)) dut_4k (
        .clk(clk), .rst_n(rst_n), .applyRGB(applyRGB), .busy(busy),
        .duty(duty_4k), .color_start(start_4k), .trns_msg(trns_4k));

    color_translate #(.PWM_SLOTS(512), .CIE_SCALE(64)) dut_512 (
        .clk(clk), .rst_n(rst_n), .applyRGB(applyRGB), .busy(busy),
        .duty(duty_512), .color_start(start_512), .trns_msg(trns_512));

    always #5 clk = ~clk;                   // 100 MHz

    // monitor on every rising edge after reset:
    //   - control outputs must never be X/Z
    //   - all instances must pulse color_start on the same cycle (same latency)
    always @(posedge clk) begin
        if (rst_n) begin
            if ($isunknown({start_1k, start_4k, start_512})) begin
                $display("[%0t] FAILED: X/Z on color_start", $time);
                errors++;
            end
            else if (start_4k !== start_1k || start_512 !== start_1k) begin
                $display("[%0t] FAILED: color_start not aligned between instances", $time);
                errors++;
            end
            if (start_1k === 1'b1) n_start++;
        end
    end

    // reference model: gamma -> fit to PWM_W bits -> * CIE / 256
    // (gamma values are read from the DUT's copy of the provided table)
    function automatic int exp_duty(input int srgb, input int pwm_w, input int cie);
        int lin, fit;
        lin = dut_1k.gamma_table[srgb];
        fit = (pwm_w >= GAMMA_W) ? (lin << (pwm_w - GAMMA_W)) : (lin >> (GAMMA_W - pwm_w));
        return (fit * cie) >> 8;
    endfunction : exp_duty

    // compare duty (and optionally trns_msg) of all instances with the reference model
    // !== is used on purpose: an X/Z in the DUT output counts as a mismatch
    task automatic check_values(input logic [N_CH*BYTE-1:0] rgb_in, input bit check_trns,
                                output int n_bad);
        int s;
        n_bad = 0;
        foreach (duty_1k[c]) begin
            s = rgb_in[c*BYTE +: BYTE];
            if (duty_1k[c]  !== exp_duty(s, 10, 128)) n_bad++;
            if (duty_4k[c]  !== exp_duty(s, 12, 256)) n_bad++;
            if (duty_512[c] !== exp_duty(s,  9,  64)) n_bad++;
            if (check_trns) begin
                if (trns_1k [c*10 +: 10] !== exp_duty(s, 10, 128)) n_bad++;
                if (trns_4k [c*12 +: 12] !== exp_duty(s, 12, 256)) n_bad++;
                if (trns_512[c*9  +: 9 ] !== exp_duty(s,  9,  64)) n_bad++;
            end
        end
    endtask : check_values

    // apply a color and wait for its report; lat = clocks until color_start (-1 = timeout)
    task automatic apply_and_wait(input logic [N_CH*BYTE-1:0] rgb_in, output int lat_out);
        @(negedge clk) applyRGB = rgb_in;
        lat_out = 0;
        do begin
            @(negedge clk);
            lat_out++;
        end while (start_1k !== 1'b1 && lat_out < 50);
        if (start_1k !== 1'b1) lat_out = -1;
    endtask : apply_and_wait

    initial begin
        // test 1: reset - no report, duty = 0 (=== also rejects X/Z)
        #20 rst_n = 1;
        repeat (10) @(negedge clk);
        if (n_start !== 0 || duty_1k !== '0 || duty_4k !== '0 || duty_512 !== '0) begin
            $display("Test 1 FAILED: activity or X/Z after reset");
            errors++;
        end
        else
            $display("Test 1 PASSED: no report and duty = 0 after reset");

        // test 2: first color - latency, values, single-cycle pulse
        rgb = {8'hFF, 8'h80, 8'h00};
        apply_and_wait(rgb, lat);
        check_values(rgb, 1, bad);
        if (lat !== 4 || bad !== 0) begin
            $display("Test 2 FAILED: latency=%0d (exp 4), %0d wrong values", lat, bad);
            errors++;
        end
        else
            $display("Test 2 PASSED: latency=4, duty_1k R=%0d G=%0d B=%0d",
                     duty_1k[2], duty_1k[1], duty_1k[0]);
        @(negedge clk);
        if (start_1k !== 1'b0) begin
            $display("Test 2b FAILED: color_start longer than one cycle");
            errors++;
        end
        else
            $display("Test 2b PASSED: color_start is a single-cycle pulse");

        // test 3: busy - duty updates at once, the report waits for !busy
        busy = 1;
        n_before = n_start;
        rgb = {8'h10, 8'h20, 8'h30};
        @(negedge clk) applyRGB = rgb;
        repeat (20) @(negedge clk);
        check_values(rgb, 0, bad);
        if (n_start !== n_before || bad !== 0) begin
            $display("Test 3 FAILED: report while busy or duty not updated");
            errors++;
        end
        else
            $display("Test 3 PASSED: duty updated, report held while busy");
        busy = 0;
        repeat (5) @(negedge clk);
        check_values(rgb, 1, bad);
        if (n_start !== n_before + 1 || bad !== 0) begin
            $display("Test 3b FAILED: no / wrong report after busy dropped");
            errors++;
        end
        else
            $display("Test 3b PASSED: report sent after busy dropped");

        // test 4: two colors while busy - exactly one report, with the latest color
        busy = 1;
        n_before = n_start;
        @(negedge clk) applyRGB = {8'h11, 8'h22, 8'h33};
        repeat (10) @(negedge clk);
        rgb = {8'hAA, 8'hBB, 8'hCC};
        @(negedge clk) applyRGB = rgb;
        repeat (10) @(negedge clk);
        busy = 0;
        repeat (20) @(negedge clk);
        check_values(rgb, 1, bad);
        if (n_start !== n_before + 1 || bad !== 0) begin
            $display("Test 4 FAILED: %0d reports (exp 1), %0d wrong values", n_start - n_before, bad);
            errors++;
        end
        else
            $display("Test 4 PASSED: one report with the latest color");

        // test 5: same color stays applied - no new report
        n_before = n_start;
        @(negedge clk) applyRGB = rgb;
        repeat (20) @(negedge clk);
        if (n_start !== n_before) begin
            $display("Test 5 FAILED: report without a color change");
            errors++;
        end
        else
            $display("Test 5 PASSED: no report when the color does not change");

        // test 6: full sweep - every sRGB value on every channel, different per channel
        n_before = errors;
        for (int i = 0; i < 256; i++) begin
            rgb = {8'(i), 8'(255 - i), 8'(i) ^ 8'h5A};
            apply_and_wait(rgb, lat);
            check_values(rgb, 1, bad);
            if (lat !== 4 || bad !== 0) begin
                if (errors - n_before < 5)          // print only the first few failures
                    $display("Test 6 FAILED at i=%0d: latency=%0d, %0d wrong values", i, lat, bad);
                errors++;
            end
        end
        if (errors == n_before)
            $display("Test 6 PASSED: 256-value sweep on all channels and resolutions");

        if (errors == 0) $display("ALL TESTS PASSED");
        else             $display("%0d TEST(S) FAILED", errors);
        $finish;
    end

endmodule : tb_color_translate