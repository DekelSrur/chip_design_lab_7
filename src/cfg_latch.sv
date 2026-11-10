`timescale 1ns/1ps

module cfg_latch (
    input logic clk,
    input logic rst_n,
    input logic btn_db,
    input logic busy,
    input logic rx_mode,            // 1 = rx_mode, then tx is disabled 
    input logic [14:0] sw_db,       //sync + debouncer switchers

    output logic start,
    output logic [7:0] byte_val,
    output logic [1:0] speed_sel,
    output logic [1:0] count_sel
);

    logic btn_d;                    //button value from previous clk
    logic press;                    //one cycle pulse on a new press

    assign press = btn_db & ~btn_d; //rising edge detector

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            btn_d <= 1'b0;
            start <= 1'b0;
            byte_val <= '0;
            speed_sel <= '0;
            count_sel <= '0;
        end

        else begin
            btn_d <= btn_db;
            start <= 1'b0;          //defualt mode

            if (press && !busy && !rx_mode) begin //new press while tx is idle and tx mode is selected
                start <= 1'b1;
                byte_val <= sw_db[7:0];
                speed_sel <= sw_db[9:8];
                count_sel <= sw_db[14:13];
            end
        end 
    end            

endmodule