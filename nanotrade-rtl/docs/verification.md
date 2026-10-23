# Verification

## Primary flow: cocotb + Verilator

Install system Verilator, Python and C++ toolchain, then `pip install -r requirements.txt`. `make test` invokes pytest, which builds and runs two independent cocotb simulations.

- `tests/cocotb_core.py`: directed checks for the current stateful quote-to-order core (configuration, gap/recover, quota, wraparound and stall handling).
- `tests/cocotb_v2.py`: directed elastic-buffer checks and randomized scoreboard. Python holds pending quotes stable while stalled and models the output as a one-entry queue.
- `tests/runner_test.py`: cocotb 2.x Python runner configuration using Verilator.

Run: `make test`, `make lint`, or `make random` (V2 suite).

Legacy SystemVerilog `tb/` and older `scripts/random_diff.py` have been retained for historical reference only; CI no longer runs them.

## Limitations

Functional simulation is not formal completeness, CDC verification, timing closure, safety certification or exchange-protocol interoperability. SVA is optional inside the RTL, not enabled by the default cocotb run.
