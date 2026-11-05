#!/bin/sh
# Table of tail + retiming results: sh scripts/tail_table.sh
printf "%-5s %-6s %-7s %-8s %-9s %-6s %-7s %-6s %-6s\n" size banks retime latency WNS_ns Fmax WHS_ns LUT FF
for f in build/v80-s*-tail-*/result.tcl; do
  case "$f" in *noretime*) r=OFF ;; *) r=ON ;; esac
  tr -d '{}' < "$f" | awk -v r="$r" '{for(i=1;i<NF;i++) v[$i]=$(i+1)
    printf "%-5s %-6s %-7s %-8s %-9s %-6.0f %-7s %-6s %-6s\n", v["size"], v["extra"], r, v["latency"],
      v["setup_slack_ns"], 1000/(v["period_ns"]-v["setup_slack_ns"]), v["hold_slack_ns"], v["lut"], v["ff"]}'
done | sort -n -k1,1 -k3,3r -k2,2n
