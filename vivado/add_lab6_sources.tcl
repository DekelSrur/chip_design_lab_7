# Adds the Lab 6 sources/testbenches to the open project.
# Usage (Vivado Tcl console, project open):
#   source /home/user/lab_6/vivado/add_lab6_sources.tcl

set root [file normalize [file join [get_property DIRECTORY [current_project]] ..]]
puts "lab_6 root: $root"

# --- design sources ---
foreach f {pkg_lab6.sv param_ctrl.sv color_translate.sv pwm_ctrl.sv black_magic_box.sv} {
    set p [file join $root src $f]
    if {![file exists $p]} { puts "MISSING on disk: $p"; continue }
    if {[llength [get_files -quiet -of [get_filesets sources_1] $p]] == 0} {
        add_files -fileset sources_1 $p
        puts "added: $f"
    } else { puts "already in project: $f" }
}
set_property file_type {Verilog Header} [get_files black_magic_box.sv]
set_property include_dirs [file join $root src] [get_filesets {sources_1 sim_1}]

# --- testbenches ---
foreach f {tb_color_translate.sv tb_pwm_ctrl.sv} {
    set p [file join $root tb $f]
    if {[file exists $p] && [llength [get_files -quiet -of [get_filesets sim_1] $p]] == 0} {
        add_files -fileset sim_1 $p
        puts "added tb: $f"
    }
}
foreach f {tb_parser.sv TB_RX_fsm.sv} {
    set g [get_files -quiet -of [get_filesets sim_1] *$f]
    if {[llength $g]} { remove_files -fileset sim_1 $g; puts "removed tb (old RX ports): $f" }
}

set_property top chip_top [get_filesets sources_1]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
puts "--- sources_1 now contains ---"
foreach f [get_files -of [get_filesets sources_1]] { puts "  $f" }
