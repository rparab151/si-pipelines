"""cocotb 2.0+ tests for V2, including directed and randomized scoreboarding."""
import random
from collections import deque

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge, RisingEdge, Timer


def intval(signal):
    return int(signal.value)


def snapshot(dut):
    return {
        "qr": intval(dut.quote_ready),
        "ov": intval(dut.order_valid),
        "ob": intval(dut.order_buy),
        "op": intval(dut.order_price),
        "oq": intval(dut.order_qty),
        "os": intval(dut.order_seq),
    }


async def initialize(dut):
    for name, val in {
        "rst_n": 0, "quote_valid": 0, "quote_seq": 0,
        "bid_px": 0, "ask_px": 0, "bid_qty": 0, "ask_qty": 0,
        "enable": 1, "feed_ok": 1, "risk_ok": 1,
        "buy_below": 95, "sell_above": 105, "order_ready": 0,
    }.items():
        getattr(dut, name).value = val
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await Timer(12, unit="ns")
    await FallingEdge(dut.clk)
    dut.rst_n.value = 1


async def cycle(dut, *, seq=0, bid=98, ask=102, bq=1, aq=1,
                valid=1, ready=0, enable=1, feed=1, risk=1,
                buy_below=95, sell_above=105):
    # Drive on falling edge. Read settled combinational handshakes BEFORE
    # the rising edge, then inspect registered outputs AFTER the rising edge.
    await FallingEdge(dut.clk)
    values = {
        "quote_valid": valid, "quote_seq": seq,
        "bid_px": bid, "ask_px": ask, "bid_qty": bq, "ask_qty": aq,
        "order_ready": ready, "enable": enable, "feed_ok": feed,
        "risk_ok": risk, "buy_below": buy_below, "sell_above": sell_above,
    }
    for name, val in values.items():
        getattr(dut, name).value = val
    await Timer(1, unit="ns")
    before = snapshot(dut)
    await RisingEdge(dut.clk)
    await Timer(1, unit="ns")
    after = snapshot(dut)
    return before, after


def order(is_buy, price, seq):
    return {"ov": 1, "ob": is_buy, "op": price, "oq": 1, "os": seq}


def assert_order(state, expected):
    for key, value in expected.items():
        assert state[key] == value, (key, state, expected)


@cocotb.test()
async def directed_elastic_behavior(dut):
    await initialize(dut)

    # T1: accept A even when downstream is not ready (empty output register)
    pre, post = await cycle(dut, seq=1, bid=88, ask=90, ready=0)
    assert pre["qr"] == 1
    assert_order(post, order(1, 90, 1))

    # T2: B is non-trading, and the stalled A must remain unchanged.
    pre, post = await cycle(dut, seq=2, bid=98, ask=102, ready=0, risk=0)
    assert pre["qr"] == 1
    assert_order(post, order(1, 90, 1))

    # T3: actionable C cannot be accepted because A is still stalled.
    pre, post = await cycle(dut, seq=3, bid=110, ask=112, ready=0)
    assert pre["qr"] == 0
    assert_order(post, order(1, 90, 1))

    # T4: simultaneous dequeue A and enqueue C; no empty-cycle bubble.
    pre, post = await cycle(dut, seq=3, bid=110, ask=112, ready=1)
    assert pre["qr"] == 1
    assert_order(post, order(0, 110, 3))

    # T5: drain C.
    _, post = await cycle(dut, valid=0, ready=1)
    assert post["ov"] == 0

    # Full-rate: consecutive actionable quotes must each produce an order.
    for seq in range(10, 20):
        pre, post = await cycle(dut, seq=seq, bid=88, ask=90, ready=1)
        assert pre["qr"] == 1
        assert_order(post, order(1, 90, seq))

    # Non-trading crossed market never generates an order.
    _, post = await cycle(dut, seq=20, bid=120, ask=80, ready=1)
    assert post["ov"] == 0


@cocotb.test()
async def randomized_scoreboard(dut):
    await initialize(dut)
    rng = random.Random(20261023)
    pending_quote = None
    expected = deque()
    accepted = produced = retired = bypassed = stalls = 0

    for step in range(1500):
        if pending_quote is None and rng.random() < 0.90:
            bid = rng.randrange(75, 130)
            pending_quote = {
                "seq": step, "bid": bid,
                "ask": max(0, bid + rng.randrange(-4, 8)),
                "bq": rng.randrange(0, 3),
                "aq": rng.randrange(0, 3),
            }
        q = pending_quote or {"seq": 0, "bid": 100, "ask": 102, "bq": 0, "aq": 0}
        valid = int(pending_quote is not None)
        ready = int(rng.random() < 0.68)
        risk = int(rng.random() < 0.85)
        en = int(rng.random() < 0.93)
        feed = int(rng.random() < 0.97)
        bb = rng.randrange(88, 104)
        sa = rng.randrange(98, 114)

        pre, post = await cycle(
            dut, **q, valid=valid, ready=ready,
            risk=risk, enable=en, feed=feed,
            buy_below=bb, sell_above=sa,
        )

        # The output observed immediately BEFORE this edge represents
        # already-accepted quotes, never the just-presented quote.
        if expected:
            assert_order(pre, expected[0])
        else:
            assert pre["ov"] == 0, (step, pre, list(expected))

        if pre["ov"] and ready:
            old = expected.popleft()
            retired += 1
            assert_order(pre, old)

        if valid and pre["qr"]:
            accepted += 1
            pending_quote = None
            market_ok = q["bid"] <= q["ask"]
            buy = market_ok and q["aq"] > 0 and q["ask"] < bb
            sell = market_ok and q["bq"] > 0 and q["bid"] > sa
            hit = en and feed and risk and (buy or sell)
            if hit:
                expected.append(
                    order(int(bool(buy)), q["ask"] if buy else q["bid"], q["seq"])
                )
                produced += 1
            else:
                bypassed += 1
        elif valid:
            stalls += 1

        assert len(expected) <= 1, (step, list(expected))
        if expected:
            assert_order(post, expected[0])
        else:
            assert post["ov"] == 0, (step, post)

    # Drain any remaining registered order at the end of the test.
    pre, post = await cycle(dut, valid=0, ready=1)
    if pre["ov"]:
        assert expected
        assert_order(pre, expected.popleft())
        retired += 1
    assert not expected
    assert post["ov"] == 0

    assert accepted > 100 and produced > 10 and retired > 10
    assert bypassed > 50 and stalls > 5
    dut._log.info(
        "Coverage: accepted=%d orders=%d retired=%d nontrade=%d stalls=%d",
        accepted, produced, retired, bypassed, stalls,
    )
