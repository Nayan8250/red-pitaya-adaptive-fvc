set root [file dirname [info script]]
cd $root
create_project simulation ./project -part xc7z010clg400-1 -force
add_files [list $root/../../rtl/analytic.v $root/../../rtl/dual_fvc.v]
add_files -fileset sim_1 $root/tb.sv
set_property top tb [get_filesets sim_1]
set_property xsim.simulate.runtime all [get_filesets sim_1]
launch_simulation
close_sim
exit
