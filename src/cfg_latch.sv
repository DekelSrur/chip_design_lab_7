`timescale 1ns/1ps

module cfg_latch
    import pkg_sys::*;
#(
    parameter int HOLD_CYCLES = CLK_FREQ_HZ  //btn hold time before latching: 1 s (small value in the TB)
)(
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

    localparam int CW = $clog2(HOLD_CYCLES + 1);

    logic [CW-1:0] hold_cnt;        //how long the button is held
    logic fired;                    //already latched during this press
    logic press;                    //one cycle pulse: button held for 1 s

    assign press = btn_db && !fired && (hold_cnt == CW'(HOLD_CYCLES - 1));

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            hold_cnt <= '0;
            fired <= 1'b0;
            start <= 1'b0;
            byte_val <= '0;
            speed_sel <= '0;
            count_sel <= '0;
        end

        else begin
            start <= 1'b0;          //defualt mode

            //hold timer: counts while the button is held, re-arms on release
            if (!btn_db) begin
                hold_cnt <= '0;
                fired <= 1'b0;
            end
            else if (press) fired <= 1'b1;
            else if (!fired) hold_cnt <= hold_cnt + 1'b1;

            if (press && !busy && !rx_mode) begin //held for 1 s while tx is idle and tx mode is selected
                start <= 1'b1;
                byte_val <= sw_db[7:0];
                speed_sel <= sw_db[9:8];
                count_sel <= sw_db[14:13];
            end
        end 
    end            

endmodule