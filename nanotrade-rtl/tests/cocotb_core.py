"""Directed cocotb coverage of the original stateful NanoTrade pipeline."""
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge, RisingEdge, Timer


def take(dut):
    names = ["quote_ready", "cfg_ready", "order_valid", "order_buy",
             "order_price", "order_qty", "order_seq", "expected_seq",
             "orders_reserved", "gap_fault"]
    return {name: int(getattr(dut, name).value) for name in names}


async def reset(dut):
    defaults = {
        "rst_n": 0, "cfg_valid": 0, "cfg_enable": 1,
        "cfg_buy_below": 95, "cfg_sell_above": 105, "cfg_max_orders": 4,
        "recover": 0, "recover_next_seq": 0,
        "quote_valid": 0, "quote_seq": 0, "bid_px": 0, "ask_px": 0,
        "bid_qty": 1, "ask_qty": 1, "order_ready": 1,
    }
    for name, value in defaults.items():
        getattr(dut, name).value = value
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await Timer(12, unit="ns")
    await FallingEdge(dut.clk)
    dut.rst_n.value = 1


async def cycle(dut, **updates):
    await FallingEdge(dut.clk)
    for name, value in updates.items():
        getattr(dut, name).value = value
    await Timer(1, unit="ns")
    pre = take(dut)
    await RisingEdge(dut.clk)
    await Timer(1, unit="ns")
    return pre, take(dut)


def check_order(s, buy, price, seq):
    assert s["order_valid"] == 1, s
    assert s["order_buy"] == buy, s
    assert s["order_price"] == price, s
    assert s["order_qty"] == 1, s
    assert s["order_seq"] == seq, s


@cocotb.test()
async def stateful_pipeline_smoke(dut):
    await reset(dut)
    pre, post = await cycle(dut, cfg_valid=1)
    assert pre["cfg_ready"] == 1 and pre["quote_ready"] == 0
    assert post["orders_reserved"] == 0

    pre, post = await cycle(
        dut, cfg_valid=0, quote_valid=1, quote_seq=0,
        bid_px=88, ask_px=90,
    )
    assert pre["quote_ready"] == 1
    check_order(post, 1, 90, 0)

    pre, post = await cycle(
        dut, quote_seq=1, bid_px=110, ask_px=112,
    )
    assert pre["quote_ready"] == 1
    check_order(post, 0, 110, 1)
    assert post["orders_reserved"] == 2
    assert post["expected_seq"] == 2

    pre, post = await cycle(dut, quote_valid=0, order_ready=0)
    assert pre["quote_ready"] == 0
    check_order(post, 0, 110, 1)

    # Stateful core does not yet implement V2's no-trade bypass optimization.
    pre, post = await cycle(
        dut, quote_valid=1, quote_seq=2, bid_px=98,
        ask_px=102, order_ready=1,
    )
    assert pre["quote_ready"] == 1
    assert post["order_valid"] == 0
    assert post["expected_seq"] == 3

    _, post = await cycle(
        dut, quote_seq=3, bid_px=110, ask_px=90,
    )
    assert post["order_valid"] == 0 and post["expected_seq"] == 4

    _, post = await cycle(
        dut, quote_seq=4, bid_px=88, ask_px=90, ask_qty=0,
    )
    assert post["order_valid"] == 0 and post["expected_seq"] == 5

    _, post = await cycle(
        dut, quote_seq=7, bid_px=88, ask_px=90, ask_qty=1,
    )
    assert post["gap_fault"] == 1
    assert post["order_valid"] == 0 and post["expected_seq"] == 5

    _, post = await cycle(dut, quote_seq=8)
    assert post["gap_fault"] == 1
    assert post["order_valid"] == 0

    pre, post = await cycle(
        dut, quote_valid=0, recover=1, recover_next_seq=9,
    )
    assert pre["quote_ready"] == 0
    assert post["gap_fault"] == 0 and post["expected_seq"] == 9

    _, post = await cycle(
        dut, recover=0, quote_valid=1, quote_seq=9,
        bid_px=88, ask_px=90,
    )
    check_order(post, 1, 90, 9)

    _, post = await cycle(
        dut, quote_seq=10, bid_px=110, ask_px=112,
    )
    check_order(post, 0, 110, 10)
    assert post["orders_reserved"] == 4

    _, post = await cycle(
        dut, quote_seq=11, bid_px=88, ask_px=90,
    )
    assert post["order_valid"] == 0
    assert post["orders_reserved"] == 4
    assert post["expected_seq"] == 12

    pre, post = await cycle(
        dut, quote_valid=0, cfg_valid=1, cfg_max_orders=1,
    )
    assert pre["cfg_ready"] == 1
    assert post["orders_reserved"] == 0

    _, post = await cycle(
        dut, cfg_valid=0, quote_valid=1, quote_seq=12,
        bid_px=88, ask_px=90,
    )
    check_order(post, 1, 90, 12)

    _, post = await cycle(
        dut, quote_valid=0, order_ready=1,
    )
    assert post["order_valid"] == 0

    _, post = await cycle(
        dut, recover=1, recover_next_seq=0xFFFFFFFF,
    )
    assert post["expected_seq"] == 0xFFFFFFFF

    _, post = await cycle(
        dut, recover=0, quote_valid=1, quote_seq=0xFFFFFFFF,
        bid_px=98, ask_px=102,
    )
    assert post["expected_seq"] == 0
    assert post["gap_fault"] == 0
    assert post["order_valid"] == 0
