`timescale 1ns/1ps

module uart_tx #(
    parameter CLKS_PER_BIT = 1736           // 100 MHz / 57,600 bps = 1736
)(
    input logic clk,
    input logic rst_n,
    input logic tx_start,
    input logic [7:0] tx_data,

    output logic tx,
    output logic tx_busy,
    output logic tx_done
);

   localparam BCW = $clog2(CLKS_PER_BIT);   // baud counter width: 1736 is 11 bits

    logic [BCW-1:0] baud_cnt;               // clocks inside the current bit
    logic [3:0]     bit_idx;                // which of the 10 frame bits is on the line
    logic [9:0]     shift_reg;              // frame = {stop, data[7:0], start}

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin                      //default
            tx_done <= 1'b0;                    
            tx <= 1'b1;
            tx_busy <= 1'b0;
            baud_cnt <= '0;
            bit_idx <= '0;
            shift_reg <= '1;
        end

        else if (!tx_busy) begin            //idle 
            tx_done <= 1'b0;
            if (tx_start) begin
                shift_reg <= {1'b1, tx_data, 1'b0};
                tx <= 1'b0;
                tx_busy <= 1'b1;
                baud_cnt <= '0;
                bit_idx <= '0;
            end
        end

        else begin                                 //busy
            tx_done <= 1'b0;                        
            if (baud_cnt == CLKS_PER_BIT-1) begin  //currnet bit time is over
                baud_cnt<= '0;

                if (bit_idx == 4'd9) begin         //stop bit finished
                    tx_busy <= 1'b0;
                    tx_done <= 1'b1;
                    tx <= 1'b1;
                end

                else begin                          //move to next bit
                    shift_reg <= {1'b1, shift_reg[9:1]};
                    tx <= shift_reg[1];
                    bit_idx <= bit_idx + 1'b1;
                end
            end

            else begin                      //still inside the currnt bit
                baud_cnt <= baud_cnt + 1'b1;
            end
        end
    end

endmodule







