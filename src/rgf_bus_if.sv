`timescale 1ns/1ps

interface rgf_bus_if import pkg_rgf::*;
#(

  parameter int DATA_W = 32
  
);
  
  logic wr_en;
  cnt_regs_t addr;
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

endinterface : rgf_bus_if

