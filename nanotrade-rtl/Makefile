.PHONY: test lint random clean help
BUILD := build

help:
	@echo 'make test  - run SystemVerilog self-checking tests with Icarus'
	@echo 'make lint  - run Verilator lint (if installed)'

$(BUILD):
	mkdir -p $(BUILD)

test: | $(BUILD)
	iverilog -g2012 -s tb_nanotrade -o $(BUILD)/sim.vvp rtl/nanotrade.sv tb/tb_nanotrade.sv
	vvp $(BUILD)/sim.vvp

random:
	python3 scripts/random_diff.py

lint:
	verilator --lint-only --timing -Wall -Wno-fatal --top-module nanotrade rtl/nanotrade.sv

clean:
	rm -rf $(BUILD)
