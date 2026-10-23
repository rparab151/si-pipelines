# NanoTrade RTL ⚡

**Low-latency streaming microarchitecture and cocotb verification study in SystemVerilog.**

> Educational RTL experiments, not live trading software. Quotes are already normalized atomic top-of-book snapshots. No proprietary employer IP.

## Versions

- [Stateful core](rtl/nanotrade.sv): sequence-gap detection, explicit recovery, configurable intent quota, registered one-entry output.
- [V2 elastic-buffer study](rtl/nanotrade_v2.sv): isolates one-entry buffering, selective non-trade bypass, and same-edge dequeue/enqueue. This learning module accepts external `feed_ok` and `risk_ok` guards; it does **not** include the stateful core's sequence-gap or quota tracking.

The planned **V1 combinational bypass** and **V3 two-slot skid buffering** remain design exercises; do not confuse them with implemented modules.

## Verification: cocotb + Verilator

Install Python 3, Verilator, a C++ compiler, and make. Then:

```bash
cd nanotrade-rtl
python3 -m pip install -r requirements.txt
make test
make lint
```

`make test` invokes pytest's [cocotb runner](tests/runner_test.py) and Verilator to simulate **both** cores. The Python [V2 tests](tests/cocotb_v2.py) check:

- Accepting an order into an empty register
- Non-trade quote bypass with an outstanding stalled order
- No overwrite while stalled, and simultaneous retirement/replacement
- Consecutive orders at one per cycle
- Seeded randomized scoreboarding across backpressure, price thresholds and risk changes

The [stateful core test](tests/cocotb_core.py) checks sequence gaps, recovery, quota, zero-quantity and crossed-market cases. GitHub Actions uses the same `make test` command.

**Simulator clarification:** cocotb is the verification framework; Verilator executes the SystemVerilog. The earlier `tb/` and `scripts/random_diff.py` files are legacy examples not run by the default target.

## Architecture

```text
 normalized quote (seq, bid, ask, qty)
                 |
            trade decision
           /              \
         BUY              SELL
           \              /
              risk guard
                 |
        one-entry order register
                 |
         valid/ready consumer
```

In V2, `quote_ready = !order_valid || order_ready || !trade_hit`. Therefore a non-trading quote can be accepted while an older order remains stalled. An order is visible after its accepting edge and transfers at a later edge when `order_ready` is asserted.

## Measurement status

Correct cycle semantics and RTL verification are the initial goals. No measured ASIC/FPGAs Fmax, PPA, or post-route latency figures are claimed.

[Microarchitecture](docs/microarchitecture.md) · [Verification notes](docs/verification.md) · [MIT license](LICENSE)
