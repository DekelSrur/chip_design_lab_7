`timescale 1ns / 1ps

// tb_chip_top - system-level testbench for Lab 6
//   Lab 5 regression : TX transfer, RX message parsing, 7-segment display
//   Lab 6            : RX color -> param_ctrl -> color_translate -> pwm_ctrl -> LED16/LED17,
//                      button editing (L/R select, U/D +-1, C apply), LED select, color report
//   RX messages (parser): color "{Rddd,Gddd,Bddd}", LED select "{L016}" / "{L017}"
//   Not tested yet (spec pending): color report sent on UART by tx_fsm,
//   RX display of applyRGB.
module tb_chip_top;
    import pkg_lab6::*;

    localparam int CPB   = 64;                  // clocks per bit in simulation
    localparam int T_BIT = CPB * 10;            // one bit = 640 ns
    localparam int SLOTS = PWM_SLOTS_DEF;       // chip_top default PWM resolution (1024)
    localparam int PWM_W = $clog2(SLOTS);
    localparam int CIE   = CIE_SCALE_DEF;       // chip_top default brightness (128)

    // selected-field pattern on leds[13:4]
    localparam logic [9:0] SEL_B   = 10'h003;   // T0 -> LED[5:4]
    localparam logic [9:0] SEL_G   = 10'h018;   // T1 -> LED[8:7]
    localparam logic [9:0] SEL_R   = 10'h060;   // T2 -> LED[10:9]
    localparam logic [9:0] SEL_LED = 10'h300;   // T3 -> LED[13:12]

    // buttons {c, u, d, l, r}
    localparam logic [4:0] B_C = 5'b10000;
    localparam logic [4:0] B_U = 5'b01000;
    localparam logic [4:0] B_D = 5'b00100;
    localparam logic [4:0] B_L = 5'b00010;
    localparam logic [4:0] B_R = 5'b00001;

//DUT signals - 4-state logic, so X/Z from the DUT stays visible
    logic clk = 0, cpu_resetn = 0;
    logic btnc = 0, btnu = 0, btnd = 0, btnl = 0, btnr = 0;
    logic [15:0] sw = '0;
    logic uart_rxd = 1;                         // UART line idles high
    logic uart_txd, led, led15, dp;
    logic [13:4] leds;
    logic [2:0] led16, led17;                   // {R, G, B}
    logic [7:0] an;
    logic [6:0] seg;

//tb-internal bookkeeping - 2-state / int
    int errors   = 0;
    int rx_n     = 0;                           // characters received by the PC model
    int n_report = 0;                           // color_start pulses
    int n_x      = 0;                           // cycles with X/Z on an output
    int n_before, n_bad;
    int hi16 [N_CH], hi17 [N_CH];               // measured PWM high cycles per channel
    logic [7:0] rx_char [3000];                 // characters sent by the FPGA

    // short times for simulation: debounce 10 clocks, delays 20/40/80 clocks
    chip_top #(.CLKS_PER_BIT(CPB), .DEBOUNCE_CYCLES(10), .DELAY_50MS(20),
               .DELAY_100MS(40), .DELAY_200MS(80), .REFRESH_DIV(4)) dut (
        .clk(clk), .cpu_resetn(cpu_resetn),
        .btnc(btnc), .btnu(btnu), .btnd(btnd), .btnl(btnl), .btnr(btnr),
        .sw(sw), .uart_rxd(uart_rxd),
        .uart_txd(uart_txd), .led(led), .led15(led15), .leds(leds),
        .led16(led16), .led17(led17), .an(an), .seg(seg), .dp(dp));

    always #5 clk = ~clk;                       // 100 MHz

    // stop the simulation if it hangs (for example a wait that never ends)
    initial begin
        #100_000_000;
        $display("tb_chip_top FAILED: timeout");
        $finish;
    end

    // PC receiver: read every character on uart_txd (8N1, LSB first)
    initial begin
        logic [7:0] r;
        forever begin
            @(negedge uart_txd);                // start bit
            #(T_BIT/2);
            for (int i = 0; i < 8; i++) begin   // sample every data bit in its middle
                #(T_BIT);
                r[i] = uart_txd;
            end
            #(T_BIT);                           // stop bit
            rx_char[rx_n] = r;
            rx_n++;
        end
    end

    // monitor after reset:
    //   - no X/Z on any chip_top output
    //   - color report only while tx_fsm is idle, carrying the current duty values
    always @(negedge clk) begin
        if (dut.rst_n === 1'b1) begin
            if ($isunknown({uart_txd, led, led15, leds, led16, led17, an, seg, dp})) begin
                if (n_x < 5) $display("[%0t] FAILED: X/Z on a chip_top output", $time);
                n_x++;
            end
            if (dut.color_start === 1'b1) begin
                n_report++;
                if (dut.busy !== 1'b0) begin
                    $display("[%0t] FAILED: color report while tx_fsm is busy", $time);
                    errors++;
                end
                if (dut.trns_msg !== dut.duty) begin
                    $display("[%0t] FAILED: trns_msg=%h, duty=%h", $time, dut.trns_msg, dut.duty);
                    errors++;
                end
            end
        end
    end

    // reference model: sRGB -> gamma (provided table) -> * CIE / 256 (PWM_W = GAMMA_W = 10)
    function automatic int exp_duty(input int srgb);
        return (dut.u_color_translate.gamma_table[srgb] * CIE) >> 8;
    endfunction : exp_duty

    // press and release buttons {c, u, d, l, r} (longer than sync + debounce)
    task automatic press_btn(input logic [4:0] b);
        {btnc, btnu, btnd, btnl, btnr} = b;
        #300;
        {btnc, btnu, btnd, btnl, btnr} = '0;
        #300;
    endtask : press_btn

    task automatic press_n(input logic [4:0] b, input int n);
        repeat (n) press_btn(b);
    endtask : press_n

    // PC transmitter: send one byte on uart_rxd
    task automatic send_byte(input logic [7:0] b);
        uart_rxd = 0;                           // start bit
        #(T_BIT);
        for (int i = 0; i < 8; i++) begin       // data bits, LSB first
            uart_rxd = b[i];
            #(T_BIT);
        end
        uart_rxd = 1;                           // stop bit
        #(T_BIT);
    endtask : send_byte

    // send a message of any length, first character first
    task automatic send_msg(input string msg);
        for (int i = 0; i < msg.len(); i++)
            send_byte(msg[i]);
        #(2 * T_BIT);
    endtask : send_msg

    // applied color and duty values against the reference model
    task automatic check_color(input logic [23:0] exp_rgb, input string name);
        int nb = 0;
        for (int c = 0; c < N_CH; c++)
            if (dut.duty[c] !== PWM_W'(exp_duty(exp_rgb[c*BYTE +: BYTE]))) nb++;
        if (dut.apply_rgb !== exp_rgb || nb != 0) begin
            $display("%s FAILED: applyRGB=%h (exp %h), %0d wrong duty values",
                     name, dut.apply_rgb, exp_rgb, nb);
            errors++;
        end
        else
            $display("%s PASSED: applyRGB=%h, duty R=%0d G=%0d B=%0d",
                     name, exp_rgb, dut.duty[2], dut.duty[1], dut.duty[0]);
    endtask : check_color

    // count high cycles of every RGB pin over one full PWM period
    // (window starts at cnt == 1 because the PWM outputs are registered)
    task automatic measure_pwm();
        repeat (2) begin                        // let a new duty reach the shadow register
            do @(negedge clk); while (dut.u_pwm_ctrl.cnt !== '1);
        end
        do @(negedge clk); while (dut.u_pwm_ctrl.cnt !== PWM_W'(1));
        for (int c = 0; c < N_CH; c++) begin
            hi16[c] = 0;
            hi17[c] = 0;
        end
        repeat (SLOTS) begin
            for (int c = 0; c < N_CH; c++) begin
                hi16[c] += (led16[c] === 1'b1);
                hi17[c] += (led17[c] === 1'b1);
            end
            @(negedge clk);
        end
    endtask : measure_pwm

    // PWM on the selected LED must match the model, the other LED must stay off
    task automatic check_pwm(input logic [23:0] rgb, input logic sel, input string name);
        int nb = 0;
        int e;
        measure_pwm();
        for (int c = 0; c < N_CH; c++) begin
            e = exp_duty(rgb[c*BYTE +: BYTE]);
            if (hi16[c] != (sel ? e : 0)) nb++;
            if (hi17[c] != (sel ? 0 : e)) nb++;
        end
        if (nb != 0) begin
            $display("%s FAILED: LED16=%0d/%0d/%0d LED17=%0d/%0d/%0d (R/G/B high cycles)",
                     name, hi16[2], hi16[1], hi16[0], hi17[2], hi17[1], hi17[0]);
            errors++;
        end
        else
            $display("%s PASSED: %s R/G/B = %0d/%0d/%0d of %0d", name, sel ? "LED16" : "LED17",
                     sel ? hi16[2] : hi17[2], sel ? hi16[1] : hi17[1], sel ? hi16[0] : hi17[0], SLOTS);
    endtask : check_pwm

    initial begin
        #100 cpu_resetn = 1;
        #100;

        // test 1: after reset - TX line idle, TX mode, RGB LEDs off, selector on B
        if (uart_txd !== 1 || led15 !== 0 || led16 !== '0 || led17 !== '0 ||
            leds !== SEL_B || dut.apply_rgb !== '0) begin
            $display("Test 1 FAILED: txd=%b led15=%b led16=%b led17=%b leds=%h",
                     uart_txd, led15, led16, led17, leds);
            errors++;
        end
        else
            $display("Test 1 PASSED: TX idle, TX mode, RGB LEDs off, selector on B");

        // test 2: TX, byte 41, N = 1, no delay "41 20 0D 0A", display "01 01 0.0 41"
        sw = 16'b0_00_000_00_0100_0001;         // {mode, count, unused, speed, byte}
        #200;                                   // let the switches pass the debouncer
        press_btn(B_C);
        wait (dut.busy == 0);
        #(20 * T_BIT);                          // let the PC receiver read the last character
        if (rx_n !== 4 || rx_char[0] !== 8'h41 || rx_char[1] !== 8'h20 ||
            rx_char[2] !== 8'h0D || rx_char[3] !== 8'h0A || led !== 1) begin
            $display("Test 2 FAILED: %0d chars", rx_n);
            errors++;
        end
        else
            $display("Test 2 PASSED: PC received %h %h %h %h", rx_char[0], rx_char[1], rx_char[2], rx_char[3]);
        if (dut.digits !== 32'h0101_0041) begin
            $display("Test 2b FAILED: display %h", dut.digits);
            errors++;
        end
        else
            $display("Test 2b PASSED: display %h", dut.digits);

        // test 3: TX, byte 55, N = 32, 50 ms -> 2112 characters, display "20 20 0.5 55"
        rx_n = 0;
        sw = 16'b0_01_000_01_0101_0101;
        #200;
        press_btn(B_C);
        wait (dut.busy == 0);
        #(20 * T_BIT);
        if (rx_n !== 2112 || dut.digits !== 32'h2020_0555) begin
            $display("Test 3 FAILED: %0d chars, display %h", rx_n, dut.digits);
            errors++;
        end
        else
            $display("Test 3 PASSED: %0d chars, display %h", rx_n, dut.digits);

        // test 4: RX mode, valid message -> display "17 0C C8 FF" (LED | R | G | B), color applied, one report
        sw[15] = 1;
        #200;
        n_before = n_report;
        send_msg("{R012,G200,B255}");
        if (led15 !== 1 || dut.digits !== 32'h170C_C8FF) begin
            $display("Test 4 FAILED: LED15=%b display %h", led15, dut.digits);
            errors++;
        end
        else
            $display("Test 4 PASSED: LED15 on, display %h", dut.digits);
        check_color({8'd12, 8'd200, 8'd255}, "Test 4b");
        if (n_report !== n_before + 1) begin
            $display("Test 4c FAILED: %0d color reports (exp 1)", n_report - n_before);
            errors++;
        end
        else
            $display("Test 4c PASSED: one color report");

        // test 5: invalid messages - display and color do not change
        send_msg("{R300,G010,B020}");           // value > 255
        send_msg("{X001,G001,B001}");           // wrong letter
        send_msg("{R001,G002B003}");            // missing comma
        send_msg("{R0a1,G002,B003}");           // not a digit
        if (dut.digits !== 32'h170C_C8FF || dut.apply_rgb !== {8'd12, 8'd200, 8'd255}) begin
            $display("Test 5 FAILED: display %h, applyRGB %h", dut.digits, dut.apply_rgb);
            errors++;
        end
        else
            $display("Test 5 PASSED: invalid messages ignored");

        // test 6: btnc does not start TX in RX mode (CENTER with an unchanged color -> no report)
        rx_n = 0;
        n_before = n_report;
        press_btn(B_C);
        #(20 * T_BIT);
        if (dut.busy !== 0 || rx_n !== 0 || n_report !== n_before) begin
            $display("Test 6 FAILED: TX or color report started in RX mode");
            errors++;
        end
        else
            $display("Test 6 PASSED: btnc ignored by TX in RX mode");

        // test 7: PWM on LED17 (default led_sel = 0) matches the color, LED16 off
        check_pwm({8'd12, 8'd200, 8'd255}, 1'b0, "Test 7");

        // test 8: L/R move the selector B -> G -> R -> LED, no wrap at either end
        n_bad = 0;
        press_btn(B_L); n_bad += (leds !== SEL_G);
        press_btn(B_L); n_bad += (leds !== SEL_R);
        press_btn(B_L); n_bad += (leds !== SEL_LED);
        press_btn(B_L); n_bad += (leds !== SEL_LED);    // left end
        press_btn(B_R); n_bad += (leds !== SEL_R);
        press_btn(B_R); n_bad += (leds !== SEL_G);
        press_btn(B_R); n_bad += (leds !== SEL_B);
        press_btn(B_R); n_bad += (leds !== SEL_B);      // right end
        if (n_bad != 0) begin
            $display("Test 8 FAILED: %0d wrong selector positions", n_bad);
            errors++;
        end
        else
            $display("Test 8 PASSED: selector moves B-G-R-LED, no wrap");

        // test 9: U/D edit the selected field, applied only on CENTER
        send_msg("{R010,G020,B030}");           // known start color, selector on B
        n_before = n_report;
        press_n(B_U, 3);                        // B: 30 -> 33
        if (dut.digits !== 32'h170A_1421) begin // display follows the edit at once
            $display("Test 9a FAILED: display %h (exp 170a1421)", dut.digits);
            errors++;
        end
        else
            $display("Test 9a PASSED: display shows the edit %h", dut.digits);
        if (dut.u_param_ctrl.current_RGB !== {8'd10, 8'd20, 8'd33} ||
            dut.apply_rgb !== {8'd10, 8'd20, 8'd30}) begin
            $display("Test 9 FAILED: edit=%h applied=%h (edit must wait for CENTER)",
                     dut.u_param_ctrl.current_RGB, dut.apply_rgb);
            errors++;
        end
        else
            $display("Test 9 PASSED: edit held until CENTER");
        press_btn(B_C);
        check_color({8'd10, 8'd20, 8'd33}, "Test 9b");
        press_btn(B_L);                         // select G
        press_n(B_D, 2);                        // G: 20 -> 18
        press_btn(B_C);
        check_color({8'd10, 8'd18, 8'd33}, "Test 9c");
        press_btn(B_R);                         // back to B
        if (n_report !== n_before + 2) begin
            $display("Test 9d FAILED: %0d color reports (exp 2)", n_report - n_before);
            errors++;
        end
        else
            $display("Test 9d PASSED: one color report per applied change");

        // test 10: no wrap - B stays 255 on UP, R stays 0 on DOWN, no report
        send_msg("{R000,G128,B255}");
        n_before = n_report;
        press_btn(B_U);                         // B = 255
        press_n(B_L, 2);                        // select R
        press_btn(B_D);                         // R = 0
        press_btn(B_C);
        if (dut.u_param_ctrl.current_RGB !== {8'd0, 8'd128, 8'd255} ||
            dut.apply_rgb !== {8'd0, 8'd128, 8'd255} || n_report !== n_before) begin
            $display("Test 10 FAILED: edit=%h applied=%h", dut.u_param_ctrl.current_RGB, dut.apply_rgb);
            errors++;
        end
        else
            $display("Test 10 PASSED: values saturate at 0 and 255");
        press_n(B_R, 2);                        // back to B

        // test 11: two buttons at once are ignored
        press_btn(B_D | B_L);
        if (dut.u_param_ctrl.current_RGB !== {8'd0, 8'd128, 8'd255} || leds !== SEL_B) begin
            $display("Test 11 FAILED: two-button press was accepted");
            errors++;
        end
        else
            $display("Test 11 PASSED: two-button press ignored");

        // test 12: LED select on T3 - UP + CENTER moves the color to LED16, DOWN + CENTER back
        press_n(B_L, 3);                        // select LED
        press_btn(B_U);
        if (dut.digits[31:24] !== 8'h16) begin
            $display("Test 12a FAILED: T3=%h (exp 16)", dut.digits[31:24]);
            errors++;
        end
        else
            $display("Test 12a PASSED: T3 shows 16 while editing the LED");
        if (leds !== SEL_LED || dut.led_sel !== 1'b0) begin
            $display("Test 12 FAILED: LED changed before CENTER (leds=%h led_sel=%b)", leds, dut.led_sel);
            errors++;
        end
        else
            $display("Test 12 PASSED: LED select held until CENTER");
        press_btn(B_C);
        check_pwm({8'd0, 8'd128, 8'd255}, 1'b1, "Test 12b");
        press_btn(B_D);
        press_btn(B_C);
        check_pwm({8'd0, 8'd128, 8'd255}, 1'b0, "Test 12c");
        press_n(B_R, 3);                        // back to B

        // test 13: a new RX color replaces an edit that was not applied
        press_btn(B_D);                         // B: 255 -> 254, not applied
        send_msg("{R001,G002,B003}");
        if (dut.u_param_ctrl.current_RGB !== {8'd1, 8'd2, 8'd3}) begin
            $display("Test 13 FAILED: edit=%h", dut.u_param_ctrl.current_RGB);
            errors++;
        end
        else
            $display("Test 13 PASSED: RX color overrides the pending edit");
        check_color({8'd1, 8'd2, 8'd3}, "Test 13b");

        // test 14: LED select from RX - "{L016}" -> LED16, "{L017}" -> LED17, bad messages ignored
        send_msg("{L016}");
        if (dut.led_sel !== 1'b1) begin
            $display("Test 14 FAILED: led_sel=%b after {L016}", dut.led_sel);
            errors++;
        end
        else
            $display("Test 14 PASSED: {L016} selects LED16");
        check_pwm({8'd1, 8'd2, 8'd3}, 1'b1, "Test 14b");
        send_msg("{L018}");                     // no such LED
        send_msg("{L16}");                      // too short
        if (dut.led_sel !== 1'b1) begin
            $display("Test 14c FAILED: invalid LED message accepted");
            errors++;
        end
        else
            $display("Test 14c PASSED: invalid LED messages ignored");
        send_msg("{L017}");
        if (dut.led_sel !== 1'b0) begin
            $display("Test 14d FAILED: led_sel=%b after {L017}", dut.led_sel);
            errors++;
        end
        else
            $display("Test 14d PASSED: {L017} selects LED17");

        // test 15: a message cut in the middle is dropped, the next "{" restarts the parser
        send_msg("{R100,G1{R005,G006,B007}");
        check_color({8'd5, 8'd6, 8'd7}, "Test 15");

        if (n_x != 0) begin
            $display("FAILED: X/Z seen on outputs in %0d cycles", n_x);
            errors++;
        end

        if (errors == 0) $display("ALL TESTS PASSED");
        else             $display("%0d TEST(S) FAILED", errors);
        $finish;
    end

endmodule : tb_chip_top