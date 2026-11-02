# Chapter 1 — Six FIFO Architectures Using 1RW SRAM

This is an **architecture comparison**, parallel to `nanotrade-rtl/`, not an RTL implementation. No verification or testbenches.

## Problem statement and assumptions

- Single logical FIFO clock, ordered data, finite capacity.
- The producer presents `wr_valid/wr_data` **without a ready handshake**: writes cannot be backpressured.
- The consumer uses `rd_valid/rd_ready`; `rd_ready` may deassert for **temporary, bounded stalls**. The FIFO may insert read-valid bubbles.
- A physical 1RW SRAM supports **one read OR one write per SRAM cycle**.
- The input arrival envelope, maximum stall duration, and required FIFO depth must be specified to prove losslessness. A finite FIFO cannot accept continuous writes forever if reads are stalled indefinitely. A bounded stall alone does not guarantee safety if input writes can permanently outpace service.
- Overflow is a system-level contract violation, not an acceptable normal operating mode.

## Option 1 — Single 1RW SRAM, write-priority arbitration

```text
producer --> [ 1RW SRAM: write wins ] --> [ output register ] --> consumer
```

Incoming writes always take the SRAM port (subject to available capacity). SRAM reads happen only in write-idle cycles; an output register holds read data while the consumer stalls.

**Pros:** Smallest memory/control footprint; simple single-clock timing; no write-side backpressure; easy ordering.

**Cons:** Sustained writes starve reads; cannot sustain 1 write + 1 read per cycle; balanced traffic requiring SRAM accesses is limited to about 0.5 write + 0.5 read per cycle. Requires burst and occupancy guarantees.

**Best for:** Low-average-rate traffic with enough write-idle slots.

## Option 2 — 1RW SRAM with one input and one output staging register

```text
producer --> [ input reg ] --> [ 1RW SRAM ] --> [ output reg ] --> consumer
```

An input register can absorb a short read/write collision. The output register decouples read-ready stalls. A scheduler transfers staged writes to SRAM and prefetches reads, maintaining FIFO order.

**Pros:** Can hide isolated port conflicts; enables empty-FIFO bypass; lowers some interface latency; modest register cost.

**Cons:** One input entry is insufficient for repeated conflicts; sustained bandwidth remains one SRAM operation per cycle; extra valid/occupancy/bypass corner cases. An input register alone does not guarantee a write is accepted when already occupied.

**Best for:** Very short, predictable contention windows.

## Option 3 — Input and output flop FIFOs around one 1RW SRAM

```text
producer --> [ input FIFO ] --> [ 1RW SRAM ] --> [ output FIFO ] --> consumer
```

Multi-entry staging absorbs finite write bursts and read stalls. The controller moves data between stages and maintains global FIFO order (older SRAM entries must drain before younger input entries bypass them).

**Pros:** Better burst elasticity; decouples the external interfaces from SRAM arbitration; configurable staging depths; can temporarily sustain 1 write + 1 read per system cycle using buffered data.

**Cons:** Additional flop area and power; complex scheduling, bypass, and occupancy accounting; long-run SRAM throughput unchanged; cannot absorb unlimited overload.

**Best for:** Bursty traffic with known maximum burst/stall bounds.

## Option 4 — Two banked 1RW SRAMs

```text
                  +--> [ bank 0 ] --+
producer --> bank |                +--> reorder/read output --> consumer
             mux  +--> [ bank 1 ] --+
```

Map successive FIFO entries across two banks (e.g. even/odd). One bank may read while the other writes, provided accesses target different banks.

**Pros:** Potential simultaneous read and write without 2× SRAM clock; aggregate physical port bandwidth increases; can support 1 write + 1 read per cycle under a conflict-free schedule.

**Cons:** Same-bank read/write conflicts remain; interleaving alone does **not** guarantee conflict-free sustained operation; buffering or a conflict-handling schedule may be required; two macros and extra control/routing.

**Best for:** Designs where banking and address/access patterns are favorable.

## Option 5 — Double-pumped 1RW SRAM, logical 1R1W interface

