`timescale 1ns/1ps

module debouncer #(
    parameter DEBOUNCE_CYCLES = 1_000_000
)(
    input logic clk,
    input logic rst_n,
    input logic [4:0] btn_in,
    input logic [15:0] sw_in,

    output logic [4:0] btn_db,
    output logic [15:0] sw_db
);

//localparam
    localparam N = 21;                                                      //5 button + 16 switchers
    localparam CW = (DEBOUNCE_CYCLES > 1) ? $clog2(DEBOUNCE_CYCLES) : 1;    //counter width

//inputs
    logic [N-1:0] din;
    logic [N-1:0] dout;

    assign din    = {sw_in, btn_in};
    assign btn_db = dout[4:0];
    assign sw_db  = dout[N-1:5];

//per bit debouncer: each input has its on counter
    genvar i;
    generate
        for (i = 0; i < N; i++) begin: DB_BIT
            logic [CW-1:0] cnt;                 //window counter
            logic q;                            //clean value

            assign dout[i] = q;

            always_ff @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    cnt <= '0;
                    q <= 1'b0;
                end

                else if (din[i] == q) begin
                    cnt <= '0;
                end

                else if (cnt == DEBOUNCE_CYCLES - 1) begin
                    q <= din[i];
                    cnt <= '0;
                end

                else begin
                    cnt <= cnt + 1'b1;
                end
            end
        end                
    endgenerate  

endmodule


