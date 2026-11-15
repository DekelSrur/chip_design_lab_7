`timescale 1ns/1ps

// DDS controller - modulates the color duty cycles with a sine wave
//
//   pattern 2'h0 static  : duty_out = duty_in
//   pattern 2'h1 breath  : all channels in phase   (init_phase ignored)
//   pattern 2'h2 rainbow : each channel starts at its own init_phase
//   pattern 2'h3 reserved: behaves as static
//
// Per channel (generate x3, [2]=R [1]=G [0]=B):
//   phase_acc += phase_inc                      (ACC_W-bit accumulator, wraps)
//   rom_addr   = phase_acc[MSBs] + init_phase   (9-bit, wraps)
//   wave_g     = sat(wave << magnitude)         (x1/x2/x4/x8, clipped at 255)
//   duty_out   = duty_in * wave_g / 256
//
// phase_inc = out_freq * 2^ACC_W / (CLK_FREQ_HZ * FREQ_DIV)
//   out_freq unit = 1/FREQ_DIV Hz  (FREQ_DIV = 1 -> Hz, as in the RGF doc)

module dds_ctrl
    import pkg_sys::*;
    import pkg_rgf::*;
#(
    parameter int  PWM_SLOTS   = PWM_SLOTS_DEF,
    parameter int  CLK_HZ      = CLK_FREQ_HZ,
    parameter int  FREQ_DIV    = 1,                    // out_freq unit = 1/FREQ_DIV Hz
    parameter int  ACC_W       = 32,                   // phase accumulator width
    localparam int PWM_W       = $clog2(PWM_SLOTS),
    localparam int PHASE_W     = 9,                    // ROM address = init_phase width
    localparam int WAVE_W      = 8                     // ROM data width
)(
    input  logic                         clk,
    input  logic                         rst_n,
    input  logic                         enable,       // from sys_rgf
    input  logic [1:0]                   pattern,      // from led_rgf
    input  lut_reg_t [N_CH-1:0]          lut_cfg,      // from pwm_rgf
    input  logic [N_CH-1:0][PWM_W-1:0]   duty_in,      // from color_translate
    output logic [N_CH-1:0][PWM_W-1:0]   duty_out      // to pwm_ctrl
);

    localparam logic [1:0] STATIC  = 2'h0;
    localparam logic [1:0] BREATH  = 2'h1;
    localparam logic [1:0] RAINBOW = 2'h2;

    // fixed-point constant: phase_inc = (out_freq * INC_K) >> FRAC
    localparam int          FRAC  = 16;
    localparam longint      INC_K = ((64'd1 << (ACC_W + FRAC)) + (CLK_HZ * FREQ_DIV) / 2)
                                    / (CLK_HZ * FREQ_DIV);
    localparam logic [WAVE_W-1:0] WAVE_MAX = '1;

    logic       modulate;                    // breath or rainbow
    logic [1:0] pattern_q;
    logic       restart;                     // re-align the channels

    assign modulate = (pattern == BREATH) || (pattern == RAINBOW);
    assign restart  = !enable || (pattern != pattern_q);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) pattern_q <= STATIC;
        else        pattern_q <= pattern;
    end

    genvar c;
    generate
        for (c = 0; c < N_CH; c++) begin : GEN_CH

            logic [ACC_W-1:0]    phase_inc, phase_acc;
            logic [PHASE_W-1:0]  phase_ofs, rom_addr;
            logic [WAVE_W-1:0]   wave;
            logic [WAVE_W+2:0]   wave_sh;    // wave << 0..3
            logic [WAVE_W-1:0]   wave_g;
            logic [PWM_W+WAVE_W-1:0] prod;

        // 1. frequency -> phase step (registered, constant multiply)
            always_ff @(posedge clk or negedge rst_n) begin
                if (!rst_n) phase_inc <= '0;
                else        phase_inc <= ACC_W'((64'(lut_cfg[c].out_freq) * INC_K) >> FRAC);
            end

        // 2. phase accumulator - wraps naturally
            always_ff @(posedge clk or negedge rst_n) begin
                if (!rst_n)       phase_acc <= '0;
                else if (restart) phase_acc <= '0;
                else              phase_acc <= phase_acc + phase_inc;
            end

        // 3. ROM address: top bits + start phase (rainbow only), 9-bit wrap
            assign phase_ofs = (pattern == RAINBOW) ? lut_cfg[c].init_phase : '0;
            assign rom_addr  = phase_acc[ACC_W-1 -: PHASE_W] + phase_ofs;

            rom #(.DEPTH(1 << PHASE_W), .WIDTH(WAVE_W)) u_rom (
                .clk (clk),
                .addr(rom_addr),
                .data(wave)                  // valid one clock later
            );

        // 4. magnitude: x1/x2/x4/x8 with saturation
            assign wave_sh = (WAVE_W+3)'(wave) << lut_cfg[c].magnitude;
            assign wave_g  = (wave_sh > WAVE_MAX) ? WAVE_MAX : wave_sh[WAVE_W-1:0];

        // 5. modulate: duty_in * wave / 256
            assign prod = duty_in[c] * wave_g;

        // 6. output select (registered)
            always_ff @(posedge clk or negedge rst_n) begin
                if (!rst_n)        duty_out[c] <= '0;
                else if (!enable)  duty_out[c] <= '0;
                else if (modulate) duty_out[c] <= prod[WAVE_W +: PWM_W];
                else               duty_out[c] <= duty_in[c];
            end
        end
    endgenerate

endmodule
