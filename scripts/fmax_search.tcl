# Find, for each size, the highest passing clock (in -step_mhz steps) and the
# fewest extra register banks at that clock. Run with tclsh after sourcing
# Vivado's settings64.sh. Reuses run_candidate.tcl and timing_search.tcl.
#
# Per size:
#   1. Probe the maximum-budget design (extra = levels-1) at -start_mhz.
#   2. If it fails, estimate Fmax from its setup slack, round down to the step,
#      and probe again there. Keep lowering until that design passes or
#      -min_mhz is reached. Each new target is always lower than the last.
#   3. At the first passing clock, run timing_search.tcl to find the minimum
#      extra banks for that clock.
set script_dir [file dirname [file normalize [info script]]]
source [file join $script_dir timing_common.tcl]
if {[lsearch -exact $argv -help] >= 0} {
    puts {Usage: tclsh scripts/fmax_search.tcl ?-sizes {8 16}? ?-width 64? ?-start_mhz 500? ?-step_mhz 5? ?-min_mhz 50? ?-layout tail|distributed (default: tail)? ?-io 0|1? ?-verify_min 1|0? ?-out NEW_DIRECTORY?}
    exit 0
}
set cfg [bt::options [dict create -part xcv80-lsva4737-2MHP-e-S \
    -sizes {8 16} -width 64 -layout tail -start_mhz 500 -step_mhz 5 \
    -min_mhz 50 -io 0 -verify_min 1 -retime 1 -uncertainty 0.1 -io_delay 0.2 \
    -threads 8 -out {}] {*}$argv]

foreach key {-io -verify_min -retime} {
    if {[dict get $cfg $key] ni {0 1}} {error "$key must be 0 or 1"}
}
foreach key {-start_mhz -step_mhz -min_mhz} {
    set value [dict get $cfg $key]
    if {![string is double -strict $value] || $value <= 0} {error "$key must be a positive number"}
}
if {[dict get $cfg -min_mhz] > [dict get $cfg -start_mhz]} {error "-min_mhz must not exceed -start_mhz"}
foreach size [dict get $cfg -sizes] {bt::geometry $size [dict get $cfg -width] 0 [dict get $cfg -layout]}
if {![llength [dict get $cfg -sizes]]} {error "-sizes must not be empty"}

set vivado [auto_execok vivado]
if {$vivado eq ""} {error "vivado not on PATH; source its settings64.sh first"}
set out [dict get $cfg -out]
if {$out eq ""} {error "-out is required"}
set out [file normalize $out]
if {[file exists $out]} {error "Refusing to overwrite existing results: $out. Choose a new -out directory."}
file mkdir $out
set fh [open [file join $out config.tcl] w]
puts $fh [list set configuration $cfg]
close $fh
set probes [open [file join $out probes.csv] w]
bt::csv $probes {size width layout extra target_mhz setup_slack_ns hold_slack_ns est_fmax_mhz lut ff runtime_s status directory}
set summary [open [file join $out fmax_summary.csv] w]
bt::csv $summary {size width layout io fmax_mhz best_extra latency minimum_verified status directory}

# Format a frequency without float noise (e.g. 440 or 437.5).
proc mhz_text {value} {
    set text [format %.3f $value]
    return [string trimright [string trimright $text 0] .]
}

