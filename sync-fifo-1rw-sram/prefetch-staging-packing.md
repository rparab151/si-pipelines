# A Closer Look at Prefetching, Staging and a 1RW SRAM

[Back to the FIFO article](README.md)

The main post asks whether a FIFO with one 1RW SRAM can keep up with a producer and consumer running every clock. This page is the scratchpad behind that question: where the memory accesses go, what prefetching actually buys us, and which small timing assumptions can break an apparently perfect schedule.

I'll use a 64-bit FIFO interface at 1 GHz. The producer has no backpressure signal, the consumer can pause temporarily, and the SRAM read is assumed to return data with one cycle of latency. A real macro's latency and read-during-write rules must replace those assumptions before RTL.

## First separate *latency* from *bandwidth*

These are two different problems, even though they show up in the same FIFO waveform.

An output prefetch register solves a latency problem. If I know the consumer will need word X, I can fetch X before `rd_ready` asks for it. When the consumer is ready, the data is already sitting in a flop.

An input staging register solves a short-term contention problem. If the port is reading this cycle, I can hold the arriving write until the SRAM is free.

Neither change makes the SRAM capable of two operations at once.

For an entry that is both written to and read from a conventional 64-bit 1RW SRAM, the total memory work is:

```text
one SRAM write + one SRAM read = two SRAM accesses / FIFO entry
```

If we need a write and a read every cycle forever, this port is short by a factor of two. A thousand staging registers would merely allow a longer interval before the bookkeeping catches up with us.

There is a caveat: an empty-FIFO bypass may forward an entry without touching SRAM at all. That's a useful optimization, especially for very small occupancies. It doesn't solve the case where a large backlog is resident in the array.

## Following a staged 64-bit FIFO for a few cycles

Say there are old words in SRAM and the output prefetch register currently holds `X`. New writes keep coming.

| Cycle | Producer | SRAM slot | Output side |
|---|---|---|---|
| 0 | A arrives | Write A | Deliver prefetched X |
| 1 | B arrives | Read old Y | Output register needs refill |
| 2 | C arrives | Write B | Deliver Y (after SRAM response) |
| 3 | D arrives | Read old Z | Refill again |

Already, C and D need room in an input stage, and we are doing only two SRAM writes in four cycles. With a sufficiently deep and continuously occupied FIFO, the input backlog grows if everything must be committed to SRAM; if we stop reading to catch up on writes, the output side runs dry instead.

I still like this organization for bursty traffic. It makes sense when the *average* request rate leaves SRAM idle slots and the staging depth is derived from the worst burst. It just isn't a sustained full-rate solution for SRAM-resident words.

## Widen the word, not the clock

Now replace the 64-bit SRAM with a 128-bit one while keeping the external word width at 64 bits.

Two consecutive input entries `A` and `B` form a single SRAM word `{B,A}`. Fetching that word later gives us two output entries, `A` followed by `B`. We trade one port access for two logical transfers.

For packing factor `k = SRAM_width / FIFO_entry_width`, a word flowing through SRAM consumes `1/k` writes and `1/k` reads, on average. For balanced steady-state rate `r` entries per clock:

```text
SRAM ops per clock = 2r / k

64-bit SRAM:   k = 1  -> r <= 0.5
128-bit SRAM:  k = 2  -> r <= 1.0
```

This is a **necessary bandwidth bound**, not a sufficient proof of an implementation. The scheduler still has to provide data on the right edge.

### One possible steady-state schedule

Assume an older output pair `X0/X1` has already been prefetched. The input packer holds `A/B`. Additional *older* pairs `Y0/Y1` and `Z0/Z1` are in SRAM. A registered read requested in cycle N is available for use in cycle N+1. The table describes a pipelined schedule with an appropriate SRAM read-response/output arrangement.

| Cycle | SRAM access | Input accepted | Output accepted |
|---|---|---|---|
| 0 | Write A/B | C | X0 |
| 1 | Read Y0/Y1 | D | X1 |
| 2 | Write C/D | E | Y0 |
| 3 | Read Z0/Z1 | F | Y1 |
| 4 | Write E/F | G | Z0 |
| 5 | Read next old pair | H | Z1 |

This is the appealing part: once the pipeline is warm, each side transfers **one 64-bit entry every cycle**, and the SRAM does precisely **one 128-bit operation every cycle**.

Notice that the words being written are younger than the words being read. No newer word can jump ahead just because it happens to be in the input packer.

Also notice what the schedule leaves us: zero spare SRAM slots. The next problem is what to do when reality stops looking like this table.

## The cases I'd draw out before writing RTL

