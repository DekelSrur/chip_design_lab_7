`timescale 1ns/1ps

// tb_parser - self-checking testbench for parser.sv (byte-stream version)
// Drives rx_byte + 1-cycle rx_ready like RX_fsm does, and checks the outputs:
//   {Rddd,Gddd,Bddd} -> RGB_wr_en pulse, {row_index,col_index,pixel_value} = {R,G,B}
//   {L016} / {L017}  -> led_wr_en pulse, led = 1 / 0
//   {W A2 A1 A0 , V 00 DH1 DH0 , V 00 DL1 DL0} -> master_wen, master_addr, master_wdata
//   {R A2 A1 A0}     -> master_ren, master_addr
//   rx_pkt / color_msg / cfg_msg pulses for cnt_rgf

module tb_parser;
    import pkg_sys::*;
    import pkg_rgf::*;

    localparam int CLK_PERIOD = 10;           // 100 MHz
    localparam int BYTE_GAP   = 20;           // clocks between bytes (real UART: ~17,000)

    logic            clk = 0, rst_n = 0;
    logic            rx_ready = 0;
    logic [BYTE-1:0] rx_byte = '0;
    logic [BYTE-1:0] row_index, col_index, pixel_value;
    logic            led, RGB_wr_en, led_wr_en;
    logic [23:0]     master_addr;
    logic [31:0]     master_wdata;
    logic            master_wen, master_ren;
    logic            rx_pkt, color_msg, cfg_msg;

    parser dut (
        .clk          (clk),
        .rst_n        (rst_n),
        .rx_ready     (rx_ready),
        .rx_byte      (rx_byte),
        .row_index    (row_index),
        .col_index    (col_index),
        .pixel_value  (pixel_value),
        .led          (led),
        .RGB_wr_en    (RGB_wr_en),
        .led_wr_en    (led_wr_en),
        .master_addr  (master_addr),
        .master_wdata (master_wdata),
        .master_wen   (master_wen),
        .master_ren   (master_ren),
        .rx_pkt       (rx_pkt),
        .color_msg    (color_msg),
        .cfg_msg      (cfg_msg)
    );

    always #(CLK_PERIOD/2) clk = ~clk;

// --- monitor: count output pulses and remember the last values ---
    int rgb_cnt = 0, led_cnt = 0;
    logic [BYTE-1:0] last_r, last_g, last_b;
    logic            last_led;

    int wen_cnt = 0, ren_cnt = 0, pkt_cnt = 0, col_cnt = 0, cfg_cnt = 0;
    logic [23:0] last_addr;
    logic [31:0] last_wdata;

    always @(posedge clk) begin
        if (master_wen) begin wen_cnt++; last_addr = master_addr; last_wdata = master_wdata; end
        if (master_ren) begin ren_cnt++; last_addr = master_addr; end
        if (rx_pkt)    pkt_cnt++;
        if (color_msg) col_cnt++;
        if (cfg_msg)   cfg_cnt++;
        if (RGB_wr_en) begin
            rgb_cnt++;
            {last_r, last_g, last_b} = {row_index, col_index, pixel_value};
        end
        if (led_wr_en) begin
            led_cnt++;
            last_led = led;
        end
    end

// --- stimulus helpers ---
    task automatic send_byte(input byte b);
        @(negedge clk) begin rx_byte = b; rx_ready = 1; end
        @(negedge clk) rx_ready = 0;
        repeat (BYTE_GAP) @(negedge clk);
    endtask

    task automatic send_str(input string s);
        for (int i = 0; i < s.len(); i++) send_byte(s[i]);
        repeat (3) @(negedge clk);             // let the outputs settle
    endtask

    // message buffer for binary messages (W / R)
    byte mbuf [32];
    int  mlen = 0;

    task automatic m_clear();               mlen = 0;              endtask
    task automatic m_add(input byte b);     mbuf[mlen] = b; mlen++; endtask
    task automatic m_send();
        for (int i = 0; i < mlen; i++) send_byte(mbuf[i]);
        repeat (3) @(negedge clk);
    endtask

// --- checkers ---
    int errors = 0;

    task automatic check(input string name, input logic ok);
        if (ok) $display("  pass  %s", name);
        else begin $display("  FAIL  %s", name); errors++; end
    endtask

    // message that SHOULD update the color
    task automatic expect_rgb(input string msg, input int r, g, b);
        int n0 = rgb_cnt, l0 = led_cnt;
        send_str(msg);
        check($sformatf("%-22s -> RGB %0d,%0d,%0d", msg, r, g, b),
              rgb_cnt == n0 + 1 && led_cnt == l0 &&
              last_r == r[7:0] && last_g == g[7:0] && last_b == b[7:0]);
    endtask

    // message that SHOULD update the LED select
    task automatic expect_led(input string msg, input logic l);
        int n0 = rgb_cnt, l0 = led_cnt;
        send_str(msg);
        check($sformatf("%-22s -> led = %0b", msg, l),
              led_cnt == l0 + 1 && rgb_cnt == n0 && last_led == l);
    endtask

    // message that must be IGNORED
    task automatic expect_none(input string msg, input string why);
        int n0 = rgb_cnt, l0 = led_cnt;
        send_str(msg);
        check($sformatf("%-22s ignored (%s)", msg, why), rgb_cnt == n0 && led_cnt == l0);
    endtask

    // {W A2 A1 A0 , V 00 DH1 DH0 , V 00 DL1 DL0}
    task automatic wr_msg(input logic [23:0] a, input logic [31:0] d);
        m_clear();
        m_add("{"); m_add("W"); m_add(a[23:16]); m_add(a[15:8]); m_add(a[7:0]);
        m_add(","); m_add("V"); m_add(8'h00); m_add(d[31:24]); m_add(d[23:16]);
        m_add(","); m_add("V"); m_add(8'h00); m_add(d[15:8]);  m_add(d[7:0]);
        m_add("}");
    endtask

    task automatic rd_msg(input logic [23:0] a);
        m_clear();
        m_add("{"); m_add("R"); m_add(a[23:16]); m_add(a[15:8]); m_add(a[7:0]); m_add("}");
    endtask

    task automatic expect_write(input logic [23:0] a, input logic [31:0] d);
        int w0, r0, c0;
        w0 = wen_cnt; r0 = ren_cnt; c0 = rgb_cnt;
        wr_msg(a, d); m_send();
        check($sformatf("write addr 0x%06h data 0x%08h", a, d),
              wen_cnt == w0 + 1 && ren_cnt == r0 && rgb_cnt == c0 &&
              last_addr == a && last_wdata == d);
    endtask

    task automatic expect_read(input logic [23:0] a);
        int w0, r0, c0;
        w0 = wen_cnt; r0 = ren_cnt; c0 = rgb_cnt;
        rd_msg(a); m_send();
        check($sformatf("read  addr 0x%06h", a),
              ren_cnt == r0 + 1 && wen_cnt == w0 && rgb_cnt == c0 && last_addr == a);
    endtask

    // sends what is in mbuf and expects nothing to happen
    task automatic expect_no_cfg(input string why);
        int w0, r0, c0;
        w0 = wen_cnt; r0 = ren_cnt; c0 = rgb_cnt;
        m_send();
        check($sformatf("ignored: %s", why), wen_cnt == w0 && ren_cnt == r0 && rgb_cnt == c0);
    endtask

    initial begin
        $dumpfile("tb_parser.vcd");
        $dumpvars(0, tb_parser);

        repeat (3) @(negedge clk); rst_n = 1;

        $display("--- 1. valid color messages");
        expect_rgb("{R012,G034,B255}", 12, 34, 255);
        expect_rgb("{R000,G000,B000}",  0,  0,   0);
        expect_rgb("{R255,G255,B255}", 255, 255, 255);
        expect_rgb("{R001,G002,B003}",  1,  2,   3);

        $display("--- 2. LED select");
        expect_led("{L016}", 1'b1);
        expect_led("{L017}", 1'b0);
        expect_led("{L016}", 1'b1);

        $display("--- 3. invalid messages are ignored");
        expect_none("[R012,G034,B255}", "wrong opening char");
        expect_none("{R012;G034,B255}", "';' instead of ','");
        expect_none("{R:12,G034,B255}", "':' is not a digit");
        expect_none("{R012,G03X,B255}", "'X' is not a digit");
        expect_none("{R012,G034BB255}", "missing ','");
        expect_none("{R012,G034,B2558", "missing '}'");
        expect_none("{X012,G034,B255}", "unknown type");
        expect_none("{L018}",           "LED must be 016/017");
        expect_none("{L16}",            "too short");
        check("outputs kept after bad messages",
              last_r == 1 && last_g == 2 && last_b == 3 && last_led == 1);

        $display("--- 4. recovery");
        // a new '{' restarts the parser even in the middle of a message
        expect_rgb("{R012,G0{R100,G101,B102}", 100, 101, 102);
        // a valid message right after a broken one
        expect_none("{R012,G0", "truncated");
        expect_rgb("{R007,G008,B009}", 7, 8, 9);
        // back-to-back messages
        begin
            int n0;
            n0 = rgb_cnt;
            send_str("{R010,G020,B030}{R040,G050,B060}");
            check("two messages back-to-back", rgb_cnt == n0 + 2 &&
                  last_r == 40 && last_g == 50 && last_b == 60);
        end

        $display("--- 5. values above 255 are rejected");
        expect_none("{R256,G100,B100}", "R > 255");
        expect_none("{R100,G999,B100}", "G > 255");
        expect_none("{R100,G100,B300}", "B > 255");

        $display("--- 6. output pulses are exactly 1 clock");
        begin
            int width;
            width = 0;
            fork
                send_str("{R011,G022,B033}");
                repeat (BYTE_GAP * 20) @(posedge clk) #1 if (RGB_wr_en) width++;
            join
            check($sformatf("RGB_wr_en width = %0d clock", width), width == 1);
        end

        $display("--- 7. write command");
        expect_write(24'h000028, 32'h0000_0002);          // SYS_CTRL = enable
        expect_write(24'h00000C, 32'h00ABCDEF);
        expect_write(24'h7B7B7B, 32'h7B7B_7B7B);          // '{' bytes inside must not restart
        expect_write(24'h000000, 32'h0000_0000);

        $display("--- 8. read command");
        expect_read(24'h000030);                          // SYS_VERSION
        expect_read(24'h7B0004);                          // '{' as an address byte
        expect_read(24'h313233);                          // {R123} = read, not a colour

        $display("--- 9. malformed W/R are ignored");
        wr_msg(24'h000028, 32'h1); mbuf[7]  = 8'h01; expect_no_cfg("W: non-zero pad byte");
        wr_msg(24'h000028, 32'h1); mbuf[6]  = "X";   expect_no_cfg("W: 'X' instead of 'V'");
        wr_msg(24'h000028, 32'h1); mbuf[5]  = ";";   expect_no_cfg("W: ';' instead of ','");
        wr_msg(24'h000028, 32'h1); mbuf[15] = "]";   expect_no_cfg("W: missing '}'");
        rd_msg(24'h000030);        mbuf[5]  = ",";   expect_no_cfg("R: ',' after a binary address");
        expect_rgb("{R001,G002,B003}", 1, 2, 3);           // still alive after junk

        $display("--- 10. packet counters (to cnt_rgf)");
        begin
            int p0, c0, f0;
            p0 = pkt_cnt; c0 = col_cnt; f0 = cfg_cnt;
            send_str("{R010,G020,B030}");                 // colour
            send_str("{L017}");                           // led
            wr_msg(24'h000004, 32'h2); m_send();          // write
            rd_msg(24'h000018);        m_send();          // read
            send_str("{R012;G034,B255}");                 // invalid
            check($sformatf("rx_pkt +4 (got +%0d)", pkt_cnt - p0), pkt_cnt == p0 + 4);
            check($sformatf("color_msg +1 (got +%0d)", col_cnt - c0), col_cnt == c0 + 1);
            check($sformatf("cfg_msg +2 (got +%0d)", cfg_cnt - f0), cfg_cnt == f0 + 2);
        end

        $display("\n=== %s (%0d errors) ===", errors ? "TEST FAILED" : "TEST PASSED", errors);
        $finish;
    end
endmodule
