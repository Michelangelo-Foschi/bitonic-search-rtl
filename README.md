# Parameterized Hierarchical Bitonic Sorter

`bitonic_sort` sorts an array of `SIZE` unsigned values, each `WIDTH` bits wide.
Set `SIZE` to any positive input count; the generated hardware scales
automatically. `ASCENDING=1` puts the smallest value at `out[0]`, while
`ASCENDING=0` puts the largest value there. Duplicates are supported.

```systemverilog
localparam integer WIDTH = 16;
localparam integer SIZE = 10;

logic [WIDTH-1:0] in [SIZE-1:0];
wire  [WIDTH-1:0] out [SIZE-1:0];

bitonic_sort #(
    .WIDTH(WIDTH),
    .SIZE(SIZE),
    .ASCENDING(1'b1)
) sorter (
    .in(in),
    .out(out)
);
```

`SIZE`, `WIDTH`, and direction are fixed at elaboration/synthesis time. Setting
`SIZE=32` creates a 32-input circuit on the next build; a running FPGA does not
resize itself when more values arrive. A runtime-variable length would need a
separate interface and hardware design.

The current sorter is combinational: there is no clock, reset, valid signal,
or pipeline register. Outputs settle after propagation through the network.
It sorts values only; signed comparison, indices, and top-k pruning are not
implemented yet. Compile the `.sv` files in SystemVerilog mode.

## Arbitrary sizes

The recursive network uses powers of two internally. Other sizes are padded
to the next power of two and the extra output lanes are discarded:

| Requested SIZE | Internal lanes |
| --- | --- |
| 1 | 1 (pass-through) |
| 4 | 4 |
| 5 | 8 |
| 8 | 8 |
| 10 | 16 |
| 17 | 32 |

Padding uses the maximum unsigned value for ascending order and zero for
descending order, so padding ends up after the retained values. Matching input
values at those extremes remain correct because only values are returned.
For padded size `P`, the full sorting network has `log2(P)*(log2(P)+1)/2`
comparator levels. FPGA capacity and timing still limit practical sizes.

## Structure

- `rtl/bitonic_sort.sv` - public array interface, parameters and padding
- `rtl/modules/bitonic_sort_power2.sv` - recursive power-of-two sorter
- `rtl/modules/bitonic_merge.sv` - recursive power-of-two bitonic merger
- `rtl/modules/compare_swap.v` - reusable unsigned comparator
- `rtl/bitonic_sort4.v`, `rtl/bitonic_sort8.v` - original scalar-port designs,
  retained for compatibility
- `rtl/modules/bitonic_merge1.v` - teammate's standalone `merge1` module
- `tb/` - fixed-size and parameterized regression testbenches

```text
bitonic_sort (SIZE=8)
`- bitonic_sort_power2 (SIZE=8)
   |- bitonic_sort_power2 (SIZE=4, ascending)
   |- bitonic_sort_power2 (SIZE=4, descending)
   `- bitonic_merge (SIZE=8)
      |- four compare_swap cells
      |- bitonic_merge (SIZE=4)
      `- bitonic_merge (SIZE=4)
```

Generate-time recursion stops at a two-input comparator. Hierarchy attributes
identify candidate block boundaries for future physical reuse. These are
synthesis hints; they do not by themselves lock placement or routing.

## Simulation

Install Icarus Verilog 13.0 or newer and run from the repository root:

```sh
make test
```

Older Icarus releases can fail to elaborate a one-element unpacked array port
(`SIZE=1`). CI builds the pinned 13.0 release so that this case is also tested.

The tests compare every output against an independent reference sort in both
directions. Coverage includes sizes 1, 2, 3, 4, 5, 7, 8, 9, 10, 16, 17, 32,
and 64; widths 1, 4, 8, 16, and 40; duplicates; all-zero/all-maximum vectors;
sorted/reversed inputs; exhaustive binary inputs for small networks; every
combination of four four-bit values; and randomized vectors. The original
4- and 8-input regression also runs. Any mismatch fails the simulation.

## Scaling with physical templates (proposed next step)

This change implements automatic RTL generation through parameter elaboration.
RapidWright integration, placement, routing, and a physical-template cache are
future work. The recursive RTL gives that tool a construction rule:

```text
Sorter(N, direction) = Sorter(N/2, direction)
                     + Sorter(N/2, opposite direction) + Merge(N, direction)
Merge(N, direction)  = N/2 comparators + two Merge(N/2, direction) blocks
```

For a 16-input implementation, the tool would:

1. Load cached ascending and descending 8-input physical sorter templates.
2. Relocate them into legal, non-overlapping FPGA regions with compatible
   resources and routing. Logical array indices do not fix physical locations.
3. Construct the 16-input merge from eight comparators and two cached 8-input
   merge blocks. A merge expects bitonic inputs; it cannot replace a sorter.
4. Route new boundaries, check timing and routing legality, and repair as needed.
5. Cache the validated larger implementation for a later 32-input build.

Cache keys need at least module type, size, width, direction, timing constraints,
pipeline configuration, device and tool versions, RTL identity, and physical
resource pattern. Different widths or directions may need separate compiled
templates. Physical scaling still depends on boundary routing and legal region
availability; RTL recursion alone does not establish a compile-time speedup.

The intended evaluation compares flat Vivado builds with this hierarchical flow
for 4, 8, 16, and 32 inputs. Include template generation cost and compare cold
and cached builds. Metrics include compile time, reused-route percentage,
timing, resource use, and routing congestion. Add a defined register/pipeline
and timing-constraint scheme before reporting clock-frequency results.
