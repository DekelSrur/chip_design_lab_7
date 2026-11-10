`timescale 1ns / 1ps
module tb_seg7_ctrl;

localparam int REFRESH_DIV = 4; 

logic clk, rst_n, rx_mode;
logic [31:0] digits;
logic [7:0] an, dps;
logic [6:0] seg;
logic dp;

seg7_ctrl #(.REFRESH_DIV(REFRESH_DIV)) dut (
    .clk(clk), .rst_n(rst_n), .rx_mode(rx_mode),
    .digits(digits), .an(an), .dps(dps),
    .seg(seg),
    .dp(dp)
);

logic reset_done = 0;
logic [31:0] last_digits;
logic [7:0]  last_dps, last_an;

task automatic reset_test; //activates a reset pulse, make sure to see idx<=3d'0, an<=8'hFF, seg<=7'h7F, dp<=1'b1
    reset_done = 0;
    @(posedge clk);
    rst_n = 0;
    @(negedge clk);
    assert(an == 8'hFF && seg == 7'h7F && dp)
        else $display (" failed reset: an=%h seg=%h  dp=%b", 
                                   an,   seg,    dp);
    rst_n = 1;     #10;
    #10;
    reset_done = 1;
    endtask

function automatic logic [6:0] expected_seg(input logic [3:0] h);
    case (h)
        4'h0: return 7'b1000000;     //0
        4'h1: return 7'b1111001;     //1
        4'h2: return 7'b0100100;     //2
        4'h3: return 7'b0110000;     //3
        4'h4: return 7'b0011001;     //4
        4'h5: return 7'b0010010;     //5
        4'h6: return 7'b0000010;     //6
        4'h7: return 7'b1111000;     //7
        4'h8: return 7'b0000000;     //8 
        4'h9: return 7'b0010000;     //9
        4'hA: return 7'b0001000;     //A 
        4'hB: return 7'b0000011;     //b
        4'hC: return 7'b1000110;     //C
        4'hD: return 7'b0100001;     //d                     
        4'hE: return 7'b0000110;     //E
        4'hF: return 7'b0001110;     //F
    endcase
endfunction

initial clk = 1'b0;
always #5 clk = ~clk;

always @(posedge clk) begin // saves the inputs to compare them to the register outputs
    last_digits <= digits;
    last_dps <= dps;
end

logic [7:0] z;
assign z = ~an;  

always @(negedge clk) begin // after output "an" was updated, checks it is only reffering to a single digit
    if (reset_done) begin
        assert(z != 0 && z == (1 << $clog2(z))) // if there is no reset, check if there's only 1 bit that equals '0' on an
            else $display (" wrong output an=%b at time=%t", 
                                   an,  $time);
    end
end

logic [2:0] k;

always @(negedge clk) begin // checks if the generated 7segments are valid
    if (reset_done) begin
        k = 3'($clog2(z));                                    
        assert (seg == expected_seg(last_digits[k*4 +: 4]))
            else $display("digit %0d: seg=%b expected %b", 
                                    k, seg,   expected_seg(last_digits[k*4 +: 4]));
        assert (dp == ~last_dps[k])
            else $display("digit %0d: dp=%b expected %b", 
                                  k,    dp,         ~last_dps[k]);
    end
end

int count;

always @(negedge clk) begin // checks if the switch rate between digits equals "tick"
    if (!reset_done) begin
        count = 0;
        last_an = 8'hFF;
    end
    else if (an != last_an) begin             
        if (count != 0) begin                    
            assert (count == REFRESH_DIV)
                else $display("digit was on for %0d clocks, expected %0d", 
                                                count,          REFRESH_DIV);
            assert (an == {last_an[6:0], last_an[7]})          
                else $display("wrong order: %b -> %b", 
                                         last_an, an);
        end
        count = 1;
    end
    else if (count != 0) count++;
    last_an = an;
end

initial begin
    rst_n = 1;
    digits = 32'b0;
    dps = 8'b0;
    last_an = 8'hFF;
    rx_mode = 0;
    
    reset_test(); 
    
    for (int i = 0; i < 16; i++) begin
        for (int j = 0; j < 8; j++)
            digits[j*4 +: 4] = (i + j) % 16;
        for (int c = 0; c < 8*REFRESH_DIV; c++)     
            @(negedge clk);
    end

    for (int c = 0; c < 200; c++) begin
        digits = $urandom;
        dps    = $urandom;
        @(negedge clk);
    end

    $display (" all test passed ");
    $finish;
end

endmodule
