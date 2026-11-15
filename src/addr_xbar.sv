`timescale 1ns/1ps

module addr_xbar 
    import pkg_rgf::*;
(
    input logic [ADDR_W-1:0] master_addr,       //register address (A2 A1 A0)
    input logic [DATA_W-1:0] master_wdata,      //write data (DH1 DH0 DL1 DL0)
    input logic master_wen,                     //write command
    input logic master_ren,                     //read command
    

    output logic master_rvalid,
    output logic [ADDR_W-1:0] master_raddr,     //adddress that wsa read
    output logic [DATA_W-1:0] master_rdata,     //value that was read
    output logic invalid_addr_evt,
    output logic ro_wr_evt,


    rgf_bus_if.rw_master led_bus,               //led rgf read & write
    rgf_bus_if.rw_master pwm_bus,               //pwm_rgf read & write
    rgf_bus_if.ro_master cnt_bus,               //cnt_rgf read only
    rgf_bus_if.rw_master sys_bus                //sys_rgf read & write
);

    logic [N_RGF-1:0] slave_sel;
    logic addr_invalid;
    logic addr_aligned;

    assign addr_aligned = (master_addr[1:0] == 2'b00);

    //address decoder 
        always_comb begin: slave_sel_dec
            slave_sel = '0;
            addr_invalid = 1'b0;

            if(!addr_aligned)
                addr_invalid = 1'b1;
            else if(master_addr <= LED_PATTERN) //led_ctrl is address 0  
                slave_sel[LED_IDX] = 1'b1;
            else if(master_addr >= PWM_CFG && master_addr <= BLUE_LUT)
                slave_sel[PWM_IDX] = 1'b1;
            else if (master_addr >= RX_PKT_CNT && master_addr <= CFG_MSG_CNT)
                slave_sel[CNT_IDX] = 1'b1;
            else if (master_addr >= SYS_CTRL && master_addr <= SYS_VERSION)
                slave_sel[SYS_IDX] = 1'b1;
            else
                addr_invalid = 1'b1;    
        end

    //broadcast from master to all RGF
    assign led_bus.addr = regs_addr_t'(master_addr);
    assign led_bus.wdata = master_wdata;
    assign led_bus.wr_en = master_wen && slave_sel[LED_IDX];
    assign led_bus.rd_en = master_ren && slave_sel[LED_IDX];

    assign pwm_bus.addr = regs_addr_t'(master_addr);
    assign pwm_bus.wdata = master_wdata;
    assign pwm_bus.wr_en = master_wen && slave_sel[PWM_IDX];
    assign pwm_bus.rd_en = master_ren && slave_sel[PWM_IDX];

    assign cnt_bus.addr = regs_addr_t'(master_addr); //read only - no data and no wr_en

    assign sys_bus.addr  = regs_addr_t'(master_addr);
    assign sys_bus.wdata = master_wdata;
    assign sys_bus.wr_en = master_wen && slave_sel[SYS_IDX];
    assign sys_bus.rd_en = master_ren && slave_sel[SYS_IDX];

    //read selected rgf to master
    always_comb begin: rdata_mux
        unique case (1'b1)
            slave_sel[LED_IDX]: master_rdata = led_bus.rdata;
            slave_sel[PWM_IDX]: master_rdata = pwm_bus.rdata;
            slave_sel[CNT_IDX]: master_rdata = cnt_bus.rdata;
            slave_sel[SYS_IDX]: master_rdata = sys_bus.rdata;
            default: master_rdata = '0;             //invalid address reads as 0
        endcase
    end

    //error events
    assign invalid_addr_evt = (master_wen || master_ren) && addr_invalid;

    // read-only targets: the whole cnt_rgf, SYS_STATUS (R0C), SYS_VERSION (RO)
    assign ro_wr_evt = master_wen && (slave_sel[CNT_IDX]        ||
                                      master_addr == SYS_STATUS ||
                                      master_addr == SYS_VERSION);

    // Read response to tx_fsm
    assign master_rvalid = master_ren;
    assign master_raddr  = master_addr;

endmodule                              




