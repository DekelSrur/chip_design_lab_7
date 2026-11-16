`timescale 1ns/1ps

module led_rgf 
        import pkg_rgf::*;
(
    input logic clk,
    input logic rst_n,
    input logic led_sel_update, hw_wr_en,         // from param_ctrl

    output logic [1:0] led_sel,                   // currently unused
    output logic cie_on,                          // to color_translate: CIE setting of the lit LED
    output logic [PATTERN_DATA_W-1:0] pattern,    // to dds_ctrl
    output logic [1:0] led_on,                    // to pwm_ctrl
    rgf_bus_if.rw_slave bus                       // interface with addr_xbar
);

led_ctrl_reg_t led_ctrl_reg;
led_pattern_reg_t led_pattern_reg;
logic led_ctrl_sel;
logic led_pattern_sel;

assign led_sel = led_ctrl_reg.led_sel_q;
//one colour drives both LEDs: use LED16's CIE setting when LED16 is on, otherwise LED17's
assign cie_on  = led_ctrl_reg.led16_on_q ? led_ctrl_reg.led16_cie_on_q : led_ctrl_reg.led17_cie_on_q;
assign led_on  = {led_ctrl_reg.led17_on_q, led_ctrl_reg.led16_on_q};
assign pattern = led_pattern_reg.pattern;

always_comb begin : reg_addr_dec
    led_ctrl_sel = '0;
    led_pattern_sel = '0;
    unique case (bus.addr)
        LED_CTRL    : led_ctrl_sel = '1;
        LED_PATTERN : led_pattern_sel = '1; 
        default: ; 
    endcase
end

always_comb begin : reg_read
    bus.rdata = '0;
    if (!bus.wr_en) begin
        unique case (1'b1)
            led_ctrl_sel    : bus.rdata = DATA_W'(led_ctrl_reg);
            led_pattern_sel : bus.rdata = DATA_W'(led_pattern_reg);
            default: ;
        endcase
    end
end

always_ff @(posedge clk or negedge rst_n) begin : led_ctrl_wr
    if (!rst_n) begin
        led_ctrl_reg <= LED_CTRL_RST;
    end
    else if (bus.wr_en && led_ctrl_sel) begin
        led_ctrl_reg <= bus.wdata[LED_DATA_W-1:0];
    end
    else if (hw_wr_en) begin
        led_ctrl_reg.led_sel_q   <= (led_sel_update) ? LED16 : LED17;
        led_ctrl_reg.led16_on_q <= led_sel_update;
        led_ctrl_reg.led17_on_q <= !led_sel_update;
    end
end

always_ff @(posedge clk or negedge rst_n) begin : led_pattern_wr
    if (!rst_n) begin
        led_pattern_reg <= LED_PATTERN_RST;
    end
    else if (bus.wr_en && led_pattern_sel) begin
        led_pattern_reg <= bus.wdata[PATTERN_DATA_W-1:0];
    end
end

endmodule


