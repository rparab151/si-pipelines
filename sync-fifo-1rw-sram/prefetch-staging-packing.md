# Prefetch, Staging, Packing, Banking and Double Pumping Around 1RW SRAM

This is an architecture-level companion to [Chapter 1](README.md), not RTL or verification. The design problem is a **single-clock, ordered, lossless FIFO** with an input that cannot be backpressured and an output that may temporarily stall.

## 0. Contract and terminology

- Logical input and output width: **64 bits**, at up to **one entry per system clock** in each direction.
- A conventional 64-bit-wide 1RW SRAM has **one read OR one write port operation per SRAM clock**, not both.
- Unless stated otherwise, the SRAM has a **registered, one-system-cycle read**. Exact request/response edges and read-during-write behavior depend on the selected macro.
- The FIFO has `wr_valid/wr_data` but **no `wr_ready`**; the reader uses `rd_valid/rd_ready`. The producer is allowed to pause, but cannot be throttled by the FIFO.
- Temporary output stalls must be **bounded** and accompanied by a traffic envelope and enough capacity. Even a bounded stall is unsafe if the long-term input rate exceeds service capacity.
- A bypass transfers **only the oldest** logical entry; it must not overtake older entries in SRAM, an SRAM read in flight, or an output prefetch register.
- `enqueue` is accepting a new input. `dequeue` is a `rd_valid && rd_ready` transfer. Moving a word between internal buffers is **neither**.

## 1. The bandwidth bound (why staging is not magic)

Let the SRAM word width be `M` bits, logical FIFO entry width `W` bits, and packing factor `k = M/W` for integer `k`.

For traffic that actually traverses SRAM, one logical entry consumes `1/k` **write** and `1/k` **read** port operations on average. At equal sustained enqueue/dequeue rate `r` entries/system-cycle with one SRAM operation/system-cycle:

`2r/k <= 1`

- **64-bit 1RW, k=1:** `r <= 0.5` entry/cycle for sustained balanced SRAM traffic. Input/output flops can cover only finite conflicts.
- **128-bit 1RW, k=2:** `r <= 1` entry/cycle. Perfect packing/scheduling can meet the throughput target, with **zero average port slack**.
- **Two independent 64-bit 1RW banks:** aggregate two port operations/cycle, but **per-bank conflicts** must still be avoided or hidden.
- **64-bit 1RW at 2x the system frequency:** two SRAM operations/system-cycle, if the macro and wrapper meet timing.

This bound applies to entries which require both an SRAM write and read. For empty/near-empty **bypass traffic** that never touches SRAM, the effective demand is lower; bypass does not rescue an arbitrarily deep backlog.

## 2. Approach A — 64-bit 1RW with input staging and output prefetch

~~~text
64-bit producer -> [input skid FIFO] -> [64-bit 1RW SRAM] -> [read response/output FIFO] -> consumer
                        \______________________________________/
                               ordered empty/near-empty bypass
~~~

**Scheduling:** prioritize compulsory input writes before staging overflows, but issue timely prefetch reads while the output buffer has room. Each SRAM cycle still performs **one** of `WRITE`, `READ` or `IDLE`. An output register hides a one-cycle synchronous-read latency and keeps valid data stable under `rd_ready=0`.

**Example:** when traffic must traverse SRAM, a six-cycle schedule `W, R, W, R, W, R` services only 3 SRAM writes + 3 reads. Six new entries and six output requests cannot all be satisfied indefinitely by that port.

**Good:** low register overhead for one-entry staging; larger flops provide burst/stall elasticity; optional bypass gives excellent empty-FIFO latency.

**Limitations:** one-entry staging only survives short write/read conflicts; no finite number of flops guarantees continuous 1+1/cycle when **every** entry must visit 64-bit 1RW SRAM. The required staging depth comes from the *worst-case* schedule, not the average. The read-data-in-flight slot counts toward total FIFO occupancy.

## 3. Approach B — 128-bit 1RW with packing and two-entry prefetch

~~~text
              two 64-bit entries / word                  two entries / fetched word
