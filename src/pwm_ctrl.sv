`timescale 1ns/1ps

module pwm_ctrl
    import pkg_lab6::*;
#(
    parameter int PWM_SLOTS = PWM_SLOTS_DEF,    // 512 / 1024 / 2048 / 4096 / 8192
    localparam int PWM_W = $clog2(PWM_SLOTS)    //counter
)(
    input logic clk, rst_n,
    input logic [N_CH-1:0][PWM_W-1:0] duty,     //{R, G, B} duty cycles
    input logic led_sel,                        //1 = LED16, 0 = LED17

    output logic [N_CH-1:0] led16,              
    output logic [N_CH-1:0] led17               
);    

    localparam int N_LEDS = 2;

    logic [PWM_W-1:0] cnt;                     //PWM counter
    logic [N_CH-1:0][PWM_W-1:0] duty_sh;       //shadow copy of duty, used by the compare
    logic [N_LEDS-1:0] led_en;                 //which led is active  
    logic [N_LEDS-1:0][N_CH-1:0] pwm_q;        //registered PWM outputs (glitch-free pins)

    assign led_en = {led_sel, ~led_sel};

//free-running counter - wraps naturally every PWM_SLOTS clocks (power of 2)
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) cnt <= '0;
        else        cnt <= cnt + 1'b1;
    end

//load a new duty only at the last slot -> the next period starts with the new value
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)          duty_sh <= '0;
        else if (cnt == '1)  duty_sh <= duty;
    end

//2 LEDs x 3 channels = 6 identical comparators
    genvar l, c;
    generate
        for (l = 0; l < N_LEDS; l++) begin : GEN_LED
            for (c = 0; c < N_CH; c++) begin : GEN_CH
                always_ff @(posedge clk or negedge rst_n) begin
                    if (!rst_n) pwm_q[l][c] <= 1'b0;
                    else        pwm_q[l][c] <= led_en[l] && (cnt < duty_sh[c]);
                end
            end
        end
    endgenerate

    assign led16 = pwm_q[1];
    assign led17 = pwm_q[0];

endmodule