# Pure Tcl helpers shared by the search driver, Vivado runner, and tests.
namespace eval bt {}

proc bt::geometry {size width extra layout} {
    foreach value [list $size $width] {
        if {![string is integer -strict $value] || $value < 1} {error "size/width must be positive integers"}
    }
    if {![string is integer -strict $extra] || $extra < 0} {error "extra must be a nonnegative integer"}
    if {$layout ni {distributed tail}} {error "layout must be distributed or tail"}
    set padded 1
    set log 0
    while {$padded < $size} {set padded [expr {$padded * 2}]; incr log}
    set levels [expr {$log * ($log+1) / 2}]
    set internal 0
    if {$layout eq "distributed"} {set internal [expr {min($extra,max(0,$levels-1))}]}
    set cuts {}
    for {set level 1} {$level < $levels} {incr level} {
        if {($level*($internal+1)/$levels) != (($level-1)*($internal+1)/$levels)} {lappend cuts $level}
    }
    return [dict create size $size width $width padded $padded levels $levels \
        comparators [expr {$padded*$levels/2}] extra $extra internal $internal \
        tail [expr {$extra-$internal}] latency [expr {$extra+2}] cuts $cuts \
        data_ff_upper_bound [expr {$padded*$width*(1+$internal)+$size*$width*(1+$extra-$internal)}]]
}

proc bt::options {defaults args} {
    if {[llength $args] % 2} {error "Options must be -name value pairs"}
    foreach {key value} $args {
        if {![dict exists $defaults $key]} {error "Unknown option $key"}
        dict set defaults $key $value
    }
    return $defaults
}

proc bt::csv {channel values} {
    set escaped {}
    foreach value $values {lappend escaped "\"[string map {\" \"\"} $value]\""}
    puts $channel [join $escaped ,]
    flush $channel
}

# callback receives an integer and must return 0/1, or throw for tool errors.
# Timing can be non-monotonic. Verify all smaller candidates before certifying
# a minimum; if the largest fails, verification scans the remaining domain.
proc bt::evaluate {callback candidate cache_name} {
    upvar 1 $cache_name cache
    if {![dict exists $cache $candidate]} {
        set passed [{*}$callback $candidate]
        if {$passed ni {0 1}} {error "Candidate callback must return 0 or 1"}
        dict set cache $candidate $passed
    }
    return [dict get $cache $candidate]
}

proc bt::search_minimum {max_extra callback {verify 1}} {
    if {![string is integer -strict $max_extra] || $max_extra < 0} {error "Invalid maximum"}
    set cache [dict create]
    set best -1
    if {[bt::evaluate $callback 0 cache]} {return [dict create best 0 verified 1 tested $cache]}
    # Grow the budget first, avoiding an unnecessarily huge first build.
    set last_fail 0
    set high 1
    while {$max_extra > 0} {
        set high [expr {min($high,$max_extra)}]
        if {[bt::evaluate $callback $high cache]} {set best $high; break}
        set last_fail $high
        if {$high == $max_extra} {break}
        set high [expr {$high*2}]
    }
    if {$best >= 0} {
        set low [expr {$last_fail+1}]
        while {$low < $high} {
            set candidate [expr {($low+$high)/2}]
            if {[bt::evaluate $callback $candidate cache]} {set best $candidate; set high $candidate} \
            else {set low [expr {$candidate+1}]}
        }
    }
    if {$verify} {
        set limit [expr {$best >= 0 ? $best : $max_extra+1}]
        for {set candidate 1} {$candidate < $limit} {incr candidate} {
            if {[bt::evaluate $callback $candidate cache]} {set best $candidate; break}
        }
    }
    return [dict create best $best verified [expr {$verify ? 1 : 0}] tested $cache]
}
