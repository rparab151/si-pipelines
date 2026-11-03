# A FIFO That Can't Say No: Six Ways to Deal With One SRAM Port

I wanted to look at a slightly awkward FIFO problem: the producer can send a word on any clock, but there is no `wr_ready` to tell it to stop. The consumer, meanwhile, can stall for a while.

With flip-flops this is straightforward to reason about. With a 1RW SRAM, not so much. The SRAM will read **or** write on a given clock, but not both. So what happens when a new word arrives at exactly the same time we need to fetch the oldest word?

This post walks through six ways I would approach it, starting with the obvious design and ending with two that can actually change the sustained bandwidth. It is an architecture exercise, not a claim that any particular RTL or macro has been measured.

## First, define what the FIFO promises

Let's use 64-bit entries and a 1 GHz system clock. The producer can supply one entry each cycle. The consumer has `rd_valid/rd_ready` and can pause temporarily. Data must remain in order; dropping a word is not an option.

There is an unavoidable limit here. If writes keep arriving and reads stop forever, *any* finite FIFO fills. Even a short stall is only safe if we know how many free entries we need at its start and whether the traffic eventually gives us a chance to recover. In other words, "no write backpressure" is a contract with the surrounding system, not something a clever SRAM wrapper can magically guarantee.

Assume our starting memory is a 64-bit-wide, single-port 1RW SRAM with a clocked read.

The bandwidth arithmetic is worth doing before drawing an FSM:

- One 64-bit entry at 1 GHz is **8 GB/s**.
- One enqueue **and** one dequeue per cycle is 8 GB/s in each direction.
- If both entries pass through the SRAM, that means **two SRAM accesses per system cycle**.
- Our 1RW SRAM has **one**.

That is the problem we need to design around.

## 1. The simple design: writes win

My first attempt would be deliberately boring: always give an incoming write the SRAM port. When there is no write, use the port to read an old entry into an output register.

```text
producer ---> [ 64-bit 1RW SRAM ] ---> [ output register ] ---> consumer
                       |
                 write has priority
```

This is easy to understand, and for sparse traffic it may be all we need. A read can be prefetched into the output register, and that register holds its contents when `rd_ready` goes low.

The catch shows up under continuous writes. The SRAM is busy every cycle, so it never gets a chance to refill the output register. The consumer might drain a prefetched word, but it cannot keep going. The input will also run out of capacity eventually.

A useful design for low-average-rate traffic, but not a way to deliver continuous reads and writes through one 64-bit port.

## 2. Add a staging register on each side

Now put one register before the SRAM and one after it.

```text
producer --> [ input staging ] --> [ 1RW SRAM ] --> [ output prefetch ] --> consumer
```

This is a surprisingly effective improvement for short conflicts. If the SRAM is reading this cycle, the incoming write can sit in the input register. If the consumer is stalled, the output register keeps the oldest word stable. When the FIFO is empty, we can even bypass the SRAM and send a newly arrived word toward the consumer.

But the input register is not a bottomless queue. If it already holds a pending write, and the SRAM needs another read, where does the next input go? We have merely moved the conflict out by one cycle.

There is also a subtle ordering rule: bypass is legal only when there isn't an older entry waiting in the SRAM, the read pipeline, or the output register. Getting that wrong produces a FIFO that works in an empty test but occasionally returns words out of order.

## 3. Make the staging buffers deeper

The natural next step is to replace those registers with small flop FIFOs.

```text
producer --> [ input flop FIFO ] --> [ 64-bit 1RW SRAM ] --> [ output flop FIFO ] --> consumer
```

Now the SRAM controller has room to choose when it writes and when it prefetches. A burst of writes can accumulate on the left. A burst of reads can be served from prefetched entries on the right.

This is often the sensible engineering choice when *average* bandwidth is low and bursts are bounded. It buys us elasticity, and we can size that elasticity from the arrival and service patterns.

What it doesn't buy is another SRAM access.

Imagine every word must eventually be written to SRAM and later read back. The controller needs two accesses per entry. A 64-bit 1RW port operating once a cycle can support, on average, no more than **half an entry per cycle** for each direction. Increasing the flop FIFO depth delays the problem; it cannot change that long-run limit.

There is an important exception: if traffic is shallow enough to pass through an ordered bypass without ever reaching SRAM, the external interfaces may run faster than the SRAM-resident traffic limit. But we must not mistake that special case for guaranteed bandwidth with a deep backlog.

At this point, I would stop tuning buffer depths and ask a different question: *Can we make the memory do more useful work per cycle?*

## 4. Two SRAM banks: more ports, but watch the addresses

Split the storage into two independent 64-bit 1RW macros and place consecutive entries in alternating banks.

