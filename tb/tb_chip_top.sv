`timescale 1ns / 1ps

// tb_chip_top - system-level testbench for Lab 7
//   The testbench plays the PC: it only touches the chip_top pins.
//     uart_rxd : sends messages (8N1, LSB first)
//     uart_txd : receives and decodes the 16-byte read responses
//     led16/17 : measures the PWM high time per channel
//   Register map (pkg_rgf):
//     0x0000 LED_CTRL   0x0004 LED_PATTERN   0x0008 PWM_CFG
//     0x000C RED_LUT    0x0010 GREEN_LUT     0x0014 BLUE_LUT
//     0x0018 RX_PKT_CNT 0x001C TX_PKT_CNT    0x0020 COLOR_MSG_CNT  0x0024 CFG_MSG_CNT
//     0x0028 SYS_CTRL   0x002C SYS_STATUS    0x0030 SYS_VERSION
//   Messages:
//     write    {W A2 A1 A0 , V 00 DH1 DH0 , V 00 DL1 DL0}
//     read     {R A2 A1 A0}
//     response {R A2 A1 A0 , V 00 DH1 DH0 , V 00 DL1 DL0}    (16 bytes)
//     color    {Rddd,Gddd,Bddd}   led select {L016} / {L017}

module tb_chip_top;
    import pkg_sys::*;

    localparam int CPB    = 32;                 // clocks per UART bit in simulation (16x oversampling)
    localparam int T_BIT  = CPB * 10;           // one bit = 320 ns
    localparam int SLOTS  = PWM_SLOTS_DEF;      // chip_top default PWM resolution (1024)
    localparam int RSP_LEN = 16;                // bytes in a read response
    localparam int R = 2, G = 1, B = 0;         // channel index in led16 / led17

    // register addresses
    localparam logic [23:0] A_LED_CTRL    = 24'h000000;
    localparam logic [23:0] A_LED_PATTERN = 24'h000004;
    localparam logic [23:0] A_PWM_CFG     = 24'h000008;
    localparam logic [23:0] A_RED_LUT     = 24'h00000C;
    localparam logic [23:0] A_GREEN_LUT   = 24'h000010;
    localparam logic [23:0] A_BLUE_LUT    = 24'h000014;
    localparam logic [23:0] A_RX_PKT_CNT  = 24'h000018;
    localparam logic [23:0] A_TX_PKT_CNT  = 24'h00001C;
    localparam logic [23:0] A_COLOR_CNT   = 24'h000020;
    localparam logic [23:0] A_CFG_CNT     = 24'h000024;
    localparam logic [23:0] A_SYS_CTRL    = 24'h000028;
    localparam logic [23:0] A_SYS_STATUS  = 24'h00002C;
    localparam logic [23:0] A_SYS_VERSION = 24'h000030;
    localparam logic [23:0] A_UNMAPPED    = 24'h000100;

//DUT signals
    logic clk = 0, cpu_resetn = 0;
    logic btnc = 0, btnu = 0, btnd = 0, btnl = 0, btnr = 0;
    logic uart_rxd = 1;                         // UART line idles high
    logic uart_txd;
    logic [2:0] led16, led17;                   // {R, G, B}
    logic [7:0] an;
    logic [6:0] seg;
    logic dp;

//tb bookkeeping
    int errors = 0;
    int rx_n   = 0;                             // bytes received by the PC model
    logic [7:0] rx_char [4096];                 // bytes sent by the FPGA
    int hi16 [3], hi17 [3];                     // PWM high cycles per channel

    // short times for simulation: UART 32 clocks/bit, debounce 10 clocks, fast display refresh
    chip_top #(
        .CLKS_PER_BIT    (CPB),
        .DEBOUNCE_CYCLES (10),
        .REFRESH_DIV     (4)
    ) dut (
        .clk        (clk),
        .cpu_resetn (cpu_resetn),
        .btnc       (btnc),
        .btnu       (btnu),
        .btnd       (btnd),
        .btnl       (btnl),
        .btnr       (btnr),
        .uart_rxd   (uart_rxd),
        .uart_txd   (uart_txd),
        .led16      (led16),
        .led17      (led17),
        .an         (an),
        .seg        (seg),
        .dp         (dp)
    );

    always #5 clk = ~clk;                       // 100 MHz

    // stop the simulation if it hangs
    initial begin
        #50_000_000;
        $display("tb_chip_top FAILED: timeout");
        $finish;
    end

//PC receiver: read every byte on uart_txd (8N1, LSB first)
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

//PC transmitter
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

    // text message (color / led select)
    task automatic send_msg(input string msg);
        for (int i = 0; i < msg.len(); i++)
            send_byte(msg[i]);
        #(2 * T_BIT);
    endtask : send_msg

        // one hex digit as an ASCII character: 0-9, A-F
    function automatic logic [7:0] hex_char(input logic [3:0] v);
        if (v < 4'd10) return 8'("0") + 8'(v);
        else           return 8'("A") + 8'(v - 4'd10);
    endfunction

    // write command {Wxxx,Vhhhhhh,Vhhhhhh}: address and data as ASCII hex characters
    // each V field: "00" and then 4 hex digits (16 bits of data)
    task automatic write_reg(input logic [23:0] a, input logic [31:0] d);
        send_byte("{");      send_byte("W");
        send_byte(hex_char(a[11:8])); send_byte(hex_char(a[7:4])); send_byte(hex_char(a[3:0]));
        send_byte(",");      send_byte("V");      send_byte("0");      send_byte("0");
        for (int i = 7; i >= 4; i--) send_byte(hex_char(d[i*4 +: 4]));
        send_byte(",");      send_byte("V");      send_byte("0");      send_byte("0");
        for (int i = 3; i >= 0; i--) send_byte(hex_char(d[i*4 +: 4]));
        send_byte("}");
        #(2 * T_BIT);
    endtask : write_reg

    // {R A2 A1 A0} -> wait for the 16-byte response, check its frame, return the data
    task automatic read_reg(input logic [23:0] a, output logic [31:0] d);
        int n0, k;
        logic [7:0] exp_frame [RSP_LEN];
        n0 = rx_n;
        send_byte("{");      send_byte("R");
        send_byte(hex_char(a[11:8])); send_byte(hex_char(a[7:4])); send_byte(hex_char(a[3:0]));
        send_byte("}");
        // response: 16 bytes x 10 bits, plus some slack
        k = 0;
        while (rx_n < n0 + RSP_LEN && k < 40 * RSP_LEN) begin
            #(T_BIT);
            k++;
        end
        if (rx_n < n0 + RSP_LEN) begin
            $display("  FAIL  read 0x%06h: only %0d of %0d response bytes", a, rx_n - n0, RSP_LEN);
            errors++;
            d = 'x;
            return;
        end
        d = {rx_char[n0+8], rx_char[n0+9], rx_char[n0+13], rx_char[n0+14]};
        exp_frame = '{"{", "R", hex_char(a[11:8]), hex_char(a[7:4]), hex_char(a[3:0]), ",", "V", 8'h00, d[31:24], d[23:16],
                      ",", "V", 8'h00, d[15:8], d[7:0], "}"};
        for (int i = 0; i < RSP_LEN; i++)
            if (rx_char[n0+i] !== exp_frame[i]) begin
                $display("  FAIL  read 0x%06h: response byte %0d = 0x%02h, expected 0x%02h",
                         a, i, rx_char[n0+i], exp_frame[i]);
                errors++;
            end
    endtask : read_reg

//checkers
    task automatic check(input string name, input logic ok);
        if (ok) $display("  pass  %s", name);
        else begin $display("  FAIL  %s", name); errors++; end
    endtask : check

    task automatic check_reg(input logic [23:0] a, input logic [31:0] exp, input string name);
        logic [31:0] d;
        read_reg(a, d);
        check($sformatf("%-26s read 0x%06h = 0x%08h (expected 0x%08h)", name, a, d, exp), d === exp);
    endtask : check_reg

    // count PWM high cycles per channel over n PWM periods
    // (pwm_ctrl loads a new duty only at the end of a period, so skip one period first)
    task automatic measure_pwm(input int n_periods);
        repeat (SLOTS) @(posedge clk);
        for (int c = 0; c < 3; c++) begin hi16[c] = 0; hi17[c] = 0; end
        repeat (n_periods * SLOTS) begin
            @(posedge clk) #1;
            for (int c = 0; c < 3; c++) begin
                hi16[c] += led16[c];
                hi17[c] += led17[c];
            end
        end
    endtask : measure_pwm

    logic [31:0] d, d0, d1, cnt0, cnt1;
    int lo, hi;

    initial begin
        $dumpfile("tb_chip_top.vcd");
        $dumpvars(0, tb_chip_top);

        #200 cpu_resetn = 1;
        #(20 * T_BIT);

        $display("--- 1. first contact: read the version");
        check_reg(A_SYS_VERSION, 32'h0007_0001, "SYS_VERSION");

        $display("--- 2. reset values");
        check_reg(A_SYS_CTRL,    32'h0000_0002, "SYS_CTRL (enable = 1)");
        check_reg(A_LED_PATTERN, 32'h0000_0000, "LED_PATTERN (static)");
        check_reg(A_PWM_CFG,     32'h0000_0400, "PWM_CFG (1024 slots)");
        check_reg(A_RED_LUT,     32'h0000_03E8, "RED_LUT (1000 Hz)");
        check_reg(A_SYS_STATUS,  32'h0000_0000, "SYS_STATUS (no errors)");

        $display("--- 3. write + read back (RW registers)");
        write_reg(A_LED_PATTERN, 32'h0000_0002);  check_reg(A_LED_PATTERN, 32'h0000_0002, "LED_PATTERN");
        write_reg(A_LED_PATTERN, 32'h0000_0000);  check_reg(A_LED_PATTERN, 32'h0000_0000, "LED_PATTERN");
        write_reg(A_GREEN_LUT,   32'h0055_1234);  check_reg(A_GREEN_LUT,   32'h0055_1234, "GREEN_LUT");
        write_reg(A_GREEN_LUT,   32'h0000_03E8);  // back to the default

        $display("--- 4. color message -> LED16, LED17 off");
        send_msg("{L016}");
        send_msg("{R255,G000,B000}");
        measure_pwm(4);
        check($sformatf("LED16 R on  (%0d cycles)", hi16[R]), hi16[R] > SLOTS);   // > 25% duty
        check($sformatf("LED16 G,B off (%0d,%0d)", hi16[G], hi16[B]), hi16[G] == 0 && hi16[B] == 0);
        check($sformatf("LED17 off (%0d,%0d,%0d)", hi17[R], hi17[G], hi17[B]),
              hi17[R] == 0 && hi17[G] == 0 && hi17[B] == 0);

        $display("--- 5. led select -> LED17");
        send_msg("{L017}");
        measure_pwm(4);
        check($sformatf("LED17 R on  (%0d cycles)", hi17[R]), hi17[R] > SLOTS);
        check($sformatf("LED16 off (%0d,%0d,%0d)", hi16[R], hi16[G], hi16[B]),
              hi16[R] == 0 && hi16[G] == 0 && hi16[B] == 0);
        send_msg("{L016}");

        $display("--- 6. SYS_CTRL.enable = 0 -> all LEDs off");
        write_reg(A_SYS_CTRL, 32'h0000_0000);
        measure_pwm(4);
        check($sformatf("LED16 off (%0d,%0d,%0d)", hi16[R], hi16[G], hi16[B]),
              hi16[R] == 0 && hi16[G] == 0 && hi16[B] == 0);
        write_reg(A_SYS_CTRL, 32'h0000_0002);
        measure_pwm(4);
        check($sformatf("LED16 R back on (%0d cycles)", hi16[R]), hi16[R] > SLOTS);

        $display("--- 7. breath: LED16 R follows the sine (5000 Hz = 20,000 clocks)");
        write_reg(A_RED_LUT, 32'h0000_1388);       // out_freq = 5000 Hz
        write_reg(A_LED_PATTERN, 32'h0000_0001);   // breath
        lo = 1 << 30; hi = 0;
        repeat (12) begin                           // ~1.2 sine periods, sample every 2nd PWM period
            measure_pwm(1);
            if (hi16[R] < lo) lo = hi16[R];
            if (hi16[R] > hi) hi = hi16[R];
        end
        check($sformatf("brightness changes (min %0d, max %0d per period)", lo, hi),
              hi > 4 * lo + 50);
        write_reg(A_LED_PATTERN, 32'h0000_0000);   // static again
        write_reg(A_RED_LUT, 32'h0000_03E8);

        $display("--- 8. counters");
        read_reg(A_RX_PKT_CNT, cnt0);
        read_reg(A_COLOR_CNT,  d0);
        send_msg("{R010,G020,B030}");               // colour
        send_msg("{L016}");                          // led
        send_msg("{R010;G020,B030}");               // invalid - not counted
        read_reg(A_RX_PKT_CNT, cnt1);
        // a read returns the count from before its own packet, so between the two RX_PKT_CNT
        // reads we count: RX read #1 + COLOR_CNT read + colour + led = 4 (the bad one is not counted)
        check($sformatf("RX_PKT_CNT +4 (got +%0d)", cnt1 - cnt0), cnt1 - cnt0 == 4);
        read_reg(A_COLOR_CNT, d1);
        check($sformatf("COLOR_MSG_CNT +1 (got +%0d)", d1 - d0), d1 - d0 == 1);
        read_reg(A_TX_PKT_CNT, d0);
        read_reg(A_TX_PKT_CNT, d1);
        check($sformatf("TX_PKT_CNT +1 per response (got +%0d)", d1 - d0), d1 - d0 == 1);

        $display("--- 9. error flags (SYS_STATUS, read-to-clear)");
        read_reg(A_UNMAPPED, d);
        check($sformatf("unmapped address reads 0 (0x%08h)", d), d === 32'h0);
        check_reg(A_SYS_STATUS, 32'h0000_0001, "SYS_STATUS invalid_addr");
        check_reg(A_SYS_STATUS, 32'h0000_0000, "SYS_STATUS cleared");
        write_reg(A_RX_PKT_CNT, 32'h1234_5678);     // CNT_RGF is read-only
        check_reg(A_SYS_STATUS, 32'h0000_0002, "SYS_STATUS ro_wr");
        write_reg(A_SYS_VERSION, 32'h0);
        check_reg(A_SYS_VERSION, 32'h0007_0001, "SYS_VERSION not written");

        $display("--- 10. SW reset: config back to reset values, SYS_CTRL kept");
        write_reg(A_LED_PATTERN, 32'h0000_0002);
        write_reg(A_SYS_CTRL, 32'h0000_0003);       // sw_rst + keep enable
        #(20 * T_BIT);
        check_reg(A_LED_PATTERN, 32'h0000_0000, "LED_PATTERN after sw_rst");
        check_reg(A_SYS_CTRL,    32'h0000_0002, "SYS_CTRL after sw_rst");

        $display("\n=== %s (%0d errors) ===", errors ? "TEST FAILED" : "TEST PASSED", errors);
        $finish;
    end
endmodule
