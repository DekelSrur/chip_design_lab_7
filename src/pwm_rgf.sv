`timescale 1ns/1ps
// PWM RGF - PWM and DDS configuration register file
// 0x0008 PWM_CFG   (RW) : [15:0] time_slots, [31:16] sweep_time
// 0x000C RED_LUT   (RW) : [12:0] out_freq, [14:13] magnitude, [23:15] init_phase
// 0x0010 GREEN_LUT (RW) : same fields
// 0x0014 BLUE_LUT  (RW) : same fields

module pwm_rgf 
    import pkg_rgf::*;
(
    input logic clk,
    input logic rst_n,

    output logic [15:0] time_slots,     //to pwm_ctrl
    output logic [15:0] sweep_time,     //to dds_ctrl
    output lut_reg_t [2:0] lut_cfg,           //to dds_ctrl:[2]=R,[1]=G,[0]=B
    
    rgf_bus_if.rw_slave bus             //interface with addr_xbar
);    

    localparam int N_CH = 3;            //[2]=R,[1]=G,[0]=B

    pwm_cfg_reg_t pwm_cfg_reg;
    lut_reg_t [N_CH-1:0] lut_reg;
    logic pwm_cfg_sel;
    logic [N_CH-1:0] lut_sel;

    assign time_slots = pwm_cfg_reg.time_slots;
    assign sweep_time = pwm_cfg_reg.sweep_time;
    assign lut_cfg    = lut_reg;

    always_comb begin: reg_addr_dec
        pwm_cfg_sel = '0;
        lut_sel = '0;
        unique case (bus.addr)
            PWM_CFG: pwm_cfg_sel = '1;
            RED_LUT: lut_sel[2] = '1;
            GREEN_LUT: lut_sel[1] = '1;
            BLUE_LUT: lut_sel[0] = '1;
        endcase    
    end

    always_comb begin: reg_read
        bus.rdata = '0;
        if(!bus.wr_en) begin
            unique case (1'b1)
                pwm_cfg_sel: bus.rdata = pwm_cfg_reg;
                lut_sel[2]: bus.rdata = DATA_W'(lut_reg[2]);    //red
                lut_sel[1]: bus.rdata = DATA_W'(lut_reg[1]);    //green 
                lut_sel[0]: bus.rdata = DATA_W'(lut_reg[0]);    //blue
            endcase
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin: pwm_cfg_wr
        if(!rst_n) begin
            pwm_cfg_reg<= PWM_CFG_RST;
        end
        else if(bus.wr_en && pwm_cfg_sel) begin
            pwm_cfg_reg <= bus.wdata;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin: lut_wr  
        if(!rst_n) begin
            lut_reg <= {N_CH{LUT_RST}};
        end
        else begin
            for (int i = 0; i < N_CH; i++) begin
                if (bus.wr_en && lut_sel[i])
                    lut_reg[i] <= bus.wdata[LUT_DATA_W-1:0];
            end
        end    
    end

endmodule





