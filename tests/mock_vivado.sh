#!/usr/bin/env sh
# Test fixture only: never used by the actual timing-search invocation.
exec tclsh "$(dirname "$0")/mock_vivado.tcl" "$@"
