IVERILOG ?= iverilog
VVP ?= vvp
TCLSH ?= tclsh

RTL := rtl/modules/compare_swap.v \
       rtl/modules/bitonic_merge4.v rtl/modules/bitonic_merge8.v \
       rtl/bitonic_sort4.v rtl/bitonic_sort8.v \
       rtl/modules/bitonic_merge.sv rtl/modules/bitonic_sort_power2.sv \
       rtl/bitonic_sort.sv rtl/bitonic_top.sv \
       rtl/bitonic_sort_pipeline.sv rtl/bitonic_timing_top.sv

.PHONY: test test-legacy test-dynamic test-pipeline test-scale test-search

test: test-legacy test-dynamic test-pipeline test-search test-scale

build:
	mkdir -p build

test-legacy: | build
	$(IVERILOG) -g2012 -Wall -s bitonic_sorter_tb -o build/legacy $(RTL) tb/bitonic_sorter_tb.v
	$(VVP) build/legacy

test-dynamic: | build
	$(IVERILOG) -g2012 -Wall -s bitonic_sort_dynamic_tb -o build/dynamic $(RTL) tb/bitonic_sort_dynamic_tb.sv
	$(VVP) build/dynamic

test-pipeline: | build
	$(IVERILOG) -g2012 -Wall -s bitonic_pipeline_tb -o build/pipeline $(RTL) tb/bitonic_pipeline_tb.sv
	$(VVP) build/pipeline

test-scale: | build
	$(IVERILOG) -g2012 -Wall -s bitonic_scale_tb -o build/scale $(RTL) tb/bitonic_pipeline_tb.sv
	$(VVP) build/scale

test-search:
	$(TCLSH) tests/timing_search_test.tcl
	$(TCLSH) tests/timing_driver_test.tcl
