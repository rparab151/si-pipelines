.PHONY: test random lint clean help
PYTHON ?= python3

help:
	@echo 'make test    - run cocotb directed + randomized tests on Verilator'
	@echo 'make random  - run the cocotb V2 randomized test (same suite as make test)'
	@echo 'make lint    - lint both RTL modules using Verilator'
	@echo 'make clean   - remove build output'

test:
	$(PYTHON) -m pytest -s tests/runner_test.py

random:
	$(PYTHON) -m pytest -s tests/runner_test.py -k nanotrade_v2

lint:
	verilator --lint-only -Wall -Wno-fatal --top-module nanotrade rtl/nanotrade.sv
	verilator --lint-only -Wall -Wno-fatal --top-module nanotrade_v2 rtl/nanotrade_v2.sv

clean:
	rm -rf build/
