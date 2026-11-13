`timescale 1ns/1ps

// SYS RGF - system control register file
// 0x0028 SYS_CTRL    (RW)  : [0] sw_rst (self-clearing, reads 0)  [1] enable (reset = 1)
// 0x002C SYS_STATUS  (R0C) : [0] invalid_addr_err  [1] ro_wr_err   (sticky, cleared on read)
// 0x0030 SYS_VERSION (RO)  : [31:16] lab number, [15:0] revision

module sys_rgf
    import pkg_rgf::*;
#(
    parameter logic [DATA_W-1:0] VERSION = 32'h0007_0001
)(
    input  logic              clk,
    input  logic              rst_n,          // HW reset only (cpu_resetn), NOT sw_rst

    // register bus, from addr_xbar
    input  logic              sel,            // address belongs to SYS RGF
    input  logic              wen,            // 1-cycle write strobe
    input  logic              ren,            // 1-cycle read strobe
    input  logic [ADDR_W-1:0] addr,
    input  logic [DATA_W-1:0] wdata,
    output logic [DATA_W-1:0] rdata,
    output logic              err,            // unmapped address inside SYS RGF

    // error events, from addr_xbar
    input  logic              invalid_addr_evt,   // 1-cycle pulse
    input  logic              ro_wr_evt,          // 1-cycle pulse

    // to the system
    output logic              sw_rst,         // 1-cycle pulse -> sync
    output logic              enable          // -> dds_ctrl, pwm_ctrl
);

    localparam int SW_RST_BIT      = 0;
    localparam int ENABLE_BIT      = 1;

    logic [1:0] status;                       // {ro_wr_err, invalid_addr_err}

// 1. address decode
    logic ctrl_wr, status_rd;
    assign ctrl_wr   = sel && wen && (addr == SYS_CTRL);
    assign status_rd = sel && ren && (addr == SYS_STATUS);

// 2. SYS_CTRL.enable - RW, on after reset
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)       enable <= 1'b1;
        else if (ctrl_wr) enable <= wdata[ENABLE_BIT];
    end

// 3. SYS_CTRL.sw_rst - self-clearing pulse
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) sw_rst <= 1'b0;
        else        sw_rst <= ctrl_wr && wdata[SW_RST_BIT];
    end

// 4. SYS_STATUS - sticky flags, cleared on read (a new event wins over the clear)
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) status <= '0;
        else        status <= (status & {2{~status_rd}}) | {ro_wr_evt, invalid_addr_evt};
    end

// 5. read mux
    always_comb begin
        rdata = '0;
        err   = 1'b0;
        if (sel) begin
            case (addr)
                SYS_CTRL    : rdata[ENABLE_BIT] = enable;       // sw_rst always reads 0
                SYS_STATUS  : rdata[1:0]        = status;
                SYS_VERSION : rdata             = VERSION;
                default     : err               = 1'b1;
            endcase
        end
    end

endmodule