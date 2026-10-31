# Chapter 1 — Synchronous FIFO with a 1RW SRAM

This chapter is a standalone design study alongside `nanotrade-rtl/`. **Writes cannot be backpressured.** The downstream reader may temporarily deassert `rd_ready`. Traffic must obey a bounded burst/stall envelope; no finite FIFO can absorb indefinite writes during indefinite stalls.

## Implementation A — single-clock, write-priority 1RW

A single-port SRAM performs one read **or** write per cycle. Write requests win arbitration. A registered output slot holds prefetched data and remains stable while `rd_ready=0`. Read operations happen only in write-idle cycles when the output slot can accept data. The output slot adds one word of storage beyond the SRAM depth.

The architecture can accept a write on every clock **until its finite capacity is exhausted**. At full occupancy an incoming write is a contract violation; `overflow` reports it (sticky) rather than overwriting old data. A maximum read-stall length by itself is insufficient to guarantee safety: sustained writes can starve reads even after the consumer resumes.

See [single-clock RTL](rtl/fifo_1rw_write_priority.sv).

## Implementation B — double-pumped 1RW, logical 1R1W

Run the SRAM at **2× the system clock** and schedule one write slot and one read slot per system cycle:

```text
clk_sys:    |----------- cycle N -----------|----------- N+1 -----------|
clk_mem:    |----- slot W -----|----- slot R -----|----- W -----|----- R --|
SRAM:       write (if valid)   read (if needed)    write         read
```

A wrapper captures system-clock requests, selects SRAM address/data/control for each fast-clock slot, and returns read data to a system-clock output register. A **registered output/skid stage** is needed to hold data during read stalls; issue reads only when that stage (and any in-flight read response) has space. A bypass for an empty FIFO is optional and must preserve ordering.

**This is a proposed timing architecture, not a drop-in synthesizable dual-clock macro wrapper.** The exact fast-slot phasing, synchronous-read latency, output-register capture edge, and same-address read-after-write semantics depend on the selected SRAM macro. Clock generation, clock-domain/phase constraints, duty cycle, skew, SRAM minimum cycle time, and STA must be specified before implementing a production wrapper. A 1 GHz FIFO clock requires an SRAM capable of a 0.5 ns cycle time (2 GHz), *including* macro cycle-time restrictions; this is not guaranteed by a 0.5 ns access-time specification.

A double-pumped SRAM can perform one physical read and one physical write per system cycle, but the FIFO still needs sufficient capacity for bounded downstream stalls. No output stage can absorb an unbounded stall with continuous writes.

## Comparison

| Property | Single-clock write-priority | Double-pumped 1RW |
| --- | --- | --- |
| SRAM operations/system cycle | 1 total | Up to 1 write + 1 read |
| Continuous write input | Until capacity exhausted | Until capacity exhausted |
| Simultaneous sustained read/write | No | Yes, when consumer ready and timing closes |
| Balanced steady-state SRAM traffic | At most ~0.5 read + ~0.5 write per cycle | Up to 1 read + 1 write per cycle |
| SRAM clock | 1× | 2× |
| Complexity | Arbitration, output register | Slot muxing, fast clock, capture, STA |
| Read stalls | Output valid/data held | Output valid/data held; suppress new reads |

## Sizing exercise

Given a write-arrival sequence `w[t]`, consumer-ready sequence `r[t]`, and scheduler, track logical occupancy:
`q[t+1] = q[t] + accepted_writes[t] - consumed_reads[t]`.
Prove `0 <= q[t] <= capacity` for every cycle of the *worst-case* bounded burst and read-stall envelope. Also account for SRAM scheduling: a ready consumer does not imply a read can be served immediately.

## RTL scope

Only the single-clock implementation is supplied as RTL. The double-pumped implementation is intentionally a **microarchitecture specification** pending selection of a real SRAM macro and its clock/read timing. No verification collateral is included.
