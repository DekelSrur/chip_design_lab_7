`timescale 1ns/1ps

package pkg_sys;

//system-uart
    parameter int CLK_FREQ_HZ = 100_000_000;
    parameter int BAUD_RATE = 57_600;
    parameter int CLKS_PER_BIT = CLK_FREQ_HZ/BAUD_RATE; //1736
 
 //data
    parameter int BYTE = 8;                             //one sRGB channel / UART byte
    parameter int N_CH = 3;                             //{R, G, B}

//color-pwm path
    parameter int N_LED = 2;                            //index 0 = LED16, index 1 = LED17
    parameter int PWM_SLOTS_DEF = 1024;                 //PWM resolution after reset (PWM_CFG.time_slots)
    parameter int PWM_SLOTS_MAX = 8192;                 //largest legal PWM_CFG.time_slots
    parameter int DUTY_W = $clog2(PWM_SLOTS_MAX);       //duty / PWM counter width: 13 bits
    parameter int GAMMA_W = 10;                         //black_magic_box entry width
    parameter int CIE_SCALE_DEF = 128;                  //brightness, out of 256

//display selectiom
    typedef enum logic [1:0] {T0, T1, T2, T3} digits_t; //T0=B, T1=G, T2=R, T3=LED
    typedef enum logic [7:0] {LEDS13_12 = 8'b11000000, 
                              LEDS10_9  = 8'b00110000, 
                              LEDS8_7   = 8'b00001100, 
                              LEDS5_4   = 8'b00000011} leds_t;

endpackage

