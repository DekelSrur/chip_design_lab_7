# Synthesis top module
TOP := chip_top
# Testbench top module (override: make sim TB=tb_uart_tx)
TB := tb_chip_top

include ../vscode-fpga/tools/common.mk
