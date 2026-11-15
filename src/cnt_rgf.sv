`timescale 1ns/1ps

// [31:0] rx valid packet counter
// [31:0] how many valid TX packets were transmitted
// [31:0] how many of the valid received packets were color messages
// [31:0] how many of the valid received packets were config messages

module cnt_rgf     
    import pkg_rgf::*;
(
    input logic clk,
    input logic rst_n,
    input logic rx_pkt, color_msg, cfg_msg,  // from parser
    input logic tx_pkt,                      // from tx_fms
    rgf_bus_if.ro_slave bus                  // interface with addr_xbar
);

logic [DATA_W-1:0] rx_pkt_reg;
logic [DATA_W-1:0] tx_pkt_reg;
logic [DATA_W-1:0] color_msg_reg;
logic [DATA_W-1:0] cfg_msg_reg;

always_comb begin : reg_read_dec
    bus.rdata = '0;
    bus.err = '0;
    unique case(bus.addr)
        RX_PKT_CNT    : bus.rdata = rx_pkt_reg;
        TX_PKT_CNT    : bus.rdata = tx_pkt_reg;
        COLOR_MSG_CNT : bus.rdata = color_msg_reg;
        CFG_MSG_CNT   : bus.rdata = cfg_msg_reg;
        default : bus.err = '1;
    endcase
end

always_ff @(posedge clk or negedge rst_n) begin : data_count_and_sort
    if (!rst_n) begin
        rx_pkt_reg <= '0;
        tx_pkt_reg <= '0;
        color_msg_reg <= '0;
        cfg_msg_reg <= '0;
    end
    else begin
        rx_pkt_reg <=+ rx_pkt_reg + DATA_W'(rx_pkt);
        tx_pkt_reg <=+ tx_pkt_reg + DATA_W'(tx_pkt);
        color_msg_reg <=+ color_msg_reg + DATA_W'(color_msg);
        cfg_msg_reg <=+ cfg_msg_reg + DATA_W'(cfg_msg);
    end
end
endmodule