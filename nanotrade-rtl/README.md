# NanoTrade RTL ⚡

**A tiny, reproducible, latency-first SystemVerilog quote-to-order decision engine, designed as a public FPGA/ASIC engineering portfolio project.**

> **Scope:** Educational microarchitecture prototype, not a real trading engine.
> It consumes *normalized, atomic* top-of-book quotes; it does not parse real Ethernet/exchange feeds or transmit exchange orders.

## Key ideas

- **One registered edge** from accepting an actionable quote to an asserted order output; up to **one quote per cycle** when the sink remains ready.
- **Latency-first fast path:** two parallel price comparators, with thresholds precomputed off the quote path.
- **Backpressure correctness:** a single-entry elastic output stage supporting same-edge consumption and replacement.
- **Fail-closed sequence tracking:** sticky sequence-gap fault, explicit recovery, and 32-bit sequence wrap.
- **Safety guard:** configurable quota, enable gating, zero-quantity and crossed-market filtering.
- **Reproducible verification:** directed SystemVerilog tests and randomized RTL-vs-Python differential testing.

## Architecture

```text
 Normalized L1 quote (seq, bid, ask, qty)
             |
        valid/ready
             |
       sequence guard <--- recover_next_seq
             |
   +---------+---------+
   |                   |
 ask < buy_below    bid > sell_above   <- configured thresholds
   |                   |
   +----risk/quota-----+
             |
       1-slot order buffer
             |
     BUY/SELL intent + ready
```

## Quick start

```bash
sudo apt-get install iverilog
cd nanotrade-rtl
make test
make random
```

The CI job in `../.github/workflows/nanotrade-ci.yml` runs these tests automatically.

## Design contract

| Feature | Implementation |
|---|---|
| Market input | Atomic normalized single-symbol L1 quote |
| Prices | 32-bit unsigned integer ticks |
| Order | One-lot intent; not an exchange order or fill |
| Latency | Order appears immediately after the accepting clock edge |
| Throughput | Up to one actionable quote/order intent per cycle with always-ready consumer |
| Output buffering | One-entry elastic valid/ready register |
| Recovery | Sticky sequence gap; explicit resynchronization |
| Quota | Generated intents per configuration epoch |
| Measured FPGA/ASIC timing or area | **Not yet measured** |

Read [microarchitecture](docs/microarchitecture.md) and [verification](docs/verification.md).

This is an original educational example; no employer-specific proprietary design or datasets are included. MIT license.
