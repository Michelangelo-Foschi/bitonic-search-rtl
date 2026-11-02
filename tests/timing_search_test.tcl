source [file join [file dirname [info script]] .. scripts timing_common.tcl]
proc assert {condition {message "assertion failed"}} {
    if {![uplevel 1 [list expr $condition]]} {error $message}
}
proc monotone {threshold candidate} {expr {$candidate >= $threshold ? 1 : 0}}
for {set max 0} {$max < 56} {incr max} {
    for {set threshold 0} {$threshold <= $max+1} {incr threshold} {
        set found [bt::search_minimum $max [list monotone $threshold]]
        set expected [expr {$threshold <= $max ? $threshold : -1}]
        assert {[dict get $found best] == $expected} "Incorrect search max=$max threshold=$threshold"
        assert {[dict get $found verified] == 1}
    }
}
proc arbitrary {passing candidate} {expr {$candidate in $passing ? 1 : 0}}
foreach passing {{2 5 9} {3} {1 9} {4 6} {} {0}} {
    set found [bt::search_minimum 9 [list arbitrary $passing]]
    set expected [expr {[llength $passing] ? [lindex $passing 0] : -1}]
    assert {[dict get $found best] == $expected} "Non-monotonic case $passing"
}
set unverified [bt::search_minimum 9 [list arbitrary {3}] 0]
assert {[dict get $unverified verified] == 0}
proc build_error {candidate} {error "resource or tool failure"}
assert {[catch {bt::search_minimum 9 build_error}] == 1} "Tool errors must propagate"

foreach size {1 2 3 8 10 16 64 256 512 1024} {
    foreach layout {tail distributed} {
        for {set extra 0} {$extra < 60} {incr extra} {
            set g [bt::geometry $size 64 $extra $layout]
            assert {[llength [dict get $g cuts]] == [dict get $g internal]}
            assert {[dict get $g internal]+[dict get $g tail] == $extra}
            assert {[dict get $g latency] == $extra+2}
            set gaps {}
            set last 0
            foreach cut [concat [dict get $g cuts] [list [dict get $g levels]]] {
                lappend gaps [expr {$cut-$last}]
                set last $cut
            }
            set ordered [lsort -integer $gaps]
            assert {[lindex $ordered end]-[lindex $ordered 0] <= 1 || $layout eq "tail"}
        }
    }
}
set g [bt::geometry 1024 64 54 distributed]
assert {[dict get $g comparators] == 28160}
assert {[dict get $g levels] == 55}
assert {[dict get $g data_ff_upper_bound] == 3670016}
assert {[catch {bt::geometry 8 64 -1 distributed}] == 1}
assert {[catch {bt::geometry 8 64 1 invalid}] == 1}
puts "PASS: search minima, non-monotonic timing, error propagation, pipeline geometry"
