`timescale 1ns/1ps

module led_rgf 
        import pkg_rgf::*;
(
    input logic clk,
    input logic rst_n,
    input logic led_sel_update,              // from param_ctrl
    output logic [1:0] led_sel, cie_en,      // to color_translate
    output logic [PATTERN_W-1:0] pattern,    // to dds_ctrl
    output logic [1:0] led_on,               // to pwm_ctrl
    rgf_bus_if.rw_slave bus                  // interface with addr_xbar
);

led_ctrl_reg_t led_ctrl_sel;
logic led_pattern_sel;
logic [LED_DATA_W-1:0] led_ctrl_reg;
logic [PATTERN_W-1:0] led_pattern_reg;

always_comb begin : reg_addr_dec
    led_ctrl_sel = '0;
    led_pattern_sel = '0;
    unique case (bus.addr)
        LED_CTRL    : led_ctrl_sel = '1;
        LED_PATTERN : led_pattern_sel = '1;  
    endcase
end

always_comb begin : reg_read
    bus.rdata = '0;
    if (!bus.wr_en) begin
        unique case (1'b1)
            led_ctrl_sel    : bus.rdata = led_ctrl_reg;
            led_pattern_sel : bus.rdata = led_pattern_reg;
        endcase
    end
end

always_ff @(posedge clk or negedge rst_n) begin : led_ctrl_wr
    if (!rst_n) begin
        led_ctrl_reg <= '0;
    end
    else if (bus.wr_en && led_ctrl_sel) begin
        led_ctrl_reg <= bus.wdata;
    end
end

always_ff @(posedge clk or negedge rst_n) begin : led_pattern_wr
    if (!rst_n) begin
        led_pattern_reg <= bus.wdata;
    end
    else if (bus.wr_en && led_pattern_sel) begin
        led_pattern_reg <= bus.wdata;
    end
end

endmodule
