`timescale 1ns / 1ps

module seg7_ctrl#(
    parameter int REFRESH_DIV = 25_000          //100MHz/25,000 = 4000Hz, 4000Hz/8 = 500Hz
)(
    input  logic clk,
    input  logic rst_n,
    input  logic [7:0] dash,                    //1 = show "-"
    input  logic [31:0] digits,
    input  logic [7:0] dps,

    output logic [7:0] an,
    output logic [6:0] seg,
    output logic dp
);

    localparam int RW = $clog2(REFRESH_DIV);    //RW = Refresh Width

    //refresh
    logic [RW-1:0] div_cnt;
    logic tick;

    assign tick = (div_cnt == RW'(REFRESH_DIV - 1));

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n || tick) 
            div_cnt <= '0;
        else
            div_cnt <= div_cnt + 1'b1;
    end

    //current digit
    logic [2:0] idx;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            idx <= 3'd0;
        else if (tick)
            idx <= idx + 1'b1;
    end

    logic [3:0] hex;
    logic [6:0] hex2seg;
    assign hex = digits[idx * 4 +: 4];

    //hex to segments
    always_comb begin //4bit value -> 7 segment display
        case (hex)
            4'h0: hex2seg = 7'b1000000;     //0
            4'h1: hex2seg = 7'b1111001;     //1
            4'h2: hex2seg = 7'b0100100;     //2
            4'h3: hex2seg = 7'b0110000;     //3
            4'h4: hex2seg = 7'b0011001;     //4
            4'h5: hex2seg = 7'b0010010;     //5
            4'h6: hex2seg = 7'b0000010;     //6
            4'h7: hex2seg = 7'b1111000;     //7
            4'h8: hex2seg = 7'b0000000;     //8 
            4'h9: hex2seg = 7'b0010000;     //9
            4'hA: hex2seg = 7'b0001000;     //A 
            4'hB: hex2seg = 7'b0000011;     //b
            4'hC: hex2seg = 7'b1000110;     //C
            4'hD: hex2seg = 7'b0100001;     //d                     
            4'hE: hex2seg = 7'b0000110;     //E
            default: hex2seg = 7'b0001110;  //F
        endcase
        if (dash[idx]) hex2seg = 7'b0111111;    
    end

    //registerd outputs
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin                      //reset - all off
            an <= 8'hFF;
            seg <= 7'h7F;
            dp <= 1'b1;
        end

        else begin
            an <= ~(8'b0000_0001 << idx);    
            seg <= hex2seg;
            dp <= ~dps[idx];
        end
    end

endmodule
