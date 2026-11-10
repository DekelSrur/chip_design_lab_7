`timescale 1ns / 1ps

module tb_parser;

    localparam int BYTE = 8;

    logic clk, rst_n, msg_valid;
    logic [127:0] rx_message;
    logic [BYTE-1:0] row_index, col_index, pixel_value;
    logic correct_format;

    parser dut(
        .clk(clk), .rst_n(rst_n), .msg_valid(msg_valid),
        .rx_message(rx_message),
        .row_index(row_index), .col_index(col_index), .pixel_value(pixel_value),
        .correct_format(correct_format)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

     initial begin
        rst_n = 0; rx_message = 0;     #20;
        rst_n = 1;                     #20;
        rx_message = "{R012,C034,V255}"; #10;   // valid
        rx_message = "{R000,C000,V000}"; #10;   // valid, all zeros
        rx_message = "{R255,C255,V255}"; #10;   // valid, max values
        rx_message = "[R012,C034,V255}"; #10;   // invalid, wrong opening char
        rx_message = "{R012;C034,V255}"; #10;   // invalid, ";" instead of ","
        rx_message = "{R:12,C034,V255}"; #10;   // invalid, ':' is not a digit
        rx_message = "{R001,C002,V003}"; #10;   // valid
        rx_message = "{R012,C03X,V255}"; #10;   // invalid, "X" is not a digit and 
        rx_message = "{R012,C038VV255}"; #10;   // invalid, "V" istead of ","
        rx_message = "{R012,C03X,V2558"; #10;   // invalid, "8" instead of closing char 
        rx_message = "{R256,C999,V300}"; #10;   // valid and values > 255, should cause wrap-around and output R00, CE7, V2C
        $finish;
    end
 
    initial begin
        $monitor("t=%0d ns  msg=%s  valid=%b  row=%h col=%h pix=%h",
                 $time, rx_message, correct_format, row_index, col_index, pixel_value);
    end
endmodule
