`timescale 1ns / 1ps

module TB_RX_fsm;


    // Parameters
    localparam int CLKS_PER_BIT  = 1736; // 100MHz / 57600 baud
    localparam int BIT_PERIOD_NS = CLKS_PER_BIT * 10;   // 17360 ns


    // Signals
    logic clk = 1'b0;
    logic rst_n;
    logic rx;
    logic [127:0] msg;
    logic msg_valid;

    logic [127:0] exp_msg;            // reference model: the last 16 bytes sent
    int   fail_count   = 0;
    int   valid_pulses = 0;   // msg_valid pulses since the last reset
    logic [127:0] msg_at_valid;       // msg captured on the clock edge where msg_valid is 1


    // DUT and clock
    RX_fsm #(
        .CLKS_PER_BIT(CLKS_PER_BIT)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .rx(rx),
        .msg(msg),
        .msg_valid(msg_valid)
    );

    always #5 clk = ~clk;             // 100MHz

    // Monitor: count msg_valid pulses and capture msg at the pulse
    always @(posedge clk) begin
        if (msg_valid) begin
            valid_pulses++;
            msg_at_valid <= msg;
        end
    end

    // Concurrent assertion: msg_valid is a one-cycle pulse
    a_msg_valid_pulse: assert property (@(posedge clk) disable iff (!rst_n) msg_valid |=> !msg_valid)
        else $error("msg_valid stayed high for more than one clock cycle");


    // Function: reference model of the shift register
    function automatic logic [127:0] push_byte(input logic [127:0] window,
                                               input logic [7:0]   data);
        return {window[119:0], data};  // new byte enters at [7:0], the oldest leaves
    endfunction


    // Tasks
    task automatic apply_reset();
        rx  = 1'b1;
        rst_n = 1'b0;
        repeat (10) @(posedge clk);
        rst_n = 1'b1;
        repeat (10) @(posedge clk);
        exp_msg = '0;
        valid_pulses = 0;
    endtask

    // One UART frame (LSB first). stop_val = 0 creates a framing error.
    task automatic send_byte(input logic [7:0] data,
                             input logic  stop_val = 1'b1,
                             input int bit_time_ns = BIT_PERIOD_NS);
        rx = 1'b0;  #(bit_time_ns); // start bit
        for (int i = 0; i < 8; i++) begin // 8 data bits
            rx = data[i];  #(bit_time_ns);
        end
        rx = stop_val;  #(bit_time_ns); // stop bit
        rx = 1'b1;  #100; // back to idle
    endtask

    // A valid byte: also updates the reference model
    task automatic send_valid(input logic [7:0] data,
                              input int  bit_time_ns = BIT_PERIOD_NS);
        send_byte(data, 1'b1, bit_time_ns);
        exp_msg = push_byte(exp_msg, data);
    endtask

    // A string of valid bytes (for example a 16-character message)
    task automatic send_string(input string s,
                               input int  bit_time_ns = BIT_PERIOD_NS);
        for (int i = 0; i < s.len(); i++)
            send_valid(s[i], bit_time_ns);
    endtask

    // Short low pulse on an idle line
    task automatic send_glitch(input int glitch_duration_ns);
        rx = 1'b1;  #100;
        rx = 1'b0;  #(glitch_duration_ns);
        rx = 1'b1;
    endtask

    task automatic wait_bits(input int nbits);
        #(nbits * BIT_PERIOD_NS);
    endtask

    // Checks (immediate assertions)
    task automatic check_msg(input string name);
        repeat (5) @(posedge clk);
        assert (msg === exp_msg) $display("[PASS] %s", name);
        else begin
            fail_count = fail_count + 1;
            $error("[FAIL] %s: msg=%h expected=%h", name, msg, exp_msg);
        end
    endtask

    task automatic check_pulses(input string name, input int expected);
        repeat (5) @(posedge clk);
        assert (valid_pulses == expected) $display("[PASS] %s", name);
        else begin
            fail_count = fail_count + 1;
            $error("[FAIL] %s: msg_valid pulses=%0d expected=%0d", name, valid_pulses, expected);
        end
    endtask

    task automatic check_msg_at_valid(input string name, input logic [127:0] expected);
        assert (msg_at_valid === expected) $display("[PASS] %s", name);
        else begin
            fail_count = fail_count + 1;
            $error("[FAIL] %s: msg at msg_valid=%h expected=%h", name, msg_at_valid, expected);
        end
    endtask


    // Test scenarios
    logic [7:0]   byte_to_send;
    logic [127:0] snap;

    initial begin
        rx = 1'b1;  
        rst_n = 1'b0;  
        exp_msg = '0;
        repeat (10) @(posedge clk);
        rst_n = 1'b1;
        repeat (20) @(posedge clk);

        $display("=== STARTING RX_FSM VERIFICATION ===");


        // Test 1: reset
        $display("Test 1: reset");
        check_msg("1a msg == 0 after reset");
        assert (msg_valid === 1'b0) $display("[PASS] 1b msg_valid == 0 after reset");
        else begin fail_count = fail_count + 1; $error("[FAIL] 1b msg_valid is not 0 after reset"); end
        assert (dut.current_state === 3'd0) $display("[PASS] 1c FSM is in IDLE after reset");
        else begin fail_count = fail_count + 1; $error("[FAIL] 1c FSM is not in IDLE after reset"); end


        // Test 2: single byte (0x55 also proves the bit order, LSB first)
        $display("Test 2: single byte 0x55");
        send_valid(8'h55);
        check_msg("2 byte 0x55 is in msg[7:0]");

 
        // Test 3: full message, 16 back-to-back bytes, and msg_valid
        $display("Test 3: full message (16 bytes) and msg_valid");
        apply_reset(); // the byte counter starts again from 0, so msg_valid lines up with byte 16
        for (int k = 1; k <= 15; k++) begin
            byte_to_send = k[7:0];
            send_valid(byte_to_send);
        end
        check_pulses("3a 15 bytes: no msg_valid yet", 0);
        send_valid(8'h10);
        check_msg("3b full 16-byte message in msg");
        check_pulses("3c 16th byte: one msg_valid pulse", 1);
        check_msg_at_valid("3d msg was complete when msg_valid was high", exp_msg);


        // Test 4: glitch on the idle line (2us)
        $display("Test 4: glitch filter, 2us pulse");
        send_glitch(2000);
        wait_bits(2);      // let the FSM reject the glitch before the next byte starts
        check_msg("4a glitch ignored, msg unchanged");
        check_pulses("4b glitch did not create msg_valid", 1);
        send_valid(8'hA5);
        check_msg("4c valid byte received after the glitch");

 
        // Test 5: framing error (stop bit = 0)
        $display("Test 5: framing error");
        send_byte(8'h3C, 1'b0);
        wait_bits(1);
        check_msg("5a framing error byte dropped, msg unchanged");
        send_valid(8'h7F);
        check_msg("5b valid byte received after the framing error");


        // Test 6: sliding window (more than 16 bytes)
        $display("Test 6: sliding window, 20 bytes");
        apply_reset();
        for (int k = 0; k < 16; k++) begin
            byte_to_send = 8'h30 + k;
            send_valid(byte_to_send);
        end
        snap = exp_msg;                     // the first 16 bytes
        for (int k = 16; k < 20; k++) begin
            byte_to_send = 8'h30 + k;
            send_valid(byte_to_send);
        end
        check_msg("6a msg holds only the last 16 of 20 bytes");
        check_pulses("6b 20 bytes: one msg_valid pulse", 1);
        check_msg_at_valid("6c the pulse came with the first 16 bytes", snap);

 
        // Test 7: baud rate deviation of +-2%
        $display("Test 7: baud rate deviation +-2%%");
        apply_reset();
        send_string("{R012,C034,V255}", BIT_PERIOD_NS * 102 / 100);   // bit time +2%
        check_msg("7a message received with +2% bit time");
        check_pulses("7b +2%: one msg_valid pulse", 1);

        apply_reset();
        send_string("{R012,C034,V255}", BIT_PERIOD_NS * 98 / 100);    // bit time -2%
        check_msg("7c message received with -2% bit time");
        check_pulses("7d -2%: one msg_valid pulse", 1);

        $display("=== TESTS FINISHED. Total failures: %0d ===", fail_count);
        if (fail_count == 0) $display(">>> ALL TESTS PASSED <<<");
        else                 $display(">>> SOME TESTS FAILED <<<");
        $finish;
    end

    // Watchdog
    initial begin
        #1_000_000_000;
        $error("TIMEOUT");
        $finish;
    end

endmodule
