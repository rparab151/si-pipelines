# Microarchitecture review

## Goal
Minimize registered quote-to-order latency for an atomic, **normalized** single-symbol L1 market-data stream, without losing an order under output backpressure. The project does not parse Ethernet/IP/UDP or exchange-native feeds.

## Fast path
Control software precomputes two price thresholds, loaded through the configuration handshake. The datapath evaluates `ask_px < buy_below` and `bid_px > sell_above` in parallel, applies market-validity, sequence, enable and order-intent quota checks, then registers a one-lot order intent.

## Clock-edge contract
A quote is accepted on a rising edge with `quote_valid && quote_ready`. An actionable quote produces a registered output visible immediately after that same edge. An output consumed at an edge can be replaced by a new intent on that edge. When `order_valid && !order_ready`, the output and payload remain stable, and input backpressure is asserted.

`quote_ready` depends combinationally on `order_ready`; this favors bubble-free one-slot replacement but creates a potential ready-path timing issue.

## Control and safety
- Configuration is accepted only with the output register empty; asserted `cfg_valid` blocks quote intake.
- The reset sequence expectation is zero; explicit recovery can reseed it. Wraparound is modulo 2^32.
- A sequence mismatch latches a sticky gap fault and suppresses further intents until recovery. It does not drain pending output intents.
- `orders_reserved` counts emitted *intents*, not fills, inventory, or outstanding live orders. Reloading config starts a new quota epoch.
- Zero relevant-side quantity and crossed quote snapshots suppress intents.
- Inputs must be synchronous to the datapath clock. CDC, replay, cancellations, physical signoff, and connectivity are out of scope.

## Next experiment
Build bypass, one-entry elastic, and two-entry skid-buffer variants. Measure post-synthesis or post-route delay, resources, and area on a declared target. RTL cycle counts alone do not establish nanosecond latency, maximum frequency, or ASIC timing closure.
