# Hierarchical Bitonic Sorter (RTL/Verilog)

Hierarchical 4-input and 8-input bitonic sorting networks in synthesizable
Verilog. The value width and sort direction are configurable.

## Structure

- `rtl/bitonic_sort4.v` - four-input sorter
- `rtl/bitonic_sort8.v` - eight-input sorter built from two four-input sorters
- `rtl/modules/` - reusable compare-and-swap and merge blocks
- `tb/bitonic_sorter_tb.v` - self-checking randomized testbench

```text
bitonic_sort8
|- bitonic_sort4 (ascending)
|- bitonic_sort4 (descending)
`- bitonic_merge8
   |- four compare_swap cells
   `- two bitonic_merge4 blocks
```

The hierarchy is intentionally preserved for experiments that compile, cache,
relocate, and reuse placed-and-routed modules when constructing larger sorters.

## Simulation

Install Icarus Verilog, then run:

```sh
iverilog -g2012 -s bitonic_sorter_tb -o sorter_tb \
  rtl/modules/compare_swap.v \
  rtl/modules/bitonic_merge4.v \
  rtl/modules/bitonic_merge8.v \
  rtl/bitonic_sort4.v \
  rtl/bitonic_sort8.v \
  tb/bitonic_sorter_tb.v
vvp sorter_tb
```

## Scaling experiment

The proposed physical-design tool treats bitonic sorting as a recursive
construction:

```text
Sorter(N) = Sorter(N/2, up) + Sorter(N/2, down) + Merge(N)
Merge(N)  = CompareStage(N/2) + two Merge(N/2) blocks
```

For example, a 16-input implementation would reuse two cached, timing-closed
8-input sorter modules and add only the new 16-input merge level. The tool would
place compatible physical templates, route their boundaries, repair timing if
needed, and cache the completed 16-input sorter for the next scaling step.

The intended evaluation compares flat Vivado builds with this hierarchical flow
for 4, 8, 16, and 32 inputs. Metrics include compile time, reused-route
percentage, maximum frequency, resource use, and routing congestion.
