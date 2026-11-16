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
                             W_COMMA1, WVH, WDH,
                             W_COMMA2, WVL, WDL, WR_MSG_END} msg_state_t;
    msg_state_t current_state, next_state;
    logic [2:0][9:0] current_RGB, next_RGB;
    logic [ADDR_W-1:0] current_addr, next_addr; //address bytes of a W/R command
    logic [DATA_W-1:0] current_data, next_data; //data bytes of a W command
    logic is_digit, next_led, current_led;
    logic in_range;                             //all three colour values <= 255
    logic addr_is_digits;                       //the 3 characters after 'R' were decimal digits (0-9)
    logic is_hex;                               //rx_byte is an ASCII hex digit: 0-9, A-F (a-f also accepted)
    logic [3:0] hex_val;                        //value of that hex digit
    logic [2:0] hex_cnt, next_hex_cnt;          //hex digits received in the current V field (0..6)


    assign is_digit = rx_byte >= "0" && rx_byte <= "9";
    assign is_hex   = is_digit || (rx_byte >= "A" && rx_byte <= "F") || (rx_byte >= "a" && rx_byte <= "f");
    assign hex_val  = is_digit ? rx_byte[3:0] : 4'(rx_byte[3:0] + 4'd9);   //"A"/"a" = 0x41/0x61 -> 1 + 9 = 10
    assign in_range = (current_RGB[2] <= 10'd255) && (current_RGB[1] <= 10'd255) && (current_RGB[0] <= 10'd255);

    //after 'R' the 3 characters are kept both as a hex address (one digit each) and as a decimal value;
    //byte 5 decides: "}" = read command, "," = colour message (only if they were 0-9).
    //hex digits A-F give nibbles 10-15, so "all nibbles <= 9" means all three were decimal digits
    assign addr_is_digits = (current_addr[11:8] <= 4'd9) && (current_addr[7:4] <= 4'd9) && (current_addr[3:0] <= 4'd9);


    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_state <= IDLE;
            current_RGB <= '0;
            current_led <= '0;
            current_addr  <= '0;
            current_data  <= '0;
            hex_cnt       <= '0;
        end
        else if (rx_ready) begin 
            current_state <= next_state;
            hex_cnt       <= next_hex_cnt;
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
        next_hex_cnt = '0;

        //every field is ASCII now, so a "{" always starts a new message
        if (rx_byte == "{") next_state = MSG_START;
        else case (current_state)
            IDLE        :  if(rx_byte == "{")            next_state = MSG_START;
            MSG_START   : begin 
                            next_addr = '0;                                //address: 3 hex digits -> 0x000..0xFFF
                            if (rx_byte == "R")      next_state = RED;
                            else if (rx_byte == "L")   next_state = LED;
                            else if (rx_byte == "W") next_state = WR;
                        end
            //read address (hex) or red value (decimal): accepted only if the character is a hex digit
            RED         : if (is_hex) begin
                              next_state = R1;
                              next_addr  = {current_addr[ADDR_W-5:0], hex_val};
                              if (is_digit) next_RGB[2] = 10'(rx_byte[3:0] * 100);
                          end
            R1          : if (is_hex) begin
                              next_state = R2;
                              next_addr  = {current_addr[ADDR_W-5:0], hex_val};
                              if (is_digit) next_RGB[2] = current_RGB[2] + 10'(rx_byte[3:0] * 10);
                          end
            R2          : if (is_hex) begin
                              next_state = R3;
                              next_addr  = {current_addr[ADDR_W-5:0], hex_val};
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

            //write command: {Wxxx,Vhhhhhh,Vhhhhhh}, x and h = ASCII hex digits (0-9, A-F)
            //xxx = address 0x000..0xFFF, accepted only if each character is a hex digit
            WR          : if (is_hex) begin next_state = WA2; next_addr = {current_addr[ADDR_W-5:0], hex_val}; end
            WA2         : if (is_hex) begin next_state = WA1; next_addr = {current_addr[ADDR_W-5:0], hex_val}; end
            WA1         : if (is_hex) begin next_state = WA0; next_addr = {current_addr[ADDR_W-5:0], hex_val}; end
            WA0         : if (rx_byte == ",") next_state = W_COMMA1;
            W_COMMA1    : if (rx_byte == "V") next_state = WVH;           //hex_cnt starts at 0
            //each V field = 6 hex digits: the first 2 are "don't care" (must be hex, not stored),
            //the last 4 are shifted into next_data: first field -> bits 31:16, second -> bits 15:0
            WVH         : if (is_hex) begin
                              if (hex_cnt >= 3'd2) next_data = {current_data[DATA_W-5:0], hex_val};
                              next_hex_cnt = hex_cnt + 1'b1;
                              next_state   = (hex_cnt == 3'd5) ? WDH : WVH;
                          end
            WDH         : if (rx_byte == ",") next_state = W_COMMA2;
            W_COMMA2    : if (rx_byte == "V") next_state = WVL;           //hex_cnt starts at 0
            WVL         : if (is_hex) begin
                              if (hex_cnt >= 3'd2) next_data = {current_data[DATA_W-5:0], hex_val};
                              next_hex_cnt = hex_cnt + 1'b1;
                              next_state   = (hex_cnt == 3'd5) ? WDL : WVL;
                          end
            WDL         : if (rx_byte == "}") next_state = WR_MSG_END;

            default     : ;
        endcase
    end

endmodule