```text
                      +--> [ bank 0: even entries ] --+
producer --> bank mux                                +--> ordered output
                      +--> [ bank 1: odd entries  ] --+
```

A read in bank 0 and a write in bank 1 can happen together. That's a real increase in aggregate port bandwidth.

The interesting failure is when the read and write pointers want the *same* bank.

Suppose the FIFO contains an even number of entries. With straightforward even/odd interleaving, the read pointer and write pointer have the same parity. They both select bank 0, for example. The other bank is free, but it cannot perform either of these accesses. If occupancy stays constant while we enqueue and dequeue, that parity conflict can recur every cycle.

So "two banks" is not automatically equivalent to a 1R1W SRAM. We need a conflict-handling schedule, buffering, or a smarter mapping, and we have to prove what happens at each occupancy—not just under a convenient test case.

## 5. Double-pump the SRAM

Instead of adding another macro, run the one we have at twice the system frequency.

```text
system clock: |------------ cycle N ------------|
SRAM slots:   |       write       |     read     |
```

At a 1 GHz interface, that asks the SRAM and its wrapper to support two accesses in a nanosecond. We could schedule a write in one half and a read in the other, then hold the read result in an output register.

Architecturally this is clean: two slots, two operations, no bank collision. Physically it may be the hardest option here. A "fast read access" number is not enough; the macro's **minimum cycle time** must support the 2 GHz rate. Clock duty cycle, setup/hold at the wrapper, read-return capture, clock power and implementation methodology all matter.

It is worth considering if a suitable macro exists. I would not pick it based on a block diagram alone.

## 6. Widen the SRAM: two entries per access

This is the option I find most interesting. Keep the interface at 64 bits but use a **128-bit 1RW SRAM**.

The input side collects two consecutive 64-bit entries into one 128-bit word. A single SRAM write stores the pair. On the read side, a single SRAM read fetches a pair into an output prefetch buffer, which hands out one 64-bit entry on each of the next two cycles.

```text
64-bit input --> [ pack A,B ] --> [ 128-bit 1RW SRAM ] --> [ unpack/prefetch ] --> 64-bit output
```

This changes the arithmetic:

- One packed write every **two** system cycles accepts two new entries.
- One packed read every **two** system cycles supplies two output entries.
- Together, that is **one SRAM access every system cycle**.

In the ideal steady state, the SRAM alternates write, read, write, read while the outside world enqueues and dequeues on *every* clock. We have the same single shared port, but each operation moves twice as much data.

There is a price. An odd number of writes leaves an incomplete 128-bit word. A consumer stall may leave an entire fetched pair sitting in the output buffer. The controller must never overwrite that pair, and it must never return a newer staged word before an older SRAM word. The SRAM's exact read latency determines how much response buffering we need.

And this schedule runs at 100% of the available port budget. One badly timed bubble or partial-word flush can force extra buffering or cost us throughput. This is not a proof that an arbitrary implementation can run indefinitely without a hiccup.

For a **32-entry logical FIFO**, the SRAM array for this scheme would be **16 words × 128 bits**. Any staging or prefetch registers must be counted carefully when defining the actual usable capacity.

I've written out a [cycle-by-cycle look at prefetch, packing and the corner cases](prefetch-staging-packing.md), including the exact reason one-entry staging does not solve the bandwidth limit.

## So which one would I use?

It depends less on the FIFO depth than on the traffic contract.

| Approach | Why I'd consider it | What would make me nervous |
|---|---|---|
| Write-priority 1RW | Simple, sparse traffic | Continuous writes starve reads |
| One-entry staging + prefetch | Small, short conflicts | The next collision arrives before the first clears |
| Deeper flop staging | Bounded bursts and stalls | Flop cost, and no improvement to SRAM's long-run rate |
| Two banked 1RW macros | Two accesses at once | Repeated same-bank conflicts |
| Double-pumped 1RW | Logical read + write per system clock | Macro timing and 2× clock power |
| 128-bit packed 1RW | Two entries per access without 2× clock | Partial pairs, zero-slack scheduling, response buffers |

For low-average-rate traffic, I would start with staging and prefetch. For a requirement to sustain one enqueue and one dequeue every cycle **through SRAM**, I would investigate packed 128-bit words, double pumping and banking—and make each one survive a cycle-level schedule before comparing area and power.

The thing I would check in every proposal is simple: **where do the read and write operations actually happen on a cycle when both interfaces are busy?** If that question doesn't have an answer, the throughput claim isn't finished.

---

*These are architectural trade-offs, not measured PPA results. The next step would be to specify a real SRAM macro and traffic envelope, then turn the selected scheme into RTL. This chapter is intentionally separate from the [NanoTrade project](../nanotrade-rtl/README.md).*
