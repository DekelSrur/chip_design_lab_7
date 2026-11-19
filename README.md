# Lab 7 – Register-Configurable RGB LED Controller with DDS

SystemVerilog design for the Nexys A7-100T (Xilinx Artix-7) that drives two RGB LEDs with PWM. A PC configures the design over a full-duplex UART link by writing and reading 13 configuration registers. A direct digital synthesizer (DDS) modulates the colors with a sine wave to create breath and rainbow patterns.

Built as part of the Chip Design and Verification program (Google & Reichman University, 2026). It extends the PWM controller of [Lab 6](https://github.com/DekelSrur/chip_design_lab_6).

**Team:** Dekel Srur, Avi Shevel, May Weiss

## Features

- **Full-duplex UART**, 57,600 baud, 8N1. Commands arrive on RX while read responses are sent on TX.
- **Register bus**: the parser is the bus master; an address decoder (`addr_xbar`) selects one of four register files. The bus is a SystemVerilog interface with modports (`rgf_bus_if`).
- **13 registers of 32 bits**, with fields, address map and reset values defined once in `pkg_rgf`.
- **DDS per color channel**: 32-bit phase accumulator and a 512-entry, 8-bit sine ROM. Frequency, magnitude and initial phase are set by registers.
- **Color path**: sRGB to PWM duty cycle, with a gamma table and CIE brightness correction that can be switched on and off.
- **PWM** with a period set at run time by a register (reset value 1024 slots, 97.7 kHz).
- **Error handling**: a write to a read-only register or an access to an unmapped address changes nothing and sets a sticky flag in `SYS_STATUS`.
- Push-button color editor and 7-segment display, kept from Lab 6.

## Architecture

```
            +--------+   +--------+   +-----------+   +---------+
 uart_rxd ->| RX_fsm |-->| parser |-->| addr_xbar |-->| led_rgf |
            +--------+   +--------+   |           |-->| pwm_rgf |
                             |        |           |-->| cnt_rgf |
                             |        +-----------+-->| sys_rgf |
                             |              | read data
                             |              v
            +---------+  +--------+   +--------+
 uart_txd <-| uart_tx |<-| tx_fsm |<--+
            +---------+  +--------+

 color -> color_translate -> dds_ctrl (+ rom) -> pwm_ctrl -> LED16 / LED17
```

`chip_top` only connects the modules. Inputs pass through `sync` (reset and input synchronizers) and `debouncer`; `param_ctrl`, `display_mux` and `seg7_ctrl` handle the buttons and the display.

## UART messages

| Message | Direction | Format |
| --- | --- | --- |
| Write register | PC to FPGA | `{Wxxx,Vhhhhhh,Vhhhhhh}`, address as 3 hex digits, data as hex digits |
| Read register | PC to FPGA | `{Rxxx}` |
| Read response | FPGA to PC | 16 bytes: address echoed as 3 hex characters, data as binary bytes |
| Set color | PC to FPGA | `{R___,G___,B___}`, each field 000–255 (sRGB) |
| Select LED | PC to FPGA | `{L016}` or `{L017}` |

Invalid messages are ignored and do not change any register, color or LED.

## Register map

| Address | Register | Access | Description |
| --- | --- | --- | --- |
| 0x0000 | LED_CTRL | RW | LED select, on / off per LED, CIE on / off per LED |
| 0x0004 | LED_PATTERN | RW | Static, breath or rainbow |
| 0x0008 | PWM_CFG | RW | `[15:0]` time slots (period), `[31:16]` sweep time |
| 0x000C | RED_LUT | RW | `[12:0]` output frequency, `[14:13]` magnitude, `[23:15]` initial phase |
| 0x0010 | GREEN_LUT | RW | Same fields |
| 0x0014 | BLUE_LUT | RW | Same fields |
| 0x0018 | RX_PKT_CNT | RO | Valid packets received |
| 0x001C | TX_PKT_CNT | RO | Packets transmitted |
| 0x0020 | COLOR_MSG_CNT | RO | Color messages received |
| 0x0024 | CFG_MSG_CNT | RO | Configuration messages received |
| 0x0028 | SYS_CTRL | RW | `[0]` software reset (self-clearing), `[1]` enable |
| 0x002C | SYS_STATUS | Read-to-clear | `[0]` invalid address, `[1]` write to a read-only register |
| 0x0030 | SYS_VERSION | RO | `[31:16]` lab number, `[15:0]` revision |

## Verification

Self-checking testbenches, run in the Vivado simulator:

- `tb_rgf` checks the register bus against a reference model of all 13 registers.
- `tb_dds` checks the ROM output and the DDS output on every clock (540,207 checks each); `tb_rom` checks the sine table on its own.
- `tb_chip_top` plays the role of the PC and checks the complete chip only through its pins: the serial lines and the PWM outputs.
- `tb_parser`, `tb_pwm_ctrl`, `tb_color_translate` and `tb_uart_tx` check single modules.

## Results

| Item | Result |
| --- | --- |
| Timing at 100 MHz | Met: WNS +1.888 ns, WHS +0.134 ns |
| Resources | 1,203 LUTs, 1,035 flip-flops, 9 DSP blocks, 31 I/O pins |
| Hardware test | 9 of 9 test cases passed on the board |

## Repository layout

| Folder | Content |
| --- | --- |
| `src/` | RTL modules, packages and the bus interface |
| `tb/` | Testbenches |
| `sim/` | Waveform configurations |
| `constr/` | Pin and timing constraints (`lab7.xdc`) |
| `scripts/` | `gen_sine.py`, generates the sine table |
| `vivado/` | Vivado project |
| `doc/` | Diagrams |

## Known limitations

`PWM_CFG.sweep_time` and `LED_CTRL` LED select are stored and can be read back, but do not affect the outputs in this version: one color drives both LEDs.
