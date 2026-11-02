# Vivado batch entry point. One fresh process per candidate avoids retaining
# prior implementations or accumulating memory during large sweeps.
set script_dir [file dirname [file normalize [info script]]]
source [file join $script_dir timing_common.tcl]
set cfg [bt::options [dict create \
    -part xcv80-lsva4737-2MHP-e-S -mhz 500 -size 8 -width 64 -extra 0 \
    -layout distributed -retime 1 -uncertainty 0.1 -io_delay 0.2 \
    -margin 0.0 -threads 8 -out {}] {*}$argv]
set out [dict get $cfg -out]
if {$out eq ""} {error "-out is required"}
if {[file exists [file join $out result.tcl]]} {error "Refusing to overwrite an existing candidate result: $out"}
file mkdir $out
set out [file normalize $out]
set started [clock seconds]
set result [dict create status error message {}]
set phase configuration

set failed [catch {
    set size [dict get $cfg -size]
    set width [dict get $cfg -width]
    set extra [dict get $cfg -extra]
    set layout [dict get $cfg -layout]
    set geometry [bt::geometry $size $width $extra $layout]
    dict for {key value} $geometry {dict set result $key $value}
    foreach key {-mhz -uncertainty -io_delay -margin} {
        set value [dict get $cfg $key]
        if {![string is double -strict $value] || $value < 0} {error "$key must be a nonnegative number"}
    }
    if {[dict get $cfg -mhz] <= 0} {error "-mhz must be positive"}
    set period [expr {1000.0/[dict get $cfg -mhz]}]
    set part [dict get $cfg -part]
    if {![llength [get_parts -quiet $part]]} {error "Part $part is unavailable; install V80 device support/license or override -part"}
    set_param general.maxThreads [dict get $cfg -threads]
    dict set result vivado_version [version -short]
    dict set result part $part
    dict set result period_ns $period
    set root [file dirname $script_dir]
    read_verilog -sv [list [file join $root rtl bitonic_sort_pipeline.sv] [file join $root rtl bitonic_timing_top.sv]]

    set xdc [file join $out timing.xdc]
    set fh [open $xdc w]
    puts $fh [format {create_clock -name core_clk -period %.9f [get_ports clk]} $period]
    puts $fh [format {set_clock_uncertainty %.9f [get_clocks core_clk]} [dict get $cfg -uncertainty]]
    puts $fh {set data_in [get_ports -filter {DIRECTION == IN && NAME != clk}]}
    puts $fh [format {set_input_delay -clock core_clk -max %.9f $data_in} [dict get $cfg -io_delay]]
    puts $fh {set_input_delay -clock core_clk -min 0.0 $data_in}
    puts $fh [format {set_output_delay -clock core_clk -max %.9f [all_outputs]} [dict get $cfg -io_delay]]
    puts $fh {set_output_delay -clock core_clk -min 0.0 [all_outputs]}
    close $fh
    read_xdc $xdc

    set phase synthesis
    set synth_args [list -top bitonic_timing_top -part $part -mode out_of_context \
        -flatten_hierarchy full -no_srlextract -generic [list WIDTH=$width SIZE=$size \
        EXTRA_REGS=$extra DISTRIBUTE=[expr {$layout eq "distributed" ? 1 : 0}]]]
    if {[dict get $cfg -retime]} {lappend synth_args -retiming} else {lappend synth_args -no_retiming}
    synth_design {*}$synth_args
    report_utilization -file [file join $out utilization_synth.rpt]
    dict set result lut [llength [get_cells -hier -filter {REF_NAME =~ LUT*}]]
    dict set result ff [llength [get_cells -hier -filter {REF_NAME =~ FD*}]]
    write_checkpoint -force [file join $out synthesized.dcp]
    set phase implementation
    opt_design
    place_design -directive Explore
    if {[dict get $cfg -retime]} {phys_opt_design -directive AddRetime} else {phys_opt_design}
    route_design -directive Explore
    report_route_status -file [file join $out route_status.rpt]
    set bad_routes [get_nets -hier -filter {ROUTE_STATUS != ROUTED && ROUTE_STATUS != INTRASITE && ROUTE_STATUS != NOLOADS && ROUTE_STATUS != HIERPORT}]
    if {[llength $bad_routes]} {error "Incomplete/invalid routing on [llength $bad_routes] nets; see route_status.rpt"}
    set phase timing
    report_timing_summary -delay_type min_max -report_unconstrained -check_timing_verbose -file [file join $out timing_summary.rpt]
    check_timing -verbose -file [file join $out check_timing.rpt]
    report_utilization -file [file join $out utilization_routed.rpt]
    report_drc -file [file join $out drc.rpt]
    set violations [get_drc_violations -quiet -filter {SEVERITY == Error}]
    if {[llength $violations]} {error "Implementation DRC errors; see drc.rpt"}
    set setup [get_timing_paths -delay_type max -max_paths 1 -sort_by slack]
    set hold [get_timing_paths -delay_type min -max_paths 1 -sort_by slack]
    if {![llength $setup] || ![llength $hold]} {error "Missing timed setup/hold paths"}
    set wns [get_property SLACK [lindex $setup 0]]
    set whs [get_property SLACK [lindex $hold 0]]
    if {![string is double -strict $wns] || ![string is double -strict $whs] || abs($wns) > 1e6 || abs($whs) > 1e6} {error "Invalid/unconstrained timing result"}
    dict set result setup_slack_ns $wns
    dict set result hold_slack_ns $whs
    dict set result lut [llength [get_cells -hier -filter {REF_NAME =~ LUT*}]]
    dict set result ff [llength [get_cells -hier -filter {REF_NAME =~ FD*}]]
    dict set result status [expr {$wns >= [dict get $cfg -margin] && $whs >= 0 ? "pass" : "timing_fail"}]
    write_checkpoint -force [file join $out routed.dcp]
} message options]

if {$failed} {
    dict set result status error
    # Capacity/routing failures are infeasible candidates, not tool failures.
    # Preserve the exact error separately; syntax/license/device errors abort.
    if {$phase in {synthesis implementation} && [regexp -nocase {over.util|too many.*(LUT|register|cell|instance|resource)|exceed.*(resource|available)|not enough.*(resource|site|slice)|not sufficient.*(resource|site|slice)|resource.*insufficient|unrout|incomplete/invalid routing|failed to place|could not place} $message]} {
        dict set result status implementation_fail
    }
    dict set result message "$phase: $message"
    set fh [open [file join $out error.txt] w]
    puts $fh [dict get $options -errorinfo]
    close $fh
}
dict set result runtime_s [expr {[clock seconds]-$started}]
set fh [open [file join $out result.tcl] w]
puts $fh [list set result $result]
close $fh
puts "BITONIC_RESULT $result"
if {[dict get $result status] eq "error"} {exit 2}
