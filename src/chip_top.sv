`timescale 1ns/1ps

module chip_top
    import pkg_rgf::*;
 #(
    parameter CLKS_PER_BIT = pkg_sys::CLKS_PER_BIT,    //from package
    parameter DEBOUNCE_CYCLES = 1_000_000,             //debounce window: 10 ms
    parameter REFRESH_DIV = 25_000,                    //100 MHz / 25,000 = 4 kHz -> 500 Hz per digit 
    parameter PWM_SLOTS = pkg_sys::PWM_SLOTS_DEF,      //PWM resolution 512..8192
    parameter CIE_SCALE = pkg_sys::CIE_SCALE_DEF,      //brightness, out of 256   
    parameter DDS_FREQ_DIV = 1
)(
    input logic clk,
    input logic cpu_resetn,
    input logic btnc, btnu, btnd, btnl, btnr,
    input logic uart_rxd,                   //serial line from the PC

    output logic uart_txd,                  //serial line to the PC
    output logic [2:0] led16,               //RGB LED16 {R,G,B}
    output logic [2:0] led17,               //RGB LED17 {R,G,B}
    output logic [7:0]  an,
    output logic [6:0]  seg,
    output logic dp
);

    localparam int PWM_W = $clog2(PWM_SLOTS);

//resets and conditioned inputs
    logic hw_rst_n;                         //cpu_resetn only to sys_rgf
    logic rst_n;                            //cpu_resetn or sw reset to everything else
    logic sw_rst;                           //SYS_CTRL.sw_rst pulse
    logic enable;                           //SYS_CTRL.enable
    logic [4:0] btn_s;                      
    logic [4:0] btn_db;
    logic rxd_s;                            //synchronized uart rx line
 //rx path
    logic [7:0] rx_byte;                    //byte from RX_fsm (PHY)
    logic rx_ready;                         //1-cycle pulse: new byte
    logic [7:0] row_idx, col_idx, pix_val;
    logic rgb_wr_en, led_wr_en, led_cmd;    //parser to param_ctrl
    logic rx_pkt, color_msg, cfg_msg;       //parser to cnt_rgf
//register bus - master side
    logic [ADDR_W-1:0] master_addr;
    logic [DATA_W-1:0] master_wdata;
    logic master_wen, master_ren;
    logic master_rvalid;
    logic [ADDR_W-1:0] master_raddr;
    logic [DATA_W-1:0] master_rdata;
    logic invalid_addr_evt, ro_wr_evt;      //addr_xbar to sys_rgf
//register bus - slave side
    rgf_bus_if led_bus ();
    rgf_bus_if pwm_bus ();
    rgf_bus_if cnt_bus ();
    logic sys_sel, sys_wen, sys_ren;
    logic [ADDR_W-1:0] sys_addr;
    logic [DATA_W-1:0] sys_wdata, sys_rdata;
    logic sys_err;                          //not used: addr_xbar checks the address itself
//tx path
    logic tx_start;
    logic tx_busy;                          //not used: tx_fsm works with tx_done
    logic tx_done;
    logic [7:0] tx_data;
    logic tx_fsm_busy;                      //not used yet
    logic tx_pkt;                           //tx_fsm -> cnt_rgf
//register outputs
    logic [1:0] led_sel_rgf;                //LED_CTRL.led_sel - not used yet (one colour for both LEDs)
    logic [1:0] cie_en;                     //LED_CTRL.cie_on - not used yet (color_translate has no bypass)
    logic [1:0] led_on;                     //LED_CTRL.led_on to pwm_ctrl
    logic [1:0] pattern;                    //LED_PATTERN to dds_ctrl
    logic [15:0] time_slots;                //PWM_CFG.time_slots - not used yet (PWM_SLOTS is a parameter)
    logic [15:0] sweep_time;                //PWM_CFG.sweep_time - not used yet
    lut_reg_t [2:0] lut_cfg;                //RED/GREEN/BLUE_LUT to dds_ctrl
//color / PWM path
    logic [23:0] apply_rgb;                 //{R, G, B}
    logic led_sel_pc;                       //param_ctrl led choice: 1 = LED16, 0 = LED17
    logic led_sel_pc_q;
    logic led_wr_en_q;
    logic hw_wr_en;                         //param_ctrl chose a led to write LED_CTRL
    logic [7:0] dig_sel;                    //selected field, 2 bits per display pair
    logic [23:0] edit_rgb;                  //{R, G, B} being edited -> display
    logic edit_led;                         //LED being edited -> display
    logic [2:0][PWM_W-1:0] duty;            //color_translate -> dds_ctrl
    logic [2:0][PWM_W-1:0] duty_mod;        //dds_ctrl -> pwm_ctrl
//display
    logic [31:0] digits;
    logic [7:0] dps_mux;
    logic [7:0] dps;
    logic [7:0] dash;

//input conditioning
    sync u_sync (
        .clk(clk), .cpu_resetn(cpu_resetn), .btn({btnc, btnu, btnd, btnl, btnr}), .uart_rxd(uart_rxd),
        .sw_rst(sw_rst),
        .hw_rst_n(hw_rst_n), .rst_n(rst_n), .btn_s(btn_s), .rxd_s(rxd_s)
    );

    debouncer #(.DEBOUNCE_CYCLES(DEBOUNCE_CYCLES)) u_debouncer (
        .clk(clk), .rst_n(rst_n), .btn_in(btn_s),
        .btn_db(btn_db)
    );

//rx path
    RX_fsm #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_RX_fsm (
        .clk(clk), .rst_n(rst_n), .rx(rxd_s),
        .rx_byte(rx_byte), .rx_ready(rx_ready)
    );

    parser u_parser (
        .clk(clk), .rst_n(rst_n), .rx_ready(rx_ready), .rx_byte(rx_byte),
        .row_index(row_idx), .col_index(col_idx), .pixel_value(pix_val),
        .RGB_wr_en(rgb_wr_en), .led_wr_en(led_wr_en), .led(led_cmd),
        .master_addr(master_addr), .master_wdata(master_wdata),
        .master_wen(master_wen), .master_ren(master_ren),
        .rx_pkt(rx_pkt), .color_msg(color_msg), .cfg_msg(cfg_msg)
    );

//register bus
    addr_xbar u_addr_xbar (
        .master_addr(master_addr), .master_wdata(master_wdata),
        .master_wen(master_wen), .master_ren(master_ren),
        .master_rvalid(master_rvalid), .master_raddr(master_raddr), .master_rdata(master_rdata),
        .invalid_addr_evt(invalid_addr_evt), .ro_wr_evt(ro_wr_evt),
        .sys_sel(sys_sel), .sys_wen(sys_wen), .sys_ren(sys_ren),
        .sys_addr(sys_addr), .sys_wdata(sys_wdata), .sys_rdata(sys_rdata),
        .led_bus(led_bus), .pwm_bus(pwm_bus), .cnt_bus(cnt_bus)
    );

//register files
    led_rgf u_led_rgf (
        .clk(clk), .rst_n(rst_n),
        .led_sel_update(led_sel_pc), .hw_wr_en(hw_wr_en),
        .led_sel(led_sel_rgf), .cie_en(cie_en), .pattern(pattern), .led_on(led_on),
        .bus(led_bus)
    );

    pwm_rgf u_pwm_rgf (
        .clk(clk), .rst_n(rst_n),
        .time_slots(time_slots), .sweep_time(sweep_time), .lut_cfg(lut_cfg),
        .bus(pwm_bus)
    );

    cnt_rgf u_cnt_rgf (
        .clk(clk), .rst_n(rst_n),
        .rx_pkt(rx_pkt), .color_msg(color_msg), .cfg_msg(cfg_msg), .tx_pkt(tx_pkt),
        .bus(cnt_bus)
    );

    sys_rgf u_sys_rgf (
        .clk(clk), .rst_n(hw_rst_n),            
        .sel(sys_sel), .wen(sys_wen), .ren(sys_ren),
        .addr(sys_addr), .wdata(sys_wdata), .rdata(sys_rdata), .err(sys_err),
        .invalid_addr_evt(invalid_addr_evt), .ro_wr_evt(ro_wr_evt),
        .sw_rst(sw_rst), .enable(enable)
    );

//tx path 
    tx_fsm u_tx_fsm (
        .clk(clk), .rst_n(rst_n),
        .master_rvalid(master_rvalid), .master_raddr(master_raddr), .master_rdata(master_rdata),
        .tx_done(tx_done),
        .tx_start(tx_start), .tx_data(tx_data), .busy(tx_fsm_busy), .tx_pkt(tx_pkt)
    );

    uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_uart_tx (
        .clk(clk), .rst_n(rst_n), .tx_start(tx_start), .tx_data(tx_data),
        .tx(uart_txd), .tx_busy(tx_busy), .tx_done(tx_done)
    );

//color / pwm path
    param_ctrl u_param_ctrl (
        .clk(clk), .rst_n(rst_n), .btn_db(btn_db),
        .row_index(row_idx), .col_index(col_idx), .pixel_value(pix_val),
        .RGB_wr_en(rgb_wr_en), .led_wr_en(led_wr_en), .led(led_cmd),
        .applyRGB(apply_rgb), .led_sel(led_sel_pc), .dig_sel(dig_sel),
        .edit_RGB(edit_rgb), .edit_led(edit_led)
    );

    //param_ctrl keeps the led choice as a level; led_rgf wants a write pulse.
    //one HW write to LED_CTRL is issued:
    //  - one cycle after a led message (led_sel_pc already holds the new choice)
    //  - when the level changes (CENTER button applied a different led)
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            led_sel_pc_q <= 1'b0;
            led_wr_en_q  <= 1'b0;
        end
        else begin
            led_sel_pc_q <= led_sel_pc;
            led_wr_en_q  <= led_wr_en;
        end
    end

    assign hw_wr_en = led_wr_en_q || (led_sel_pc != led_sel_pc_q);

    color_translate #(.PWM_SLOTS(PWM_SLOTS), .CIE_SCALE(CIE_SCALE)) u_color_translate (
        .clk(clk), .rst_n(rst_n), .applyRGB(apply_rgb),
        .busy(1'b0),                            //Lab 6 colour report is not sent in Lab 7
        .duty(duty), .color_start(), .trns_msg()
    );

    dds_ctrl #(.PWM_SLOTS(PWM_SLOTS), .FREQ_DIV(DDS_FREQ_DIV)) u_dds_ctrl (
        .clk(clk), .rst_n(rst_n), .enable(enable), .pattern(pattern), .lut_cfg(lut_cfg),
        .duty_in(duty), .duty_out(duty_mod)
    );

    pwm_ctrl #(.PWM_SLOTS(PWM_SLOTS)) u_pwm_ctrl (
        .clk(clk), .rst_n(rst_n), .duty(duty_mod), .led_on(led_on),
        .led16(led16), .led17(led17)
    );

//display - always the colour editor layout: T3 = LED, T2 = R, T1 = G, T0 = B
    display_mux u_display_mux (
        .rx_mode(1'b1),                        
        .byte_val(8'd0), .speed_sel(2'd0), .count_sel(2'd0), .rows_sent(9'd0),
        .edit_rgb(edit_rgb), .edit_led(edit_led),
        .digits(digits), .dps(dps_mux), .dash(dash)
    );

    assign dps = dps_mux | dig_sel;

    seg7_ctrl #(.REFRESH_DIV(REFRESH_DIV)) u_seg7_ctrl (
        .clk(clk), .rst_n(rst_n), .digits(digits), .dps(dps), .dash(dash),
        .an(an), .seg(seg), .dp(dp)
    );

endmodule