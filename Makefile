IVERILOG ?= iverilog
VVP ?= vvp

RTL := rtl/modules/compare_swap.v \
       rtl/modules/bitonic_merge4.v rtl/modules/bitonic_merge8.v \
       rtl/bitonic_sort4.v rtl/bitonic_sort8.v \
       rtl/modules/bitonic_merge.sv rtl/modules/bitonic_sort_power2.sv \
       rtl/bitonic_sort.sv

.PHONY: test test-legacy test-dynamic

test: test-legacy test-dynamic

build:
	mkdir -p build

test-legacy: | build
	$(IVERILOG) -g2012 -Wall -s bitonic_sorter_tb -o build/legacy $(RTL) tb/bitonic_sorter_tb.v
	$(VVP) build/legacy

test-dynamic: | build
	$(IVERILOG) -g2012 -Wall -s bitonic_sort_dynamic_tb -o build/dynamic $(RTL) tb/bitonic_sort_dynamic_tb.sv
	$(VVP) build/dynamic
