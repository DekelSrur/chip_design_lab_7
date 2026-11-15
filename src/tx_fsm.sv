`timescale 1ns/1ps

module tx_fsm 
    import pkg_rgf::*;
(
    input logic clk,
    input logic rst_n,
    input logic master_rvalid,                  //raddr/radata are valid                     
    input logic [ADDR_W-1:0] master_raddr,      //address that was sent
    input logic [DATA_W-1:0] master_rdata,      //value that was read
    input logic tx_done,                      

    output logic tx_start,
    output logic [7:0] tx_data,
    output logic busy,
    output logic tx_pkt
);

    localparam int MSG_LEN = 16;                 //bytes in a read response
    localparam int IDX_W = $clog2(MSG_LEN);

//state encoding
    typedef enum logic [1:0] {
        IDLE = 2'b00,                           //waiting for a read 
        SEND = 2'b01,                           //hand 1 byte to uart_tx
        WAIT = 2'b10                            //wait until uart_tx finished the byte
    } state_t;

    state_t curr_st, next;

    logic [ADDR_W-1:0] addr_q;                  //latched address
    logic [DATA_W-1:0] data_q;                  //latched data
    logic [IDX_W-1:0] byte_idx;                 //index of the byte being sent (0..15)
    logic [IDX_W-1:0] next_idx;                 //index of the byte being sent (0..15)
    logic last_byte;                            //byte_idx is the closing "}"
    logic [7:0] msg_byte;                       //message byte number next_idx

//block 1 - state register
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) curr_st <= IDLE;
        else curr_st <= next;
    end

//block 2 - decoders and next state logic
    always_comb begin
        last_byte = (byte_idx == IDX_W'(MSG_LEN-1));
        next = curr_st;
        next_idx = byte_idx;
        unique case (curr_st)
            IDLE: if(master_rvalid) begin
                    next = SEND;
                    next_idx = '0;
            end
            SEND: next = WAIT;
            WAIT: if(tx_done) begin
                    if(last_byte) next = IDLE;
                    else begin
                        next = SEND;
                        next_idx = byte_idx + 1'b1;
                    end
            end
            default: next = IDLE; 
        endcase
            
//{R A2 A1 A0 , V 00 DH1 DH0 , V 00 DL1 DL0}
        unique case (next_idx)                 
            4'd0 : msg_byte = "{";
            4'd1 : msg_byte = "R";
            4'd2 : msg_byte = addr_q[23:16];    //A2
            4'd3 : msg_byte = addr_q[15:8];     //A1
            4'd4 : msg_byte = addr_q[7:0];      //A0
            4'd5 : msg_byte = ",";
            4'd6 : msg_byte = "V";
            4'd7 : msg_byte = 8'h00;
            4'd8 : msg_byte = data_q[31:24];    //DH1
            4'd9 : msg_byte = data_q[23:16];    //DH0
            4'd10: msg_byte = ",";
            4'd11: msg_byte = "V";
            4'd12: msg_byte = 8'h00;
            4'd13: msg_byte = data_q[15:8];     //DL1
            4'd14: msg_byte = data_q[7:0];      //DL0
            4'd15: msg_byte = "}";
        endcase
    end

//block 3 - registerd outputs
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_start <= 1'b0;
            tx_data  <= '0;
            busy     <= 1'b0;
            tx_pkt   <= 1'b0;
            addr_q   <= '0;
            data_q   <= '0;
            byte_idx <= '0;
        end
        else begin
            busy <= (next != IDLE);
            byte_idx <= next_idx;

            if(curr_st == IDLE && master_rvalid) begin
                addr_q <= master_raddr;
                data_q <= master_rdata;
            end

            if(next == SEND) begin
                tx_start <= 1'b1;
                tx_data <= msg_byte;
            end

            else tx_start <= 1'b0;
                 tx_pkt <= (curr_st == WAIT) && tx_done && last_byte;
        end
    end
    endmodule







