`timescale 1ns/1ps

module color_translate
    import pkg_sys::*;
#(
    parameter int PWM_SLOTS = PWM_SLOTS_DEF,    // 512 / 1024 / 2048 / 4096 / 8192
    parameter int CIE_SCALE = CIE_SCALE_DEF,    // brightness = CIE_SCALE / 256 (1..256)
    localparam int PWM_W = $clog2(PWM_SLOTS)    // duty width (derived - cannot override)
)(
    input logic clk, rst_n,
    input logic [N_CH*BYTE-1:0] applyRGB,       // {R, G, B} sRGB from param_ctrl
    input logic [N_LEDS-1:0] cie_en,            // from led_rgf, [0]=LED16 [1]=LED17:
                                                //   1 = gamma + CIE brightness, 0 = linear (sRGB scaled to PWM_W)
    input logic busy,                           // tx_fsm busy, hold the report
    output logic [N_LEDS-1:0][N_CH-1:0][PWM_W-1:0] duty, // per LED {R, G, B} duty cycles, pwm_ctrl
    output logic color_start,                   // 1-cycle pulse, tx_fsm
    output logic [N_CH*PWM_W-1:0] trns_msg      // {R, G, B} translated values of LED16, tx_fsm
);

    `include "black_magic_box.sv"               // const logic [9:0] gamma_table [0:255]

//elaboration-time parameter checks (no hardware)
    generate
        if (PWM_SLOTS != (1 << PWM_W) || PWM_W < 9 || PWM_W > 13)
            $error("color_translate: PWM_SLOTS must be a power of 2 in 512..8192 (got %0d)", PWM_SLOTS);
        if (CIE_SCALE < 1 || CIE_SCALE > 256)
            $error("color_translate: CIE_SCALE must be in 1..256 (got %0d)", CIE_SCALE);
    endgenerate

    logic [N_CH*BYTE-1:0] rgb_q;                // previous applyRGB (change detection, linear path)
    logic [N_LEDS-1:0] cie_q;                   // previous cie_en (change detection, stage 2 select)
    logic rgb_chg;                              // applyRGB or cie_en changed this cycle
    logic [GAMMA_W-1:0] lin_q [N_CH];           // stage 1: gamma-corrected (linear) value
    logic [PWM_W-1:0] lin_fit [N_CH];           // linear value resized to PWM_W bits
    logic [PWM_W+8:0] scaled [N_CH];            // lin_fit * CIE_SCALE (before the /256)
    logic [PWM_W-1:0] srgb_fit [N_CH];          // linear path: sRGB stretched to PWM_W bits
    logic vld1, vld2;                           // pipeline valid flags (stage 1, stage 2)
    logic pending;                              // new duty waiting to be reported

    assign rgb_chg = (applyRGB != rgb_q) || (cie_en != cie_q);

// one identical datapath per color channel
    genvar c, l;
    generate
        for (c = 0; c < N_CH; c++) begin : GEN_CH
            //stage 1 - gamma look-up table, synchronous read
            //(no reset on purpose: a ROM read port has no reset)
            always_ff @(posedge clk)
                lin_q[c] <= gamma_table[applyRGB[c*BYTE +: BYTE]];

            // fit the 10-bit table (1024 slots) to the PWM resolution - pure wiring, no logic
            if (PWM_W > GAMMA_W) begin : G_UP           // 2048/4096/8192 slots: x2/x4/x8
                assign lin_fit[c] = {lin_q[c], {(PWM_W-GAMMA_W){1'b0}}};
            end
            else if (PWM_W < GAMMA_W) begin : G_DOWN    // 512 slots: /2 (keep the MSBs)
                assign lin_fit[c] = lin_q[c][GAMMA_W-1 -: PWM_W];
            end
            else begin : G_EQ                           // 1024 slots: as is
                assign lin_fit[c] = lin_q[c];
            end

            //CIE brightness scaling: duty = lin * CIE_SCALE / 256 (constant multiply + shift)
            //keeps the perceived color (ratios stay linear) but limits the LED intensity
            assign scaled[c] = lin_fit[c] * (PWM_W+9)'(CIE_SCALE);

            //linear path (CIE off): sRGB stretched to PWM_W bits by repeating its MSBs
            //0 -> 0 and 255 -> all ones (full range), pure wiring, no logic
            //rgb_q is applyRGB delayed one clock - aligned with the gamma stage 1
            assign srgb_fit[c] = {rgb_q[c*BYTE +: BYTE], rgb_q[c*BYTE + BYTE-1 -: PWM_W-BYTE]};

            //stage 2 - registered duty value per LED, CIE on/off selected per LED
            for (l = 0; l < N_LEDS; l++) begin : GEN_LED
                always_ff @(posedge clk or negedge rst_n) begin
                    if (!rst_n)        duty[l][c] <= '0;
                    else if (cie_q[l]) duty[l][c] <= scaled[c][8 +: PWM_W];   // gamma, divide by 256
                    else               duty[l][c] <= srgb_fit[c];             // linear
                end
            end
        end
    endgenerate

//control: track the pipeline and report the new values to tx_fsm when it is idle
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rgb_q <= '0;
            cie_q <= '1;                     // led_rgf reset: CIE on for both LEDs
            vld1 <= 1'b0;
            vld2 <= 1'b0;
            pending <= 1'b0;
            color_start <= 1'b0;
            trns_msg <= '0;
        end
        else begin
            rgb_q <= applyRGB;
            cie_q <= cie_en;
            vld1 <= rgb_chg;                 // lin_q holds the new color
            vld2 <= vld1;                    // duty holds the new color
            color_start <= 1'b0;             // default: pulse lasts one cycle

            if (vld2)                        // a newer color always re-arms the report
                pending <= 1'b1;
            else if (pending && !busy) begin // tx_fsm idle -> send the report
                color_start <= 1'b1;
                trns_msg <= duty[0];         // LED16 values
                pending <= 1'b0;
            end
        end
    end

endmodule