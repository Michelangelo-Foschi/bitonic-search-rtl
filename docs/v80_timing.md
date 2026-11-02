# V80 retiming and pipeline search at 500 MHz

The requested initial experiment targets **1,024 inputs of eight bytes each**:
`SIZE=1024`, `WIDTH=64`. Default part: `xcv80-lsva4737-2MHP-e-S`.
Default clock: **500 MHz / 2.000 ns**, with 0.100 ns clock uncertainty and
0.200 ns maximum input/output interface delays. All are configurable.

These scripts implement and time an **out-of-context FPGA IP block**, not a
complete V80 platform or board image. The 65,536-bit input and output buses
connect to internal FPGA logic; they are not assigned to physical card pins.
PCIe, HBM, the platform shell, clock generation, and deployment are separate.
The full core would request 4.096 TB/s of input at one vector per 500 MHz cycle;
the parallel interface does not imply the board can supply that bandwidth.

## RTL and register budget

`rtl/bitonic_sort_pipeline.sv` builds the same comparator schedule as the
recursive combinational sorter. `rtl/bitonic_timing_top.sv` packs/unpacks flat
vector ports for timing experiments. The existing `bitonic_top.sv` contributed
by the teammate is retained unchanged.

```systemverilog
bitonic_timing_top #(
    .SIZE(1024), .WIDTH(64),
    .EXTRA_REGS(20), .DISTRIBUTE(1)
) sorter (
    .clk(clk), .rst(rst),
    .in_valid(in_valid), .in_flat(in_flat),
    .out_valid(out_valid), .out_flat(out_flat)
);
```

`EXTRA_REGS` counts **whole-vector register banks**, beyond one mandatory input
bank and one mandatory output bank. It does not count individual flip-flops.
One bank at 1024 x 64 is 65,536 data flip-flops before synthesis/retiming.

| Mode | What the RTL generates |
| --- | --- |
| `DISTRIBUTE=0` / `-layout tail` | All additional banks after the output. Vivado retiming may move registers into the combinational logic. |
| `DISTRIBUTE=1` / `-layout distributed` | Balanced register cuts between comparator levels. Budgets exceeding the available internal boundaries become additional output banks. Vivado can further retime the result. |

For six comparator levels and two additional banks, distributed cuts follow
levels 2 and 4. For 55 levels and 54 additional banks, every comparator level
is followed by a register bank, including the mandatory final output bank.
At zero additional banks, both modes reduce to the registered combinational
core: input bank -> all comparator levels -> output bank.

Appending output banks by itself adds latency and does not shorten the
unretimed comparator path. The tail experiment tests whether the implementation
tool can redistribute those registers. The distributed mode provides explicit
RTL boundaries even when tail retiming is unsuccessful. An aggressive clock
may still require retiming inside comparators or a different architecture.

Data registers have no reset or clock enable, and shift-register extraction is
disabled. This keeps them eligible for retiming. `rst` synchronously clears
the valid pipeline only; ignore output data when `out_valid=0`. There is no
backpressure: a valid input vector can arrive on every rising edge, with bubbles
indicated by `in_valid=0`.

There are `2 + EXTRA_REGS` registered sampling stages. Precisely: a vector
accepted at rising edge **k** appears with `out_valid` at edge
**k + 1 + EXTRA_REGS**. Retiming preserves the external latency. Reset flushes
all in-flight validity; invalid data values remain unspecified.

The retiming implementation deliberately allows full hierarchy flattening.
The original recursive RTL remains available for physical-template research;
locking those boundaries during retiming is a different experiment.

## Running the experiment

Use a machine with licensed Vivado, V80 device support, and enough memory for
large synthesis/routing jobs. Source its `settings64.sh` first. Vivado is not
installed in the development workspace used for this change, so **500 MHz has
not been measured or established** by the local tests.

Plan the default eight-size sweep without launching Vivado:

```sh
tclsh scripts/timing_search.tcl -dry_run 1
```

Start with small sizes to validate your Vivado setup:

In a shell, protect a multi-value `-sizes` argument with quotes:

```sh
tclsh scripts/timing_search.tcl \
  -sizes '8 16 32' -width 64 -mhz 500 \
  -layout distributed -out build/v80-pilot-500
```

Full scaling sweep, sizes 8, 16, 32, 64, 128, 256, 512, 1024:

```sh
tclsh scripts/timing_search.tcl \
  -layout distributed -out build/v80-distributed-500

tclsh scripts/timing_search.tcl \
  -layout tail -out build/v80-tail-500
```

The target part and frequency default to the requested V80 and 500 MHz.
For eight **bits** rather than eight bytes, explicitly pass `-width 8`.
Each `-out` directory must be new: previous experiment outputs are never
overwritten. Each candidate starts a fresh Vivado process. Large sweeps may
take hours and retain substantial checkpoint/log data.

Compile one chosen candidate directly:

```sh
vivado -mode batch -source scripts/run_candidate.tcl -tclargs \
  -size 1024 -width 64 -extra 54 -layout distributed \
  -mhz 500 -out build/v80-1024-extra54
```

Useful search options:

