`timescale 1ns/1ps

// SYS RGF - system control register file
// 0x0028 SYS_CTRL    (RW)  : [0] sw_rst (self-clearing, reads 0)  [1] enable (reset = 1)
// 0x002C SYS_STATUS  (R0C) : [0] invalid_addr_err  [1] ro_wr_err   (sticky, cleared on read)
// 0x0030 SYS_VERSION (RO)  : [31:16] lab number, [15:0] revision

module sys_rgf
    import pkg_rgf::*;
(
    input  logic clk,
    input  logic rst_n,                         // HW reset only (cpu_resetn), NOT sw_rst
    input  logic invalid_addr_evt,              // from addr_xbar, 1-cycle pulse
    input  logic ro_wr_evt,                     // from addr_xbar, 1-cycle pulse
    output logic sw_rst,                        // to sync, 1-cycle pulse
    output logic enable,                        // to dds_ctrl, pwm_ctrl
    rgf_bus_if.rw_r0c_slave bus               // interface with addr_xbar

    sys_ctrl_reg_t   sys_ctrl_reg;
    sys_status_reg_t sys_status_reg;
    logic sys_ctrl_sel, sys_status_sel, sys_version_sel;
    logic status_rd;

    assign enable = sys_ctrl_reg.enable_q;
    assign sw_rst = sys_ctrl_reg.sw_rst_q;

// 1. address decode
    always_comb begin : reg_addr_dec
        sys_ctrl_sel    = '0;
        sys_status_sel  = '0;
        sys_version_sel = '0;
        unique case (bus.addr)
            SYS_CTRL    : sys_ctrl_sel    = '1;
            SYS_STATUS  : sys_status_sel  = '1;
            SYS_VERSION : sys_version_sel = '1;
            default     : ;
        endcase
    end

    assign status_rd = bus.rd_en && sys_status_sel;

// 2. read mux
    always_comb begin : reg_read
        bus.rdata = '0;
        if (!bus.wr_en) begin
            unique case (1'b1)
                sys_ctrl_sel    : bus.rdata = DATA_W'({sys_ctrl_reg.enable_q, 1'b0});   // sw_rst reads 0
                sys_status_sel  : bus.rdata = DATA_W'(sys_status_reg);
                sys_version_sel : bus.rdata = SYS_VERSION_VAL;
                default         : ;
            endcase
        end
    end

// 3. SYS_CTRL - enable is RW, sw_rst clears itself one clock after it was set
    always_ff @(posedge clk or negedge rst_n) begin : sys_ctrl_wr
        if (!rst_n) begin
            sys_ctrl_reg <= SYS_CTRL_RST;
        end
        else if (bus.wr_en && sys_ctrl_sel) begin
            sys_ctrl_reg <= bus.wdata[SYS_CTRL_DATA_W-1:0];
        end
        else begin
            sys_ctrl_reg.sw_rst_q <= 1'b0;
        end
    end

// 4. SYS_STATUS - sticky flags, cleared on read (a new event wins over the clear)
    always_ff @(posedge clk or negedge rst_n) begin : sys_status_wr
        if (!rst_n) begin
            sys_status_reg <= SYS_STATUS_RST;
        end
        else begin
            sys_status_reg <= (sys_status_reg & {SYS_STATUS_DATA_W{~status_rd}})
                            | {ro_wr_evt, invalid_addr_evt};
        end
    end

endmodule
