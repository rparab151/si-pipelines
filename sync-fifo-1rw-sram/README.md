# Chapter 1 — Synchronous FIFO Using 1RW SRAM

This chapter builds a single-clock FIFO using **one single-port 1RW SRAM**. It sits at the repository root, in parallel with `nanotrade-rtl/`.

## Key constraint

A 1RW macro permits **one read OR one write per cycle**, never both. A conventional FIFO that accesses the array with both a read and write on one edge cannot map to this macro. The design uses read-priority arbitration and a registered output slot. This implementation is deliberately not a fall-through FIFO.

The SRAM contains up to DEPTH words; the output register can store one more, giving a **total logical capacity of DEPTH+1**. Pointers wrap explicitly for non-power-of-two depths.

- Push handshake: `push_valid && push_ready`; pops: `pop_valid && pop_ready`.
- When the output slot is free and SRAM is nonempty, issue an SRAM read and stall pushes for that cycle.
- Otherwise accept a write if SRAM has space.
- Read data is captured on the clock edge and becomes visible through the output register after the edge.
- Backpressure keeps output data stable.
- In sustained steady state, SRAM read and write accesses alternate, limiting balanced push/pop throughput to 0.5 words per clock.
- SRAM contents are intentionally not reset.

```text
 producer -> write gate -> [ single-port 1RW SRAM ] -> read data register -> consumer
                             wr_ptr / rd_ptr
                            occupancy counter
```

## Implementation

[RTL: sync_fifo_1rw.sv](rtl/sync_fifo_1rw.sv)

The SystemVerilog array is a **behavioral model** illustrating the single-port operation. For ASIC use, replace it with a foundry SRAM wrapper matching its exact synchronous-read timing and enable polarity. No verification collateral is included in this chapter.

## Architecture exercises

1. Draw a cycle-accurate waveform showing an empty FIFO receiving three consecutive writes, then continuous reads.
2. Modify the policy to write priority. Analyze starvation, latency, and throughput.
3. Add an empty-FIFO push-to-pop bypass without issuing two SRAM accesses.
4. Compare 1RW, 1R1W, and flop-based FIFOs for sustained one-push/one-pop-per-clock throughput.
5. Discuss whether extra input staging can eliminate bubbles, or only shift them.