### Only one 64-bit entry is waiting in the packer

Suppose A arrives and then the producer goes quiet. A isn't a complete 128-bit word, but the consumer may be waiting for it.

We can retain A in a one-entry valid tail and bypass it when no older data exists. Or we can commit a partially valid 128-bit word using a write mask and/or explicit lane-valid state, if the macro and layout allow it. In either case, the second lane must not accidentally become a valid FIFO entry.

This case is easy to overlook if the first test always writes an even number of entries.

### The reader stalls just as a read returns

Say the output buffer already has an unconsumed pair. A previously issued SRAM read is also returning. If there's nowhere to store the response, we've lost data or overwritten the oldest entry.

The controller needs to reserve response space *at the time it issues the read*, not merely check whether space exists when it comes back. Depending on the macro and staging scheme, this may mean a separate read-response register in addition to the two-entry output buffer.

When `rd_valid && !rd_ready`, the oldest word presented to the consumer has to stay stable.

### SRAM becomes empty while the input packer isn't

This is where the bypass matters. If the only remaining entry lives in a partial packer, it should not have to wait for a second entry before the consumer can read it.

But "SRAM empty" isn't always enough: perhaps an older word is still in the read-return pipeline or output register. The bypass arbiter must look at **logical age**, not just whether the SRAM's stored-word count happens to be zero.

### The reader stalls for eight clocks

A continuously writing producer adds eight entries to the FIFO during an eight-cycle stall. The buffer must have that headroom before the stall begins, including any reservations for outstanding reads and pending writes.

When the consumer resumes at one entry/cycle while the producer continues at one entry/cycle, the backlog **does not shrink**. Occupancy stays at the elevated level. So an eight-cycle stall bound alone isn't enough: the traffic contract also needs opportunities to drain the accumulated entries, or extra service capacity.

### Occupancy bookkeeping crosses storage boundaries

It's tempting to use the SRAM read pointer as the FIFO's dequeue pointer. That is wrong once we prefetch. A word read out of SRAM but waiting in an output register is still logically in the FIFO.

I would track global logical occupancy from external enqueues and accepted dequeues, and separately track what's valid in the packer, SRAM, response path and output stage. A transfer between those storage locations must never look like a second enqueue or dequeue.

## Banking deserves its own trap

Two 64-bit 1RW banks offer two physical operations per system cycle, but only when the operations target different banks.

With simple even/odd interleaving, read and write pointers separated by an **even** occupancy have matching parity. Both can select bank 0 in the same cycle. If you keep accepting and producing one word each cycle, occupancy stays even and the same conflict may persist.

This is the first test I would write for a banked version: not just "does bank 0 read while bank 1 writes?", but "what if both pointers demand bank 0 ten cycles in a row?"

Bank conflict avoidance needs a convincing schedule, buffering argument, or mapping scheme. Counting two ports on a slide isn't sufficient.

## Double pumping moves the problem into timing closure

Two 64-bit SRAM operations per system clock also meet the arithmetic. If the interface runs at 1 GHz, though, the memory has to operate at 2 GHz.

That means checking the macro's **minimum cycle time**, not confusing it with read access delay. There is also the wrapper: address/data selection, capture of the read response, clock phase and duty cycle, setup/hold margins and clock power.

Compared with a 128-bit SRAM, double pumping avoids half-full words. Compared with two banks, it avoids same-bank arbitration. But it only looks simple until someone asks whether the memory compiler actually provides a macro that closes at 2 GHz in this corner.

## The comparison I would make

| Design | Where the extra effective throughput comes from | Limitation |
|---|---|---|
| Input staging + output prefetch on 64-bit 1RW | It doesn't add port throughput; it hides temporary conflicts | Buffer backlog if sustained SRAM traffic needs 1R+1W |
| 128-bit 1RW with pack/unpack | Two 64-bit entries per SRAM operation | Pairing, partial words, prefetch timing, no idle port slots |
| Two 64-bit 1RW banks | Two independent physical ports | Same-bank read/write conflicts |
| 64-bit 1RW at 2× clock | Two port cycles per interface cycle | SRAM frequency, power and wrapper timing |

If I were choosing a direction for RTL, I would first get an actual SRAM macro specification and a precise traffic envelope. Then I would do a cycle-by-cycle schedule for **full-rate traffic, a stalled reader, a lone odd entry, and a nearly full FIFO**. Only after those work would I spend time comparing synthesized area or power.

That is the distinction I care about: a diagram that seems capable of one read and one write per cycle, versus an implementation that can demonstrate exactly where both transactions go.
