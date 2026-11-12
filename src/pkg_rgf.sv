`timescale 1ns/1ps

package pkg_rgf;

  parameter int ADDR_W = 32;
  parameter int LED_DATA_W = 4;
  parameter int PATTERN_W = 2;

  parameter logic [ADDR_W-1:0] RW_REG_ADDR  = 8'h00;
  parameter logic [ADDR_W-1:0] RO_REG_ADDR  = 8'h01;
  parameter logic [ADDR_W-1:0] R0C_REG_ADDR = 8'h02;

  // --- led_rgf register types--- 
  typedef struct packed {
    logic [1:0] led_sel; 
    logic led16_on;
    logic led17_on;
    logic led16_cie_on;
    logic led17_cie_on;
  } led_ctrl_reg_t;

  typedef struct packed {
    logic [3:0] pattern;
    logic [3:0] frm_cnt;
  } led_pattern_reg_t;
  
  // --- cnt_rgf register types
  typedef struct packed {
    logic invalid_addr_err;
    logic timeout_err;
    logic busy;
  } r0c_reg_t;

  typedef enum { RX_PKT_CNT    = 32'h0000,
                 TX_PKT_CNT    = 32'h0004,
                 COLOR_MSG_CNT = 32'h0008,
                 CFG_MSG_CNT   = 32'h000C} cnt_regs_t;

  typedef enum {LED_CTRL    = 32'h0000,
                LED_PATTERN = 32'h0004} led_regs_t;
                 
  // parameter int RW_REG_th_START     = 0;
  // parameter int RW_REG_th_STOP      = 7;
  // parameter int RW_REG_enable_START = 8;
  // parameter int RW_REG_enable_STOP  = 8;
  // parameter int RW_REG_mode_START   = 9;
  // parameter int RW_REG_mode_STOP    = 10;

  parameter rw_reg_t RW_REG_RST = '{mode: 2'd0, enable: 1'b0, th: 8'h80};

endpackage

