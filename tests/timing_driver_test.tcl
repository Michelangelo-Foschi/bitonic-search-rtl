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
        if {[lindex $columns 2] ne "tail"} {error "Default search must use tail placement: $line"}
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
        source [file join $dest size_8 extra_0 mock_synth_args.tcl]
        set generic_index [lsearch -exact $mock_synth_args -generic]
        set generics [lindex $mock_synth_args [expr {$generic_index+1}]]
        if {[lsearch -exact $generics DISTRIBUTE=0] < 0 ||
            [lsearch -exact $mock_synth_args -retiming] < 0 ||
            [lsearch -exact $mock_synth_args -no_srlextract] < 0} {
            error "Default runner must append output banks and enable retiming: $mock_synth_args"
        }
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
# -io 0 must time only internal paths: clock constraint kept, no port delays.
set env(BITONIC_TEST_MODE) monotonic
set dest [file join $scratch io_off]
exec [info nameofexecutable] $driver -sizes {8} -io 0 -out $dest 2>@1
set channel [open [file join $dest size_8 extra_0 timing.xdc] r]
set constraints [read $channel]
close $channel
if {[string first {create_clock -name core_clk -period 2.000000000} $constraints] < 0} {error "-io 0 dropped the clock"}
if {[string first set_input_delay $constraints] >= 0 || [string first set_output_delay $constraints] >= 0} {error "-io 0 still constrains ports"}
if {![catch {exec [info nameofexecutable] $driver -sizes {8} -io 2 -dry_run 1 2>@1}]} {error "-io 2 was accepted"}

# Check the single-candidate entry point independently, without a -layout flag.
set env(BITONIC_TEST_MODE) monotonic
set single [file join $scratch default-tail10]
exec [file join $scratch bin vivado] -source [file join $test_root scripts run_candidate.tcl] \
    -tclargs -size 8 -width 64 -extra 10 -out $single 2>@1
source [file join $single result.tcl]
source [file join $single mock_synth_args.tcl]
set generic_index [lsearch -exact $mock_synth_args -generic]
if {[dict get $result internal] != 0 || [dict get $result tail] != 10 ||
    [dict get $result latency] != 12 ||
    [lsearch -exact [lindex $mock_synth_args [expr {$generic_index+1}]] DISTRIBUTE=0] < 0} {
    error "Single-candidate default did not keep all ten extra banks at the output"
}

# The frequency-search entry point must propagate the same default to its
# candidate probes and nested register-budget search.
set frequency_out [file join $scratch default-frequency-tail]
exec [info nameofexecutable] [file join $test_root scripts fmax_search.tcl] \
    -sizes {8} -out $frequency_out 2>@1
source [file join $frequency_out config.tcl]
if {[dict get $configuration -layout] ne "tail"} {error "Frequency search did not default to tail"}
source [file join $frequency_out size_8 probe_500mhz result.tcl]
if {[dict get $result internal] != 0 || [dict get $result tail] != 5} {
    error "Frequency-search probe inserted internal banks"
}
source [file join $frequency_out size_8 search_500mhz config.tcl]
if {[dict get $configuration -layout] ne "tail"} {error "Nested search did not keep tail placement"}
puts "PASS: driver/runner orchestration, default tail placement, retiming flags, reports, failures, minima, 500 MHz constraints (mock tool only)"
