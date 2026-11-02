# End-to-end test of the real driver/runner/report code with a fake tool.
set test_root [file normalize [file join [file dirname [info script]] ..]]
set scratch [file join $test_root build mock-timing-[pid]]
file mkdir [file join $scratch bin]
file copy [file join $test_root tests mock_vivado.sh] [file join $scratch bin vivado]
file copy [file join $test_root tests mock_vivado.tcl] [file join $scratch bin mock_vivado.tcl]
file attributes [file join $scratch bin vivado] -permissions 0755
set env(PATH) "[file join $scratch bin]:$env(PATH)"
set driver [file join $test_root scripts timing_search.tcl]
foreach mode {monotonic nonmonotonic resource no_solution tool_error} {
    set env(BITONIC_TEST_MODE) $mode
    set dest [file join $scratch $mode]
    set failed [catch {exec [info nameofexecutable] $driver -sizes {8 16} -out $dest 2>@1} output options]
    if {$mode in {no_solution tool_error}} {
        set expected [expr {$mode eq "tool_error" ? 2 : 1}]
        if {!$failed || [lindex [dict get $options -errorcode] 2] != $expected} {error "Wrong exit code in $mode: $output"}
    } elseif {$failed} {error "Unexpected driver failure in $mode: $output"}
    set channel [open [file join $dest summary.csv] r]
    set lines [split [string trim [read $channel]] \n]
    close $channel
    if {[llength $lines] != 3} {error "Expected two size summaries in $mode"}
    foreach line [lrange $lines 1 end] {
        set columns [split [string map {\" {}} $line] ,]
        set best [lindex $columns 4]
        set status [lindex $columns 8]
        if {$mode eq "tool_error"} {
            if {$status ne "error"} {error "Tool errors were treated as timing: $line"}
        } elseif {$mode eq "no_solution"} {
            if {$best != -1 || $status ne "no_passing_candidate"} {error "Incorrect no-solution result"}
        } else {
            set expected [expr {$mode eq "nonmonotonic" ? 3 : 2}]
            if {$best != $expected || [lindex $columns 6] != 1 || $status ne "pass"} {error "Incorrect minimum: $line"}
        }
    }
    # The fixture must be clearly marked, and period must be exactly 2 ns.
    source [file join $dest size_8 extra_0 result.tcl]
    if {$mode ne "tool_error" && ([dict get $result vivado_version] ne "MOCK_TEST_ONLY" || [dict get $result period_ns] != 2.0)} {error "Runner did not use the correct target"}
    if {$mode ne "tool_error"} {
        set channel [open [file join $dest size_8 extra_0 timing.xdc] r]
        set constraints [read $channel]
        close $channel
        foreach required {
            {create_clock -name core_clk -period 2.000000000 [get_ports clk]}
            {set_clock_uncertainty 0.100000000 [get_clocks core_clk]}
            {set_input_delay -clock core_clk -max 0.200000000 $data_in}
            {set_output_delay -clock core_clk -min 0.0 [all_outputs]}
        } {
            if {[string first $required $constraints] < 0} {error "Missing timing constraint: $required"}
        }
    }
    if {![catch {exec [info nameofexecutable] $driver -sizes {8} -out $dest 2>@1}]} {error "Results were overwritten"}
}
puts "PASS: driver/runner orchestration, reports, failures, minima, 500 MHz constraints (mock tool only)"
