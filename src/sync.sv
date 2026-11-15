`timescale 1ns/1ps

module sync(
    input logic clk,
    input logic cpu_resetn,
    input logic [4:0] btn,
    input logic uart_rxd,
    input logic sw_rst,

    output logic hw_rst_n,
    output logic rst_n,
    output logic [4:0] btn_s,
    output logic rxd_s 
);

//reset syncroniser
    logic [1:0] rst_ff = 2'b00;

    always_ff @(posedge clk or negedge cpu_resetn) begin
        if (!cpu_resetn)
            rst_ff <= 2'b00;            
        else
            rst_ff <= {rst_ff[0], 1'b1};
    end        

    assign hw_rst_n = rst_ff[1];

//system reset: same as the hardware reset, plus a synchronous restart on sw_rst
    logic [1:0] sys_rst_ff;

    always_ff @(posedge clk or negedge cpu_resetn) begin
        if (!cpu_resetn)
            sys_rst_ff <= 2'b00;
        else if (sw_rst)
            sys_rst_ff <= 2'b00;            //registered, so rst_n is glitch-free
        else
            sys_rst_ff <= {sys_rst_ff[0], 1'b1};
    end

    assign rst_n = sys_rst_ff[1];

//button and switchers
    logic [4:0] btn_ff1 = '0;
    logic [4:0] btn_ff2 = '0;

//uart rx line
    logic [1:0] rxd_ff = 2'b11;

    always_ff @(posedge clk or negedge cpu_resetn) begin
        if(!cpu_resetn) begin
            btn_ff1 <= '0;
            btn_ff2 <= '0;
            rxd_ff  <= 2'b11;
        end
        else begin
            btn_ff1 <= btn;
            btn_ff2 <= btn_ff1;
            rxd_ff <= {rxd_ff[0], uart_rxd};
        end
    end

    assign btn_s = btn_ff2;
    assign rxd_s  = rxd_ff[1];

endmodule
