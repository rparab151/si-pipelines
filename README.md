# si-pipelines

A collection of RTL projects and hardware-architecture notes, mostly around latency, buffering, and moving data without surprises.

## Writing

### [A FIFO That Can't Say No: Six Ways to Deal With One SRAM Port](sync-fifo-1rw-sram/README.md)

What happens when writes can't be backpressured, the reader can stall, and the only SRAM has one shared read/write port? I work through the simple solution first, then staging, banking, double pumping, and 128-bit packing. There's also a [closer look at the cycle-level schedules and the edge cases](sync-fifo-1rw-sram/prefetch-staging-packing.md).

## Projects

### [NanoTrade RTL — quote-to-order datapath](nanotrade-rtl/README.md)

A synthesizable SystemVerilog project for exploring low-latency trading pipelines. It includes parallel comparisons, elastic buffering, sequence-gap handling, order-intent gating, and directed/randomized verification. This is an educational RTL design, not a live trading system.

### On the list

- **UDP packet parser:** Streaming packet parsing and cycle-by-cycle latency.
- **AXI-Stream FIFO:** Flow control, backpressure and timing-aware implementations.

## What I focus on

Cycle-level behavior, memory and pipeline trade-offs, timing closure, and the less obvious corner cases that show up when an architecture turns into RTL.

The hardware examples are design exercises; I don't present timing or PPA numbers unless they have actually been measured.

## Tooling

SystemVerilog, Python, cocotb and FPGA/ASIC implementation tools as appropriate to each project.
