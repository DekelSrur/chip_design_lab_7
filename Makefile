# Synthesis top module
TOP := chip_top
# Testbench top module (override: make sim TB=tb_uart_tx)
TB := tb_chip_top

# Package compile order (a package must come after any package it imports)
SRC_PKG := src/pkg_sys.sv src/pkg_rgf.sv

include ../vscode-fpga/tools/common.mk
