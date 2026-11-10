`timescale 1ns/1ps

module display_mux (
    input logic rx_mode,                //0 = tx_mode, 1 = rx_mode
    // TX mode values
    input  logic [7:0]  byte_val,       // T0
    input  logic [1:0]  speed_sel,      // T1
    input  logic [1:0]  count_sel,      // T2
    input  logic [8:0]  rows_sent,      // T3 

    // RX mode values
    input  logic [23:0] edit_rgb,       // {R, G, B}: T2 = R, T1 = G, T0 = B
    input  logic edit_led,              // T3: 1 = "16", 0 = "17"

    output logic [31:0] digits,         
    output logic [7:0] dps,           //decimal point per digit
    output logic [7:0] dash
    
);

    logic [8:0] count_val;
    logic [3:0] t1_int, t1_frac;

    always_comb begin
        unique case (count_sel)
            2'd0:    count_val = 9'd1;
            2'd1:    count_val = 9'd32;
            2'd2:    count_val = 9'd128;
            default: count_val = 9'd256;
        endcase

        unique case (speed_sel)
            2'd0:    begin t1_int = 4'd0; t1_frac = 4'd0; end   //0.0
            2'd1:    begin t1_int = 4'd0; t1_frac = 4'd5; end   //0.5
            2'd2:    begin t1_int = 4'd1; t1_frac = 4'd0; end   //1.0
            default: begin t1_int = 4'd2; t1_frac = 4'd0; end   //2.0
        endcase

        if (!rx_mode) begin                                     //tx layout
            digits = { (rows_sent[8] ? 8'hFF : rows_sent[7:0]), //t3
                       (count_val[8] ? 8'hFF : count_val[7:0]), //t2
                       t1_int, t1_frac,                         //t1
                       byte_val };                              //t0
            dps  = 8'b0000_1000;                                //decimal point t1
            dash = 8'b0000_0000;
        end
        else begin                                              //rx layout
            digits = {(edit_led ? 8'h16 : 8'h17),              //t3: LED16 / LED17
                       edit_rgb };                              //t2 = R, t1 = G, t0 = B (hex)
            dps  = 8'b0000_0000;
            dash = 8'b0000_0000;
        end
    end

endmodule


