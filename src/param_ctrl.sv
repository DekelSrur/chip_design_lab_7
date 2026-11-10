`timescale 1ns/1ps

module param_ctrl 
    import pkg_lab6::*; 
(
    input logic clk, rst_n,
    input logic [4:0] btn_db,                                   // {center, up, down, left, right}
    input logic [BYTE-1:0] row_index, col_index, pixel_value,
    input logic RGB_wr_en, led_wr_en, led,                      // led==1 => led16, led==0 => led17
    
    output logic [23:0] applyRGB,                               // {8bit R, 8bit G, 8bit B}
    output logic led_sel,                              
    output logic [7:0] dig_sel,                                  // {[1:0]T3, [1:0]T2, [1:0]T1, [1:0]T0}
    output logic [23:0] edit_RGB,                               // {R, G, B} being edited (to the display)
    output logic edit_led                                     // LED being edited: 1 = LED16, 0 = LED17
);

    typedef enum logic [1:0] {IDLE, ACTIVATED, PRESSED} state_t;
    typedef enum logic [4:0] {
                                NOCMND = 5'b00000,
                                RIGHT  = 5'b00001,
                                LEFT   = 5'b00010,
                                DOWN   = 5'b00100,
                                UP     = 5'b01000,
                                CENTER = 5'b10000} buttons_t;

    state_t current_state, next_state;
    buttons_t opcode;                                            // {center, up, down, left, right}
    logic [4:0] single_btn;
    logic current_led;
    logic [23:0] current_RGB;  
    digits_t current_digits;                                     // 00=T0, 01=T1 10=T2, 11=T3
    leds_t digit_leds;

    assign dig_sel = digit_leds;
    assign edit_RGB = current_RGB;
    assign edit_led = current_led;

    //mealy fsm - converting the debounced button press into a single command
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) opcode <= NOCMND;                  
        else if (next_state == ACTIVATED) opcode <= buttons_t'(single_btn);  
        else opcode <= NOCMND;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) current_state <= IDLE;
        else begin
            current_state <= next_state;
        end
    end

    always_comb begin
        if ((btn_db & (btn_db - 1'b1)) == 0) single_btn = btn_db;      // checks if only one button is pressed 
        else single_btn = '0;                                          // else sends a signal that no button is pressed

        next_state = current_state; 
        case (current_state)
            IDLE      : if (|single_btn) next_state = ACTIVATED;
            ACTIVATED : if (|single_btn) next_state = PRESSED;
                        else next_state = IDLE;
            PRESSED   : if (!(|single_btn)) next_state = IDLE;
            default   : next_state = IDLE;
        endcase

        case (current_digits)
            T0 : digit_leds = LEDS5_4;
            T1 : digit_leds = LEDS8_7;
            T2 : digit_leds = LEDS10_9;
            T3 : digit_leds = LEDS13_12;
            default : digit_leds = LEDS5_4;
        endcase
    end

    // button controller, affects the output RGB, the display and the leds
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            applyRGB <= 24'd0;
            current_digits <= T0;
            current_RGB <= 24'd0;
            current_led <=0;
            led_sel <=0;
        end
        else if (RGB_wr_en) begin                                 // update the color to the rx message
            current_RGB <= {row_index, col_index, pixel_value};
            applyRGB <= {row_index, col_index, pixel_value};
        end
        else if (led_wr_en) begin                                 // update the led to the rx message
            current_led <= led;
            led_sel <= led;
        end
        else begin
            case (opcode)
                RIGHT   : if (current_digits != T0) begin
                                current_digits <= digits_t'(current_digits - 2'd1);     // go right unless it's on the most right digits
                        end
                LEFT    : if (current_digits != T3) current_digits <= digits_t'(current_digits + 2'd1);     // go left unless it's on the most left digits 
                DOWN    : begin
                            if (current_digits == T3) begin
                                if (current_led) current_led <= '0;
                            end
                            else if(current_RGB[BYTE * current_digits +: BYTE] != '0) 
                                    current_RGB[BYTE * current_digits +: BYTE] <= current_RGB[BYTE * current_digits +: BYTE] - BYTE'(1);
                        end
                UP      : begin
                            if (current_digits == T3) begin
                                if (!current_led) current_led <= '1;
                            end
                            else if(current_RGB[BYTE * current_digits +: BYTE] != '1) 
                                    current_RGB[BYTE * current_digits +: BYTE] <= current_RGB[BYTE * current_digits +: BYTE] + BYTE'(1);
                        end
                CENTER  : begin
                            led_sel <= current_led;
                            applyRGB <= current_RGB;
                        end
                        default: ;
            endcase
        end
    end

endmodule