# One Vivado run of the maximum-budget design at a given clock.
proc probe {size extra mhz} {
    global cfg script_dir out probes vivado
    set run [file join $out size_$size probe_[mhz_text $mhz]mhz]
    file mkdir $run
    set args [list -size $size -extra $extra -mhz [mhz_text $mhz] -margin 0.0 -out $run]
    foreach key {-part -width -layout -retime -uncertainty -io_delay -threads -io} {lappend args $key [dict get $cfg $key]}
    puts "PROBE size=$size extra=$extra target=[mhz_text $mhz]MHz"
    set failed [catch {exec {*}$vivado -mode batch -notrace -nojournal -log [file join $run vivado.log] \
        -source [file join $script_dir run_candidate.tcl] -tclargs {*}$args >[file join $run console.log] 2>@1} message]
    set file [file join $run result.tcl]
    if {![file exists $file]} {error "Vivado did not produce a result: $run ($message)"}
    source $file
    set est {}
    if {[dict exists $result setup_slack_ns]} {
        set period [expr {1000.0/$mhz}]
        set est [format %.1f [expr {1000.0/($period - [dict get $result setup_slack_ns])}]]
    }
    set row [list $size [dict get $cfg -width] [dict get $cfg -layout] $extra [mhz_text $mhz]]
    foreach key {setup_slack_ns hold_slack_ns} {lappend row [expr {[dict exists $result $key] ? [dict get $result $key] : ""}]}
    lappend row $est
    foreach key {lut ff runtime_s status} {lappend row [expr {[dict exists $result $key] ? [dict get $result $key] : ""}]}
    lappend row $run
    bt::csv $probes $row
    if {$failed || [dict get $result status] eq "error"} {error "Build error (not a timing failure): [dict get $result message]. Logs: $run"}
    puts "PROBE_RESULT size=$size target=[mhz_text $mhz]MHz status=[dict get $result status] est_fmax=${est}MHz"
    return [list [dict get $result status] $est]
}

# Next lower target: the estimate rounded down to the step, but always at
# least one step below the clock that just failed.
proc next_target {current est} {
    global cfg
    set step [dict get $cfg -step_mhz]
    set lower [expr {$current - $step}]
    if {$est ne "" && $est > 0} {
        set rounded [expr {floor($est/$step)*$step}]
        if {$rounded < $lower} {set lower $rounded}
    }
    return $lower
}

set errors 0
set no_solution 0
foreach size [dict get $cfg -sizes] {
    set levels [dict get [bt::geometry $size [dict get $cfg -width] 0 [dict get $cfg -layout]] levels]
    set full [expr {max(0,$levels-1)}]
    set mhz [dict get $cfg -start_mhz]
    set found {}
    set failed [catch {
        while {$mhz >= [dict get $cfg -min_mhz]} {
            lassign [probe $size $full $mhz] status est
            if {$status eq "pass"} {set found $mhz; break}
            set mhz [next_target $mhz $est]
        }
    } message]
    if {$failed} {
        incr errors
        puts stderr "SIZE $size STOPPED: $message"
        bt::csv $summary [list $size [dict get $cfg -width] [dict get $cfg -layout] [dict get $cfg -io] {} {} {} {} error [file join $out size_$size]]
        continue
    }
    if {$found eq ""} {
        incr no_solution
        puts "FMAX size=$size none at or above [dict get $cfg -min_mhz]MHz"
        bt::csv $summary [list $size [dict get $cfg -width] [dict get $cfg -layout] [dict get $cfg -io] {} {} {} {} no_passing_clock [file join $out size_$size]]
        continue
    }
    # Minimum extra banks at the passing clock, using the existing search.
    set search_out [file join $out size_$size search_[mhz_text $found]mhz]
    puts "FMAX size=$size passing_clock=[mhz_text $found]MHz; searching minimum extra banks"
    set args [list -sizes $size -mhz [mhz_text $found] -out $search_out]
    foreach key {-part -width -layout -retime -uncertainty -io_delay -threads -io -verify_min} {lappend args $key [dict get $cfg $key]}
    catch {exec [info nameofexecutable] [file join $script_dir timing_search.tcl] {*}$args >@stdout 2>@stderr}
    set best {}; set latency {}; set verified {}; set status error
    set summary_file [file join $search_out summary.csv]
    if {[file exists $summary_file]} {
        set channel [open $summary_file r]
        set lines [split [string trim [read $channel]] \n]
        close $channel
        if {[llength $lines] >= 2} {
            set columns [split [string map {\" {}} [lindex $lines 1]] ,]
            lassign [lrange $columns 4 6] best latency verified
            set status [lindex $columns 8]
        }
    }
    if {$status eq "error"} {incr errors}
    if {$status eq "no_passing_candidate"} {incr no_solution}
    bt::csv $summary [list $size [dict get $cfg -width] [dict get $cfg -layout] [dict get $cfg -io] \
        [mhz_text $found] $best $latency $verified $status $search_out]
}
close $probes
close $summary
puts "Results: [file join $out fmax_summary.csv]"
if {$errors} {exit 2}
if {$no_solution} {exit 1}
