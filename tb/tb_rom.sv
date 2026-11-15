`timescale 1ns/1ps

// tb_rom - checks all 512 entries of rom.sv against the raised-cosine formula
module tb_rom;

    localparam int DEPTH = 512, WIDTH = 8, ADDR_W = $clog2(DEPTH);
    localparam real PI = 3.141592653589793;

    logic              clk = 0;
    logic [ADDR_W-1:0] addr = '0;
    logic [WIDTH-1:0]  data;

    int errors = 0;
    int expected;

    rom #(.DEPTH(DEPTH), .WIDTH(WIDTH)) dut (.*);

    always #5 clk = ~clk;

    initial begin
        $dumpfile("tb_rom.vcd");
        $dumpvars(0, tb_rom);

        // sweep all addresses; data appears one clock after addr (sync read)
        for (int i = 0; i < DEPTH; i++) begin
            @(negedge clk) addr = i;
            @(posedge clk) #1;
            expected = $rtoi(255.0 * (1.0 - $cos(2.0 * PI * i / DEPTH)) / 2.0 + 0.5);
            if (data !== WIDTH'(expected)) begin
                errors++;
                if (errors < 10) $display("  FAIL addr %0d: got %0d expected %0d", i, data, expected);
            end
        end

        // shape checks
        @(negedge clk) addr = 0;   @(posedge clk) #1;
        if (data !== 8'd0)   begin errors++; $display("  FAIL start is not 0"); end
        @(negedge clk) addr = 256; @(posedge clk) #1;
        if (data !== 8'd255) begin errors++; $display("  FAIL peak is not 255"); end

        $display("\n=== %s (%0d errors) ===", errors ? "TEST FAILED" : "TEST PASSED", errors);
        $finish;
    end
endmodule
