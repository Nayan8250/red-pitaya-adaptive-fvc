# Standalone Vivado 2020.1 batch build for the wideband frequency locker.
# Reads the pinned vendor checkout but creates all generated files under build/.

set script_dir  [file dirname [info script]]
set project_root [file dirname $script_dir]
set vendor_root C:/RedPitaya/_Codex/vendor/RedPitaya-FPGA
if {[info exists ::env(RP_VENDOR_ROOT)]} {set vendor_root [file normalize $::env(RP_VENDOR_ROOT)]}
if {![string match "2020.1*" [version -short]]} {error "Vivado 2020.1 required"}
set custom_hdl   [file join $script_dir "rtl"]
set build_dir    [file join $script_dir "build" "vivado"]
set output_bit   [file join $script_dir "build" "iq_dualinput_fvc.bit"]
set report_dir   [file join $build_dir "reports"]

file mkdir $build_dir
file mkdir $report_dir
cd $build_dir

set part xc7z010clg400-1
create_project -in_memory -part $part
set_property verilog_define {Z10 SCOPE_ONLY} [current_fileset]
set_param board.repoPaths [list [file join $vendor_root "brd"]]
set_param iconstr.diffPairPulltype {opposite}

# Generate the unchanged Z10 processing-system block design in the local build.
set ::gpio_width 24
set ::hp0_clk_freq 125000000
set ::hp1_clk_freq 125000000
set ::hp2_clk_freq 250000000
set ::hp3_clk_freq 250000000
source [file join $vendor_root "prj" "v0.94" "ip" "systemZ10.tcl"]

# The loopback uses the ADC-derived PLL clocks and PS FCLK0 reset only.  The
# legacy XADC AXI subsystem is the sole remaining critical path at its default
# 200 MHz FCLK3 rate.  Keep the complete vendor-compatible PS wrapper, but
# operate this unused auxiliary FCLK3 domain at 100 MHz.  FCLK0 and every ADC/
# DAC clock are unchanged, and the timing gate below remains strict.
set_property CONFIG.PCW_FPGA3_PERIPHERAL_FREQMHZ {100} [get_bd_cells processing_system7]
validate_bd_design
save_bd_design
generate_target all [get_files system.bd]

# Shared vendor RTL, the selected v0.94 support files, and local custom HDL.
add_files -quiet [glob -nocomplain [file join $vendor_root "rtl" "*_pkg.sv"]]
add_files $vendor_root/rtl
remove_files [get_files */rtl/sys_bus_cdc.sv]
add_files [list [file join $project_root rtl sys_bus_cdc.sv]]
add_files [list \
  [file join $vendor_root "prj" "v0.94" "rtl" "osc_calib.v"] \
  [file join $vendor_root "prj" "v0.94" "rtl" "osc_filter.v"] \
  [file join $vendor_root "prj" "v0.94" "rtl" "red_pitaya_ps.sv"] \
  [file join $custom_hdl "redpitaya_top.sv"]]

set bd_hdl [file join $build_dir ".srcs" "sources_1" "bd" "system" "hdl"]
add_files [list $bd_hdl]
add_files [glob [file join $custom_hdl *.v]]

# Preserve both the physical-board constraints and v0.94 timing constraints.
add_files -fileset constrs_1 [list [file join $project_root constraints redpitaya.xdc]]
add_files -fileset constrs_1 [list [file join $project_root constraints timing.xdc]]

set_property generic "GITH=160'h0000000000000000000000000000000000000000" [current_fileset]
set_property top red_pitaya_top [current_fileset]
update_compile_order -fileset sources_1
if {[info exists ::create_only]} {
 save_project_as frequency_to_voltage [file join $build_dir project] -force
 exit
}

synth_design -top red_pitaya_top -flatten_hierarchy none -bufg 16 -keep_equivalent_registers
write_checkpoint -force [file join $report_dir "post_synth.dcp"]
report_timing_summary -file [file join $report_dir "post_synth_timing_summary.rpt"]

opt_design
power_opt_design
place_design
phys_opt_design
write_checkpoint -force [file join $report_dir "post_place.dcp"]
report_timing_summary -file [file join $report_dir "post_place_timing_summary.rpt"]

route_design
source [file join $project_root scripts finish_build.tcl]