| Option | Default | Meaning |
| --- | --- | --- |
| `-part` | `xcv80-lsva4737-2MHP-e-S` | Exact Vivado part; checked before synthesis. |
| `-mhz` | `500` | Required clock frequency. |
| `-width` | `64` | Unsigned comparison width in bits. |
| `-max_extra` | `auto` | Search up to levels minus one. Override, e.g. `80`, for a larger budget. |
| `-verify_min` | `1` | Check every smaller candidate before reporting a minimum. |
| `-retime` | `1` | Synthesis retiming and post-place `AddRetime`; `0` disables both for comparison. |
| `-margin` | `0.0` | Required setup slack in ns, beyond uncertainty already in the clock constraint. |
| `-uncertainty` | `0.1` | Clock uncertainty in ns. |
| `-io_delay` | `0.2` | Maximum internal-core interface delay budget in ns; minimum is zero. |
| `-threads` | `8` | Vivado maximum threads. |

## Search and pass criteria

1. Try zero additional banks.
2. Increase the budget as 1, 2, 4, 8, ... until a passing build or the cap.
3. Binary-search the resulting interval for an initial candidate.
4. By default, evaluate every smaller count before reporting a minimum. If no
   bracket passes, check untested counts across the bounded domain.

Placement/routing can be non-monotonic, and changing the register count changes
cut locations. Binary search alone cannot prove minimality. `-verify_min 0`
skips exhaustive confirmation and explicitly records an **unverified** result.
The reported minimum applies only to this placement rule, tool/constraints,
device, and measured runs; it is not a globally optimal retiming solution or
the fewest possible individual flip-flops.

Each candidate uses `synth_design -retiming -no_srlextract`, full flattening,
`opt_design`, `place_design -directive Explore`,
`phys_opt_design -directive AddRetime`, and `route_design -directive Explore`.
Disabling retiming uses `-no_retiming` (appropriate for Versal) and ordinary
physical optimization. No false paths or multicycle relaxations hide sorter
paths. This benchmark does not use RapidWright physical-template reuse.

A pass requires complete valid routing, no error-level implementation DRCs,
valid finite timing paths, setup slack >= the requested margin, and hold slack
>= 0. Setup/hold, utilization, route status, DRC, and constraint-check reports
are saved. Final board integration must be timed again with the real clock,
platform, floorplan and interfaces.

Known resource/unroutable candidates are logged as `implementation_fail` and
are infeasible, distinct from `timing_fail`. License/device, script and other
unexpected tool errors are logged as `error` and stop that size's search.
Neither missing reports nor a failed process can become a timing pass. Other
sizes continue so smaller working designs remain available.

The driver exits 0 if all requested sizes have a passing candidate, 1 if some
bounded search has no passing candidate, and 2 on tool/configuration errors.
The summary's `minimum_verified` column states whether minimality was checked.

## Outputs and scale

`trials.csv` records every attempted count, layout, pipeline latency, routed
setup/hold slack, actual LUT/FF cell counts, runtime and result status.
`summary.csv` records the best count per size and minimality verification.
Each trial retains its constraint file, logs, reports, result dictionary, and
available synthesized/routed checkpoints. `config.tcl` records the run options;
each result records the part and Vivado version. Failed candidates have an
`error.txt` with the full Tcl error trace. A winning checkpoint is under
`size_N/extra_K/routed.dcp`.

| Inputs x 64 bits | Comparator levels | Comparators | Maximum auto extra banks |
| --- | --- | --- | --- |
| 8 | 6 | 24 | 5 |
| 64 | 21 | 672 | 20 |
| 256 | 36 | 4,608 | 35 |
| 512 | 45 | 11,520 | 44 |
| 1024 | 55 | 28,160 | 54 |

The full 1024 x 64 distributed pipeline has an RTL data-register upper bound
of **3,670,016 FFs**, plus validity. Synthesis may change this. LUT/FF capacity,
SLR crossings and routing may limit feasibility before the clock target is met.
Adding registers does not guarantee fit or timing closure.

## Verification performed without Vivado

`make test` runs the original combinational regressions, streaming tests for
ascending/descending output, high 64-bit values, duplicate values, non-power-of-
two counts, tail/distributed budgets, bubbles, reset flushing and exact latency.
It includes 512 x 64 and 1024 x 64 simulations. The 1024 case uses 54 additional
distributed banks; simulation confirms functionality, not physical timing.

Pure Tcl tests verify search results across monotonic and non-monotonic timing
fixtures. A separate mock-tool integration test executes the real driver and
runner to check CSV reporting, clock constraints, failure handling, and refusal
to overwrite prior results. Mock numbers are explicitly marked `MOCK_TEST_ONLY`
and are not V80 timing measurements. Tests write artifacts under `build/`.

## Sources

- [AMD V80 device and part](https://xilinx.github.io/amr-docs/docs/3.0.0/V80/index.html)
- [AMD synthesis retiming, Versal defaults, and shift-register extraction](https://docs.amd.com/r/2025.1-English/ug835-vivado-tcl-commands/synth_design)
- [AMD physical optimization and AddRetime](https://docs.amd.com/r/2024.1-English/ug835-vivado-tcl-commands/phys_opt_design)
- [AMD post-place retiming scope](https://docs.amd.com/r/en-US/ug904-vivado-implementation/Retiming)
