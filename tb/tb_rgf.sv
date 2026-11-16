`timescale 1ns/1ps

//tb_rgf - self-checking testbench for the register bus:
//         addr_xbar (master side) + led_rgf, pwm_rgf, cnt_rgf, sys_rgf (slaves)
//The testbench plays two roles:
//master: drives master_addr / master_wdata / master_wen / master_ren (like parser)
//        and checks master_rvalid / master_raddr / master_rdata (like tx_fsm)
//hardware: drives the pulses that reach the RGFs from the design
//         (rx_pkt, color_msg, cfg_msg, tx_pkt, led_sel_update, hw_wr_en)
//and checks the configuration outputs of the RGFs.


module tb_rgf;
    import pkg_rgf::*;

    localparam int CLK_PERIOD = 10;                 // 100 MHz

//clock and reset
    logic clk = 0;
    logic rst_n = 0;

//master side (parser / tx_fsm)
    logic [ADDR_W-1:0] master_addr = '0;
    logic [DATA_W-1:0] master_wdata = '0;
    logic master_wen = 0, master_ren = 0;
    logic master_rvalid;
    logic [ADDR_W-1:0] master_raddr;
    logic [DATA_W-1:0] master_rdata;
    logic invalid_addr_evt, ro_wr_evt;

//hardware side of the RGFs
    logic led_sel_update = 0, hw_wr_en = 0;         // param_ctrl -> led_rgf
    logic rx_pkt = 0, color_msg = 0, cfg_msg = 0;   // parser -> cnt_rgf
    logic tx_pkt = 0;                               // tx_fsm -> cnt_rgf

//RGF outputs
    logic [1:0] led_sel, led_on;
    logic       cie_on;
    logic [PATTERN_DATA_W-1:0] pattern;
    logic [15:0] time_slots, sweep_time;
    lut_reg_t [2:0] lut_cfg;                        // [2]=R, [1]=G, [0]=B
    logic sw_rst, enable;

//slave buses - one interface per RGF, as in chip_top
    rgf_bus_if led_bus ();
    rgf_bus_if pwm_bus ();
    rgf_bus_if cnt_bus ();
    rgf_bus_if sys_bus ();

    int errors = 0;

//reference model: expected value of every register, the key is the register address
    logic [DATA_W-1:0] exp_val [regs_addr_t];

//design under test: the master (addr_xbar) and its four slaves
    addr_xbar u_addr_xbar (
        .master_addr(master_addr), .master_wdata(master_wdata),
        .master_wen(master_wen), .master_ren(master_ren),
        .master_rvalid(master_rvalid), .master_raddr(master_raddr), .master_rdata(master_rdata),
        .invalid_addr_evt(invalid_addr_evt), .ro_wr_evt(ro_wr_evt),
        .led_bus(led_bus), .pwm_bus(pwm_bus), .cnt_bus(cnt_bus), .sys_bus(sys_bus)
    );

    led_rgf u_led_rgf (
        .clk(clk), .rst_n(rst_n),
        .led_sel_update(led_sel_update), .hw_wr_en(hw_wr_en),
        .led_sel(led_sel), .cie_on(cie_on), .pattern(pattern), .led_on(led_on),
        .bus(led_bus)
    );

    pwm_rgf u_pwm_rgf (
        .clk(clk), .rst_n(rst_n),
        .time_slots(time_slots), .sweep_time(sweep_time), .lut_cfg(lut_cfg),
        .bus(pwm_bus)
    );

    cnt_rgf u_cnt_rgf (
        .clk(clk), .rst_n(rst_n),
        .rx_pkt(rx_pkt), .color_msg(color_msg), .cfg_msg(cfg_msg), .tx_pkt(tx_pkt),
        .bus(cnt_bus)
    );

    sys_rgf u_sys_rgf (
        .clk(clk), .rst_n(rst_n),
        .invalid_addr_evt(invalid_addr_evt), .ro_wr_evt(ro_wr_evt),
        .sw_rst(sw_rst), .enable(enable),
        .bus(sys_bus)
    );

    always #(CLK_PERIOD/2) clk = ~clk;

//stop the simulation if it hangs
    initial begin
        #100_000;
        $display("tb_rgf FAILED: timeout");
        $finish;
    end

//write one register: master_wen is high for one clock, like the parser pulse
    task automatic write(input logic [ADDR_W-1:0] addr, input logic [DATA_W-1:0] data);
        @(negedge clk);
        master_addr  = addr;
        master_wdata = data;
        master_wen   = 1;
        @(negedge clk);
        master_wen   = 0;
    endtask

//read one register and compare with the expected value
//the read path is combinational, so the data is checked in the same clock as master_ren
    task automatic read_check(input logic [ADDR_W-1:0] addr, input logic [DATA_W-1:0] expected);
        regs_addr_t reg_name;                       // only for the name in the messages
        reg_name = regs_addr_t'(addr);
        @(negedge clk);
        master_addr = addr;
        master_ren  = 1;
        #1;
        if (master_rdata !== expected || master_rvalid !== 1 || master_raddr !== addr) begin
            $display("FAILED: read %s (addr %h) = %h, expected %h (rvalid = %b, raddr = %h)",
                     reg_name.name(), addr, master_rdata, expected, master_rvalid, master_raddr);
            errors++;
        end
        else
            $display("read %s (addr %h) = %h", reg_name.name(), addr, master_rdata);
        @(negedge clk);
        master_ren = 0;
    endtask

//compare a configuration output of an RGF with the expected value
    task automatic out_check(input int test, input logic ok);
        if (!ok) begin
            $display("FAILED: test %0d, RGF outputs are wrong", test);
            errors++;
        end    
        else
            $display("test %0d: RGF outputs are correct", test);
    endtask

//load the reference model with the reset value of every register (as in the register file)
    task automatic set_reset_values();
        exp_val[LED_CTRL]      = 32'h0000_003D;
        exp_val[LED_PATTERN]   = 32'h0000_0000;
        exp_val[PWM_CFG]       = 32'h0000_0400;
        exp_val[RED_LUT]       = 32'h0000_03E8;
        exp_val[GREEN_LUT]     = 32'h0000_03E8;
        exp_val[BLUE_LUT]      = 32'h0000_03E8;
        exp_val[RX_PKT_CNT]    = 32'h0000_0000;
        exp_val[TX_PKT_CNT]    = 32'h0000_0000;
        exp_val[COLOR_MSG_CNT] = 32'h0000_0000;
        exp_val[CFG_MSG_CNT]   = 32'h0000_0000;
        exp_val[SYS_CTRL]      = 32'h0000_0002;     // enable = 1
        exp_val[SYS_STATUS]    = 32'h0000_0000;
        exp_val[SYS_VERSION]   = 32'h0007_0001;
    endtask

//read every register of the map and compare with the reference model
//used to see that a write changed only its own register
    task automatic check_all();
        foreach (exp_val[addr])
            read_check(addr, exp_val[addr]);
    endtask

    initial begin
        #20 rst_n = 1;

//test 1: reset values of all 13 registers and of the RGF outputs
        $display("Test 1: reset values");
        set_reset_values();
        check_all();
        out_check(1, led_sel === 2'b01 && cie_on === 1'b1 && led_on === 2'b11 && pattern === 2'h0);
        out_check(1, time_slots === 16'd1024 && sweep_time === 16'd0 && enable === 1 && sw_rst === 0);
        out_check(1, lut_cfg[2].out_freq === 13'd1000 && lut_cfg[1].out_freq === 13'd1000 &&
                     lut_cfg[0].out_freq === 13'd1000);

//test 2: led_rgf - write, read back, outputs follow the fields
        $display("Test 2: led_rgf write / read");
        write(LED_CTRL, 32'h0000_002A);                 //led_sel = LED17, LED17 on, LED17 CIE on
        read_check(LED_CTRL, 32'h0000_002A);
        out_check(2, led_sel === 2'b10 && led_on === 2'b10 && cie_on === 1'b1);
        write(LED_PATTERN, 32'h0000_0002);              //rainbow
        read_check(LED_PATTERN, 32'h0000_0002);
        out_check(2, pattern === 2'h2);
        write(LED_CTRL, 32'hFFFF_FFFF);                 //bits[31:6] do not exist
        read_check(LED_CTRL, 32'h0000_003F);
        write(LED_PATTERN, 32'hFFFF_FFFD);              //bits[31:2] do not exist
        read_check(LED_PATTERN, 32'h0000_0001);

//test 3: pwm_rgf - write, read back, outputs follow the fields
        $display("Test 3: pwm_rgf write / read");
        write(PWM_CFG, 32'h1234_0800);                  //sweep_time = 0x1234, time_slots = 2048
        read_check(PWM_CFG, 32'h1234_0800);
        out_check(3, time_slots === 16'd2048 && sweep_time === 16'h1234);
        write(RED_LUT,   32'h0000_8064);                //init_phase = 1,  magnitude = 0, out_freq = 100
        write(GREEN_LUT, 32'h0055_20C8);                //init_phase = 170, magnitude = 1, out_freq = 200
        write(BLUE_LUT,  32'h00AA_C12C);                //init_phase = 341, magnitude = 2, out_freq = 300
        out_check(3, lut_cfg[2].init_phase === 9'd1   && lut_cfg[2].magnitude === 2'd0 &&
                     lut_cfg[2].out_freq === 13'd100);
        out_check(3, lut_cfg[1].init_phase === 9'd170 && lut_cfg[1].magnitude === 2'd1 &&
                     lut_cfg[1].out_freq === 13'd200);
        out_check(3, lut_cfg[0].init_phase === 9'd341 && lut_cfg[0].magnitude === 2'd2 &&
                     lut_cfg[0].out_freq === 13'd300);
        write(RED_LUT, 32'hFFFF_FFFF);                  //bits[31:24] do not exist
        read_check(RED_LUT, 32'h00FF_FFFF);
        write(RED_LUT, 32'h0000_8064);

//test 4: every write changed only its own register (slave select and address decode)
        $display("Test 4: one register per write");
        exp_val[LED_CTRL]    = 32'h0000_003F;
        exp_val[LED_PATTERN] = 32'h0000_0001;
        exp_val[PWM_CFG]     = 32'h1234_0800;
        exp_val[RED_LUT]     = 32'h0000_8064;
        exp_val[GREEN_LUT]   = 32'h0055_20C8;
        exp_val[BLUE_LUT]    = 32'h00AA_C12C;
        check_all();

//test 5: hardware write to LED_CTRL (LED message or CENTER button)
        $display("Test 5: led_rgf hardware write");
        @(negedge clk);
        led_sel_update = 0;                             //choose LED17
        hw_wr_en       = 1;
        @(negedge clk);
        hw_wr_en       = 0;
        read_check(LED_CTRL, 32'h0000_003A);            //CIE bits kept, LED17 on, led_sel = LED17
        @(negedge clk);
        led_sel_update = 1;                             //choose LED16
        hw_wr_en       = 1;
        @(negedge clk);
        hw_wr_en       = 0;
        read_check(LED_CTRL, 32'h0000_0035);            //CIE bits kept, LED16 on, led_sel = LED16
        @(negedge clk);                                 //PC write and hardware write in the same clock
        master_addr    = LED_CTRL;
        master_wdata   = 32'h0000_001E;
        master_wen     = 1;
        led_sel_update = 1;
        hw_wr_en       = 1;
        @(negedge clk);
        master_wen     = 0;
        hw_wr_en       = 0;
        read_check(LED_CTRL, 32'h0000_001E);            //the PC write wins

//test 6: cnt_rgf - every pulse is counted in its own counter
        $display("Test 6: cnt_rgf counters");
        for (int i = 0; i < 3; i++) begin
            @(negedge clk) rx_pkt = 1;
            @(negedge clk) rx_pkt = 0;
        end
        for (int i = 0; i < 4; i++) begin
            @(negedge clk) tx_pkt = 1;
            @(negedge clk) tx_pkt = 0;
        end
        for (int i = 0; i < 2; i++) begin
            @(negedge clk) color_msg = 1;
            @(negedge clk) color_msg = 0;
        end
        @(negedge clk) cfg_msg = 1;
        @(negedge clk) cfg_msg = 0;
        @(negedge clk);                                 // two pulses in the same clock
        rx_pkt    = 1;
        color_msg = 1;
        @(negedge clk);
        rx_pkt    = 0;
        color_msg = 0;
        read_check(RX_PKT_CNT,    32'd4);
        read_check(TX_PKT_CNT,    32'd4);
        read_check(COLOR_MSG_CNT, 32'd3);
        read_check(CFG_MSG_CNT,   32'd1);

//test 7: write to a read-only register - nothing changes, ro_wr_err is set, cleared by the read
        $display("Test 7: write to read-only registers");
        write(RX_PKT_CNT, 32'hFFFF_FFFF);
        read_check(RX_PKT_CNT, 32'd4);
        read_check(SYS_STATUS, 32'h0000_0002);          // ro_wr_err
        read_check(SYS_STATUS, 32'h0000_0000);          // R0C: the first read cleared it
        write(SYS_VERSION, 32'h0000_0000);
        read_check(SYS_VERSION, 32'h0007_0001);
        read_check(SYS_STATUS, 32'h0000_0002);
        write(SYS_STATUS, 32'h0000_0003);               // cannot set the flags by a write
        read_check(SYS_STATUS, 32'h0000_0002);          // only ro_wr_err of this write
        read_check(SYS_STATUS, 32'h0000_0000);

//test 8: invalid addresses - read returns 0, invalid_addr_err is set, registers do not change
        $display("Test 8: invalid addresses");
        read_check(24'h00_0034, 32'h0000_0000);         // first address after the map
        read_check(SYS_STATUS, 32'h0000_0001);          // invalid_addr_err
        read_check(SYS_STATUS, 32'h0000_0000);
        write(24'h00_0002, 32'hFFFF_FFFF);              // not a multiple of 4
        write(24'h01_0000, 32'hFFFF_FFFF);              // far outside the map
        read_check(SYS_STATUS, 32'h0000_0001);
        write(24'h00_0100, 32'h0000_0000);              // invalid address ...
        write(CFG_MSG_CNT, 32'h0000_0000);              // ... and a read-only register
        read_check(SYS_STATUS, 32'h0000_0003);          // both flags are kept until the read
        read_check(SYS_STATUS, 32'h0000_0000);
        exp_val[LED_CTRL]      = 32'h0000_001E;         // from test 5
        exp_val[RX_PKT_CNT]    = 32'd4;                 // from test 6
        exp_val[TX_PKT_CNT]    = 32'd4;
        exp_val[COLOR_MSG_CNT] = 32'd3;
        exp_val[CFG_MSG_CNT]   = 32'd1;
        check_all();                                    // nothing changed in any register

//test 9: sys_rgf - enable bit and the self-clearing sw_rst pulse
        $display("Test 9: SYS_CTRL");
        write(SYS_CTRL, 32'h0000_0000);
        read_check(SYS_CTRL, 32'h0000_0000);
        out_check(9, enable === 0 && sw_rst === 0);
        write(SYS_CTRL, 32'h0000_0003);                 // enable = 1 and SW reset
        out_check(9, sw_rst === 1 && enable === 1);     // the clock after the write
        @(negedge clk);
        out_check(9, sw_rst === 0 && enable === 1);     // one clock later sw_rst is back to 0
        read_check(SYS_CTRL, 32'h0000_0002);            // sw_rst always reads 0

//test 10: reset brings every register back to its reset value
        $display("Test 10: reset");
        @(negedge clk) rst_n = 0;
        @(negedge clk) rst_n = 1;
        set_reset_values();
        check_all();

        if (errors == 0) $display("tb_rgf PASSED");
        else             $display("tb_rgf FAILED, %0d errors", errors);
        $finish;
    end

endmodule 
