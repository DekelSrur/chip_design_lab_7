`timescale 1ns/1ps

package pkg_rgf;

//general parameters
  parameter int ADDR_W = 24;
  parameter int DATA_W = 32;

//addr_xbar parameters
  parameter int N_RGF = 4;
  typedef enum int {
      LED_IDX = 0,
      PWM_IDX = 1,
      CNT_IDX = 2,
      SYS_IDX = 3
      } rgf_idx_t;

//led_ctrl parameters
  parameter int LED_DATA_W = 6;
  parameter int PATTERN_DATA_W = 2;

//LED_CTRL.led_sel: bit 0 = LED16, bit 1 = LED17
  typedef enum logic [1:0] {
      LED_NONE = 2'b00,
      LED16 = 2'b01,
      LED17 = 2'b10,
      LED_BOTH = 2'b11
      } led_sel_t;

//led_rgf register types
  typedef struct packed {
    logic led17_cie_on_q;   // [5]
    logic led16_cie_on_q;   // [4]
    logic led17_on_q;       // [3]
    logic led16_on_q;       // [2]
    led_sel_t led_sel_q;    // [1:0]
  } led_ctrl_reg_t;

  typedef struct packed {
    logic [1:0] pattern;
  } led_pattern_reg_t;

//led_rgf reset values 
  parameter led_ctrl_reg_t LED_CTRL_RST = '{led17_cie_on_q: 1'b1, led16_cie_on_q: 1'b1,
                                            led17_on_q: 1'b1, led16_on_q: 1'b0, led_sel_q: LED17};
  parameter led_pattern_reg_t LED_PATTERN_RST = '{pattern: 2'h0};

//pwm_rgf register types
typedef struct packed{
  logic [15:0] sweep_time;
  logic [15:0] time_slots;
} pwm_cfg_reg_t;


typedef struct packed{
  logic [8:0]  init_phase;   // [23:15]
  logic [1:0]  magnitude;    // [14:13]
  logic [12:0] out_freq;     // [12:0]
} lut_reg_t;

//pwm_rgf parameter
  parameter pwm_cfg_reg_t PWM_CFG_RST = '{sweep_time: 16'h0000, time_slots: 16'h0400};
  parameter lut_reg_t LUT_RST = '{init_phase: 9'h000, magnitude: 2'h0, out_freq: 13'h03E8};
  parameter int LUT_DATA_W = 24;

  //sys_rgf register types
  parameter int SYS_CTRL_DATA_W   = 2;
  parameter int SYS_STATUS_DATA_W = 2;

  typedef struct packed {
    logic enable_q;             // [1] DDS + PWM enable
    logic sw_rst_q;             // [0] SW reset, self-clearing (reads 0)
  } sys_ctrl_reg_t;

  typedef struct packed {
    logic ro_wr_err_q;          // [1] write to a read-only register (sticky)
    logic invalid_addr_err_q;   // [0] access to an unmapped address (sticky)
  } sys_status_reg_t;

//sys_rgf reset values
  parameter sys_ctrl_reg_t     SYS_CTRL_RST    = '{enable_q: 1'b1, sw_rst_q: 1'b0};
  parameter sys_status_reg_t   SYS_STATUS_RST  = '{ro_wr_err_q: 1'b0, invalid_addr_err_q: 1'b0};
  parameter logic [DATA_W-1:0] SYS_VERSION_VAL = 32'h0007_0001;    // lab 7, revision 1
  
  typedef enum logic [ADDR_W-1:0] {
                LED_CTRL      = 24'h0000,
                LED_PATTERN   = 24'h0004,
                PWM_CFG       = 24'h0008,
                RED_LUT       = 24'h000C,
                GREEN_LUT     = 24'h0010,
                BLUE_LUT      = 24'h0014,
                RX_PKT_CNT    = 24'h0018,
                TX_PKT_CNT    = 24'h001C,
                COLOR_MSG_CNT = 24'h0020,
                CFG_MSG_CNT   = 24'h0024,
                SYS_CTRL      = 24'h0028,
                SYS_STATUS    = 24'h002C,
                SYS_VERSION   = 24'h0030
  } regs_addr_t;

endpackage

