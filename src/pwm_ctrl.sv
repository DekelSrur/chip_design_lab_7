`timescale 1ns/1ps

// PWM controller - runtime period from PWM_CFG.time_slots (pwm_rgf)
//
//   counter 0 ... slots-1, slots = pwm_slots clamped to 2 .. PWM_SLOTS_MAX
//   duty arrives scaled to PWM_SLOTS (2^PWM_W = 100%) and is rescaled to the
//   current period:  duty_sh = duty * slots / 2^PWM_W
//   new pwm_slots and duty are loaded together at the last slot of a period,
//   so a change never cuts a period short
//   out = led_on && (cnt < duty_sh)

module pwm_ctrl
    import pkg_sys::*;
#(
    parameter int PWM_SLOTS = PWM_SLOTS_DEF,    //duty input full scale (100%) and slots after reset
    localparam int PWM_W = $clog2(PWM_SLOTS)    //duty input width
)(
    input logic clk, rst_n,
    input logic [N_CH-1:0][PWM_W-1:0] duty,     //{R, G, B} duty cycles, scaled to PWM_SLOTS
    input logic [15:0] pwm_slots,               //PWM_CFG.time_slots from pwm_rgf
    input logic [1:0] led_on,                   //LED_CTRL.led_on: [0] = LED16, [1] = LED17

    output logic [N_CH-1:0] led16,              
    output logic [N_CH-1:0] led17               
);    

    localparam int N_LEDS = 2;
    localparam int SLOTS_MIN = 2;               //shortest legal period

    logic [DUTY_W-1:0] cnt;                    //PWM counter: 0 ... slots_q-1
    logic [DUTY_W:0] slots_q;                  //period in use (up to PWM_SLOTS_MAX)
    logic [DUTY_W:0] slots_new;                //pwm_slots clamped to SLOTS_MIN .. PWM_SLOTS_MAX
    logic last_slot;                           //cnt is the last slot of the period
    logic [N_CH-1:0][DUTY_W-1:0] duty_sh;      //shadow copy of duty, rescaled to slots_q
    logic [N_LEDS-1:0] led_en;                 //which led is active  
    logic [N_LEDS-1:0][N_CH-1:0] pwm_q;        //registered PWM outputs (glitch-free pins)

    assign led_en = {led_on[0], led_on[1]};    //pwm_q[1] = LED16, pwm_q[0] = LED17

//illegal values from the PC are clamped (0/1 -> 2, above 8192 -> 8192)
    always_comb begin
        if (pwm_slots < 16'(SLOTS_MIN))          slots_new = (DUTY_W+1)'(SLOTS_MIN);
        else if (pwm_slots > 16'(PWM_SLOTS_MAX)) slots_new = (DUTY_W+1)'(PWM_SLOTS_MAX);
        else                                slots_new = pwm_slots[DUTY_W:0];
    end

    assign last_slot = ({1'b0, cnt} >= slots_q - 1'b1);

//counter: wraps after the last slot of the current period
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)         cnt <= '0;
        else if (last_slot) cnt <= '0;
        else                cnt <= cnt + 1'b1;
    end

//load the new period and duty only at the last slot -> the next period starts with them
//duty rescale: duty * slots / 2^PWM_W (constant shift, 3 small multipliers)
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            slots_q <= (DUTY_W+1)'(PWM_SLOTS);
            duty_sh <= '0;
        end
        else if (last_slot) begin
            slots_q <= slots_new;
            for (int c = 0; c < N_CH; c++)
                duty_sh[c] <= DUTY_W'(((PWM_W+DUTY_W+1)'(duty[c]) * slots_new) >> PWM_W);   //full-width product
        end
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