64-bit in -> [pack/stage A,B] -> [128-bit 1RW SRAM] -> [read-return + unpack] -> 64-bit out
                   \_________________ ordered bypass ___________________/
~~~

**Core idea:** pair consecutive 64-bit entries into one 128-bit write; fetch a pair with one 128-bit read, then serve the pair over two system cycles.

When the read/write phases align and buffers are prefilled, the port can alternate **one packed write** and **one packed read** per cycle. In a steady interval, a single read or write does **two** logical entries' worth of work.

### Illustrative steady-state timeline

Preconditions: an older pair X0/X1 is already in the output buffer; A/B is a complete incoming write pair; further older pairs Y0/Y1 and Z0/Z1 are resident in SRAM; output is continuously ready. The SRAM read is one-cycle; fetched data is available by the next cycle's output phase. The table is a *pipeline schedule*, not a claim that the output pairs are consecutive in storage to the concurrently written pairs.

| System cycle | 1RW SRAM slot | New input | Output accepted | Buffer work |
|---|---|---|---|---|
| 0 | WRITE packed A/B | C | X0 | Start collecting C |
| 1 | READ packed Y0/Y1 | D | X1 | Finish collecting C/D |
| 2 | WRITE packed C/D | E | Y0 | Capture fetched Y pair; start E |
| 3 | READ packed Z0/Z1 | F | Y1 | Finish E/F |
| 4 | WRITE packed E/F | G | Z0 | Capture fetched Z pair |
| 5 | READ next packed pair | H | Z1 | Continue alternation |

The logical output is in strict FIFO order; the input pairs being written now are **younger** than the already-stored output pairs. An SRAM with a different read pipeline requires rescheduling or a deeper read-return buffer.

**Benefits:** 1 enqueue + 1 dequeue per system cycle is **possible** for sustained balanced, full-pair traffic without a 2x SRAM clock. Denser SRAM storage than flip-flop staging.

**Costs and edge cases:**
- **Odd input count / partial pair:** keep a valid one-entry staging tail, bypass it only when there is no older queued entry, or flush a padded/masked word with explicit valid-lane metadata; a padded word is not automatically a second valid entry.
- **Read stalled after prefetch:** freeze the oldest output; don't overwrite a full output buffer with the next SRAM read response. Continue accepting input only while physical and staging capacity remain.
- **SRAM empty, staging nonempty:** bypass the staged oldest entry if legal; no reason to wait for a packed write followed by a packed read.
- **Full or nearly full FIFO:** physical SRAM word occupancy + uncommitted staged entries + prefetched entries + read responses in flight must all be included in the capacity/reservation calculation.
- **Bubble or misalignment:** exactly 100% utilization in the simple alternating schedule leaves no slot to catch up; deeper staging, lookahead arbitration and/or idle opportunity may be required to survive disturbances.
- **Reads/writes to the same physical address:** macro read/write collision semantics must be defined, even though only one SRAM operation issues per cycle.

**Practical structure:** minimum logical packing is two input lanes and two output lanes, but **read-return timing and arbitration may require separate response and output holding registers**. Do not assume "exactly two flops each side" is a sufficient implementation for every macro.

### Physical capacity example

For **32 logical entries in the SRAM array**, use **16 × 128-bit words** (not 32 × 128). Staging and prefetch registers can add physical storage but **do not silently increase the advertised FIFO capacity** unless the interface contract and full/overflow logic count them.

## 4. Approach C — Two independent 64-bit 1RW banks

~~~text
                      +--> [even-address 1RW bank] --+
producer -> bank map -|                              +-> ordered read/output staging -> consumer
                      +--> [odd-address  1RW bank] --+
~~~

Interleave consecutive entries across bank 0 and bank 1. One bank can perform a read while the other performs a write in the same system cycle. This offers two aggregate accesses, unlike one SRAM macro.

**Critical gotcha:** if both read and write pointers select the **same bank**, that bank sees a conflict, even though the second bank is idle. With naïve even/odd mapping, the difference in bank selection depends on FIFO occupancy parity: an even separation can repeatedly target the same bank while both pointers advance together. Two banks **do not inherently guarantee** steady 1+1/cycle at all occupancies.

