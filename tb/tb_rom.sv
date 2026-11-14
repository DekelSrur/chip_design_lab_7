`timescale 1ns/1ps

module tb_rom;

    localparam int DEPTH = 512, WIDTH = 8, ADDR_W = $clog2(DEPTH);

    logic              clk = 0;
    logic [ADDR_W-1:0] addr = '0;
    logic [WIDTH-1:0]  data;

    logic [WIDTH-1:0]  golden [DEPTH];   // expected values, same file
    int errors = 0;

    rom #(.DEPTH(DEPTH), .WIDTH(WIDTH)) dut (.*);

    always #5 clk = ~clk;

    initial begin
        $dumpfile("tb_rom.vcd");
        $dumpvars(0, tb_rom);
        $readmemh("sine_lut.mem", golden);

        // sweep all addresses; data appears one clock after addr (sync read)
        for (int i = 0; i < DEPTH; i++) begin
            @(negedge clk) addr = i;
            @(posedge clk) #1;
            if (data !== golden[i]) begin
                errors++;
                if (errors < 10) $display("  FAIL addr %0d: got %0d expected %0d", i, data, golden[i]);
            end
        end

        // shape checks
        if (golden[0]   !== 8'd0)   begin errors++; $display("  FAIL start is not 0"); end
        if (golden[256] !== 8'd255) begin errors++; $display("  FAIL peak is not 255"); end

        $display("\n=== %s (%0d errors) ===", errors ? "TEST FAILED" : "TEST PASSED", errors);
        $finish;
    end
endmodule
