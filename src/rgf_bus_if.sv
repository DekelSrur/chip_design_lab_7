`timescale 1ns/1ps

interface rgf_bus_if
  import pkg_rgf::*;
();
  
  logic wr_en;
  logic rd_en;     // 1-cycle read strobe - only for RGFs with R0C registers. 
  regs_addr_t addr;
  logic [DATA_W-1:0] wdata;
  logic [DATA_W-1:0] rdata;
  logic err;

  modport rw_master (
    output wr_en, addr, wdata,
    input  rdata
    );

  modport rw_slave (
    input  wr_en, addr, wdata,
    output rdata
    );

  modport ro_master (
    output addr,   
    input  rdata, err
    ); 

  modport ro_slave (
    input  addr, 
    output rdata, err
    );  

  // RW + read-to-clear: like rw_*, plus a read strobe (sys_rgf: SYS_STATUS is R0C)
  modport rw_r0c_master (
    output wr_en, rd_en, addr, wdata,
    input  rdata
    );

  modport rw_r0c_slave (
    input  wr_en, rd_en, addr, wdata,
    output rdata
    );

endinterface : rgf_bus_if