```text
system clock cycle: |--------- N ---------|--------- N+1 ---------|
2x SRAM slots:      | write  | read       | write  | read       |
producer --> [ 1R1W wrapper / phase mux ] --> [ 1RW SRAM @ 2x ] --> output stage --> consumer
```

A 2× SRAM clock schedules one write slot and one read slot per system cycle, emulating a logical 1R1W port. The wrapper must capture commands, multiplex addresses/data, manage in-flight read responses, and retain read output across stalls.

**Pros:** Potential sustained 1 write + 1 read per system cycle using one SRAM macro; avoids bank conflicts; retains single-port macro density.

**Cons:** SRAM must meet **half the system clock period** (e.g. 2 GHz macro for 1 GHz system); extra clock power and clocking complexity; challenging setup/hold, duty-cycle, phase, read-capture, and read-during-write semantics. A macro's read access time alone does not prove its minimum cycle time. The exact wrapper is macro-specific.

**Best for:** A high-throughput FIFO when a suitable fast SRAM macro and clocking methodology are available.

## Option 6 — 128-bit packed 1RW SRAM with input packing and output prefetch

```text
64-bit input --> [pack 2 x 64-bit] --> [128-bit 1RW SRAM] --> [prefetch/unpack] --> 64-bit output
```

A widened SRAM port transfers **two logical FIFO entries per SRAM access**. One packed write every two system cycles and one packed read every two cycles can deliver one 64-bit enqueue plus one 64-bit dequeue each cycle in a sustained, suitably scheduled steady state. For a single 128-bit 1RW port, the ideal access budget is `0.5 packed write + 0.5 packed read = 1 SRAM operation/system cycle`.

**Pros:** Potential full simultaneous 1-entry/cycle input and output without 2x clock or same-bank conflicts; SRAM storage remains dense; a two-entry prefetch buffer hides the synchronous read access.

**Cons:** A partial input pair needs explicit handling; buffer availability and one-cycle read-return timing must be scheduled carefully; a fully loaded alternating schedule has no spare port cycles to recover from bubbles/stalls. A finite FIFO still needs a bounded write/stall traffic envelope and full/overflow proof.

**Best for:** Sustained balanced 64-bit FIFO traffic when a suitable 128-bit-wide SRAM macro is available.

**Deep dive:** [Prefetch, staging, packing, banking and double pumping](prefetch-staging-packing.md) — cycle-level schedules, port-rate proof, partial-pair and stall edge cases, and a focused four-way trade-off comparison.

## Side-by-side comparison

| Option | 1 write + 1 read every system cycle? | Area / power | Timing and control risk | Principal tradeoff |
|---|---|---|---|---|
| 1. Write-priority | No | Lowest | Low | Read starvation |
| 2. One-entry staging | Only brief bursts | Low–moderate | Moderate | Limited elasticity |
| 3. Flop FIFO staging | Temporarily, bounded by buffers | Higher flop cost | Moderate–high | No sustained SRAM bandwidth gain |
| 4. Two banks | Conditional; conflicts must be handled | Two macros | Moderate–high | Bank conflicts |
| 5. Double pump | Potentially yes | One fast macro + wrapper; higher clock power | High | 2× SRAM timing |
| 6. Widened 128-bit pack/prefetch | Potentially yes, with scheduled full-pair traffic | Wider macro + pack/unpack flops | Moderate–high | Partial pairs, prefetch timing and zero port slack |

## Cycle-level questions before choosing

1. What are the maximum consecutive write burst and maximum downstream read-stall duration?
2. What is the required sustained arrival/departure rate and maximum tolerated read latency?
3. Can the SRAM macro operate at 2× system clock, and what is its synchronous-read latency?
4. For banking, can simultaneous reads and writes ever target the same bank?
5. What is the worst-case FIFO occupancy under the actual arrival and service envelopes?
6. Can a wider SRAM port pack consecutive FIFO entries, and what happens with odd-length traffic, empty bypass and stalled read output?

**Selection guideline:** Start with Option 1 for simple low-rate traffic; use Option 3 for bounded burst elasticity; consider Options 4, 5 or 6 when true sustained simultaneous read/write throughput is mandatory. None removes the need for finite-capacity traffic assumptions.
