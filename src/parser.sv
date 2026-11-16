`timescale 1ns/1ps

module parser
    import pkg_sys::*;
    import pkg_rgf::*;
(
    input logic clk, rst_n, 
    input logic rx_ready,                                         // from sync module
    input logic [BYTE-1:0] rx_byte,                               // from sync module

    output logic [BYTE-1:0] row_index, col_index, pixel_value,    // RGB parameters to param_ctrl
    output logic led, RGB_wr_en, led_wr_en,                       // to param_ctrl
    output logic [ADDR_W-1:0] master_addr,                        // register address {A2, A1, A0}
    output logic [DATA_W-1:0] master_wdata,                       // write data {DH1, DH0, DL1, DL0}
    output logic master_wen,                                      // write command to addr_xbar
    output logic master_ren,                                      // read command to addr_xbar
    output logic rx_pkt,                                          // any valid packet, to cnt_rgf 
    output logic color_msg,                                       // valid colour message, to cnt_rgf
    output logic cfg_msg                                          // valid write/read command, to cnt_rgf
); 

    typedef enum logic[5:0] {IDLE, MSG_START,
                             RED, R1, R2, R3, R_COMMA,
                             GREEN, G1, G2, G3, G_COMMA, 
                             BLUE, B1, B2, B3, RGB_MSG_END,
                             LED, L1, L2, L3, LED_MSG_END,
                             RD_MSG_END, 
                             WR, WA2, WA1, WA0,
                             W_COMMA1, WVH, WZH, WDH1, WDH0,
                             W_COMMA2, WVL, WZL, WDL1, WDL0, WR_MSG_END} msg_state_t;
    msg_state_t current_state, next_state;
    logic [2:0][9:0] current_RGB, next_RGB;
    logic [ADDR_W-1:0] current_addr, next_addr; //address bytes of a W/R command
    logic [DATA_W-1:0] current_data, next_data; //data bytes of a W command
    logic is_digit, next_led, current_led;
    logic in_range;                             //all three colour values <= 255
    logic addr_is_digits;                       //the 3 bytes after 'R' were ASCII digits
    logic bin_field;                            //the next byte is binary (address/data)


    assign is_digit = rx_byte >= "0" && rx_byte <= "9";
    assign in_range = (current_RGB[2] <= 10'd255) && (current_RGB[1] <= 10'd255) && (current_RGB[0] <= 10'd255);

    //after 'R' the same 3 bytes are kept both as a raw address and as a decimal value;
    //byte 5 decides: "}" = read command, "," = colour message (only if they were digits)
    assign addr_is_digits = (current_addr[23:16] >= "0" && current_addr[23:16] <= "9") &&
                            (current_addr[15:8]  >= "0" && current_addr[15:8]  <= "9") &&
                            (current_addr[7:0]   >= "0" && current_addr[7:0]   <= "9");

    //in these states the next byte is binary, so a "{" value must not restart the message
    assign bin_field = (current_state == RED)  || (current_state == R1)   || (current_state == R2)  ||
                       (current_state == WR)   || (current_state == WA2)  || (current_state == WA1) ||
                       (current_state == WZH)  || (current_state == WDH1) ||
                       (current_state == WZL)  || (current_state == WDL1);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_state <= IDLE;
            current_RGB <= '0;
            current_led <= '0;
            current_addr  <= '0;
            current_data  <= '0;
        end
        else if (rx_ready) begin 
            current_state <= next_state;
            current_RGB <= next_RGB;
            current_led   <= next_led;
            current_addr  <= next_addr;
            current_data  <= next_data;
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
            master_addr  <= '0;
            master_wdata <= '0;
            master_wen   <= '0;
            master_ren   <= '0;
            rx_pkt       <= '0;
            color_msg    <= '0;
            cfg_msg      <= '0;
        end
        else begin
            RGB_wr_en <= '0;                                       
            led_wr_en <= '0;
            master_wen <= '0;
            master_ren <= '0;
            rx_pkt     <= '0;
            color_msg  <= '0;
            cfg_msg    <= '0;


            if (rx_ready) begin
                unique case (next_state)
                    RGB_MSG_END : begin
                        {row_index, col_index, pixel_value} <= {current_RGB[2][7:0], current_RGB[1][7:0], current_RGB[0][7:0]};
                        RGB_wr_en <= '1;
                        rx_pkt    <= '1;
                        color_msg <= '1;
                    end
                    LED_MSG_END : begin
                        led       <= next_led;
                        led_wr_en <= '1;
                        rx_pkt    <= '1;
                    end
                    WR_MSG_END : begin
                        master_addr  <= current_addr;
                        master_wdata <= current_data;
                        master_wen   <= '1;
                        rx_pkt       <= '1;
                        cfg_msg      <= '1;
                    end
                    RD_MSG_END : begin
                        master_addr <= current_addr;
                        master_ren  <= '1;
                        rx_pkt      <= '1;
                        cfg_msg     <= '1;
                    end
                    default : ;
                endcase
            end
        end
    end


    always_comb begin
        next_state = IDLE;
        next_RGB   = current_RGB;
        next_led   = current_led;
        next_addr  = current_addr;
        next_data  = current_data;

        if (rx_byte == "{" && !bin_field) next_state = MSG_START;
        else case (current_state)
            IDLE        :  if(rx_byte == "{")            next_state = MSG_START;
            MSG_START   : begin 
                            if (rx_byte == "R")      next_state = RED;
                            else if (rx_byte == "L")   next_state = LED;
                            else if (rx_byte == "W") next_state = WR;
                        end
            RED         : begin
                              next_state       = R1;
                              next_addr[23:16] = rx_byte;
                              if (is_digit) next_RGB[2] = 10'(rx_byte[3:0] * 100);
                          end
            R1          : begin
                              next_state      = R2;
                              next_addr[15:8] = rx_byte;
                              if (is_digit) next_RGB[2] = current_RGB[2] + 10'(rx_byte[3:0] * 10);
                          end
            R2          : begin
                              next_state     = R3;
                              next_addr[7:0] = rx_byte;
                              if (is_digit) next_RGB[2] = current_RGB[2] + 10'(rx_byte[3:0]);
                          end
            R3          : begin
                              if      (rx_byte == "}")                   next_state = RD_MSG_END;
                              else if (rx_byte == "," && addr_is_digits) next_state = R_COMMA;
                          end
            //colour message
            R_COMMA     : if (rx_byte == "G") next_state = GREEN;
            GREEN       : if (is_digit) begin
                              next_state  = G1;
                              next_RGB[1] = 10'(rx_byte[3:0] * 100);
                          end
            G1          : if (is_digit) begin
                              next_state  = G2;
                              next_RGB[1] = current_RGB[1] + 10'(rx_byte[3:0] * 10);
                          end
            G2          : if (is_digit) begin
                              next_state  = G3;
                              next_RGB[1] = current_RGB[1] + 10'(rx_byte[3:0]);
                          end
            G3          : if (rx_byte == ",") next_state = G_COMMA;
            G_COMMA     : if (rx_byte == "B") next_state = BLUE;
            BLUE        : if (is_digit) begin
                              next_state  = B1;
                              next_RGB[0] = 10'(rx_byte[3:0] * 100);
                          end
            B1          : if (is_digit) begin
                              next_state  = B2;
                              next_RGB[0] = current_RGB[0] + 10'(rx_byte[3:0] * 10);
                          end
            B2          : if (is_digit) begin
                              next_state  = B3;
                              next_RGB[0] = current_RGB[0] + 10'(rx_byte[3:0]);
                          end
            B3          : if (rx_byte == "}" && in_range) next_state = RGB_MSG_END;
            //led select message
            LED         : if (rx_byte == "0") next_state = L1;
            L1          : if (rx_byte == "1") next_state = L2;
            L2          : if (rx_byte == "6") begin
                              next_state = L3;
                              next_led   = '1;
                          end
                          else if (rx_byte == "7") begin
                              next_state = L3;
                              next_led   = '0;
                          end
            L3          : if (rx_byte == "}") next_state = LED_MSG_END;

            //write command: {W A2 A1 A0 , V 00 DH1 DH0 , V 00 DL1 DL0}
            WR          : begin next_state = WA2;  next_addr[23:16] = rx_byte; end
            WA2         : begin next_state = WA1;  next_addr[15:8]  = rx_byte; end
            WA1         : begin next_state = WA0;  next_addr[7:0]   = rx_byte; end
            WA0         : if (rx_byte == ",")   next_state = W_COMMA1;
            W_COMMA1    : if (rx_byte == "V")   next_state = WVH;
            WVH         : if (rx_byte == 8'h00) next_state = WZH;
            WZH         : begin next_state = WDH1; next_data[31:24] = rx_byte; end
            WDH1        : begin next_state = WDH0; next_data[23:16] = rx_byte; end
            WDH0        : if (rx_byte == ",")   next_state = W_COMMA2;
            W_COMMA2    : if (rx_byte == "V")   next_state = WVL;
            WVL         : if (rx_byte == 8'h00) next_state = WZL;
            WZL         : begin next_state = WDL1; next_data[15:8]  = rx_byte; end
            WDL1        : begin next_state = WDL0; next_data[7:0]   = rx_byte; end
            WDL0        : if (rx_byte == "}")   next_state = WR_MSG_END;

            default     : ;
        endcase
    end

endmodule