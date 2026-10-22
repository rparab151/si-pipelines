#!/usr/bin/env python3
"""Cycle-by-cycle RTL-versus-Python differential test (requires iverilog/vvp)."""
import argparse
import pathlib
import random
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]


class Ref:
    def __init__(self):
        self.reset()

    def reset(self):
        self.enabled = 0
        self.buy_below = 0
        self.sell_above = 0xFFFFFFFF
        self.max_orders = 0
        self.expected_seq = 0
        self.gap = 0
        self.reserved = 0
        self.ov = 0
        self.ob = 0
        self.op = 0
        self.oq = 0
        self.os = 0

    def cycle(self, v):
        (rst, cv, ce, cb, cs, cm, rec, rs,
         qv, seq, bid, ask, bq, aq, ord_ready) = v
        if not rst:
            self.reset()  # async reset settles before handshake observation
        out_slot = (not self.ov) or bool(ord_ready)
        cfg_ready = int(not self.ov)
        quote_ready = int(out_slot and not cv and not rec)
        cfg_fire = cv and cfg_ready
        quote_fire = qv and quote_ready
        good_market = bid <= ask
        want_buy = good_market and aq != 0 and ask < self.buy_below
        want_sell = good_market and bq != 0 and bid > self.sell_above
        risk_ok = self.enabled and self.reserved < self.max_orders

        if rst:
            if out_slot:
                self.ov = 0
            if cfg_fire:
                self.enabled = ce
                self.buy_below = cb
                self.sell_above = cs
                self.max_orders = cm
                self.reserved = 0
            if rec:
                self.gap = 0
                self.expected_seq = rs
            elif quote_fire and not self.gap:
                if seq != self.expected_seq:
                    self.gap = 1
                else:
                    self.expected_seq = (self.expected_seq + 1) & 0xFFFFFFFF
                    if risk_ok and (want_buy or want_sell):
                        self.ov = 1
                        self.ob = int(bool(want_buy))
                        self.op = ask if want_buy else bid
                        self.oq = 1
                        self.os = seq
                        self.reserved += 1

        return [quote_ready, cfg_ready, self.ov, self.ob,
                self.op, self.oq, self.os, self.gap,
                self.expected_seq, self.reserved, int(not self.ov)]


def vectors(n, seed):
    rng = random.Random(seed)
    tracker = Ref()
    # First event asserts reset; next loads the initial threshold policy.
    for v in ([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1],
              [1, 1, 1, 95, 105, 12, 0, 0, 0, 0, 0, 0, 0, 0, 1]):
        tracker.cycle(v)
        yield v
    # Use the independently maintained feed cursor for mostly in-order
    # snapshots; deliberately inject occasional gaps and forced recovery.
    for _ in range(n):
        reset = int(rng.random() < 0.003)
        cv = int(rng.random() < 0.02)
        rec = int(rng.random() < 0.015)
        en = int(rng.random() < 0.9)
        cb = rng.randrange(80, 112)
        cs = rng.randrange(100, 132)
        cap = rng.randrange(0, 18)
        qv = int(rng.random() < 0.88)
        ready = int(rng.random() < 0.66)
        seqval = tracker.expected_seq
        if rng.random() < 0.015:
            seqval = (seqval + rng.randrange(1, 5)) & 0xFFFFFFFF
        bid = rng.randrange(70, 135)
        ask = max(0, bid + rng.randrange(-5, 7))
        bq, aq = rng.randrange(0, 4), rng.randrange(0, 4)
        next_seq = rng.randrange(0, 24)
        if reset:
            cv = 0
            rec = 0
        v = [1 - reset, cv, en, cb, cs, cap, rec, next_seq,
             qv, seqval, bid, ask, bq, aq, ready]
        tracker.cycle(v)
        yield v


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--cycles', type=int, default=3000)
    ap.add_argument('--seed', type=int, default=20261021)
    args = ap.parse_args()
    stimulus = list(vectors(args.cycles, args.seed))
    model = Ref()
    expected = [model.cycle(v) for v in stimulus]
    coverage = {
        'order_output_cycles': sum(x[2] for x in expected),
        'gap_fault_cycles': sum(x[7] for x in expected),
        'stalled_output_cycles': sum(bool(x[2] and not v[-1])
                                     for x, v in zip(expected, stimulus)),
        'accepted_quotes': sum(bool(x[0] and v[8])
                               for x, v in zip(expected, stimulus)),
    }
    with tempfile.TemporaryDirectory() as td:
        td = pathlib.Path(td)
        inp, out, sim = td / 'stim.txt', td / 'got.txt', td / 'sim.vvp'
        inp.write_text('\n'.join(' '.join(map(str, row)) for row in stimulus) + '\n')
        subprocess.run([
            'iverilog', '-g2012', '-s', 'tb_trace', '-o', str(sim),
            str(ROOT / 'rtl/nanotrade.sv'), str(ROOT / 'tb/tb_trace.sv')
        ], check=True)
        subprocess.run(['vvp', str(sim), f'+TRACE_IN={inp}', f'+TRACE_OUT={out}'], check=True)
        actual = [[int(x) for x in line.split()] for line in out.read_text().splitlines()]
    if len(actual) != len(expected):
        raise SystemExit(f'Trace length mismatch: got {len(actual)} expected {len(expected)}')
    for i, (a, e) in enumerate(zip(actual, expected)):
        if a != e:
            raise SystemExit(f'FAIL at cycle {i}\n  inputs={stimulus[i]}\n  actual={a}\nexpected={e}')
    print(f'PASS: {len(actual)} randomized RTL/reference cycles (seed={args.seed}); coverage={coverage}')


if __name__ == '__main__':
    main()
