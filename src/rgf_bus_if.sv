`timescale 1ns/1ps

interface rgf_bus_if
  import pkg_rgf::*;
();
  
  logic wr_en;
  logic rd_en;     // 1-cycle read strobe (needed for R0C registers)
  regs_addr_t addr;
  logic [DATA_W-1:0] wdata;
  logic [DATA_W-1:0] rdata;
  logic err;

  modport rw_master (
    output wr_en, rd_en, addr, wdata,
    input  rdata
    ); 

  modport rw_slave (
    input  wr_en, rd_en, addr, wdata,
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

endinterface : rgf_bus_if

