set root [file dirname [file dirname [info script]]]
file mkdir $root/build/simulation
cd $root/build/simulation
create_project simulation ./project -part xc7z010clg400-1 -force
add_files $root/rtl/frequency_to_voltage.v
add_files -fileset sim_1 $root/tb/tb_frequency_to_voltage.sv
set_property top tb_frequency_to_voltage [get_filesets sim_1]
set_property xsim.simulate.runtime all [get_filesets sim_1]
launch_simulation
close_sim
exit
