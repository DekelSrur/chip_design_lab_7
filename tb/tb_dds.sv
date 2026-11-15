`timescale 1ns / 1ps

// tb_dds - dds_ctrl together with its sine ROM (rom.sv is instantiated inside dds_ctrl)
//
//   TB: duty_in, pattern, enable, lut_cfg -> dds_ctrl (+ rom) -> duty_out -> TB
//
// What is checked:
//   1. rom        : every clock, wave = raised-cosine(rom_addr) of the previous clock
//                   (reference computed with $cos, not read from the DUT table)
//   2. dds_ctrl   : every clock, duty_out follows the mode:
//                     disabled -> 0, static / reserved -> duty_in,
//                     breath / rainbow -> duty_in * sat(wave << magnitude) / 256
//   3. waveform   : the whole ROM range is swept (0..255), output frequency is correct,
//                   breath = channels in phase, rainbow = channels offset by init_phase
//
// Checks 1-2 run on every rising edge for the whole simulation (scoreboard style);
// the stimulus block walks through the scenarios and checks the waveform shape.

module tb_dds;
    import pkg_sys::*;
    import pkg_rgf::*;

    localparam int  SLOTS    = 1024;
    localparam int  PWM_W    = $clog2(SLOTS);
    localparam int  PHASE_W  = 9;                     // ROM address width (512 entries)
    localparam int  WAVE_W   = 8;                     // ROM data width
    localparam int  DEPTH    = 1 << PHASE_W;
    localparam int  F_OUT    = 5000;                  // Hz - 20,000 clocks per period (short sim)
    localparam int  PERIOD   = CLK_FREQ_HZ / F_OUT;
    localparam int  MAX_MSG  = 20;                    // print only the first errors
    localparam real PI       = 3.141592653589793;

    localparam logic [1:0] STATIC   = 2'h0;
    localparam logic [1:0] BREATH   = 2'h1;
    localparam logic [1:0] RAINBOW  = 2'h2;
    localparam logic [1:0] RESERVED = 2'h3;

//DUT signals - 4-state logic, so X/Z from the DUT stays visible
    logic clk = 0;
    logic rst_n = 0;
    logic enable = 0;                                 // sys_rgf
    logic [1:0] pattern = STATIC;                     // led_rgf
    lut_reg_t [N_CH-1:0] lut_cfg;                     // pwm_rgf, [2]=R [1]=G [0]=B
    logic [N_CH-1:0][PWM_W-1:0] duty_in = '0;         // driven by the TB (color_translate's role)
    logic [N_CH-1:0][PWM_W-1:0] duty_out;             // to pwm_ctrl

//TB bookkeeping - 2-state / int
    int errors = 0;
    int n_rom  = 0;                                   // ROM reads checked
    int n_dds  = 0;                                   // dds outputs checked

    dds_ctrl #(.PWM_SLOTS(SLOTS)) dut (
        .clk(clk), .rst_n(rst_n), .enable(enable), .pattern(pattern),
        .lut_cfg(lut_cfg), .duty_in(duty_in), .duty_out(duty_out));

    always #5 clk = ~clk;                             // 100 MHz

//--------------------------------------------------------------------------- reference models
    //raised cosine, same formula as scripts/gen_sine.py (independent of rom.sv)
    //int'() rounds to the nearest integer
    function automatic int sine_ref(input int addr);
        return int'(255.0 * (1.0 - $cos(2.0 * PI * addr / DEPTH)) / 2.0);
    endfunction : sine_ref

    //magnitude x1/x2/x4/x8 with saturation at 255
    function automatic int gain_ref(input int wave, input int mag);
        int g = wave << mag;
        return (g > 255) ? 255 : g;
    endfunction : gain_ref

    //count an error; returns 1 if its message should still be printed
    function automatic bit new_error();
        errors++;
        if (errors == MAX_MSG + 1) $display("... more errors suppressed");
        return (errors <= MAX_MSG);
    endfunction : new_error

//--------------------------------------------------------------------------- per-clock checkers
//expected values are built from the pre-edge state (what the flops see at the edge)
//and compared 1 ns after the edge
    genvar c;
    generate
        for (c = 0; c < N_CH; c++) begin : G_CHK
            int exp_wave, exp_duty, addr;

            always @(posedge clk) begin
                if (rst_n) begin
                    //1. ROM: synchronous read of the current address
                    addr     = dut.GEN_CH[c].rom_addr;
                    exp_wave = sine_ref(addr);

                    //2. DDS output mux / modulation
                    if (!enable)
                        exp_duty = 0;
                    else if (pattern == BREATH || pattern == RAINBOW)
                        exp_duty = (duty_in[c] * gain_ref(dut.GEN_CH[c].wave, lut_cfg[c].magnitude)) >> WAVE_W;
                    else
                        exp_duty = duty_in[c];

                    #1;
                    if (dut.GEN_CH[c].wave !== WAVE_W'(exp_wave))
                        if (new_error())
                            $display("[%0t] FAILED: ch%0d ROM: addr %0d -> wave %0d, expected %0d",
                                     $time, c, addr, dut.GEN_CH[c].wave, exp_wave);
                    n_rom++;

                    if (duty_out[c] !== PWM_W'(exp_duty))
                        if (new_error())
                            $display("[%0t] FAILED: ch%0d DDS: pattern %0d duty_out %0d, expected %0d",
                                     $time, c, pattern, duty_out[c], exp_duty);
                    n_dds++;
                end
            end
        end
    endgenerate

//--------------------------------------------------------------------------- stimulus helpers
    task automatic set_lut(input int ch, input int freq, input int mag, input int phase);
        lut_cfg[ch].out_freq   = 13'(freq);
        lut_cfg[ch].magnitude  = 2'(mag);
        lut_cfg[ch].init_phase = 9'(phase);
    endtask : set_lut

    task automatic set_duty(input int r, input int g, input int b);
        @(negedge clk);
        duty_in = {PWM_W'(r), PWM_W'(g), PWM_W'(b)};
    endtask : set_duty

    //run n clocks and record the waveform shape
    int wmin [N_CH], wmax [N_CH], dmin [N_CH], dmax [N_CH];
    int n_phase_bad, wraps, first_wrap, last_wrap;

    task automatic run_track(input int n_clk, input int ref_phase [N_CH]);
        logic [31:0] acc_prev;
        for (int ch = 0; ch < N_CH; ch++) begin
            wmin[ch] = 1 << 30; wmax[ch] = -1;
            dmin[ch] = 1 << 30; dmax[ch] = -1;
        end
        n_phase_bad = 0; wraps = 0; first_wrap = 0; last_wrap = 0;
        acc_prev = dut.GEN_CH[0].phase_acc;
        for (int t = 0; t < n_clk; t++) begin
            @(posedge clk); #2;
            for (int ch = 0; ch < N_CH; ch++) begin
                int w, d;
                case (ch)
                    0:       w = dut.GEN_CH[0].wave;
                    1:       w = dut.GEN_CH[1].wave;
                    default: w = dut.GEN_CH[2].wave;
                endcase
                d = duty_out[ch];
                if (w < wmin[ch]) wmin[ch] = w;
                if (w > wmax[ch]) wmax[ch] = w;
                if (d < dmin[ch]) dmin[ch] = d;
                if (d > dmax[ch]) dmax[ch] = d;
            end
            //channel phase relation: addr[ch] - addr[0] == ref_phase[ch] - ref_phase[0] (mod 512)
            if (PHASE_W'(dut.GEN_CH[1].rom_addr - dut.GEN_CH[0].rom_addr) != PHASE_W'(ref_phase[1] - ref_phase[0]) ||
                PHASE_W'(dut.GEN_CH[2].rom_addr - dut.GEN_CH[0].rom_addr) != PHASE_W'(ref_phase[2] - ref_phase[0]))
                n_phase_bad++;
            //frequency: count phase accumulator wraps of channel 0
            if (dut.GEN_CH[0].phase_acc < acc_prev) begin
                if (wraps == 0) first_wrap = t;
                last_wrap = t;
                wraps++;
            end
            acc_prev = dut.GEN_CH[0].phase_acc;
        end
    endtask : run_track

    //shape checks after a modulated run
    task automatic check_shape(input string name);
        int per;
        for (int ch = 0; ch < N_CH; ch++) begin
            if (wmin[ch] != 0 || wmax[ch] != 255)
                if (new_error())
                    $display("%s FAILED: ch%0d ROM range %0d..%0d, expected the full 0..255",
                             name, ch, wmin[ch], wmax[ch]);
            if (dmin[ch] != 0)
                if (new_error())
                    $display("%s FAILED: ch%0d duty_out never reached 0 (min %0d)", name, ch, dmin[ch]);
            if (dmax[ch] > duty_in[ch])
                if (new_error())
                    $display("%s FAILED: ch%0d duty_out %0d above duty_in %0d", name, ch, dmax[ch], duty_in[ch]);
        end
        if (n_phase_bad != 0)
            if (new_error())
                $display("%s FAILED: channel phase relation broken on %0d clocks", name, n_phase_bad);
        if (wraps < 2) begin
            if (new_error())
                $display("%s FAILED: fewer than 2 waveform periods seen", name);
        end
        else begin
            per = (last_wrap - first_wrap) / (wraps - 1);
            if (per < PERIOD - 2 || per > PERIOD + 2)
                if (new_error())
                    $display("%s FAILED: period %0d clocks, expected %0d (%0d Hz)", name, per, PERIOD, F_OUT);
            $display("  %s: period %0d clocks (expected %0d), duty_out R/G/B %0d..%0d / %0d..%0d / %0d..%0d",
                     name, per, PERIOD, dmin[2], dmax[2], dmin[1], dmax[1], dmin[0], dmax[0]);
        end
    endtask : check_shape

//--------------------------------------------------------------------------- scenarios
    initial begin
        int zero_ph [N_CH] = '{0, 0, 0};
        int rb_ph   [N_CH] = '{0, 171, 341};          // [0]=B [1]=G [2]=R

        for (int ch = 0; ch < N_CH; ch++) set_lut(ch, F_OUT, 0, 0);
        for (int i = 0; i < 5; i++) @(negedge clk);
        rst_n = 1;

        //1. disabled: duty_out must be 0 whatever duty_in is
        $display("\n-- 1. disabled");
        set_duty(1023, 512, 100);
        for (int i = 0; i < 50; i++) @(negedge clk);
        if (duty_out !== '0)
            if (new_error()) $display("FAILED: disabled, duty_out is not 0");

        //2. static: duty_out = duty_in (the ROM is not used)
        $display("-- 2. static");
        enable = 1; pattern = STATIC;
        for (int i = 0; i < 5; i++) @(negedge clk);
        if (duty_out !== duty_in)
            if (new_error()) $display("FAILED: static, duty_out != duty_in");

        //3. breath: all channels in phase, full sine on every channel
        $display("-- 3. breath");
        set_duty(1023, 1023, 1023);
        @(negedge clk); pattern = BREATH;
        run_track(PERIOD * 5 / 2, zero_ph);
        check_shape("breath");

        //4. rainbow: init_phase offsets, magnitude x2 on G and x8 on B (saturation)
        $display("-- 4. rainbow + magnitude");
        for (int ch = 0; ch < N_CH; ch++) lut_cfg[ch].init_phase = 9'(rb_ph[ch]);
        lut_cfg[1].magnitude = 2'd1;
        lut_cfg[0].magnitude = 2'd3;
        @(negedge clk); pattern = RAINBOW;
        run_track(PERIOD * 5 / 2, rb_ph);
        check_shape("rainbow");

        //5. breath ignores init_phase
        $display("-- 5. breath ignores init_phase");
        @(negedge clk); pattern = BREATH;
        run_track(PERIOD * 3 / 2, zero_ph);
        if (n_phase_bad != 0)
            if (new_error()) $display("FAILED: breath with init_phase, %0d clocks out of phase", n_phase_bad);

        //6. new duty_in while modulating: the output scales with it
        $display("-- 6. duty_in change while modulating");
        set_duty(100, 700, 3);
        run_track(PERIOD * 5 / 2, zero_ph);
        check_shape("breath, new duty");

        //7. reserved pattern behaves as static
        $display("-- 7. reserved pattern");
        @(negedge clk); pattern = RESERVED;
        for (int i = 0; i < 5; i++) @(negedge clk);
        if (duty_out !== duty_in)
            if (new_error()) $display("FAILED: reserved pattern, duty_out != duty_in");

        //8. disable again
        $display("-- 8. disable");
        @(negedge clk); enable = 0;
        for (int i = 0; i < 5; i++) @(negedge clk);
        if (duty_out !== '0)
            if (new_error()) $display("FAILED: disable, duty_out is not 0");

        $display("\nchecked %0d ROM reads and %0d DDS outputs", n_rom, n_dds);
        $display("\n=== %s (%0d errors) ===", errors ? "TEST FAILED" : "TEST PASSED", errors);
        $finish;
    end

endmodule
