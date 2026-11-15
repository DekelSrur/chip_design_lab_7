`timescale 1ns/1ps

module chip_top #(
    parameter CLKS_PER_BIT = pkg_sys::CLKS_PER_BIT,    //from package
    parameter DEBOUNCE_CYCLES = 1_000_000,              //debounce window: 10 ms
    parameter DELAY_50MS = 5_000_000,
    parameter DELAY_100MS = 10_000_000,
    parameter DELAY_200MS = 20_000_000,
    parameter REFRESH_DIV = 25_000,                     //100 MHz / 25,000 = 4 kHz -> 500 Hz per digit 
    parameter PWM_SLOTS = pkg_sys::PWM_SLOTS_DEF,      //PWM resolution 512..8192
    parameter CIE_SCALE = pkg_sys::CIE_SCALE_DEF       //brightness, out of 256   
)(
    input logic clk,
    input logic cpu_resetn,
    input logic btnc, btnu, btnd, btnl, btnr,
    input logic [15:0] sw,                  //0 = TX mode, 1 = RX mode
    input logic uart_rxd,                   //serial line from the PC

    output logic uart_txd,                  //serial line to the PC
    output logic led,                       //LED[0] toggles on every TX data byte
    output logic led15,                     //LED[15] RX/TX mode indicator (1 = RX)
    output logic [13:4] leds,               //selected field: [5:4]B [8:7]G [10:9]R [13:12]LED
    output logic [2:0] led16,               //RGB LED16 {R,G,B}
    output logic [2:0] led17,               //RGB LED17 {R,G,B}
    output logic [7:0]  an,
    output logic [6:0]  seg,
    output logic dp
);

    localparam int PWM_W = $clog2(PWM_SLOTS);

//input signals
    logic rst_n;
    logic [4:0] btn_s;                      //{c, u, d, l, r}
    logic [4:0] btn_db;
    logic [15:0] sw_s;
    logic [15:0] sw_db;
    logic rxd_s;                            //synchronized uart rx line
    logic rx_mode;                          //sw_db[15]: 0 = TX mode, 1 = RX mode
    // TX path
    logic start;
    logic busy;
    logic [7:0] byte_val;
    logic [1:0] speed_sel, count_sel;
    logic tx_start;
    logic tx_busy;
    logic tx_done;
    logic [7:0] tx_data;
    logic [8:0] rows_sent;
    logic [16:0] bytes_sent;
    // RX path
    logic [7:0] rx_byte;                    //byte from RX_fsm (PHY)
    logic rx_ready;                         //1-cycle pulse: new byte
    logic [7:0] row_idx, col_idx, pix_val;
    logic rgb_wr_en, led_wr_en, led_cmd;    //parser -> param_ctrl
    // color / PWM path
    logic [23:0] apply_rgb;                 //{R, G, B}
    logic led_sel;                          //1 = LED16, 0 = LED17
    logic [7:0] dig_sel;
    logic [23:0] edit_rgb;                  //{R, G, B} being edited -> display
    logic edit_led;                         //LED being edited -> display
    logic [pkg_sys::N_LEDS-1:0][pkg_sys::N_CH-1:0][PWM_W-1:0] duty;   //per LED, [0]=LED16 [1]=LED17
    logic [pkg_sys::N_LEDS-1:0] cie_en;              //from led_rgf, [0]=LED16 [1]=LED17
    logic color_start;
    logic [3*PWM_W-1:0] trns_msg;
    // display
    logic [31:0] digits;
    logic [7:0] dps;
    logic [7:0] dash;

//mode select
    assign rx_mode = sw_db[15];             //debounced mode switch
    assign led15 = rx_mode;

//selected field leds
    assign leds = {dig_sel[7:6], 1'b0, dig_sel[5:2], 1'b0, dig_sel[1:0]};

//input conditioning
    sync u_sync (
        .clk(clk), .cpu_resetn(cpu_resetn), .btn({btnc, btnu, btnd, btnl, btnr}), .sw(sw), .uart_rxd(uart_rxd),
        .rst_n(rst_n), .btn_s(btn_s), .sw_s(sw_s), .rxd_s(rxd_s)
    );

    debouncer #(.DEBOUNCE_CYCLES(DEBOUNCE_CYCLES)) u_debouncer (
        .clk(clk), .rst_n(rst_n), .btn_in(btn_s), .sw_in(sw_s),
        .btn_db(btn_db), .sw_db(sw_db)
    );

    cfg_latch u_cfg_latch (
        .clk(clk), .rst_n(rst_n), .btn_db(btn_db[4]), .busy(busy), .rx_mode(rx_mode), .sw_db(sw_db[14:0]),
        .start(start), .byte_val(byte_val), .speed_sel(speed_sel), .count_sel(count_sel)
    );

//tx path
    tx_fsm #(
        .DELAY_50MS(DELAY_50MS), .DELAY_100MS(DELAY_100MS), .DELAY_200MS(DELAY_200MS), .PWM_W(PWM_W)
    ) u_tx_fsm (
        .clk(clk), .rst_n(rst_n), .start(start), .byte_val(byte_val),
        .speed_sel(speed_sel), .count_sel(count_sel), .tx_done(tx_done),
        .color_start(color_start), .trns_msg(trns_msg),
        .tx_start(tx_start), .tx_data(tx_data), .led(led), .busy(busy),
        .rows_sent(rows_sent), .bytes_sent(bytes_sent)
    );

    uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_uart_tx (
        .clk(clk), .rst_n(rst_n), .tx_start(tx_start), .tx_data(tx_data),
        .tx(uart_txd), .tx_busy(tx_busy), .tx_done(tx_done)
    );

//rx path
    RX_fsm #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_RX_fsm (
        .clk(clk), .rst_n(rst_n), .rx(rxd_s),
        .rx_byte(rx_byte), .rx_ready(rx_ready)
    );

    parser u_parser (
        .clk(clk), .rst_n(rst_n), .rx_ready(rx_ready), .rx_byte(rx_byte),
        .row_index(row_idx), .col_index(col_idx), .pixel_value(pix_val),
        .RGB_wr_en(rgb_wr_en), .led_wr_en(led_wr_en), .led(led_cmd)
    );

//color / pwm path
    param_ctrl u_param_ctrl (
        .clk(clk), .rst_n(rst_n), .btn_db(btn_db),
        .row_index(row_idx), .col_index(col_idx), .pixel_value(pix_val),
        .RGB_wr_en(rgb_wr_en), .led_wr_en(led_wr_en), .led(led_cmd),
        .applyRGB(apply_rgb), .led_sel(led_sel), .dig_sel(dig_sel),
        .edit_RGB(edit_rgb), .edit_led(edit_led)
    );

    assign cie_en = '1;                     //CIE on for both LEDs until led_rgf is connected

    color_translate #(.PWM_SLOTS(PWM_SLOTS), .CIE_SCALE(CIE_SCALE)) u_color_translate (
        .clk(clk), .rst_n(rst_n), .applyRGB(apply_rgb), .cie_en(cie_en), .busy(busy),
        .duty(duty), .color_start(color_start), .trns_msg(trns_msg)
    );

    pwm_ctrl #(.PWM_SLOTS(PWM_SLOTS)) u_pwm_ctrl (
        .clk(clk), .rst_n(rst_n), .duty(duty), .led_sel(led_sel),
        .led16(led16), .led17(led17)
    );

//display
    display_mux u_display_mux (
        .rx_mode(rx_mode),
        .byte_val(byte_val), .speed_sel(speed_sel), .count_sel(count_sel), .rows_sent(rows_sent),
        .edit_rgb(edit_rgb), .edit_led(edit_led),
        .digits(digits), .dps(dps), .dash(dash)
    
    );

    seg7_ctrl #(.REFRESH_DIV(REFRESH_DIV)) u_seg7_ctrl (
        .clk(clk), .rst_n(rst_n), .digits(digits), .dps(dps), .dash(dash),
        .an(an), .seg(seg), .dp(dp)
    );

endmodule