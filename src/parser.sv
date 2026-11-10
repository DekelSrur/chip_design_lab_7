`timescale 1ns/1ps

module parser import pkg_lab6::*;(
    input logic clk, rst_n, rx_ready,
    input logic [BYTE-1:0] rx_byte,
    output logic [BYTE-1:0] row_index, col_index, pixel_value,
    output logic led, RGB_wr_en, led_wr_en
); 

    typedef enum logic[4:0] {IDLE, MSG_START, RED, R1, R2, R3, R_COMMA,
                                              GREEN, G1, G2, G3, G_COMMA, 
                                              BLUE, B1, B2, B3, RGB_MSG_END, LED, L1, L2, L3, LED_MSG_END} msg_state_t;
    msg_state_t current_state, next_state;
    logic [2:0][BYTE-1:0] current_RGB, next_RGB;
    logic is_digit, next_led, current_led;

    assign is_digit = rx_byte >= "0" && rx_byte <= "9";

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_state <= IDLE;
            current_RGB <= '0;
            current_led <= '0;
        end
        else if (rx_ready) begin 
            current_state <= next_state;
            current_RGB <= next_RGB;
            current_led <= next_led;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            row_index <= '0;
            col_index <= '0;
            pixel_value <= '0;
            RGB_wr_en <= '0;
            led_wr_en <= '0;
            led <=0;
        end
        else begin
            RGB_wr_en <= '0;                                       
            led_wr_en <= '0;

            if (rx_ready && next_state == RGB_MSG_END) begin       
                {row_index, col_index, pixel_value} <= next_RGB;
                RGB_wr_en <= '1;
            end
            else if (rx_ready && next_state == LED_MSG_END) begin  
                led <= next_led;
                led_wr_en <= '1;
            end
        end
    end

    always_comb begin
        next_state = IDLE;
        next_RGB   = current_RGB;
        next_led   = current_led;

        if (rx_byte == "{") next_state = MSG_START;
        else case (current_state)
            IDLE        :  if(rx_byte == "{")            next_state = MSG_START;
            MSG_START   : begin if (rx_byte == "R")      next_state = RED;
                              else if (rx_byte == "L")   next_state = LED;
                          end
            RED         : begin if(is_digit) begin                  
                                                         next_state = R1;
                                                         next_RGB [2] = BYTE'(rx_byte[3:0] * 100);
                                     end
                                    end
            R1          : if(is_digit) begin                  
                                                         next_state = R2;
                                                         next_RGB [2] = current_RGB [2] + BYTE'(rx_byte[3:0] * 10);
                                     end
            R2          : if(is_digit) begin                  
                                                         next_state = R3;
                                                         next_RGB [2] = current_RGB [2] + BYTE'(rx_byte[3:0]);
                                     end
            R3      : if (rx_byte == ",")                next_state = R_COMMA;
            R_COMMA : if (rx_byte == "G")                next_state = GREEN;
            GREEN       : if(is_digit) begin                  
                                                         next_state = G1;
                                                         next_RGB [1] = BYTE'(rx_byte[3:0] * 100);
                                     end
            G1          : if(is_digit) begin                  
                                                         next_state = G2;
                                                         next_RGB [1] = current_RGB [1] + BYTE'(rx_byte[3:0] * 10);
                                     end
            G2          : if(is_digit) begin                  
                                                         next_state = G3;
                                                         next_RGB [1] = current_RGB [1] + BYTE'(rx_byte[3:0]);
                                     end
            G3      : if (rx_byte == ",")                next_state = G_COMMA;
            G_COMMA : if (rx_byte == "B")                next_state = BLUE;
            BLUE        : if(is_digit) begin                  
                                                         next_state = B1;
                                                         next_RGB [0] = BYTE'(rx_byte[3:0] * 100);
                                     end
            B1          : if(is_digit) begin                  
                                                         next_state = B2;
                                                         next_RGB [0] = current_RGB [0] + BYTE'(rx_byte[3:0] * 10);
                                     end
            B2          : if(is_digit) begin                  
                                                         next_state = B3;
                                                         next_RGB [0] = current_RGB [0] + BYTE'(rx_byte[3:0]);
                                     end
            B3          : if(rx_byte == "}")             next_state = RGB_MSG_END;
            RGB_MSG_END : if(rx_byte == "{")             next_state = MSG_START;
            LED         : if(rx_byte == "0")             next_state = L1;
            L1          : if(rx_byte == "1")             next_state = L2;
            L2          : if(rx_byte == "6") begin                  
                                                         next_state = L3;
                                                         next_led = '1;
                          end
                          else if (rx_byte == "7") begin
                                                         next_state = L3;
                                                         next_led = '0;
                          end
            L3          : if(rx_byte == "}")             next_state = LED_MSG_END;
            LED_MSG_END : if(rx_byte == "{")             next_state = MSG_START;
            default: ;
        endcase
    end

endmodule
