# Shared timing-closure/reporting gate for a fresh build or an existing checkpoint.
# Post-route physical optimization preserves logical behavior and constraints.
for {set attempt 0} {$attempt < 2} {incr attempt} {
 set slack [get_property SLACK [get_timing_paths -delay_type max -max_paths 1 -nworst 1]]
 if {$slack ne "" && $slack >= 0.0} {break}
 phys_opt_design -directive AggressiveExplore
 route_design -directive Explore
}
write_checkpoint -force [file join $report_dir post_route.dcp]
report_timing_summary -file [file join $report_dir post_route_timing_summary.rpt]
report_timing -file [file join $report_dir post_route_timing.rpt] -sort_by group -max_paths 100 -path_type summary
report_drc -file [file join $report_dir post_route_drc.rpt]
report_utilization -file [file join $report_dir post_route_utilization.rpt]
set worst_setup [get_property SLACK [get_timing_paths -delay_type max -max_paths 1 -nworst 1]]
set worst_hold [get_property SLACK [get_timing_paths -delay_type min -max_paths 1 -nworst 1]]
puts "Worst setup slack: $worst_setup ns; worst hold slack: $worst_hold ns"
if {$worst_setup eq "" || $worst_hold eq "" || $worst_setup < 0.0 || $worst_hold < 0.0} {
 error "Final implementation timing failed"
}
set final_timing [report_timing_summary -return_string]
if {![string match "*All user specified timing constraints are met*" $final_timing]} {error "Final timing summary did not pass"}
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
write_bitstream -force $output_bit
puts "SUCCESS: bitstream written to $output_bit"
exit
