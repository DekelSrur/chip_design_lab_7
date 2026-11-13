`timescale 1ns/1ps

package pkg_rgf;

// --- general parameters ---
  parameter int ADDR_W = 24;
  parameter int DATA_W = 32;

// --- led_ctrl parameters ---
  parameter int LED_DATA_W = 6;
  parameter int PATTERN_DATA_W = 2;
  typedef enum {LED16 = 2'b01, LED17 = 2'b10} led_sel_t;

  parameter logic [ADDR_W-1:0] RW_REG_ADDR  = 8'h00;
  parameter logic [ADDR_W-1:0] RO_REG_ADDR  = 8'h01;
  parameter logic [ADDR_W-1:0] R0C_REG_ADDR = 8'h02;

  // --- led_rgf register types --- 
  typedef struct packed {
    led_sel_t led_sel_q; 
    logic led16_on_q;
    logic led17_on_q;
    logic led16_cie_on_q;
    logic led17_cie_on_q;
  } led_ctrl_reg_t;

  typedef struct packed {
    logic [1:0] pattern;
  } led_pattern_reg_t;

  typedef enum {LED_CTRL      = 32'h0000,
                LED_PATTERN   = 32'h0004,
                PWM_CFG       = 32'h0008,
                RED_LUT       = 32'h000C,
                GREEN_LUT     = 32'h0010,
                BLUE_LUT      = 32'h0014,
                RX_PKT_CNT    = 32'h0018,
                TX_PKT_CNT    = 32'h001C,
                COLOR_MSG_CNT = 32'h0020,
                CFG_MSG_CNT   = 32'h0024,
                SYS_CTRL      = 32'h0028,
                SYS_STATUS    = 32'h002C,
                SYS_VERSION   = 32'h0030
  } regs_addr_t;
endpackage

