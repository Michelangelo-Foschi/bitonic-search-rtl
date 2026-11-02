# Executes the real runner with a synthetic Vivado API to test control flow.
# All produced timing values are fixtures, not FPGA measurements.
set source_index [lsearch -exact $argv -source]
set runner [lindex $argv [expr {$source_index+1}]]
set args_index [lsearch -exact $argv -tclargs]
set argv [lrange $argv [expr {$args_index+1}] end]
set mock_cfg [dict create {*}$argv]
set mode $::env(BITONIC_TEST_MODE)
set extra [dict get $mock_cfg -extra]
proc get_parts {args} {expr {$::mode eq "tool_error" ? {} : {mock_v80}}}
proc version {args} {return MOCK_TEST_ONLY}
foreach command {set_param read_verilog read_xdc synth_design opt_design phys_opt_design route_design report_route_status report_timing_summary check_timing report_utilization report_drc write_checkpoint} {
    proc $command {args} {}
}
proc place_design {args} {
    if {$::mode eq "resource" && $::extra == 0} {error "Placement could not place all instances: not enough resources"}
}
proc get_cells {args} {return {mock_cell0 mock_cell1}}
proc get_nets {args} {return {}}
proc get_drc_violations {args} {return {}}
proc get_timing_paths {args} {return [expr {[lsearch -exact $args max] >= 0 ? "setup" : "hold"}]}
proc get_property {property object} {
    if {$object eq "hold"} {return 0.1}
    if {$::mode eq "no_solution"} {return -0.2}
    if {$::mode eq "nonmonotonic"} {return [expr {$::extra == 3 ? 0.1 : -0.2}]}
    return [expr {$::extra >= 2 ? 0.1 : -0.2}]
}
source $runner