**Possible mitigations:** allocate buffered write and read windows, remap/batch addresses, or use banks with different scheduling, but every variant must prove bank conflict freedom or bounded conflict accumulation. Two banks may have worse physical macro overhead and read-mux routing than one widened macro.

## 5. Approach D — Double-pumped 64-bit 1RW SRAM

~~~text
system cycle:  |----------- N -----------|----------- N+1 -----------|
SRAM 2x slots: | WRITE  | READ             | WRITE  | READ             |
external:      1 x 64-bit write + 1 x 64-bit read per system cycle (when valid)
~~~

A wrapper captures logical requests and issues two SRAM operations per system clock, using either a 2x clock or an appropriately engineered clocking scheme. It buffers responses so `rd_valid/rd_ready` remains stable under stalls.

**Benefits:** true potential logical 1R1W service with one 64-bit macro; no even/odd bank conflict and no packing/unpacking alignment.

**Risks:** SRAM minimum cycle time must meet **half** the system cycle plus clock/jitter/margin requirements. A short read-access time alone is insufficient. Check capture edges, duty-cycle asymmetry, hold, clock distribution/power, SRAM setup/hold, read-data phase crossing, and exact vendor macro behavior.

## 6. Comparison and design-selection table

| Approach | SRAM port work/system cycle | Sustained 1 enqueue + 1 dequeue? | Extra buffering/control | Key risk |
|---|---|---|---|---|
| A. 64-bit 1RW + stages/prefetch | 1 × 64-bit access | **Not for continuously SRAM-resident traffic**; bypass may sustain shallow traffic | Small to large flop buffers, read-return handling | Port backlog |
| B. 128-bit packed 1RW + prefetch | 1 × 128-bit access | **Possible** under stable pairing/scheduling | Pair pack/unpack, valid lanes, prefetch and read-response buffer | Zero port slack; partial pairs |
| C. Two 64-bit 1RW banks | Up to 2 × 64-bit, one/bank | **Conditional** on bank-conflict handling | Address interleave, bank arbitration, output-order tracking | Same-bank conflicts |
| D. Double-pumped 64-bit 1RW | Up to 2 × 64-bit at 2x | **Possible** if SRAM and wrapper meet timing | Clock-phase mux, request/response registers | SRAM 2x timing, power/clock complexity |

No option can guarantee lossless infinite input under an unbounded reader stall; specify a bound and prove worst-case occupancy.

## 7. Specific microarchitecture review questions

1. Which entries are physically in *input stage*, *SRAM*, *read in flight*, and *output stage*? Is global occupancy conserved across all moves?
2. Can `rd_valid && !rd_ready` hold oldest data stable without losing a returning SRAM read?
3. If SRAM is empty, can input bypass the SRAM without passing older data in the output stage?
4. If an odd 64-bit entry is left in the 128-bit packer, how is it returned on a drain-to-empty request?
5. Is the 128-bit read response returned early enough to replace the just-consumed two-entry output pair?
6. What happens if a stall or arrival bubble breaks a zero-slack alternating read/write schedule?
7. For two banks, what proof covers collisions when `read_bank == write_bank` for many cycles?
8. For double pumping, does **minimum SRAM cycle time** (not just access delay) pass at 2x, with hold and clock power included?
9. Given a maximum read stall `S` cycles and producer rate 1 entry/cycle, is there **at least S entries** of safe unused capacity at stall onset? What additional margin is needed for in-flight accesses and recovery?
10. Which architecture meets not only peak throughput, but **lossless worst-case throughput** under the specified traffic envelope?

## Recommendation for the exercise

Compare A–D analytically first; then choose whether 128-bit packing or double pumping is the better *SRAM-only* throughput upgrade. If 128-bit macros are unavailable, two banks or double pumping are candidates, but each requires a schedule/timing proof. Keep the work architecture-only until RTL is explicitly requested.
